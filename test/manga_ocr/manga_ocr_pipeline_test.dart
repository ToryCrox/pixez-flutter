import 'package:flutter_test/flutter_test.dart';
import 'package:pixez/manga_ocr/manga_ocr_models.dart';
import 'package:pixez/manga_ocr/manga_ocr_pipeline.dart';
import 'package:pixez/manga_ocr/manga_translation_segments.dart';

MangaTextBlock _block(
  String id, {
  required double left,
  required double top,
  MangaTextDirection direction = MangaTextDirection.horizontal,
}) => MangaTextBlock(
  id: id,
  bounds: MangaNormalizedRect(
    left: left,
    top: top,
    right: left + 0.1,
    bottom: top + 0.1,
  ),
  direction: direction,
);

void main() {
  test('日漫 RTL 按列从右到左、列内从上到下', () {
    final sorted = MangaOcrPipeline.sortBlocks([
      _block(
        'left',
        left: 0.2,
        top: 0.1,
        direction: MangaTextDirection.vertical,
      ),
      _block(
        'right-bottom',
        left: 0.8,
        top: 0.5,
        direction: MangaTextDirection.vertical,
      ),
      _block(
        'right-top',
        left: 0.81,
        top: 0.1,
        direction: MangaTextDirection.vertical,
      ),
    ], MangaReadingOrder.mangaRtl);
    expect(sorted.map((item) => item.id), [
      'right-top',
      'right-bottom',
      'left',
    ]);
  });

  test('LTR 按行从上到下、同行从左到右', () {
    final sorted = MangaOcrPipeline.sortBlocks([
      _block('bottom', left: 0.1, top: 0.8),
      _block('right', left: 0.7, top: 0.1),
      _block('left', left: 0.1, top: 0.11),
    ], MangaReadingOrder.leftToRight);
    expect(sorted.map((item) => item.id), ['left', 'right', 'bottom']);
  });

  test('翻译分段恢复保留稳定 ID，并可发现缺失块', () {
    final batch = MangaTranslationBatch.fromBlocks({
      'block-a': 'こんにちは',
      'block-b': 'Hello',
    });
    final restored = batch.restore(
      '${batch.markers['block-a']}你好\n'
      '${batch.markers['block-b']}你好！',
    );
    expect(restored, {'block-a': '你好', 'block-b': '你好！'});

    final missing = batch.restore('${batch.markers['block-a']}你好');
    expect(missing.containsKey('block-b'), isFalse);
  });
}
