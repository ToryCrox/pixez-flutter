import 'dart:math' as math;

const mangaOcrProtocolVersion = 1;
const mangaOcrPreprocessorId = 'adaptive_page_preprocessor';
const mangaOcrPreprocessorVersion = '1';
const mangaOcrDefaultDetectorId = 'ctd_onnx';
const mangaOcrDefaultRecognizerId = 'baberu_ocr_int4';

enum MangaTextDirection {
  horizontal,
  vertical,
  unknown;

  static MangaTextDirection fromJson(String? value) => values.firstWhere(
    (item) => item.name == value,
    orElse: () => MangaTextDirection.unknown,
  );
}

enum MangaReadingOrder {
  automatic,
  mangaRtl,
  leftToRight;

  static MangaReadingOrder fromJson(String? value) => values.firstWhere(
    (item) => item.name == value,
    orElse: () => MangaReadingOrder.automatic,
  );
}

enum MangaOcrStage {
  idle,
  preparing,
  tiling,
  detecting,
  recognizing,
  translating,
  completed,
  cancelled,
  failed,
}

class MangaNormalizedRect {
  final double left;
  final double top;
  final double right;
  final double bottom;

  const MangaNormalizedRect({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  const MangaNormalizedRect.zero() : left = 0, top = 0, right = 0, bottom = 0;

  double get width => math.max(0, right - left);
  double get height => math.max(0, bottom - top);
  double get area => width * height;
  double get centerX => (left + right) / 2;
  double get centerY => (top + bottom) / 2;

  MangaNormalizedRect clamp() => MangaNormalizedRect(
    left: left.clamp(0.0, 1.0),
    top: top.clamp(0.0, 1.0),
    right: right.clamp(0.0, 1.0),
    bottom: bottom.clamp(0.0, 1.0),
  );

  MangaNormalizedRect inflate(double fraction) {
    final dx = width * fraction;
    final dy = height * fraction;
    return MangaNormalizedRect(
      left: left - dx,
      top: top - dy,
      right: right + dx,
      bottom: bottom + dy,
    ).clamp();
  }

  double intersectionOverUnion(MangaNormalizedRect other) {
    final intersectionWidth = math.max(
      0.0,
      math.min(right, other.right) - math.max(left, other.left),
    );
    final intersectionHeight = math.max(
      0.0,
      math.min(bottom, other.bottom) - math.max(top, other.top),
    );
    final intersection = intersectionWidth * intersectionHeight;
    final union = area + other.area - intersection;
    return union <= 0 ? 0 : intersection / union;
  }

  MangaNormalizedRect union(MangaNormalizedRect other) => MangaNormalizedRect(
    left: math.min(left, other.left),
    top: math.min(top, other.top),
    right: math.max(right, other.right),
    bottom: math.max(bottom, other.bottom),
  );

  Map<String, dynamic> toJson() => {
    'left': left,
    'top': top,
    'right': right,
    'bottom': bottom,
  };

  factory MangaNormalizedRect.fromJson(Map<String, dynamic> json) =>
      MangaNormalizedRect(
        left: (json['left'] as num?)?.toDouble() ?? 0,
        top: (json['top'] as num?)?.toDouble() ?? 0,
        right: (json['right'] as num?)?.toDouble() ?? 0,
        bottom: (json['bottom'] as num?)?.toDouble() ?? 0,
      ).clamp();
}

class MangaTextBlock {
  final String id;
  final MangaNormalizedRect bounds;
  final String sourceText;
  final String translatedText;
  final String language;
  final MangaTextDirection direction;
  final double detectionConfidence;
  final double recognitionConfidence;
  final int order;
  final bool usedHighResolutionRetry;
  final String? warning;

  const MangaTextBlock({
    required this.id,
    required this.bounds,
    this.sourceText = '',
    this.translatedText = '',
    this.language = 'unknown',
    this.direction = MangaTextDirection.unknown,
    this.detectionConfidence = 0,
    this.recognitionConfidence = 0,
    this.order = 0,
    this.usedHighResolutionRetry = false,
    this.warning,
  });

  bool get isLowConfidence =>
      sourceText.trim().isEmpty || recognitionConfidence < 0.45;

  MangaTextBlock copyWith({
    MangaNormalizedRect? bounds,
    String? sourceText,
    String? translatedText,
    String? language,
    MangaTextDirection? direction,
    double? detectionConfidence,
    double? recognitionConfidence,
    int? order,
    bool? usedHighResolutionRetry,
    String? warning,
    bool clearWarning = false,
  }) => MangaTextBlock(
    id: id,
    bounds: bounds ?? this.bounds,
    sourceText: sourceText ?? this.sourceText,
    translatedText: translatedText ?? this.translatedText,
    language: language ?? this.language,
    direction: direction ?? this.direction,
    detectionConfidence: detectionConfidence ?? this.detectionConfidence,
    recognitionConfidence: recognitionConfidence ?? this.recognitionConfidence,
    order: order ?? this.order,
    usedHighResolutionRetry:
        usedHighResolutionRetry ?? this.usedHighResolutionRetry,
    warning: clearWarning ? null : warning ?? this.warning,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'bounds': bounds.toJson(),
    'sourceText': sourceText,
    'translatedText': translatedText,
    'language': language,
    'direction': direction.name,
    'detectionConfidence': detectionConfidence,
    'recognitionConfidence': recognitionConfidence,
    'order': order,
    'usedHighResolutionRetry': usedHighResolutionRetry,
    'warning': warning,
  };

  factory MangaTextBlock.fromJson(Map<String, dynamic> json) => MangaTextBlock(
    id: json['id'] as String? ?? '',
    bounds: MangaNormalizedRect.fromJson(
      Map<String, dynamic>.from(json['bounds'] as Map? ?? const {}),
    ),
    sourceText: json['sourceText'] as String? ?? '',
    translatedText: json['translatedText'] as String? ?? '',
    language: json['language'] as String? ?? 'unknown',
    direction: MangaTextDirection.fromJson(json['direction'] as String?),
    detectionConfidence: (json['detectionConfidence'] as num?)?.toDouble() ?? 0,
    recognitionConfidence:
        (json['recognitionConfidence'] as num?)?.toDouble() ?? 0,
    order: json['order'] as int? ?? 0,
    usedHighResolutionRetry: json['usedHighResolutionRetry'] as bool? ?? false,
    warning: json['warning'] as String?,
  );
}

class MangaPageOcrResult {
  final String imageSha256;
  final int pageIndex;
  final int imageWidth;
  final int imageHeight;
  final String preprocessorId;
  final String preprocessorVersion;
  final String detectorId;
  final String detectorVersion;
  final String recognizerId;
  final String recognizerVersion;
  final DateTime createdAt;
  final List<MangaTextBlock> blocks;

  const MangaPageOcrResult({
    required this.imageSha256,
    required this.pageIndex,
    required this.imageWidth,
    required this.imageHeight,
    required this.preprocessorId,
    required this.preprocessorVersion,
    required this.detectorId,
    required this.detectorVersion,
    required this.recognizerId,
    required this.recognizerVersion,
    required this.createdAt,
    required this.blocks,
  });

  MangaPageOcrResult copyWith({List<MangaTextBlock>? blocks}) =>
      MangaPageOcrResult(
        imageSha256: imageSha256,
        pageIndex: pageIndex,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        preprocessorId: preprocessorId,
        preprocessorVersion: preprocessorVersion,
        detectorId: detectorId,
        detectorVersion: detectorVersion,
        recognizerId: recognizerId,
        recognizerVersion: recognizerVersion,
        createdAt: createdAt,
        blocks: blocks ?? this.blocks,
      );

  Map<String, dynamic> toJson() => {
    'imageSha256': imageSha256,
    'pageIndex': pageIndex,
    'imageWidth': imageWidth,
    'imageHeight': imageHeight,
    'preprocessorId': preprocessorId,
    'preprocessorVersion': preprocessorVersion,
    'detectorId': detectorId,
    'detectorVersion': detectorVersion,
    'recognizerId': recognizerId,
    'recognizerVersion': recognizerVersion,
    'createdAt': createdAt.toIso8601String(),
    'blocks': blocks.map((item) => item.toJson()).toList(),
  };

  factory MangaPageOcrResult.fromJson(
    Map<String, dynamic> json,
  ) => MangaPageOcrResult(
    imageSha256: json['imageSha256'] as String? ?? '',
    pageIndex: json['pageIndex'] as int? ?? 0,
    imageWidth: json['imageWidth'] as int? ?? 0,
    imageHeight: json['imageHeight'] as int? ?? 0,
    preprocessorId: json['preprocessorId'] as String? ?? mangaOcrPreprocessorId,
    preprocessorVersion:
        json['preprocessorVersion'] as String? ?? mangaOcrPreprocessorVersion,
    detectorId: json['detectorId'] as String? ?? mangaOcrDefaultDetectorId,
    detectorVersion: json['detectorVersion'] as String? ?? '',
    recognizerId:
        json['recognizerId'] as String? ?? mangaOcrDefaultRecognizerId,
    recognizerVersion: json['recognizerVersion'] as String? ?? '',
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0),
    blocks:
        (json['blocks'] as List<dynamic>? ?? const [])
            .whereType<Map>()
            .map(
              (item) =>
                  MangaTextBlock.fromJson(Map<String, dynamic>.from(item)),
            )
            .toList(),
  );
}

class MangaOcrOptions {
  final int maxWorkingEdge;
  final double longPageAspectRatio;
  final double tileOverlap;
  final double cropPadding;
  final double lowConfidenceThreshold;
  final double duplicateIouThreshold;
  final MangaReadingOrder readingOrder;

  const MangaOcrOptions({
    this.maxWorkingEdge = 2048,
    this.longPageAspectRatio = 3,
    this.tileOverlap = 0.10,
    this.cropPadding = 0.12,
    this.lowConfidenceThreshold = 0.45,
    this.duplicateIouThreshold = 0.55,
    this.readingOrder = MangaReadingOrder.automatic,
  });

  Map<String, dynamic> toJson() => {
    'maxWorkingEdge': maxWorkingEdge,
    'longPageAspectRatio': longPageAspectRatio,
    'tileOverlap': tileOverlap,
    'cropPadding': cropPadding,
    'lowConfidenceThreshold': lowConfidenceThreshold,
    'duplicateIouThreshold': duplicateIouThreshold,
    'readingOrder': readingOrder.name,
    'highResolutionRetryScale': 2.0,
    'highResolutionRetryCount': 1,
  };
}
