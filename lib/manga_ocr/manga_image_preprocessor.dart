import 'dart:math' as math;

import 'package:pixez/manga_ocr/manga_ocr_models.dart';

class MangaImageTile {
  final int index;
  final MangaNormalizedRect bounds;
  final int workingWidth;
  final int workingHeight;

  const MangaImageTile({
    required this.index,
    required this.bounds,
    required this.workingWidth,
    required this.workingHeight,
  });
}

class MangaPagePreparation {
  final int sourceWidth;
  final int sourceHeight;
  final double scale;
  final List<MangaImageTile> tiles;

  const MangaPagePreparation({
    required this.sourceWidth,
    required this.sourceHeight,
    required this.scale,
    required this.tiles,
  });

  bool get tiled => tiles.length > 1;
}

abstract interface class MangaImagePreprocessor {
  String get id;
  String get version;

  MangaPagePreparation plan({
    required int width,
    required int height,
    MangaOcrOptions options = const MangaOcrOptions(),
  });
}

class AdaptivePagePreprocessor implements MangaImagePreprocessor {
  @override
  String get id => mangaOcrPreprocessorId;

  @override
  String get version => mangaOcrPreprocessorVersion;

  @override
  MangaPagePreparation plan({
    required int width,
    required int height,
    MangaOcrOptions options = const MangaOcrOptions(),
  }) {
    if (width <= 0 || height <= 0) {
      throw ArgumentError('图片宽高必须大于 0');
    }
    final longEdge = math.max(width, height);
    final scale = math.min(1.0, options.maxWorkingEdge / longEdge);
    final aspect = math.max(width / height, height / width);
    if (aspect <= options.longPageAspectRatio) {
      return MangaPagePreparation(
        sourceWidth: width,
        sourceHeight: height,
        scale: scale,
        tiles: [
          MangaImageTile(
            index: 0,
            bounds: const MangaNormalizedRect(
              left: 0,
              top: 0,
              right: 1,
              bottom: 1,
            ),
            workingWidth: math.max(1, (width * scale).round()),
            workingHeight: math.max(1, (height * scale).round()),
          ),
        ],
      );
    }

    final vertical = height >= width;
    final shortEdge = vertical ? width : height;
    final longAxis = vertical ? height : width;
    final shortScale = math.min(1.0, options.maxWorkingEdge / shortEdge);
    final tileLongSource = options.maxWorkingEdge / shortScale;
    final step = tileLongSource * (1 - options.tileOverlap);
    final tiles = <MangaImageTile>[];
    var start = 0.0;
    while (start < longAxis) {
      final end = math.min(longAxis.toDouble(), start + tileLongSource);
      final normalizedStart = start / longAxis;
      final normalizedEnd = end / longAxis;
      final bounds =
          vertical
              ? MangaNormalizedRect(
                left: 0,
                top: normalizedStart,
                right: 1,
                bottom: normalizedEnd,
              )
              : MangaNormalizedRect(
                left: normalizedStart,
                top: 0,
                right: normalizedEnd,
                bottom: 1,
              );
      tiles.add(
        MangaImageTile(
          index: tiles.length,
          bounds: bounds,
          workingWidth: math.max(
            1,
            ((vertical ? shortEdge : end - start) * shortScale).round(),
          ),
          workingHeight: math.max(
            1,
            ((vertical ? end - start : shortEdge) * shortScale).round(),
          ),
        ),
      );
      if (end >= longAxis) break;
      start += step;
    }
    return MangaPagePreparation(
      sourceWidth: width,
      sourceHeight: height,
      scale: shortScale,
      tiles: tiles,
    );
  }

  MangaNormalizedRect mapTileRectToPage(
    MangaNormalizedRect tileRect,
    MangaImageTile tile,
  ) =>
      MangaNormalizedRect(
        left: tile.bounds.left + tileRect.left * tile.bounds.width,
        top: tile.bounds.top + tileRect.top * tile.bounds.height,
        right: tile.bounds.left + tileRect.right * tile.bounds.width,
        bottom: tile.bounds.top + tileRect.bottom * tile.bounds.height,
      ).clamp();

  List<MangaTextBlock> mergeDuplicates(
    Iterable<MangaTextBlock> blocks, {
    double iouThreshold = 0.55,
  }) {
    final merged = <MangaTextBlock>[];
    for (final block in blocks) {
      final index = merged.indexWhere(
        (current) =>
            current.direction == block.direction &&
            current.bounds.intersectionOverUnion(block.bounds) >= iouThreshold,
      );
      if (index < 0) {
        merged.add(block);
        continue;
      }
      final current = merged[index];
      final preferred =
          block.recognitionConfidence > current.recognitionConfidence
              ? block
              : current;
      merged[index] = preferred.copyWith(
        bounds: current.bounds.union(block.bounds),
        detectionConfidence: math.max(
          current.detectionConfidence,
          block.detectionConfidence,
        ),
      );
    }
    return merged;
  }
}
