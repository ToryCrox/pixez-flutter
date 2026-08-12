import 'package:flutter_test/flutter_test.dart';
import 'package:pixez/manga_ocr/manga_image_preprocessor.dart';
import 'package:pixez/manga_ocr/manga_ocr_models.dart';

void main() {
  final preprocessor = AdaptivePagePreprocessor();

  test('普通大图按最长边 2048 等比缩小', () {
    final plan = preprocessor.plan(width: 4000, height: 2000);
    expect(plan.tiled, isFalse);
    expect(plan.scale, closeTo(0.512, 0.0001));
    expect(plan.tiles.single.workingWidth, 2048);
    expect(plan.tiles.single.workingHeight, 1024);
  });

  test('超过 3:1 的长图使用 10% 重叠分块', () {
    final plan = preprocessor.plan(width: 1000, height: 10000);
    expect(plan.tiled, isTrue);
    expect(plan.tiles.length, greaterThan(4));
    expect(
      plan.tiles.every(
        (tile) => tile.workingWidth <= 2048 && tile.workingHeight <= 2048,
      ),
      isTrue,
    );
    final first = plan.tiles[0].bounds;
    final second = plan.tiles[1].bounds;
    expect(first.bottom, greaterThan(second.top));
  });

  test('分块坐标可反算到整页归一化坐标', () {
    final tile = MangaImageTile(
      index: 1,
      bounds: const MangaNormalizedRect(
        left: 0,
        top: 0.4,
        right: 1,
        bottom: 0.7,
      ),
      workingWidth: 1000,
      workingHeight: 2048,
    );
    final mapped = preprocessor.mapTileRectToPage(
      const MangaNormalizedRect(left: 0.2, top: 0.5, right: 0.8, bottom: 1),
      tile,
    );
    expect(mapped.left, closeTo(0.2, 0.0001));
    expect(mapped.top, closeTo(0.55, 0.0001));
    expect(mapped.bottom, closeTo(0.7, 0.0001));
  });

  test('裁剪补边会扩张并限制在页面范围内', () {
    final padded = const MangaNormalizedRect(
      left: 0.01,
      top: 0.01,
      right: 0.2,
      bottom: 0.3,
    ).inflate(0.12);
    expect(padded.left, 0);
    expect(padded.top, 0);
    expect(padded.right, greaterThan(0.2));
  });

  test('跨分块重复框按 IoU 和方向合并', () {
    MangaTextBlock block(String id, double left) => MangaTextBlock(
      id: id,
      bounds: MangaNormalizedRect(
        left: left,
        top: 0.2,
        right: left + 0.2,
        bottom: 0.4,
      ),
      direction: MangaTextDirection.vertical,
      recognitionConfidence: id == 'b' ? 0.9 : 0.7,
    );

    final merged = preprocessor.mergeDuplicates([
      block('a', 0.2),
      block('b', 0.21),
    ]);
    expect(merged, hasLength(1));
    expect(merged.single.id, 'b');
    expect(merged.single.bounds.left, closeTo(0.2, 0.0001));
  });
}
