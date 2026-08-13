import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'tag_ai_shared.dart';

const _apiBaseUrl = 'https://api.bgm.tv';
const _userAgent = 'tag-ai-process/1.0';

Future<void> main(List<String> args) async {
  final client = HttpClient();
  try {
    final cli = _parseArgs(args);
    if (cli.help) {
      _printUsage();
      return;
    }

    final cache = _BangumiCache.load(cli.cachePath);
    final api = _BangumiApi(
      client: client,
      cache: cache,
      timeout: Duration(seconds: cli.timeoutSeconds),
      delay: Duration(milliseconds: cli.delayMs),
    );

    late final Map<String, Object?> payload;
    if (cli.inputPath.isNotEmpty) {
      payload = await _runBatch(cli, api);
    } else {
      payload = await _runSingle(cli, api);
    }

    cache.save();
    final encoder = const JsonEncoder.withIndent('  ');
    final text = '${encoder.convert(payload)}\n';
    if (cli.outPath.isEmpty) {
      stdout.write(text);
    } else {
      ensureParentDirectory(cli.outPath);
      File(cli.outPath).writeAsStringSync(text);
      stdout.writeln('已生成 Bangumi 查询结果: ${cli.outPath}');
    }
  } on Object catch (error) {
    stderr.writeln('bangumi_lookup 执行失败: $error');
    exitCode = 1;
  } finally {
    client.close(force: true);
  }
}

Future<Map<String, Object?>> _runSingle(
  _CliOptions cli,
  _BangumiApi api,
) async {
  if (cli.command != 'subject' && cli.command != 'character') {
    throw const FormatException('单查模式只支持 subject 或 character');
  }
  if (cli.query.isEmpty) {
    throw const FormatException('缺少查询关键词');
  }

  final result =
      cli.command == 'subject'
          ? await api.lookupSubject(cli.query, cli)
          : await api.lookupCharacter(cli.query, cli);

  return {
    'version': 1,
    'generated_at': DateTime.now().toIso8601String(),
    'mode': cli.command,
    'query': cli.query,
    'stats': api.stats(),
    'result': result,
  };
}

Future<Map<String, Object?>> _runBatch(_CliOptions cli, _BangumiApi api) async {
  final inputFile = File(cli.inputPath);
  if (!inputFile.existsSync()) {
    throw FileSystemException('找不到输入文件', cli.inputPath);
  }
  final root = jsonDecode(inputFile.readAsStringSync());
  if (root is! Map<String, Object?>) {
    throw const FormatException('输入根节点必须是 JSON 对象');
  }
  final pendingTags = root['pending_tags'];
  if (pendingTags is! List) {
    throw const FormatException('输入缺少 pending_tags 数组');
  }

  final results = <Map<String, Object?>>[];
  var visited = 0;
  var subjectQueries = 0;
  var characterQueries = 0;

  for (final rawTag in pendingTags) {
    if (rawTag is! Map<String, Object?>) {
      continue;
    }
    if (cli.batchLimit > 0 && visited >= cli.batchLimit) {
      break;
    }
    if (!_shouldLookup(rawTag)) {
      continue;
    }
    visited++;

    final name = cleanText(rawTag['name'] as String?);
    final result = <String, Object?>{
      'tag_name': name,
      'count': rawTag['count'],
      'ai_focus': rawTag['ai_focus'],
      'queries': <String, Object?>{},
      'errors': <String>[],
    };
    final queries = result['queries'] as Map<String, Object?>;
    final errors = result['errors'] as List<String>;

    if (_shouldSearchSubject(rawTag)) {
      try {
        queries['subject'] = await api.lookupSubject(name, cli);
        subjectQueries++;
      } on Object catch (error) {
        errors.add('subject: $error');
      }
    }

    if (_shouldSearchCharacter(rawTag)) {
      try {
        queries['character'] = await api.lookupCharacter(name, cli);
        characterQueries++;
      } on Object catch (error) {
        errors.add('character: $error');
      }
    }

    if (queries.isNotEmpty || errors.isNotEmpty) {
      results.add(result);
    }
  }

  return {
    'version': 1,
    'generated_at': DateTime.now().toIso8601String(),
    'source': {
      'input': cli.inputPath,
      'api_base_url': _apiBaseUrl,
      'user_agent': _userAgent,
      'search_limit': cli.limit,
      'character_limit': cli.characterLimit,
      'related_subject_limit': cli.relatedSubjectLimit,
      'batch_limit': cli.batchLimit == 0 ? null : cli.batchLimit,
    },
    'stats': {
      'pending_count': pendingTags.length,
      'lookup_count': results.length,
      'subject_query_count': subjectQueries,
      'character_query_count': characterQueries,
      ...api.stats(),
    },
    'results': results,
  };
}

