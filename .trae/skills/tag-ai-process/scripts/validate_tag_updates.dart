import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import 'tag_ai_shared.dart';

const _allowedCategories = {0, 1, 2, 4, 5, 6};

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
    final inputPath =
        cleanText(options['input']).isEmpty
            ? defaultBuildPath('tag_updates.json')
            : cleanText(options['input']);
    final reportPath =
        cleanText(options['report']).isEmpty
            ? defaultBuildPath('tag_updates.validation.json')
            : cleanText(options['report']);
    final strict = hasFlag(options, 'strict');

    final issues = <Map<String, Object?>>[];
    final inputFile = File(inputPath);
    if (!inputFile.existsSync()) {
      issues.add({
        'level': 'error',
        'code': 'INPUT_NOT_FOUND',
        'message': '找不到输入文件: $inputPath',
      });
      _writeReport(reportPath, false, strict, issues);
      exitCode = 1;
      return;
    }

    final root = jsonDecode(inputFile.readAsStringSync());
    if (root is! Map<String, Object?>) {
      throw const FormatException('根节点必须是 JSON 对象');
    }

    final version = root['version'];
    if (version is! int) {
      issues.add({
        'level': 'error',
        'code': 'INVALID_VERSION',
        'message': 'version 必须是整数',
      });
    }

    final updates = root['updates'];
    if (updates is! List) {
      issues.add({
        'level': 'error',
        'code': 'INVALID_UPDATES',
        'message': 'updates 必须是数组',
      });
      _writeReport(reportPath, false, strict, issues);
      exitCode = 1;
      return;
    }

    final database = sqlite3.open(dbPath);
    try {
      final tagRows = _readTagRows(database);
      final tagByName = {for (final tag in tagRows) tag.name: tag};
      final tagById = {for (final tag in tagRows) tag.id: tag};
      final seenNames = <String>{};

      for (var index = 0; index < updates.length; index++) {
        final rawItem = updates[index];
        if (rawItem is! Map<String, Object?>) {
          issues.add({
            'level': 'error',
            'code': 'INVALID_ITEM',
            'message': 'updates[$index] 必须是对象',
          });
          continue;
        }
        _validateItem(rawItem, index, tagByName, tagById, seenNames, issues);
      }
    } finally {
      database.dispose();
    }

    final hasErrors = issues.any((issue) => issue['level'] == 'error');
    final hasWarnings = issues.any((issue) => issue['level'] == 'warning');
    final valid = !hasErrors && (!strict || !hasWarnings);
    _writeReport(reportPath, valid, strict, issues);

    stdout.writeln(
      '校验完成: ${valid ? '通过' : '未通过'}，错误 ${issues.where((e) => e['level'] == 'error').length} 条，警告 ${issues.where((e) => e['level'] == 'warning').length} 条。',
    );
    stdout.writeln('报告已写入: $reportPath');
    if (!valid) {
      exitCode = 1;
    }
  } on Object catch (error) {
    stderr.writeln('validate_tag_updates 执行失败: $error');
    exitCode = 1;
  }
}

void _printUsage() {
  stdout.writeln('validate_tag_updates.dart');
  stdout.writeln(
    '用法: dart run .agent/skills/tag-ai-process/scripts/validate_tag_updates.dart [--db <path>] [--input <path>] [--report <path>] [--strict]',
  );
  stdout.writeln('默认输入: ${defaultBuildPath('tag_updates.json')}');
  stdout.writeln('默认报告: ${defaultBuildPath('tag_updates.validation.json')}');
}

List<_TagRow> _readTagRows(Database database) {
  final result = database.select('''
    SELECT id, name, translated_name, custom_translated_name, category, parent_id, referenced_tag_id
    FROM downloaded_tags
    ''');

  return result
      .map(
        (row) => _TagRow(
          id: row['id'] as int,
          name: cleanText(row['name'] as String?),
          translatedName: cleanText(row['translated_name'] as String?),
          customTranslatedName: cleanText(
            row['custom_translated_name'] as String?,
          ),
          category: row['category'] as int? ?? 0,
          parentId: row['parent_id'] as int? ?? 0,
          referencedTagId: row['referenced_tag_id'] as int? ?? 0,
        ),
      )
      .toList();
}

