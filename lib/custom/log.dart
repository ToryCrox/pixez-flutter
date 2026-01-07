import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

import 'logger_pretty_printer.dart';
import 'log_file_output.dart';

final excludePaths = [
  'package:pixez/custom/log.dart',
];
final excludeMethods = <String>[];
final logMemoryOut = MemoryOutput(
  bufferSize: 500,
);
final logFileOutput = LogFileOutput();
final logFilter = ProductionFilter();
final logger = Logger(
  level: kReleaseMode ? Level.info : Level.trace,
  filter: logFilter,
  output: MultiOutput([
    if (kDebugMode) ConsoleOutput(),
    logMemoryOut,
    logFileOutput,
  ]),
  printer: LoggerPrettyPrinter(
      methodCount: 1,
      printEmojis: false,
      lineLength: 160,
      printTime: true,
      colors: !Platform.isIOS && kDebugMode,
      excludePaths: [],
      excludeFilter: (method, segment) {
        if (excludeMethods.contains(method)) {
          return true;
        }

        /// segment: package:app/src/log/log.dart:96:15
        if (excludePaths.any((e) => segment.contains(e))) {
          return true;
        }
        return false;
      }),
);

void setLoggerLevel(Level level) {
  logFilter.level = level;
}

class Log {
  final LogLevel level;
  final String title;
  final String content;
  final DateTime time = DateTime.now();

  @override
  toString() => "${level.name} $title $time \n$content\n\n";

  Log(this.level, this.title, this.content);

  /// Log a message at level [Level.debug].
  ///
  /// Corresponds to [Logger.d].
  static void d(Object message, {Object? error, StackTrace? stackTrace}) {
    logger.d(message, error: error, stackTrace: stackTrace);
  }

  /// Log a message at level [Level.info].
  ///
  /// Corresponds to [Logger.i].
  static void i(Object message, {Object? error, StackTrace? stackTrace}) {
    logger.i(message, error: error, stackTrace: stackTrace);
  }

  /// Log a message at level [Level.warning].
  ///
  /// Corresponds to [Logger.w].
  static void w(Object message, {Object? error, StackTrace? stackTrace}) {
    logger.w(message, error: error, stackTrace: stackTrace);
  }

  /// Log a message at level [Level.error].
  ///
  /// Corresponds to [Logger.e].
  static void e(Object message, {Object? error, StackTrace? stackTrace}) {
    logger.e(message, error: error, stackTrace: stackTrace);
  }

  @override
  bool operator ==(Object other) {
    if (other is! Log) return false;
    return other.level == level &&
        other.title == title &&
        other.content == content;
  }

  @override
  int get hashCode => level.hashCode ^ title.hashCode ^ content.hashCode;
}

enum LogLevel { error, warning, info, debug }
