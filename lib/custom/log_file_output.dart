import 'dart:convert';
import 'dart:io';

import 'package:intl/intl.dart';
import 'package:logger/logger.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// 自定义文件日志输出
/// - 只输出 Level.info 及以上级别的日志
/// - 文件最大 10MB，超出后创建带时间戳的新文件
/// - 文件按天命名：pixez_YYYY-MM-DD.log
class LogFileOutput extends LogOutput {
  static const int maxFileSize = 10 * 1024 * 1024; // 10MB

  final String logDirectory;
  final Encoding encoding;
  IOSink? _sink;
  File? _currentFile;
  String? _currentFilePath;
  String? _todayDate;

  LogFileOutput({this.encoding = utf8}) : logDirectory = '';

  @override
  Future<void> init() async {
    final docDir = await getApplicationDocumentsDirectory();
    final logsDir = Directory(path.join(docDir.path, 'pixez', 'logs'));
    if (!await logsDir.exists()) {
      await logsDir.create(recursive: true);
    }
    await _initNewFile();
  }

  Future<void> _initNewFile() async {
    final docDir = await getApplicationDocumentsDirectory();
    final logsDir = path.join(docDir.path, 'pixez', 'logs');

    final now = DateTime.now();
    _todayDate = DateFormat('yyyy-MM-dd').format(now);
    _currentFilePath = path.join(logsDir, 'pixez_$_todayDate.log');
    _currentFile = File(_currentFilePath!);

    // 检查今日文件是否已存在且超出大小限制
    if (await _currentFile!.exists()) {
      final size = await _currentFile!.length();
      if (size >= maxFileSize) {
        await _rotateFile();
      }
    }

    _sink = _currentFile!.openWrite(
      mode: FileMode.writeOnlyAppend,
      encoding: encoding,
    );
  }

  Future<void> _checkFileSizeAndRotate() async {
    if (_currentFile == null) return;

    final size = await _currentFile!.length();
    if (size >= maxFileSize) {
      await _rotateFile();
    }
  }

  Future<void> _rotateFile() async {
    await _sink?.flush();
    await _sink?.close();

    // 创建带时间戳的新文件名：pixez_YYYY-MM-DD_HHMMSS.log
    final now = DateTime.now();
    final timestamp = DateFormat('HHmmss').format(now);
    final docDir = await getApplicationDocumentsDirectory();
    final logsDir = path.join(docDir.path, 'pixez', 'logs');
    final newPath = path.join(logsDir, 'pixez_$_todayDate\_$timestamp.log');

    // 重命名当前文件
    if (await _currentFile!.exists()) {
      await _currentFile!.rename(newPath);
    }

    // 创建新文件
    await _initNewFile();
  }

  Future<void> _checkDayChange() async {
    final now = DateTime.now();
    final today = DateFormat('yyyy-MM-dd').format(now);

    if (today != _todayDate) {
      // 日期变更，关闭旧文件，创建新文件
      await _sink?.flush();
      await _sink?.close();
      await _initNewFile();
    }
  }

  @override
  void output(OutputEvent event) {
    // 只输出 info 及以上级别
    if (event.level.index < Level.info.index) {
      return;
    }

    // 检查日期变更
    _checkDayChange();

    // 使用原始日志内容，不使用 PrettyPrinter 格式化的内容
    final message = _formatMessage(event);
    _sink?.writeln(message);

    // 检查文件大小
    _checkFileSizeAndRotate();
  }

  String _formatMessage(OutputEvent event) {
    final time = DateFormat('HH:mm:ss.SSS').format(event.origin.time);
    final level = event.level.name.toUpperCase();
    final message = _stringifyMessage(event.origin.message);

    final buffer = StringBuffer();
    buffer.write('[$time] [$level] $message');

    if (event.origin.error != null) {
      buffer.write('\nError: ${_formatError(event.origin.error)}');
    }

    if (event.origin.stackTrace != null) {
      buffer.write('\nStackTrace:\n${event.origin.stackTrace}');
    }

    return buffer.toString();
  }

  String _formatError(Object? error) {
    if (error == null) return '';
    // 使用 error 的 toString() 方法，它会包含错误类型和消息
    return error.toString();
  }

  String _stringifyMessage(dynamic message) {
    final finalMessage = message is Function ? message() : message;
    if (finalMessage is Map || finalMessage is Iterable) {
      const encoder = JsonEncoder.withIndent('  ', _toEncodableFallback);
      return encoder.convert(finalMessage);
    } else {
      return finalMessage.toString();
    }
  }

  static Object _toEncodableFallback(dynamic object) {
    return object.toString();
  }

  @override
  Future<void> destroy() async {
    await _sink?.flush();
    await _sink?.close();
  }
}
