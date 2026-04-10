import 'dart:io';

const String defaultDatabasePath = r'E:\Pictures\pixez_downloads\download.db';

Map<String, String?> parseCliArgs(List<String> args) {
  final options = <String, String?>{};

  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '--help' || arg == '-h') {
      options['help'] = 'true';
      continue;
    }
    if (!arg.startsWith('--')) {
      throw FormatException('未知参数格式: $arg');
    }

    final equalIndex = arg.indexOf('=');
    if (equalIndex != -1) {
      final key = arg.substring(2, equalIndex);
      final value = arg.substring(equalIndex + 1);
      options[key] = value;
      continue;
    }

    final key = arg.substring(2);
    if (i + 1 < args.length && !args[i + 1].startsWith('--')) {
      options[key] = args[++i];
    } else {
      options[key] = 'true';
    }
  }

  return options;
}

bool hasFlag(Map<String, String?> options, String key) {
  return options[key] == 'true';
}

String findRepoRoot() {
  var current = File.fromUri(Platform.script).parent;
  while (true) {
    if (File(joinPath(current.path, 'pubspec.yaml')).existsSync()) {
      return current.path;
    }
    final parent = current.parent;
    if (parent.path == current.path) {
      throw StateError('无法从脚本路径定位仓库根目录');
    }
    current = parent;
  }
}

String joinPath(String base, String child) {
  if (base.isEmpty) return child;
  if (base.endsWith(Platform.pathSeparator)) {
    return '$base$child';
  }
  return '$base${Platform.pathSeparator}$child';
}

String joinPaths(Iterable<String> segments) {
  return segments.reduce(joinPath);
}

String defaultBuildPath(String fileName) {
  return joinPaths([findRepoRoot(), 'build', fileName]);
}

void ensureParentDirectory(String filePath) {
  File(filePath).parent.createSync(recursive: true);
}

String cleanText(String? value) {
  return value?.trim() ?? '';
}

bool isNullOrEmpty(String? value) {
  return cleanText(value).isEmpty;
}

String normalizeLookup(String value) {
  return value
      .trim()
      .toLowerCase()
      .replaceAll('（', '(')
      .replaceAll('）', ')')
      .replaceAll(RegExp(r'\s+'), '')
      .replaceAll('・', '')
      .replaceAll('·', '');
}

bool containsHan(String value) {
  return RegExp(r'[\u3400-\u9FFF]').hasMatch(value);
}

bool containsKana(String value) {
  return RegExp(r'[\u3040-\u30FF]').hasMatch(value);
}

bool containsLatin(String value) {
  return RegExp(r'[A-Za-z]').hasMatch(value);
}

bool isNaturalChinese(String value) {
  final text = cleanText(value);
  if (text.isEmpty || !containsHan(text)) {
    return false;
  }
  if (containsKana(text)) {
    return false;
  }
  return !RegExp(r'[A-Za-z]').hasMatch(text);
}

String detectLanguage(String value) {
  final text = cleanText(value);
  if (text.isEmpty) {
    return 'empty';
  }
  final hasHan = containsHan(text);
  final hasKana = containsKana(text);
  final hasLatinChar = containsLatin(text);

  if (hasKana && !hasLatinChar) {
    return hasHan ? 'ja_mixed' : 'ja';
  }
  if (hasHan && !hasKana && !hasLatinChar) {
    return 'zh';
  }
  if (hasLatinChar && !hasHan && !hasKana) {
    return 'en';
  }
  if (hasHan || hasKana || hasLatinChar) {
    return 'mixed';
  }
  return 'other';
}

String? extractBracketContent(String value) {
  final match = RegExp(r'^.+[（(]([^（）()]+)[）)]$').firstMatch(value.trim());
  return match?.group(1)?.trim();
}

String? firstNonEmpty(Iterable<String?> values) {
  for (final value in values) {
    final text = cleanText(value);
    if (text.isNotEmpty) {
      return text;
    }
  }
  return null;
}
