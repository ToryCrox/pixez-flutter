import 'package:flutter_test/flutter_test.dart';
import 'package:pixez/ai/ai_result_cache.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test(
    'AI result cache persists metadata and invalidates changed source',
    () async {
      final cache = AiResultCache(databasePath: inMemoryDatabasePath);
      addTearDown(cache.close);

      await cache.put(
        sceneId: 'comment_translation',
        resourceKey: 'comment:42',
        sourceText: 'こんにちは',
        resultText: '你好',
        metadata: {'model': 'test-model'},
      );

      final cached = await cache.get(
        sceneId: 'comment_translation',
        resourceKey: 'comment:42',
        sourceText: 'こんにちは',
      );
      expect(cached?.resultText, '你好');
      expect(cached?.metadata['model'], 'test-model');

      final changedSource = await cache.get(
        sceneId: 'comment_translation',
        resourceKey: 'comment:42',
        sourceText: 'こんばんは',
      );
      expect(changedSource, isNull);
    },
  );

  test('source hash is deterministic', () {
    expect(
      AiResultCache.hashSource('same source'),
      AiResultCache.hashSource('same source'),
    );
    expect(
      AiResultCache.hashSource('same source'),
      isNot(AiResultCache.hashSource('different source')),
    );
  });
}
