import 'dart:async';

import 'package:dio/dio.dart';
import 'package:pixez/debug/mana_manager.dart';
import 'package:pixez/debug/network_logger.dart';

enum BangumiLookupType { subject, character }

abstract interface class BangumiApiTransport {
  Future<dynamic> post(
    String path, {
    required Map<String, dynamic> queryParameters,
    required Object data,
  });

  Future<dynamic> get(String path);
}

class DioBangumiApiTransport implements BangumiApiTransport {
  final Dio dio;
  final bool _usesDefaultDio;

  DioBangumiApiTransport({Dio? dio})
    : dio = dio ?? _createDefaultDio(),
      _usesDefaultDio = dio == null {
    if (_usesDefaultDio) {
      this.dio.interceptors.add(NetworkLogInterceptor());
      final manaInterceptor = ManaManager.instance.dioInterceptor;
      if (manaInterceptor != null) {
        this.dio.interceptors.add(manaInterceptor);
      }
    }
  }

  static Dio _createDefaultDio() => Dio(
    BaseOptions(
      baseUrl: 'https://api.bgm.tv',
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
      sendTimeout: const Duration(seconds: 10),
      headers: const {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'User-Agent': 'PixEz-BangumiTagLookup/1.0',
      },
      responseType: ResponseType.json,
    ),
  );

  @override
  Future<dynamic> post(
    String path, {
    required Map<String, dynamic> queryParameters,
    required Object data,
  }) async {
    final response = await dio.post<dynamic>(
      path,
      queryParameters: queryParameters,
      data: data,
    );
    return response.data;
  }

  @override
  Future<dynamic> get(String path) async {
    final response = await dio.get<dynamic>(path);
    return response.data;
  }
}

class BangumiLookupException implements Exception {
  final String message;

  const BangumiLookupException(this.message);

  @override
  String toString() => message;
}

class BangumiSubjectCandidate {
  final int id;
  final String name;
  final String nameCn;
  final int? type;
  final List<String> matchedQueries;

  const BangumiSubjectCandidate({
    required this.id,
    required this.name,
    required this.nameCn,
    required this.type,
    required this.matchedQueries,
  });
}

class BangumiCharacterCandidate {
  final int id;
  final String name;
  final String nameCn;
  final List<String> matchedQueries;
  final List<BangumiSubjectCandidate> subjects;

  const BangumiCharacterCandidate({
    required this.id,
    required this.name,
    required this.nameCn,
    required this.matchedQueries,
    required this.subjects,
  });
}

class BangumiLookupResult {
  final BangumiLookupType type;
  final List<String> queries;
  final List<BangumiSubjectCandidate> subjects;
  final List<BangumiCharacterCandidate> characters;

  const BangumiLookupResult({
    required this.type,
    required this.queries,
    this.subjects = const [],
    this.characters = const [],
  });

  bool get hasCandidates => subjects.isNotEmpty || characters.isNotEmpty;

  String toPromptText() {
    final buffer = StringBuffer();
    buffer.writeln('查询词：${queries.join('、')}');
    if (subjects.isNotEmpty) {
      buffer.writeln('作品候选：');
      for (var index = 0; index < subjects.length; index++) {
        final subject = subjects[index];
        buffer.writeln(
          '${index + 1}. ${_displayName(subject.name, subject.nameCn)}'
          '（匹配：${subject.matchedQueries.join('、')}）',
        );
      }
    }
    if (characters.isNotEmpty) {
      buffer.writeln('角色候选：');
      for (var index = 0; index < characters.length; index++) {
        final character = characters[index];
        buffer.writeln(
          '${index + 1}. ${_displayName(character.name, character.nameCn)}'
          '（匹配：${character.matchedQueries.join('、')}）',
        );
        if (character.subjects.isEmpty) {
          buffer.writeln('   关联作品：无');
          continue;
        }
        buffer.writeln('   关联作品：');
        for (final subject in character.subjects) {
          buffer.writeln('   - ${_displayName(subject.name, subject.nameCn)}');
        }
      }
    }
    return buffer.toString().trim();
  }

  static String _displayName(String name, String nameCn) {
    if (nameCn.isEmpty || nameCn == name) return name;
    return '$name / $nameCn';
  }
}

