
import 'dart:io';
import 'package:open_file/open_file.dart';

class FileUtils {
  /// 打开文件或文件夹
  /// 针对 Windows 下 Unicode 路径（如 ④ 等特殊字符）导致的 cmd 截断问题：
  /// 1. 不使用 explorer.exe，因为它会强制使用系统资源管理器，跳过三方管理器。
  /// 2. 不使用 cmd /c start，因为它存在旧版编码问题，不支持复杂的 Unicode。
  /// 3. 使用 powershell -Command Start-Process，它既支持 Unicode，又能尊重系统默认关联。
  static Future<void> openFileOrDirectory(String path) async {
    if (Platform.isWindows) {
      final type = await FileSystemEntity.type(path);
      if (type == FileSystemEntityType.directory) {
        // 使用 powershell 的 Start-Process。
        // 它与 cmd 的 start 命令行为一致（通过 ShellExecute 唤起），能支持三方文件管理器。
        // 同时 powershell 是原生 Unicode 环境，不会截断 ④ 等特殊字符。
        // 我们需要对路径中的单引号进行转义，防止 powershell 语法错误。
        final escapedPath = path.replaceAll("'", "''");
        await Process.run('powershell', [
          '-NoProfile',
          '-Command',
          "Start-Process -FilePath '$escapedPath'"
        ]);
        return;
      }
    }
    // 其他情况（非 Windows，或 Windows 下的文件）使用 open_file
    await OpenFile.open(path);
  }
}
