import 'package:pixez/manga_ocr/manga_ocr_models.dart';

abstract interface class MangaTextDetector {
  String get id;
  String get version;
  Map<String, dynamic> get runtimeConfiguration;
}

abstract interface class MangaTextRecognizer {
  String get id;
  String get version;
  Map<String, dynamic> get runtimeConfiguration;
}

class OnnxMangaTextDetector implements MangaTextDetector {
  @override
  final String id;
  @override
  final String version;
  final String modelFile;

  const OnnxMangaTextDetector({
    this.id = mangaOcrDefaultDetectorId,
    this.version = 'beta-0.3',
    this.modelFile = 'comictextdetector.pt.onnx',
  });

  @override
  Map<String, dynamic> get runtimeConfiguration => {
    'engineId': id,
    'version': version,
    'modelFile': modelFile,
  };
}

class BaberuOcrRecognizer implements MangaTextRecognizer {
  @override
  final String id;
  @override
  final String version;

  const BaberuOcrRecognizer({
    this.id = mangaOcrDefaultRecognizerId,
    this.version = 'step295000-int4-int8',
  });

  @override
  Map<String, dynamic> get runtimeConfiguration => {
    'engineId': id,
    'version': version,
    'visionModel': 'vision_int4.onnx',
    'decoderPrefillModel': 'decoder_prefill_int8.onnx',
    'decoderStepModel': 'decoder_step_int8.onnx',
    'vocabulary': 'vocab.json',
  };
}

class MangaOcrEngineRegistry {
  MangaOcrEngineRegistry._();

  static final instance =
      MangaOcrEngineRegistry._()
        ..registerDetector(const OnnxMangaTextDetector())
        ..registerRecognizer(const BaberuOcrRecognizer());

  final Map<String, MangaTextDetector> _detectors = {};
  final Map<String, MangaTextRecognizer> _recognizers = {};

  Iterable<MangaTextDetector> get detectors => _detectors.values;
  Iterable<MangaTextRecognizer> get recognizers => _recognizers.values;

  void registerDetector(MangaTextDetector detector) {
    _detectors[detector.id] = detector;
  }

  void registerRecognizer(MangaTextRecognizer recognizer) {
    _recognizers[recognizer.id] = recognizer;
  }

  MangaTextDetector detector(String id) {
    final value = _detectors[id];
    if (value == null) throw StateError('未注册 OCR 检测器：$id');
    return value;
  }

  MangaTextRecognizer recognizer(String id) {
    final value = _recognizers[id];
    if (value == null) throw StateError('未注册 OCR 识别器：$id');
    return value;
  }
}
