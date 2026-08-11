import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:pixez/custom/log.dart';

class WebpToolCheck {
  final String? executablePath;
  final String? version;
  final String? error;

  const WebpToolCheck({this.executablePath, this.version, this.error});

  bool get isAvailable => executablePath != null && error == null;
}

/// 应用内 cwebp 命令行工具的统一调用入口。
class CwebpTool {
  final String executablePath;

  const CwebpTool._(this.executablePath);

  static Future<CwebpTool?> resolve({String? preferredPath}) async {
    if (preferredPath != null && await File(preferredPath).exists()) {
      return CwebpTool._(preferredPath);
    }
    if (!Platform.isWindows && !Platform.isMacOS) return null;

    final fileName = Platform.isWindows ? 'cwebp.exe' : 'cwebp-macos';
    final executableDir = path.dirname(Platform.resolvedExecutable);
    final possiblePaths = <String>[
      if (Platform.isWindows)
        path.join(
          executableDir,
          'data',
          'flutter_assets',
          'assets',
          'executables',
          fileName,
        )
      else ...[
        // Flutter macOS 将 flutter_assets 放在 App.framework 的 Resources 中。
        path.normalize(
          path.join(
            executableDir,
            '..',
            'Frameworks',
            'App.framework',
            'Versions',
            'A',
            'Resources',
            'flutter_assets',
            'assets',
            'executables',
            fileName,
          ),
        ),
        // 兼容未来 Flutter 布局调整或手动分发时的传统 Resources 位置。
        path.normalize(
          path.join(
            executableDir,
            '..',
            'Resources',
            'flutter_assets',
            'assets',
            'executables',
            fileName,
          ),
        ),
      ],
      path.join(executableDir, 'assets', 'executables', fileName),
      path.join(Directory.current.path, 'assets', 'executables', fileName),
    ];
    for (final candidate in possiblePaths) {
      if (await File(candidate).exists()) return CwebpTool._(candidate);
    }
    return null;
  }

  static Future<WebpToolCheck> checkAvailability() async {
    final tool = await resolve();
    if (tool == null) {
      return const WebpToolCheck(error: '未找到随应用提供的 cwebp 工具');
    }
    try {
      final result = await tool.run(const ['-version']);
      if (result.exitCode != 0) {
        return WebpToolCheck(error: 'cwebp 无法执行：${result.stderr}');
      }
      return WebpToolCheck(
        executablePath: tool.executablePath,
        version: result.stdout.toString().trim(),
      );
    } catch (e, stackTrace) {
      Log.e('检查 cwebp 工具失败', error: e, stackTrace: stackTrace);
      return WebpToolCheck(error: 'cwebp 无法执行：$e');
    }
  }

  /// 统一执行 cwebp；调用方仅需传入 cwebp 原生参数。
  Future<ProcessResult> run(List<String> arguments) {
    return Process.run(executablePath, arguments, runInShell: false);
  }
}
