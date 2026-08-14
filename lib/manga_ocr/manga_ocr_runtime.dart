import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:pixez/custom/log.dart';
import 'package:pixez/manga_ocr/manga_ocr_models.dart';

class MangaOcrRuntimeException implements Exception {
  final String message;
  const MangaOcrRuntimeException(this.message);

  @override
  String toString() => message;
}

class MangaOcrRuntimeProgress {
  final String requestId;
  final MangaOcrStage stage;
  final int completed;
  final int total;
  final String? message;

  const MangaOcrRuntimeProgress({
    required this.requestId,
    required this.stage,
    required this.completed,
    required this.total,
    this.message,
  });
}

abstract interface class MangaOcrRuntime {
  Stream<MangaOcrRuntimeProgress> get progress;

  Future<Map<String, dynamic>> capabilities();
  Future<void> loadModels({
    required String modelDirectory,
    required Map<String, dynamic> detector,
    required Map<String, dynamic> recognizer,
  });
  Future<Map<String, dynamic>> analyzePage(Map<String, dynamic> payload);
  Future<void> cancel(String requestId);
  Future<void> shutdown();
}

class MangaOcrProcessRuntime implements MangaOcrRuntime {
  final String? helperPath;
  final Duration requestTimeout;
  Process? _process;
  StreamSubscription<String>? _stdoutSubscription;
  StreamSubscription<String>? _stderrSubscription;
  final Map<String, Completer<Map<String, dynamic>>> _pending = {};
  final _progressController =
      StreamController<MangaOcrRuntimeProgress>.broadcast();
  int _nextRequestId = 0;
  String? _loadedModelSignature;

  MangaOcrProcessRuntime({
    this.helperPath,
    this.requestTimeout = const Duration(minutes: 5),
  });

  @override
  Stream<MangaOcrRuntimeProgress> get progress => _progressController.stream;

  @override
  Future<Map<String, dynamic>> capabilities() =>
      _request('capabilities', const {});

  @override
  Future<void> loadModels({
    required String modelDirectory,
    required Map<String, dynamic> detector,
    required Map<String, dynamic> recognizer,
  }) async {
    final signature = jsonEncode({
      'modelDirectory': modelDirectory,
      'detector': detector,
      'recognizer': recognizer,
    });
    if (_process != null && _loadedModelSignature == signature) {
      Log.d(() => '复用已加载的漫画 OCR 模型');
      return;
    }
    await _request('loadModels', {
      'modelDirectory': modelDirectory,
      'detector': detector,
      'recognizer': recognizer,
    });
    _loadedModelSignature = signature;
  }

  @override
  Future<Map<String, dynamic>> analyzePage(Map<String, dynamic> payload) =>
      _request('analyzePage', payload);

  @override
  Future<void> cancel(String requestId) async {
    await _request('cancel', {'targetRequestId': requestId});
  }

  @override
  Future<void> shutdown() async {
    final process = _process;
    if (process == null) return;
    try {
      await _request('shutdown', const {}, timeout: const Duration(seconds: 2));
    } catch (_) {
      process.kill();
    }
    await _resetProcess(const MangaOcrRuntimeException('OCR helper 已关闭'));
  }

  Future<Map<String, dynamic>> _request(
    String method,
    Map<String, dynamic> payload, {
    Duration? timeout,
  }) async {
    final process = await _ensureProcess();
    final requestId = 'dart-${++_nextRequestId}';
    final completer = Completer<Map<String, dynamic>>();
    _pending[requestId] = completer;
    Log.d(() => '漫画 OCR helper 发送请求: method=$method, requestId=$requestId');
    try {
      process.stdin.writeln(
        jsonEncode({
          'protocolVersion': mangaOcrProtocolVersion,
          'requestId': requestId,
          'method': method,
          'payload': payload,
        }),
      );
      // Windows 下 pipe 写入不能依赖下一次事件循环触发，显式刷新可以让
      // helper 立即开始处理，也便于把卡顿稳定定位为 helper 内部的问题。
      await process.stdin.flush();
    } catch (error, stackTrace) {
      Log.e(
        '漫画 OCR helper 请求写入失败: method=$method, requestId=$requestId',
        error: error,
        stackTrace: stackTrace,
      );
      await _resetProcess(
        MangaOcrRuntimeException('无法向 OCR helper 发送请求：$method'),
      );
      rethrow;
    }
    try {
      final result = await completer.future.timeout(timeout ?? requestTimeout);
      Log.d(() => '漫画 OCR helper 请求完成: method=$method, requestId=$requestId');
      return result;
    } on TimeoutException {
      Log.e(
        '漫画 OCR helper 请求超时: method=$method, requestId=$requestId, '
        'timeout=${timeout ?? requestTimeout}',
      );
      await _resetProcess(MangaOcrRuntimeException('OCR helper 请求超时：$method'));
      rethrow;
    } finally {
      _pending.remove(requestId);
    }
  }