bool _shouldLookup(Map<String, Object?> tag) {
  if (tag['needs_ai'] != true) {
    return false;
  }
  final aiFocus = _stringList(tag['ai_focus']);
  return aiFocus.contains('确认中文译名') ||
      aiFocus.contains('确认所属作品') ||
      aiFocus.contains('判断分类');
}

bool _shouldSearchSubject(Map<String, Object?> tag) {
  final signals = _signals(tag);
  if (signals['looks_meta'] == true ||
      signals['looks_general'] == true ||
      signals['looks_feature'] == true) {
    return false;
  }
  final aiFocus = _stringList(tag['ai_focus']);
  return aiFocus.contains('确认中文译名') || aiFocus.contains('判断分类');
}

bool _shouldSearchCharacter(Map<String, Object?> tag) {
  final signals = _signals(tag);
  if (signals['looks_meta'] == true ||
      signals['looks_general'] == true ||
      signals['looks_feature'] == true) {
    return false;
  }
  final aiFocus = _stringList(tag['ai_focus']);
  return signals['looks_character'] == true || aiFocus.contains('确认所属作品');
}

Map<String, Object?> _signals(Map<String, Object?> tag) {
  final raw = tag['signals'];
  return raw is Map<String, Object?> ? raw : <String, Object?>{};
}

List<String> _stringList(Object? value) {
  if (value is! List) {
    return const [];
  }
  return value.map((item) => cleanText(item?.toString())).toList();
}

class _BangumiApi {
  _BangumiApi({
    required this.client,
    required this.cache,
    required this.timeout,
    required this.delay,
  });

  final HttpClient client;
  final _BangumiCache cache;
  final Duration timeout;
  final Duration delay;
  int apiRequestCount = 0;
  int cacheHitCount = 0;

  Map<String, Object?> stats() => {
    'api_request_count': apiRequestCount,
    'cache_hit_count': cacheHitCount,
    'cache_entry_count': cache.entryCount,
  };

  Future<Map<String, Object?>> lookupSubject(
    String query,
    _CliOptions options,
  ) async {
    final raw = await _cached(
      'subject:${options.limit}:$query',
      () => _postJson('/v0/search/subjects?limit=${options.limit}', {
        'keyword': query,
        'sort': 'match',
        'filter': {
          'type': [1, 2, 4],
        },
      }),
    );
    final data = _asList(raw['data']);
    return {'query': query, 'matches': data.map(_compactSubject).toList()};
  }

  Future<Map<String, Object?>> lookupCharacter(
    String query,
    _CliOptions options,
  ) async {
    final raw = await _cached(
      'character:${options.limit}:$query',
      () => _postJson('/v0/search/characters?limit=${options.limit}', {
        'keyword': query,
      }),
    );

    final matches = <Map<String, Object?>>[];
    final data = _asList(raw['data']);
    for (final item in data.take(options.characterLimit)) {
      if (item is! Map) {
        continue;
      }
      final id = _intValue(item['id']);
      if (id == null) {
        continue;
      }
      final detail = await _cached(
        'character-detail:$id',
        () => _getJson('/v0/characters/$id'),
      );
      final subjectsRaw = await _cached(
        'character-subjects:$id',
        () => _getJson('/v0/characters/$id/subjects'),
      );
      final subjects =
          _asList(subjectsRaw['data'])
              .map(_compactRelatedSubject)
              .take(options.relatedSubjectLimit)
              .toList();
      matches.add({
        ..._compactCharacter(item),
        'detail': _compactCharacterDetail(detail),
        'subjects': subjects,
      });
    }

    return {'query': query, 'matches': matches};
  }

  Future<Map<String, Object?>> _cached(
    String key,
    Future<Map<String, Object?>> Function() fetch,
  ) async {
    final cached = cache.read(key);
    if (cached != null) {
      cacheHitCount++;
      return cached;
    }
    if (delay.inMilliseconds > 0 && apiRequestCount > 0) {
      await Future<void>.delayed(delay);
    }
    apiRequestCount++;
    final data = await fetch();
    cache.write(key, data);
    return data;
  }

