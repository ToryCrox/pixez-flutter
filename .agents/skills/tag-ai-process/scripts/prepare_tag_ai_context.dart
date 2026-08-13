import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import 'tag_ai_shared.dart';

const _metaKeywords = <String>{
  'highres',
  'absurdres',
  'commentary',
  'commentary_request',
  'signature',
  'lowres',
  'text',
  'watermark',
  'scan',
  'translated',
};

const _generalKeywords = <String>{
  'solo',
  'simple_background',
  'white_background',
  'black_background',
  'transparent_background',
  'multiple_girls',
  'multiple_boys',
  'looking_at_viewer',
  'cowboy_shot',
  'upper_body',
  'full_body',
  'no_humans',
};

const _featureKeywords = <String>{
  'smile',
  'blush',
  'open_mouth',
  'closed_mouth',
  'sitting',
  'standing',
  'long_hair',
  'short_hair',
  'black_hair',
  'brown_hair',
  'blonde_hair',
  'breasts',
  'large_breasts',
  'small_breasts',
  'black_pantyhose',
  'pantyhose',
  'school_uniform',
  'maid',
  'bunny_girl',
  'dress',
  'swimsuit',
};

final _countTagPattern = RegExp(r'^\d+\+?(girl|girls|boy|boys|other|others)$');
final _bracketPattern = RegExp(r'^.+[（(][^（）()]+[）)]$');

void main(List<String> args) {
  try {
    final options = parseCliArgs(args);
    if (hasFlag(options, 'help')) {
      _printUsage();
      return;
    }

    final dbPath =
        cleanText(options['db']).isEmpty
            ? defaultDatabasePath
            : cleanText(options['db']);
    final outputPath =
        cleanText(options['out']).isEmpty
            ? defaultBuildPath('ai_tag_batch.json')
            : cleanText(options['out']);
    final limit = int.tryParse(cleanText(options['limit'])) ?? 50;

    final database = sqlite3.open(dbPath);
    try {
      final pendingTags = _readPendingTags(database, limit);
      final workTags = _readWorkTags(database);
      final canonicalWorks = _buildCanonicalWorks(workTags);
      final aliasLookup = _buildAliasLookup(workTags, canonicalWorks);
      final analyzedTags =
          pendingTags
              .map((tag) => _analyzePendingTag(tag, aliasLookup))
              .toList();

      final resolvedParents = <String, Map<String, Object?>>{};
      for (final tag in analyzedTags) {
        final parentName = cleanText(
          (tag['signals'] as Map<String, Object?>)['resolved_parent_name']
              as String?,
        );
        if (parentName.isEmpty) {
          continue;
        }
        final work = canonicalWorks[parentName];
        if (work == null) {
          continue;
        }
        resolvedParents[parentName] = {
          'name': work.name,
          'translated_name':
              work.translatedName.isEmpty ? null : work.translatedName,
          'custom_translated_name':
              work.customTranslatedName.isEmpty
                  ? null
                  : work.customTranslatedName,
          'count': work.count,
        };
      }

      final deterministicCount =
          analyzedTags
              .where((tag) => tag['deterministic_suggestion'] != null)
              .length;
      final needsAiCount =
          analyzedTags.where((tag) => tag['needs_ai'] == true).length;

      final payload = <String, Object?>{
        'version': 1,
        'generated_at': DateTime.now().toIso8601String(),
        'source': {'db_path': dbPath, 'limit': limit},
        'stats': {
          'pending_count': analyzedTags.length,
          'deterministic_count': deterministicCount,
          'needs_ai_count': needsAiCount,
          'resolved_parent_reference_count': resolvedParents.length,
        },
        'workflow': [
          '优先采用 deterministic_suggestion 里的高置信度建议',
          '仅对 needs_ai = true 的标签做额外判断',
          '如果 ai_focus 为空，不要再展开分析',
          '除非 ai_focus 明确要求，否则不要联网',
        ],
        'resolved_parent_reference': resolvedParents.values.toList(),
        'pending_tags': analyzedTags,
      };

      ensureParentDirectory(outputPath);
      final encoder = const JsonEncoder.withIndent('  ');
      File(outputPath).writeAsStringSync('${encoder.convert(payload)}\n');

      stdout.writeln('已生成 AI 批次文件: $outputPath');
      stdout.writeln(
        '待处理 ${analyzedTags.length} 条，其中高置信规则建议 $deterministicCount 条，仍需 AI $needsAiCount 条。',
      );
    } finally {
      database.dispose();
    }
  } on Object catch (error) {
    stderr.writeln('prepare_tag_ai_context 执行失败: $error');
    exitCode = 1;
  }
}

