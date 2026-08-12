import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> arguments) async {
  final values = _arguments(arguments);
  final helper = values['helper'];
  final models = values['models'];
  final datasetPath = values['dataset'];
  if (helper == null || models == null || datasetPath == null) {
    stderr.writeln(
      '用法: dart tool/manga_ocr_benchmark.dart '
      '--helper <helper> --models <模型目录> --dataset <标注.json>',
    );
    exitCode = 64;
    return;
  }

  final datasetFile = File(datasetPath);
  final dataset = jsonDecode(await datasetFile.readAsString());
  if (dataset is! Map<String, dynamic>) {
    throw const FormatException('dataset 顶层必须是 JSON object');
  }
  final pages = dataset['pages'] as List<dynamic>? ?? const [];
  final client = await _HelperClient.start(helper);
  try {
    await client.request('loadModels', {
      'modelDirectory': models,
      'detector': {
        'engineId': 'ctd_onnx',
        'version': 'beta-0.3',
        'modelFile': 'comictextdetector.pt.onnx',
      },
      'recognizer': {
        'engineId': 'baberu_ocr_int4',
        'version': 'step295000-int4-int8',
      },
    });
    var expectedBlocks = 0;
    var detectedBlocks = 0;
    var characterErrors = 0;
    var characters = 0;
    var retries = 0;
    var peakMemory = 0;
    final durations = <int>[];
    final pageResults = <Map<String, dynamic>>[];

    for (var index = 0; index < pages.length; index++) {
      final page = Map<String, dynamic>.from(pages[index] as Map);
      final imageValue = page['image'] as String;
      final imagePath =
          File(imageValue).isAbsolute
              ? imageValue
              : '${datasetFile.parent.path}${Platform.pathSeparator}$imageValue';
      final expected =
          (page['blocks'] as List<dynamic>? ?? const [])
              .map((item) => Map<String, dynamic>.from(item as Map))
              .toList();
      final stopwatch = Stopwatch()..start();
      final response = await client.request('analyzePage', {
        'imagePath': imagePath,
        'imageSha256': 'benchmark-$index',
        'pageIndex': index,
        'preprocessor': {
          'id': 'adaptive_page_preprocessor',
          'version': '1',
          'maxWorkingEdge': 2048,
          'longPageAspectRatio': 3.0,
          'tileOverlap': 0.10,
          'cropPadding': 0.12,
          'lowConfidenceThreshold': 0.45,
          'duplicateIouThreshold': 0.55,
          'highResolutionRetryCount': 1,
        },
      });
      stopwatch.stop();
      durations.add(stopwatch.elapsedMilliseconds);
      final actual =
          (response['blocks'] as List<dynamic>? ?? const [])
              .map((item) => Map<String, dynamic>.from(item as Map))
              .toList();
      expectedBlocks += expected.length;
      peakMemory =
          peakMemory > (response['peakMemoryBytes'] as int? ?? 0)
              ? peakMemory
              : response['peakMemoryBytes'] as int? ?? 0;
      retries +=
          actual
              .where((item) => item['usedHighResolutionRetry'] == true)
              .length;
      var pageDetected = 0;
      for (final groundTruth in expected) {
        final expectedRect = Map<String, dynamic>.from(
          groundTruth['bounds'] as Map,
        );
        Map<String, dynamic>? best;
        var bestIou = 0.0;
        for (final candidate in actual) {
          final iou = _iou(
            expectedRect,
            Map<String, dynamic>.from(candidate['bounds'] as Map),
          );
          if (iou > bestIou) {
            bestIou = iou;
            best = candidate;
          }
        }
        if (bestIou < 0.5 || best == null) continue;
        pageDetected++;
        detectedBlocks++;
        final expectedText = groundTruth['text'] as String? ?? '';
        final actualText = best['sourceText'] as String? ?? '';
        characters += expectedText.runes.length;
        characterErrors += _levenshtein(
          expectedText.runes.toList(),
          actualText.runes.toList(),
        );
      }
      pageResults.add({
        'image': imageValue,
        'expectedBlocks': expected.length,
        'detectedBlocks': pageDetected,
        'elapsedMs': stopwatch.elapsedMilliseconds,
      });
    }

    stdout.writeln(
      const JsonEncoder.withIndent('  ').convert({
        'pages': pages.length,
        'detectionRecall':
            expectedBlocks == 0 ? 1.0 : detectedBlocks / expectedBlocks,
        'cer': characters == 0 ? 0.0 : characterErrors / characters,
        'totalElapsedMs': durations.fold<int>(0, (sum, value) => sum + value),
        'averagePageMs':
            durations.isEmpty
                ? 0
                : durations.fold<int>(0, (sum, value) => sum + value) /
                    durations.length,
        'highResolutionRetries': retries,
        'peakMemoryBytes': peakMemory,
        'results': pageResults,
      }),
    );
  } finally {
    await client.close();
  }
}