  Future<Map<String, Object?>> _postJson(
    String path,
    Map<String, Object?> body,
  ) async {
    final request = await client.postUrl(Uri.parse('$_apiBaseUrl$path'));
    _setHeaders(request);
    request.write(jsonEncode(body));
    return _readResponse(request);
  }

  Future<Map<String, Object?>> _getJson(String path) async {
    final request = await client.getUrl(Uri.parse('$_apiBaseUrl$path'));
    _setHeaders(request);
    return _readResponse(request);
  }

  void _setHeaders(HttpClientRequest request) {
    request.headers.contentType = ContentType.json;
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.headers.set(HttpHeaders.userAgentHeader, _userAgent);
  }

  Future<Map<String, Object?>> _readResponse(HttpClientRequest request) async {
    final response = await request.close().timeout(timeout);
    final text = await response.transform(utf8.decoder).join().timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('HTTP ${response.statusCode}: $text');
    }
    final decoded = jsonDecode(text);
    if (decoded is Map<String, Object?>) {
      return decoded;
    }
    if (decoded is List) {
      return {'data': decoded};
    }
    throw const FormatException('Bangumi 响应不是 JSON 对象或数组');
  }
}

Map<String, Object?> _compactSubject(Object? raw) {
  final item = raw is Map ? raw : const {};
  final rating = item['rating'];
  return {
    'id': _intValue(item['id'] ?? item['subject_id']),
    'name': cleanText(item['name']?.toString()),
    'name_cn': cleanText(item['name_cn']?.toString()),
    'type': _intValue(item['type']),
    'date': cleanText(item['date']?.toString()),
    'rank': _intValue(item['rank']),
    'score': rating is Map ? rating['score'] : null,
  };
}

Map<String, Object?> _compactCharacter(Object? raw) {
  final item = raw is Map ? raw : const {};
  return {
    'id': _intValue(item['id']),
    'name': cleanText(item['name']?.toString()),
    'relation': cleanText(item['relation']?.toString()),
  };
}

Map<String, Object?> _compactCharacterDetail(Map<String, Object?> raw) {
  return {
    'id': _intValue(raw['id']),
    'name': cleanText(raw['name']?.toString()),
    'summary': _shortText(raw['summary']),
    'infobox': _compactInfobox(raw['infobox']),
  };
}

Map<String, Object?> _compactRelatedSubject(Object? raw) {
  final item = raw is Map ? raw : const {};
  return {
    'id': _intValue(item['id'] ?? item['subject_id']),
    'name': cleanText(
      (item['name'] ?? item['subject_name'] ?? item['name_cn'])?.toString(),
    ),
    'name_cn': cleanText(item['name_cn']?.toString()),
    'type': _intValue(item['type'] ?? item['subject_type']),
    'staff': cleanText(item['staff']?.toString()),
  };
}

List<Map<String, Object?>> _compactInfobox(Object? raw) {
  if (raw is! List) {
    return const [];
  }
  final result = <Map<String, Object?>>[];
  final interesting = RegExp(r'中文|简体|別名|别名|英文|罗马|羅馬');
  for (final item in raw) {
    if (item is! Map) {
      continue;
    }
    final key = cleanText(item['key']?.toString());
    if (key.isEmpty || !interesting.hasMatch(key)) {
      continue;
    }
    result.add({'key': key, 'value': _compactValue(item['value'])});
  }
  return result.take(8).toList();
}

Object? _compactValue(Object? value) {
  if (value is String || value is num || value is bool || value == null) {
    return value;
  }
  if (value is List) {
    return value.map(_compactValue).take(8).toList();
  }
  if (value is Map) {
    final output = <String, Object?>{};
    for (final entry in value.entries) {
      output[entry.key.toString()] = _compactValue(entry.value);
    }
    return output;
  }
  return value.toString();
}

String _shortText(Object? value) {
  final text = cleanText(value?.toString());
  if (text.length <= 160) {
    return text;
  }
  return '${text.substring(0, 160)}...';
}

List<Object?> _asList(Object? value) {
  if (value is List) {
    return value;
  }
  return const [];
}

int? _intValue(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(cleanText(value?.toString()));
}

class _BangumiCache {
  _BangumiCache(this.path, this._root);

  final String path;
  final Map<String, Object?> _root;

  int get entryCount => _entries.length;

  Map<String, Object?> get _entries {
    final entries = _root['entries'];
    if (entries is Map<String, Object?>) {
      return entries;
    }
    final created = <String, Object?>{};
    _root['entries'] = created;
    return created;
  }