void _printUsage() {
  stdout.writeln('prepare_tag_ai_context.dart');
  stdout.writeln(
    '用法: dart run .agent/skills/tag-ai-process/scripts/prepare_tag_ai_context.dart [--db <path>] [--out <path>] [--limit <n>]',
  );
  stdout.writeln('默认数据库: $defaultDatabasePath');
  stdout.writeln('默认输出: ${defaultBuildPath('ai_tag_batch.json')}');
}

List<_PendingTag> _readPendingTags(Database database, int limit) {
  final result = database.select(
    '''
    SELECT id, name, translated_name, custom_translated_name, count
    FROM downloaded_tags
    WHERE category = 0 AND count > 0
    ORDER BY count DESC
    LIMIT ?
    ''',
    [limit],
  );

  return result
      .map(
        (row) => _PendingTag(
          id: row['id'] as int,
          name: cleanText(row['name'] as String?),
          translatedName: cleanText(row['translated_name'] as String?),
          customTranslatedName: cleanText(
            row['custom_translated_name'] as String?,
          ),
          count: row['count'] as int? ?? 0,
        ),
      )
      .toList();
}

List<_WorkTag> _readWorkTags(Database database) {
  final result = database.select('''
    SELECT id, name, translated_name, custom_translated_name, category, count, referenced_tag_id
    FROM downloaded_tags
    WHERE count > 0 AND (category = 1 OR name = 'バーチャルYouTuber')
    ORDER BY count DESC
    ''');

  return result
      .map(
        (row) => _WorkTag(
          id: row['id'] as int,
          name: cleanText(row['name'] as String?),
          translatedName: cleanText(row['translated_name'] as String?),
          customTranslatedName: cleanText(
            row['custom_translated_name'] as String?,
          ),
          category: row['category'] as int? ?? 0,
          count: row['count'] as int? ?? 0,
          referencedTagId: row['referenced_tag_id'] as int? ?? 0,
        ),
      )
      .toList();
}

Map<String, _WorkTag> _buildCanonicalWorks(List<_WorkTag> workTags) {
  final grouped = <int, List<_WorkTag>>{};
  for (final tag in workTags) {
    final rootId = tag.referencedTagId != 0 ? tag.referencedTagId : tag.id;
    grouped.putIfAbsent(rootId, () => []).add(tag);
  }

  final canonicalWorks = <String, _WorkTag>{};
  for (final group in grouped.values) {
    group.sort(_compareCanonicalWork);
    final canonical = group.first;
    canonicalWorks[canonical.name] = canonical;
  }
  return canonicalWorks;
}

Map<String, _ParentMatch> _buildAliasLookup(
  List<_WorkTag> workTags,
  Map<String, _WorkTag> canonicalWorks,
) {
  final grouped = <int, List<_WorkTag>>{};
  for (final tag in workTags) {
    final rootId = tag.referencedTagId != 0 ? tag.referencedTagId : tag.id;
    grouped.putIfAbsent(rootId, () => []).add(tag);
  }

  final aliasLookup = <String, _ParentMatch>{};
  for (final group in grouped.values) {
    group.sort(_compareCanonicalWork);
    final canonical = group.first;
    for (final tag in group) {
      _registerAlias(aliasLookup, tag.name, canonical.name, 'name');
      _registerAlias(
        aliasLookup,
        tag.translatedName,
        canonical.name,
        'translated_name',
      );
      _registerAlias(
        aliasLookup,
        tag.customTranslatedName,
        canonical.name,
        'custom_translated_name',
      );
    }
  }

  final vtuberCanonical = canonicalWorks['バーチャルYouTuber'];
  if (vtuberCanonical != null) {
    for (final alias in ['nijisanji', 'にじさんじ', 'hololive', 'vtuber']) {
      _registerAlias(aliasLookup, alias, vtuberCanonical.name, 'special_alias');
    }
  }

  return aliasLookup;
}

void _registerAlias(
  Map<String, _ParentMatch> aliasLookup,
  String rawValue,
  String canonicalName,
  String source,
) {
  final normalized = normalizeLookup(rawValue);
  if (normalized.isEmpty) {
    return;
  }
  aliasLookup.putIfAbsent(
    normalized,
    () => _ParentMatch(canonicalName: canonicalName, source: source),
  );
}

