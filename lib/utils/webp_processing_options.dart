import 'dart:math' as math;

/// 批量静态图片 WebP 处理的参数。
class WebpProcessingOptions {
  final int quality;
  final int percentage;
  final int? maxWidth;
  final int? maxHeight;

  const WebpProcessingOptions({
    this.quality = 80,
    this.percentage = 100,
    this.maxWidth,
    this.maxHeight,
  });

  String? validate() {
    if (quality < 0 || quality > 100) return '压缩质量必须在 0 到 100 之间';
    if (percentage < 1 || percentage > 100) return '缩放百分比必须在 1 到 100 之间';
    if (maxWidth != null && maxWidth! <= 0) return '最大宽度必须大于 0';
    if (maxHeight != null && maxHeight! <= 0) return '最大高度必须大于 0';
    return null;
  }

  /// 计算不会放大的最终尺寸。多个约束同时存在时取最小缩放比例。
  WebpTargetSize targetSizeFor(int width, int height) {
    if (width <= 0 || height <= 0) {
      throw ArgumentError('图片尺寸必须大于 0');
    }

    var scale = math.min(1.0, percentage / 100);
    if (maxWidth != null) scale = math.min(scale, maxWidth! / width);
    if (maxHeight != null) scale = math.min(scale, maxHeight! / height);
    scale = math.min(1.0, scale);

    return WebpTargetSize(
      width: math.max(1, (width * scale).round()),
      height: math.max(1, (height * scale).round()),
    );
  }
}

class WebpTargetSize {
  final int width;
  final int height;

  const WebpTargetSize({required this.width, required this.height});

  @override
  bool operator ==(Object other) =>
      other is WebpTargetSize && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);
}
