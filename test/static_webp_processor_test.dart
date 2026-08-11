import 'package:flutter_test/flutter_test.dart';
import 'package:pixez/utils/webp_processing_options.dart';

void main() {
  group('WebpProcessingOptions.targetSizeFor', () {
    test('按百分比缩小', () {
      const options = WebpProcessingOptions(percentage: 50);
      expect(
        options.targetSizeFor(4000, 3000),
        const WebpTargetSize(width: 2000, height: 1500),
      );
    });

    test('按单边最大宽度缩小', () {
      const options = WebpProcessingOptions(maxWidth: 1600);
      expect(
        options.targetSizeFor(4000, 3000),
        const WebpTargetSize(width: 1600, height: 1200),
      );
    });

    test('按单边最大高度缩小', () {
      const options = WebpProcessingOptions(maxHeight: 1000);
      expect(
        options.targetSizeFor(4000, 3000),
        const WebpTargetSize(width: 1333, height: 1000),
      );
    });

    test('多个限制取最小缩放比例', () {
      const options = WebpProcessingOptions(
        percentage: 50,
        maxWidth: 1600,
        maxHeight: 1400,
      );
      expect(
        options.targetSizeFor(4000, 3000),
        const WebpTargetSize(width: 1600, height: 1200),
      );
    });

    test('不会放大原图', () {
      const options = WebpProcessingOptions(
        percentage: 100,
        maxWidth: 4000,
        maxHeight: 3000,
      );
      expect(
        options.targetSizeFor(1000, 800),
        const WebpTargetSize(width: 1000, height: 800),
      );
    });

    test('极小比例仍至少保留一个像素', () {
      const options = WebpProcessingOptions(percentage: 1);
      expect(
        options.targetSizeFor(1, 10000),
        const WebpTargetSize(width: 1, height: 100),
      );
    });
  });
}