Map<String, Object?> _analyzePendingTag(
  _PendingTag tag,
  Map<String, _ParentMatch> aliasLookup,
) {
  final name = tag.name;
  final normalizedName = normalizeLookup(name);
  final bracketHint = extractBracketContent(name);
  final resolvedParent =
      bracketHint == null ? null : aliasLookup[normalizeLookup(bracketHint)];

  final looksMeta = _looksMeta(normalizedName);
  final looksGeneral = _looksGeneral(normalizedName);
  final looksFeature = _looksFeature(normalizedName);
  final exactWorkAlias = aliasLookup[normalizedName];
  final looksWork = exactWorkAlias != null && !_bracketPattern.hasMatch(name);
  final looksCharacter = bracketHint != null || _looksLikeCharacter(name);
  final language = detectLanguage(name);
  final hasChineseTranslation =
      isNaturalChinese(tag.customTranslatedName) ||
      isNaturalChinese(tag.translatedName) ||
      isNaturalChinese(name);

  Map<String, Object?>? deterministicSuggestion;
  if (looksMeta) {
    deterministicSuggestion = {
      'category': 5,
      'reason': 'Pixiv 常见元数据',
      'confidence': 'high',
    };
  } else if (looksGeneral) {
    deterministicSuggestion = {
      'category': 4,
      'reason': '通用构图或人数标签',
      'confidence': 'high',
    };
  } else if (looksFeature) {
    deterministicSuggestion = {
      'category': 6,
      'reason': '明显外观或服装特征',
      'confidence': 'high',
    };
  } else if (bracketHint != null && resolvedParent != null) {
    deterministicSuggestion = {
      'category': 2,
      'parent_name': resolvedParent.canonicalName,
      'reason': '角色名含作品括号',
      'confidence': 'high',
    };
  } else if (looksWork) {
    deterministicSuggestion = {
      'category': 1,
      'reason': '命中已有作品别名',
      'confidence': 'high',
    };
  }

  final aiFocus = <String>[];
  if (deterministicSuggestion == null) {
    aiFocus.add('判断分类');
  }
  if (!hasChineseTranslation &&
      (language == 'ja' || language == 'en' || language == 'mixed')) {
    aiFocus.add('确认中文译名');
  }
  if (looksCharacter && cleanText(resolvedParent?.canonicalName).isEmpty) {
    aiFocus.add('确认所属作品');
  }

  return {
    'id': tag.id,
    'name': tag.name,
    'translated_name': tag.translatedName.isEmpty ? null : tag.translatedName,
    'custom_translated_name':
        tag.customTranslatedName.isEmpty ? null : tag.customTranslatedName,
    'count': tag.count,
    'signals': {
      'language': language,
      'looks_meta': looksMeta,
      'looks_general': looksGeneral,
      'looks_feature': looksFeature,
      'looks_work': looksWork,
      'looks_character': looksCharacter,
      'has_bracket_work_hint': bracketHint != null,
      'work_hint': bracketHint,
      'resolved_parent_name': resolvedParent?.canonicalName,
      'resolved_parent_source': resolvedParent?.source,
    },
    'deterministic_suggestion': deterministicSuggestion,
    'needs_ai': aiFocus.isNotEmpty,
    'ai_focus': aiFocus,
  };
}

bool _looksMeta(String normalizedName) {
  return _metaKeywords.contains(normalizedName) ||
      normalizedName.endsWith('_request') ||
      normalizedName.endsWith('_commentary');
}

bool _looksGeneral(String normalizedName) {
  return _generalKeywords.contains(normalizedName) ||
      _countTagPattern.hasMatch(normalizedName);
}

bool _looksFeature(String normalizedName) {
  return _featureKeywords.contains(normalizedName);
}

bool _looksLikeCharacter(String name) {
  final normalized = normalizeLookup(name);
  if (normalized.isEmpty) {
    return false;
  }
  if (_looksMeta(normalized) ||
      _looksGeneral(normalized) ||
      _looksFeature(normalized)) {
    return false;
  }
  if (name.contains('_')) {
    return false;
  }
  return containsHan(name) || containsKana(name) || containsLatin(name);
}

int _compareCanonicalWork(_WorkTag a, _WorkTag b) {
  final scoreDiff = _scoreCanonicalWork(b) - _scoreCanonicalWork(a);
  if (scoreDiff != 0) {
    return scoreDiff;
  }
  return a.name.compareTo(b.name);
}

int _scoreCanonicalWork(_WorkTag tag) {
  var score = tag.count * 100;
  score += tag.name.length * 3;
  if (tag.customTranslatedName.isNotEmpty) {
    score += 25;
  }
  if (tag.translatedName.isNotEmpty) {
    score += 10;
  }
  if (RegExp(r'^[a-z0-9]{1,5}$').hasMatch(normalizeLookup(tag.name))) {
    score -= 40;
  }
  return score;
}

class _PendingTag {
  const _PendingTag({
    required this.id,
    required this.name,
    required this.translatedName,
    required this.customTranslatedName,
    required this.count,
  });

  final int id;
  final String name;
  final String translatedName;
  final String customTranslatedName;
  final int count;
}

class _WorkTag {
  const _WorkTag({
    required this.id,
    required this.name,
    required this.translatedName,
    required this.customTranslatedName,
    required this.category,
    required this.count,
    required this.referencedTagId,
  });

  final int id;
  final String name;
  final String translatedName;
  final String customTranslatedName;
  final int category;
  final int count;
  final int referencedTagId;
}

class _ParentMatch {
  const _ParentMatch({required this.canonicalName, required this.source});

  final String canonicalName;
  final String source;
}