abstract interface class BangumiLookupService {
  Future<BangumiLookupResult> lookup({
    required BangumiLookupType type,
    required List<String> queries,
  });
}

class BangumiApiLookupService implements BangumiLookupService {
  static const _searchLimit = 5;
  static const _maxSubjectCandidates = 12;
  static const _maxCharacterCandidates = 3;
  static const _maxRelatedSubjects = 5;

  final BangumiApiTransport transport;
  final Duration requestDelay;
  final Map<String, Future<BangumiLookupResult>> _cache = {};
  DateTime? _lastRequestAt;

  BangumiApiLookupService({
    BangumiApiTransport? transport,
    this.requestDelay = const Duration(milliseconds: 120),
  }) : transport = transport ?? DioBangumiApiTransport();

  @override
  Future<BangumiLookupResult> lookup({
    required BangumiLookupType type,
    required List<String> queries,
  }) async {
    final normalizedQueries = _normalizeQueries(queries);
    if (normalizedQueries.isEmpty) {
      return BangumiLookupResult(type: type, queries: const []);
    }
    final key = '${type.name}:${normalizedQueries.join('\u0000')}';
    final cached = _cache[key];
    if (cached != null) return cached;

    final future = _lookupUncached(type, normalizedQueries);
    _cache[key] = future;
    try {
      return await future;
    } catch (_) {
      if (identical(_cache[key], future)) _cache.remove(key);
      rethrow;
    }
  }

  Future<BangumiLookupResult> _lookupUncached(
    BangumiLookupType type,
    List<String> queries,
  ) async {
    return switch (type) {
      BangumiLookupType.subject => _lookupSubjects(queries),
      BangumiLookupType.character => _lookupCharacters(queries),
    };
  }

  Future<BangumiLookupResult> _lookupSubjects(List<String> queries) async {
    final byId = <int, _MutableSubjectCandidate>{};
    Object? lastError;
    var successCount = 0;
    for (final query in queries) {
      try {
        final payload = await _post(
          '/v0/search/subjects',
          queryParameters: const {'limit': _searchLimit},
          data: {
            'keyword': query,
            'sort': 'match',
            'filter': {
              'type': [1, 2, 4],
            },
          },
        );
        successCount++;
        for (final item in _dataList(payload).take(_searchLimit)) {
          final candidate = _parseSubject(item);
          if (candidate == null) continue;
          final existing = byId[candidate.id];
          if (existing == null) {
            byId[candidate.id] = _MutableSubjectCandidate.from(
              candidate,
              query,
            );
          } else {
            existing.addQuery(query);
          }
        }
      } catch (error) {
        lastError = error;
      }
    }
    if (successCount == 0 && lastError != null) {
      throw BangumiLookupException('Bangumi 作品查询失败：$lastError');
    }
    final candidates = byId.values
        .take(_maxSubjectCandidates)
        .map((item) => item.freeze())
        .toList(growable: false);
    return BangumiLookupResult(
      type: BangumiLookupType.subject,
      queries: queries,
      subjects: candidates,
    );
  }

  Future<BangumiLookupResult> _lookupCharacters(List<String> queries) async {
    final byId = <int, _MutableCharacterCandidate>{};
    Object? lastError;
    var successCount = 0;
    for (final query in queries) {
      try {
        final payload = await _post(
          '/v0/search/characters',
          queryParameters: const {'limit': _searchLimit},
          data: {'keyword': query},
        );
        successCount++;
        for (final item in _dataList(payload).take(_searchLimit)) {
          final candidate = _parseCharacter(item);
          if (candidate == null) continue;
          final existing = byId[candidate.id];
          if (existing == null) {
            byId[candidate.id] = _MutableCharacterCandidate.from(
              candidate,
              query,
            );
          } else {
            existing.addQuery(query);
          }
        }
      } catch (error) {
        lastError = error;
      }
    }
    if (successCount == 0 && lastError != null) {
      throw BangumiLookupException('Bangumi 角色查询失败：$lastError');
    }

    final candidates = <BangumiCharacterCandidate>[];
    for (final candidate in byId.values.take(_maxCharacterCandidates)) {
      try {
        final payload = await _get('/v0/characters/${candidate.id}/subjects');
        candidate.subjects.addAll(
          _dataList(payload)
              .map(_parseSubject)
              .whereType<BangumiSubjectCandidate>()
              .take(_maxRelatedSubjects),
        );
      } catch (_) {
        // 角色搜索结果仍然可以作为候选；关联作品查询失败时留空。
      }
      candidates.add(candidate.freeze());
    }
    return BangumiLookupResult(
      type: BangumiLookupType.character,
      queries: queries,
      characters: candidates,
    );
  }

