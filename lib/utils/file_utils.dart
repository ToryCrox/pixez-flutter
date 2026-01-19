
import 'dart:io';
import 'package:open_file/open_file.dart';

class FileUtils {
  /// 打开文件或文件夹
  /// 如果是 Windows 且是文件夹，尝试使用 cmd start 启动以支持第三方文件管理器（如 One Commander）的默认设置
  static Future<void> openFileOrDirectory(String path) async {
    if (Platform.isWindows) {
      final type = await FileSystemEntity.type(path);
      if (type == FileSystemEntityType.directory) {
         // 使用 cmd start 打开文件夹，start 命令如果不带参数会遵循 ShellExecute 的默认动作，
         // 如果传递了空标题和路径，也能正确唤起默认文件管理器。
         // 注意：start 命令的第一个参数如果带引号会被视为窗口标题，所以这里可以留空。
         // Process.run('cmd', ['/c', 'start', '', path]); 
         // 这里的 path 如果包含空格，Process.run 的参数解析通常会处理好，
         // 但为了保险，cmd /c 的行为有时候比较怪。
         // 简单测试：start "" "path with spaces" 是标准写法。
         await Process.run('cmd', ['/c', 'start', '', path]);
         return;
      }
    }
    // 其他情况（非 Windows，或 Windows 下的文件）使用 open_file
    await OpenFile.open(path);
  }
}