void _validateItem(
  Map<String, Object?> item,
  int index,
  Map<String, _TagRow> tagByName,
  Map<int, _TagRow> tagById,
  Set<String> seenNames,
  List<Map<String, Object?>> issues,
) {
  final name = cleanText(item['name'] as String?);
  if (name.isEmpty) {
    issues.add({
      'level': 'error',
      'code': 'EMPTY_NAME',
      'message': 'updates[$index].name 不能为空',
      'index': index,
    });
    return;
  }

  if (!seenNames.add(name)) {
    issues.add({
      'level': 'error',
      'code': 'DUPLICATE_NAME',
      'message': '标签重复出现: $name',
      'index': index,
      'name': name,
    });
  }

  final currentTag = tagByName[name];
  if (currentTag == null) {
    issues.add({
      'level': 'error',
      'code': 'TAG_NOT_FOUND',
      'message': '数据库中不存在标签: $name',
      'index': index,
      'name': name,
    });
    return;
  }

  final category = item['category'];
  if (category != null && category is! int) {
    issues.add({
      'level': 'error',
      'code': 'INVALID_CATEGORY_TYPE',
      'message': 'category 必须是整数',
      'index': index,
      'name': name,
    });
  } else if (category is int && !_allowedCategories.contains(category)) {
    issues.add({
      'level': 'error',
      'code': 'INVALID_CATEGORY_VALUE',
      'message': 'category 不在允许范围内: $category',
      'index': index,
      'name': name,
    });
  }

  final customTranslatedName =
      item['custom_translated_name'] == null
          ? ''
          : cleanText(item['custom_translated_name'] as String?);
  final parentName =
      item['parent_name'] == null
          ? ''
          : cleanText(item['parent_name'] as String?);
  final reason =
      item['reason'] == null ? '' : cleanText(item['reason'] as String?);

  if (reason.length > 20) {
    issues.add({
      'level': 'warning',
      'code': 'REASON_TOO_LONG',
      'message': 'reason 建议控制在 20 字以内',
      'index': index,
      'name': name,
      'value': reason,
    });
  }

  if (customTranslatedName.isNotEmpty &&
      isNaturalChinese(name) &&
      customTranslatedName == name) {
    issues.add({
      'level': 'warning',
      'code': 'REDUNDANT_TRANSLATION',
      'message': '中文标签通常不需要把 custom_translated_name 设为原名',
      'index': index,
      'name': name,
    });
  }

  if (customTranslatedName.isNotEmpty &&
      customTranslatedName == currentTag.customTranslatedName) {
    issues.add({
      'level': 'warning',
      'code': 'UNCHANGED_TRANSLATION',
      'message': 'custom_translated_name 与数据库当前值一致',
      'index': index,
      'name': name,
    });
  }

  String? resolvedParentName;
  if (parentName.isNotEmpty) {
    final parentTag = tagByName[parentName];
    if (parentTag == null) {
      issues.add({
        'level': 'error',
        'code': 'PARENT_NOT_FOUND',
        'message': 'parent_name 不存在于数据库: $parentName',
        'index': index,
        'name': name,
      });
    } else {
      resolvedParentName = _resolveMainTagName(parentTag, tagById);
      if (resolvedParentName != parentName) {
        issues.add({
          'level': 'warning',
          'code': 'PARENT_NOT_CANONICAL',
          'message': 'parent_name 不是主标签，建议改为: $resolvedParentName',
          'index': index,
          'name': name,
          'value': parentName,
        });
      }
      if (resolvedParentName == name ||
          resolvedParentName == _resolveMainTagName(currentTag, tagById)) {
        issues.add({
          'level': 'error',
          'code': 'SELF_PARENT',
          'message': 'parent_name 不能指向标签自身或其同义主标签',
          'index': index,
          'name': name,
        });
      }

      final resolvedParent = tagByName[resolvedParentName];
      if (resolvedParent != null &&
          resolvedParent.category != 1 &&
          resolvedParent.name != 'バーチャルYouTuber') {
        issues.add({
          'level': 'warning',
          'code': 'PARENT_NOT_WORK',
          'message': 'parent_name 通常应为作品主标签或 バーチャルYouTuber',
          'index': index,
          'name': name,
          'value': resolvedParentName,
        });
      }
    }
  }

  final currentParentName =
      currentTag.parentId == 0
          ? ''
          : (tagById[currentTag.parentId]?.name ?? '');
  final hasAnyChange =
      (category is int && category != currentTag.category) ||
      (customTranslatedName.isNotEmpty &&
          customTranslatedName != currentTag.customTranslatedName) ||
      (parentName.isNotEmpty && resolvedParentName != currentParentName);

  if (!hasAnyChange) {
    issues.add({
      'level': 'warning',
      'code': 'NO_EFFECTIVE_CHANGE',
      'message': '该项不会对数据库产生实际变更',
      'index': index,
      'name': name,
    });
  }
}

String _resolveMainTagName(_TagRow tag, Map<int, _TagRow> tagById) {
  if (tag.referencedTagId == 0) {
    return tag.name;
  }
  return tagById[tag.referencedTagId]?.name ?? tag.name;
}

void _writeReport(
  String reportPath,
  bool valid,
  bool strict,
  List<Map<String, Object?>> issues,
) {
  ensureParentDirectory(reportPath);
  final payload = {
    'version': 1,
    'generated_at': DateTime.now().toIso8601String(),
    'valid': valid,
    'strict': strict,
    'error_count': issues.where((issue) => issue['level'] == 'error').length,
    'warning_count':
        issues.where((issue) => issue['level'] == 'warning').length,
    'issues': issues,
  };

  final encoder = const JsonEncoder.withIndent('  ');
  File(reportPath).writeAsStringSync('${encoder.convert(payload)}\n');
}

class _TagRow {
  const _TagRow({
    required this.id,
    required this.name,
    required this.translatedName,
    required this.customTranslatedName,
    required this.category,
    required this.parentId,
    required this.referencedTagId,
  });

  final int id;
  final String name;
  final String translatedName;
  final String customTranslatedName;
  final int category;
  final int parentId;
  final int referencedTagId;
}