  Future<dynamic> _post(
    String path, {
    required Map<String, dynamic> queryParameters,
    required Object data,
  }) async {
    await _respectRequestDelay();
    return transport.post(path, queryParameters: queryParameters, data: data);
  }

  Future<dynamic> _get(String path) async {
    await _respectRequestDelay();
    return transport.get(path);
  }

  Future<void> _respectRequestDelay() async {
    final last = _lastRequestAt;
    if (last != null) {
      final elapsed = DateTime.now().difference(last);
      final remaining = requestDelay - elapsed;
      if (remaining > Duration.zero) await Future<void>.delayed(remaining);
    }
    _lastRequestAt = DateTime.now();
  }

  static List<String> _normalizeQueries(List<String> queries) {
    final result = <String>[];
    for (final raw in queries) {
      final query = raw.trim();
      if (query.isEmpty || result.contains(query)) continue;
      result.add(query);
      if (result.length == 3) break;
    }
    return result;
  }

  static List<dynamic> _dataList(dynamic payload) {
    if (payload is List) return payload;
    if (payload is Map && payload['data'] is List) {
      return payload['data'] as List<dynamic>;
    }
    return const [];
  }

  static BangumiSubjectCandidate? _parseSubject(dynamic raw) {
    if (raw is! Map) return null;
    final id = _intValue(raw['id'] ?? raw['subject_id']);
    if (id == null) return null;
    return BangumiSubjectCandidate(
      id: id,
      name: _text(raw['name']),
      nameCn: _text(raw['name_cn']),
      type: _intValue(raw['type'] ?? raw['subject_type']),
      matchedQueries: const [],
    );
  }

  static BangumiCharacterCandidate? _parseCharacter(dynamic raw) {
    if (raw is! Map) return null;
    final id = _intValue(raw['id']);
    if (id == null) return null;
    return BangumiCharacterCandidate(
      id: id,
      name: _text(raw['name']),
      nameCn: _text(raw['name_cn']),
      matchedQueries: const [],
      subjects: const [],
    );
  }

  static String _text(dynamic value) => value?.toString().trim() ?? '';

  static int? _intValue(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(_text(value));
  }
}

class _MutableSubjectCandidate {
  final int id;
  final String name;
  final String nameCn;
  final int? type;
  final Set<String> matchedQueries = {};

  _MutableSubjectCandidate({
    required this.id,
    required this.name,
    required this.nameCn,
    required this.type,
  });

  factory _MutableSubjectCandidate.from(
    BangumiSubjectCandidate candidate,
    String query,
  ) => _MutableSubjectCandidate(
    id: candidate.id,
    name: candidate.name,
    nameCn: candidate.nameCn,
    type: candidate.type,
  )..addQuery(query);

  void addQuery(String query) => matchedQueries.add(query);

  BangumiSubjectCandidate freeze() => BangumiSubjectCandidate(
    id: id,
    name: name,
    nameCn: nameCn,
    type: type,
    matchedQueries: List.unmodifiable(matchedQueries),
  );
}

class _MutableCharacterCandidate {
  final int id;
  final String name;
  final String nameCn;
  final Set<String> matchedQueries = {};
  final List<BangumiSubjectCandidate> subjects = [];

  _MutableCharacterCandidate({
    required this.id,
    required this.name,
    required this.nameCn,
  });

  factory _MutableCharacterCandidate.from(
    BangumiCharacterCandidate candidate,
    String query,
  ) => _MutableCharacterCandidate(
    id: candidate.id,
    name: candidate.name,
    nameCn: candidate.nameCn,
  )..addQuery(query);

  void addQuery(String query) => matchedQueries.add(query);

  BangumiCharacterCandidate freeze() => BangumiCharacterCandidate(
    id: id,
    name: name,
    nameCn: nameCn,
    matchedQueries: List.unmodifiable(matchedQueries),
    subjects: List.unmodifiable(subjects),
  );
}