  Future<Process> _ensureProcess() async {
    final current = _process;
    if (current != null) return current;
    final resolved = helperPath ?? await resolveHelperPath();
    if (resolved == null) {
      Log.e('未找到漫画 OCR helper 可执行文件');
      throw const MangaOcrRuntimeException(
        '未找到 OCR helper。请先构建并打包 manga-ocr-helper。',
      );
    }
    if (!Platform.isWindows) {
      await Process.run('chmod', ['755', resolved], runInShell: false);
    }
    Log.i(() => '启动漫画 OCR helper: $resolved');
    final process = await Process.start(resolved, const [
      '--jsonl',
    ], runInShell: false);
    _process = process;
    _stdoutSubscription = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_handleLine);
    _stderrSubscription = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) => Log.w(() => 'manga-ocr-helper: $line'));
    unawaited(
      process.exitCode.then((code) {
        if (identical(_process, process)) {
          Log.e(() => '漫画 OCR helper 异常退出: code=$code');
          _resetProcess(MangaOcrRuntimeException('OCR helper 异常退出：$code'));
        }
      }),
    );
    return process;
  }

  void _handleLine(String line) {
    try {
      final message = jsonDecode(line) as Map<String, dynamic>;
      if (message['protocolVersion'] != mangaOcrProtocolVersion) {
        throw const FormatException('helper 协议版本不匹配');
      }
      final requestId = message['requestId'] as String? ?? '';
      if (message['type'] == 'progress') {
        Log.d(
          () =>
              '漫画 OCR helper 进度: requestId=$requestId, '
              'stage=${message['stage']}, '
              '${message['completed']}/${message['total']}, '
              'message=${message['message']}',
        );
        _progressController.add(
          MangaOcrRuntimeProgress(
            requestId: requestId,
            stage: MangaOcrStage.values.firstWhere(
              (value) => value.name == message['stage'],
              orElse: () => MangaOcrStage.preparing,
            ),
            completed: message['completed'] as int? ?? 0,
            total: message['total'] as int? ?? 0,
            message: message['message'] as String?,
          ),
        );
        return;
      }
      final completer = _pending[requestId];
      if (completer == null || completer.isCompleted) return;
      if (message['ok'] == true) {
        completer.complete(
          Map<String, dynamic>.from(message['result'] as Map? ?? const {}),
        );
      } else {
        Log.e(
          () =>
              '漫画 OCR helper 返回错误: requestId=$requestId, '
              'error=${message['error']}',
        );
        completer.completeError(
          MangaOcrRuntimeException(
            message['error'] as String? ?? 'OCR helper 返回未知错误',
          ),
        );
      }
    } catch (error, stackTrace) {
      Log.e(
        '漫画 OCR helper 输出解析失败: line=$line',
        error: error,
        stackTrace: stackTrace,
      );
      unawaited(
        _resetProcess(MangaOcrRuntimeException('OCR helper 输出无效：$error')),
      );
    }
  }

  Future<void> _resetProcess(Object error) async {
    final process = _process;
    Log.w(() => '重置漫画 OCR helper: reason=$error, pending=${_pending.length}');
    _process = null;
    _loadedModelSignature = null;
    process?.kill();
    await _stdoutSubscription?.cancel();
    await _stderrSubscription?.cancel();
    _stdoutSubscription = null;
    _stderrSubscription = null;
    final pending = _pending.values.toList();
    _pending.clear();
    for (final completer in pending) {
      if (!completer.isCompleted) completer.completeError(error);
    }
  }

  static Future<String?> resolveHelperPath() async {
    if (!Platform.isMacOS && !Platform.isWindows) return null;
    final fileName =
        Platform.isWindows
            ? 'manga-ocr-helper-windows-x64.exe'
            : 'manga-ocr-helper-macos-arm64';
    final executableDir = path.dirname(Platform.resolvedExecutable);
    final candidates = <String>[
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
      path.join(Directory.current.path, 'assets', 'executables', fileName),
      path.join(
        Directory.current.path,
        'native',
        'manga_ocr_helper',
        'target',
        'release',
        Platform.isWindows ? 'manga-ocr-helper.exe' : 'manga-ocr-helper',
      ),
    ];
    for (final candidate in candidates) {
      if (await File(candidate).exists()) return candidate;
    }
    return null;
  }
}
