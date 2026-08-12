import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pixez/manga_ocr/manga_ocr_cache.dart';
import 'package:pixez/manga_ocr/manga_ocr_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory temporaryDirectory;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'pixez_manga_ocr_test_',
    );
  });

  tearDown(() async {
    await temporaryDirectory.delete(recursive: true);
  });

  MangaOcrCacheKey key({String detectorVersion = '1'}) => MangaOcrCacheKey(
    imageSha256: 'abc',
    pageIndex: 2,
    preprocessorId: mangaOcrPreprocessorId,
    preprocessorVersion: mangaOcrPreprocessorVersion,
    detectorId: mangaOcrDefaultDetectorId,
    detectorVersion: detectorVersion,
    recognizerId: mangaOcrDefaultRecognizerId,
    recognizerVersion: '1',
    options: const MangaOcrOptions(),
  );

  test('模型或预处理参数变化会生成不同缓存键', () {
    expect(key().value, isNot(key(detectorVersion: '2').value));
    final changedOptions = MangaOcrCacheKey(
      imageSha256: 'abc',
      pageIndex: 2,
      preprocessorId: mangaOcrPreprocessorId,
      preprocessorVersion: mangaOcrPreprocessorVersion,
      detectorId: mangaOcrDefaultDetectorId,
      detectorVersion: '1',
      recognizerId: mangaOcrDefaultRecognizerId,
      recognizerVersion: '1',
      options: const MangaOcrOptions(
        maxWorkingEdge: 1024,
        detectorConfidenceThreshold: 0.20,
        highRecallMaxTiles: 2,
      ),
    );
    expect(key().value, isNot(changedOptions.value));
  });

  test('独立 SQLite 缓存可保存和恢复归一化结果', () async {
    final cache = MangaOcrCache(
      databasePath: '${temporaryDirectory.path}/ocr.db',
    );
    final result = MangaPageOcrResult(
      imageSha256: 'abc',
      pageIndex: 2,
      imageWidth: 1000,
      imageHeight: 2000,
      preprocessorId: mangaOcrPreprocessorId,
      preprocessorVersion: mangaOcrPreprocessorVersion,
      detectorId: mangaOcrDefaultDetectorId,
      detectorVersion: '1',
      recognizerId: mangaOcrDefaultRecognizerId,
      recognizerVersion: '1',
      createdAt: DateTime.utc(2026),
      blocks: const [
        MangaTextBlock(
          id: 'a',
          bounds: MangaNormalizedRect(
            left: 0.1,
            top: 0.2,
            right: 0.3,
            bottom: 0.4,
          ),
          sourceText: 'テスト',
        ),
      ],
    );
    await cache.put(key(), result);
    final restored = await cache.get(key());
    expect(restored?.blocks.single.sourceText, 'テスト');
    expect(restored?.blocks.single.bounds.left, 0.1);
    await cache.close();
  });
}