  static _BangumiCache load(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      return _BangumiCache(path, {
        'version': 1,
        'entries': <String, Object?>{},
      });
    }
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is Map<String, Object?>) {
      return _BangumiCache(path, decoded);
    }
    return _BangumiCache(path, {'version': 1, 'entries': <String, Object?>{}});
  }

  Map<String, Object?>? read(String key) {
    final entry = _entries[key];
    if (entry is! Map<String, Object?>) {
      return null;
    }
    final data = entry['data'];
    return data is Map<String, Object?> ? data : null;
  }

  void write(String key, Map<String, Object?> data) {
    _entries[key] = {
      'saved_at': DateTime.now().toIso8601String(),
      'data': data,
    };
  }

  void save() {
    ensureParentDirectory(path);
    final encoder = const JsonEncoder.withIndent('  ');
    File(path).writeAsStringSync('${encoder.convert(_root)}\n');
  }
}

class _CliOptions {
  const _CliOptions({
    required this.help,
    required this.command,
    required this.query,
    required this.inputPath,
    required this.outPath,
    required this.cachePath,
    required this.limit,
    required this.characterLimit,
    required this.relatedSubjectLimit,
    required this.batchLimit,
    required this.timeoutSeconds,
    required this.delayMs,
  });

  final bool help;
  final String command;
  final String query;
  final String inputPath;
  final String outPath;
  final String cachePath;
  final int limit;
  final int characterLimit;
  final int relatedSubjectLimit;
  final int batchLimit;
  final int timeoutSeconds;
  final int delayMs;
}

_CliOptions _parseArgs(List<String> args) {
  final options = <String, String?>{};
  final positional = <String>[];

  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '--help' || arg == '-h') {
      options['help'] = 'true';
      continue;
    }
    if (!arg.startsWith('--')) {
      positional.add(arg);
      continue;
    }
    final equalIndex = arg.indexOf('=');
    if (equalIndex != -1) {
      options[arg.substring(2, equalIndex)] = arg.substring(equalIndex + 1);
      continue;
    }
    final key = arg.substring(2);
    if (i + 1 < args.length && !args[i + 1].startsWith('--')) {
      options[key] = args[++i];
    } else {
      options[key] = 'true';
    }
  }

  final inputPath = cleanText(options['input']);
  final command = positional.isEmpty ? '' : positional.first;
  final query = positional.length < 2 ? '' : positional.sublist(1).join(' ');
  final defaultOut =
      inputPath.isEmpty ? '' : defaultBuildPath('bangumi_lookup.json');

  return _CliOptions(
    help: options['help'] == 'true',
    command: command,
    query: query,
    inputPath: inputPath,
    outPath:
        cleanText(options['out']).isEmpty
            ? defaultOut
            : cleanText(options['out']),
    cachePath:
        cleanText(options['cache']).isEmpty
            ? defaultBuildPath('bangumi_lookup.cache.json')
            : cleanText(options['cache']),
    limit: int.tryParse(cleanText(options['limit'])) ?? 5,
    characterLimit: int.tryParse(cleanText(options['character-limit'])) ?? 1,
    relatedSubjectLimit:
        int.tryParse(cleanText(options['related-subject-limit'])) ?? 5,
    batchLimit: int.tryParse(cleanText(options['batch-limit'])) ?? 0,
    timeoutSeconds: int.tryParse(cleanText(options['timeout'])) ?? 20,
    delayMs: int.tryParse(cleanText(options['delay-ms'])) ?? 150,
  );
}

void _printUsage() {
  stdout.writeln('bangumi_lookup.dart');
  stdout.writeln(
    '用法: dart run .agent/skills/tag-ai-process/scripts/bangumi_lookup.dart subject <关键词> [--out <path>]',
  );
  stdout.writeln(
    '用法: dart run .agent/skills/tag-ai-process/scripts/bangumi_lookup.dart character <关键词> [--out <path>]',
  );
  stdout.writeln(
    '用法: dart run .agent/skills/tag-ai-process/scripts/bangumi_lookup.dart --input <ai_tag_batch.json> [--out <path>]',
  );
  stdout.writeln('默认输出: ${defaultBuildPath('bangumi_lookup.json')}');
  stdout.writeln('默认缓存: ${defaultBuildPath('bangumi_lookup.cache.json')}');
  stdout.writeln('常用选项: --limit 5 --character-limit 1 --batch-limit 20');
}