Map<String, String> _arguments(List<String> arguments) {
  final result = <String, String>{};
  for (var index = 0; index + 1 < arguments.length; index += 2) {
    if (arguments[index].startsWith('--')) {
      result[arguments[index].substring(2)] = arguments[index + 1];
    }
  }
  return result;
}

double _iou(Map<String, dynamic> a, Map<String, dynamic> b) {
  double value(Map<String, dynamic> source, String key) =>
      (source[key] as num).toDouble();
  final left =
      value(a, 'left') > value(b, 'left') ? value(a, 'left') : value(b, 'left');
  final top =
      value(a, 'top') > value(b, 'top') ? value(a, 'top') : value(b, 'top');
  final right =
      value(a, 'right') < value(b, 'right')
          ? value(a, 'right')
          : value(b, 'right');
  final bottom =
      value(a, 'bottom') < value(b, 'bottom')
          ? value(a, 'bottom')
          : value(b, 'bottom');
  final intersection =
      (right - left).clamp(0.0, 1.0) * (bottom - top).clamp(0.0, 1.0);
  final areaA =
      (value(a, 'right') - value(a, 'left')) *
      (value(a, 'bottom') - value(a, 'top'));
  final areaB =
      (value(b, 'right') - value(b, 'left')) *
      (value(b, 'bottom') - value(b, 'top'));
  return intersection / (areaA + areaB - intersection);
}

int _levenshtein(List<int> a, List<int> b) {
  var previous = List<int>.generate(b.length + 1, (index) => index);
  for (var row = 1; row <= a.length; row++) {
    final current = List<int>.filled(b.length + 1, 0)..[0] = row;
    for (var column = 1; column <= b.length; column++) {
      final substitution =
          previous[column - 1] + (a[row - 1] == b[column - 1] ? 0 : 1);
      final insertion = current[column - 1] + 1;
      final deletion = previous[column] + 1;
      current[column] = [
        substitution,
        insertion,
        deletion,
      ].reduce((left, right) => left < right ? left : right);
    }
    previous = current;
  }
  return previous.last;
}

class _HelperClient {
  final Process process;
  final StreamIterator<String> lines;
  var _request = 0;

  _HelperClient(this.process, this.lines);

  static Future<_HelperClient> start(String helper) async {
    final process = await Process.start(helper, const ['--jsonl']);
    return _HelperClient(
      process,
      StreamIterator(
        process.stdout.transform(utf8.decoder).transform(const LineSplitter()),
      ),
    );
  }

  Future<Map<String, dynamic>> request(
    String command,
    Map<String, dynamic> payload,
  ) async {
    final requestId = 'benchmark-${++_request}';
    process.stdin.writeln(
      jsonEncode({
        'protocolVersion': 1,
        'requestId': requestId,
        'command': command,
        'payload': payload,
      }),
    );
    await process.stdin.flush();
    while (await lines.moveNext()) {
      final response = jsonDecode(lines.current) as Map<String, dynamic>;
      if (response['requestId'] != requestId ||
          response['type'] == 'progress') {
        continue;
      }
      if (response['ok'] != true) {
        throw StateError(response['error'] as String? ?? 'helper 请求失败');
      }
      return Map<String, dynamic>.from(response['result'] as Map? ?? const {});
    }
    throw StateError('helper 提前退出');
  }

  Future<void> close() async {
    try {
      await request('shutdown', const {});
    } finally {
      process.kill();
    }
  }
}
