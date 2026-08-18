import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as image_lib;
import 'package:path/path.dart' as path;
import 'package:pixez/models/download_record.dart';
import 'package:pixez/models/illust.dart';
import 'package:pixez/utils/translation_result_replacer.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => Directory.systemTemp.path,
        );
  });

  group('TranslationResultReplacer', () {
    late Directory temporary;
    late DownloadDatabaseProvider provider;
    late DownloadedIllust illust;
    late Directory workDirectory;

    setUp(() async {
      temporary = await Directory.systemTemp.createTemp('pixez_translation_');
      provider = DownloadDatabaseProvider();
      await provider.open(temporary.path);
      illust = DownloadedIllust.fromIllusts(
        _illust(100),
        path.join('[作者][1]', '[100]测试'),
      );
      await provider.insertIllust(illust);
      workDirectory = Directory(
        provider.getIllustAbsolutePath(illust.relativePath),
      );
      await workDirectory.create(recursive: true);
    });

    tearDown(() async {
      await provider.db.close();
      if (await temporary.exists()) await temporary.delete(recursive: true);
    });

    test('仅替换同名译图并清理本次翻译结果目录', () async {
      final originalOne = File(path.join(workDirectory.path, '1.webp'));
      final originalTwo = File(path.join(workDirectory.path, '2.jpg'));
      await originalOne.writeAsBytes(_pngBytes(8, 8));
      await originalTwo.writeAsBytes(_pngBytes(6, 6));
      await _insertImage(provider, 100, 0, '1', '.webp', originalOne);
      await _insertImage(provider, 100, 1, '2', '.jpg', originalTwo);

      final resultDir = Directory(path.join(workDirectory.path, 'result'));
      final inpaintedDir = Directory(
        path.join(workDirectory.path, 'inpainted'),
      );
      final maskDir = Directory(path.join(workDirectory.path, 'mask'));
      await resultDir.create();
      await inpaintedDir.create();
      await maskDir.create();
      await File(
        path.join(resultDir.path, '1.png'),
      ).writeAsBytes(_pngBytes(12, 10));
      await File(
        path.join(resultDir.path, 'extra.png'),
      ).writeAsBytes(_pngBytes(4, 4));
      await File(path.join(inpaintedDir.path, 'data.tmp')).writeAsString('x');
      await File(path.join(maskDir.path, 'data.tmp')).writeAsString('x');

      final replacer = TranslationResultReplacer(provider);
      final plan = await replacer.prepare(illust);
      expect(plan.pairs, hasLength(1));
      expect(plan.unmatched, hasLength(2));

      final summary = await replacer.apply(plan);
      expect(summary.successCount, 1);
      expect(summary.failureCount, 0);
      final translatedIllust = await provider.getIllustByIllustId(100);
      expect(translatedIllust?.isTranslated, isTrue);
      expect(translatedIllust?.title, illust.title);
      expect(summary.translationResultDirectoriesCleaned, isTrue);
      expect(summary.intermediateDirectoriesCleaned, isTrue);
      expect(await originalOne.exists(), isFalse);
      expect(
        await File(path.join(workDirectory.path, '1.png')).exists(),
        isTrue,
      );
      expect(await originalTwo.exists(), isTrue);
      expect(await File(path.join(resultDir.path, '1.png')).exists(), isFalse);
      expect(
        await File(path.join(resultDir.path, 'extra.png')).exists(),
        isFalse,
      );
      expect(await resultDir.exists(), isFalse);
      expect(await inpaintedDir.exists(), isFalse);
      expect(await maskDir.exists(), isFalse);

      final image = await provider.getImage(100, 0);
      expect(image?.extension, '.png');
      expect(image?.width, 12);
      expect(image?.height, 10);
      expect(
        image?.fileSize,
        await File(path.join(workDirectory.path, '1.png')).length(),
      );
    });

    test('翻译标记可以单独更新并支持序列化', () async {
      final marked = illust.copyWith(isTranslated: true);
      final restored = DownloadedIllust.fromJson(marked.toJson());
      expect(restored.isTranslated, isTrue);

      await provider.updateIllustTranslationStatus(100, true);
      expect((await provider.getIllustByIllustId(100))?.isTranslated, isTrue);
      await provider.updateIllustTranslationStatus(100, false);
      final updated = await provider.getIllustByIllustId(100);
      expect(updated?.isTranslated, isFalse);
      expect(updated?.title, illust.title);

      final refreshed = DownloadedIllust.fromIllusts(
        _illust(100).copyWith(title: '更新后的标题'),
        illust.relativePath,
        isTranslated: true,
      );
      await provider.updateIllust(refreshed);
      final afterRefresh = await provider.getIllustByIllustId(100);
      expect(afterRefresh?.isTranslated, isTrue);
      expect(afterRefresh?.title, '更新后的标题');
    });

    test('全部替换成功后清理 result、inpainted 与 mask', () async {
      final original = File(path.join(workDirectory.path, '1.webp'));
      await original.writeAsBytes(_pngBytes(8, 8));
      await _insertImage(provider, 100, 0, '1', '.webp', original);
      final resultDir = Directory(path.join(workDirectory.path, 'result'));
      final inpaintedDir = Directory(
        path.join(workDirectory.path, 'inpainted'),
      );
      final maskDir = Directory(path.join(workDirectory.path, 'mask'));
      await resultDir.create();
      await inpaintedDir.create();
      await maskDir.create();
      await File(
        path.join(resultDir.path, '1.png'),
      ).writeAsBytes(_pngBytes(9, 7));
      await File(path.join(inpaintedDir.path, 'data.tmp')).writeAsString('x');
      await File(path.join(maskDir.path, 'data.tmp')).writeAsString('x');

      final replacer = TranslationResultReplacer(provider);
      final summary = await replacer.apply(await replacer.prepare(illust));

      expect(summary.successCount, 1);
      expect(summary.intermediateDirectoriesCleaned, isTrue);
      expect(
        await File(path.join(workDirectory.path, '1.png')).exists(),
        isTrue,
      );
      expect(await resultDir.exists(), isFalse);
      expect(await inpaintedDir.exists(), isFalse);
      expect(await maskDir.exists(), isFalse);
    });

    test('缺少部分译图时仍清理已完成替换的中间目录', () async {
      final translatedOriginal = File(path.join(workDirectory.path, '1.webp'));
      final untranslatedOriginal = File(
        path.join(workDirectory.path, '2.webp'),
      );
      await translatedOriginal.writeAsBytes(_pngBytes(8, 8));
      await untranslatedOriginal.writeAsBytes(_pngBytes(8, 8));
      await _insertImage(provider, 100, 0, '1', '.webp', translatedOriginal);
      await _insertImage(provider, 100, 1, '2', '.webp', untranslatedOriginal);

      final resultDir = Directory(path.join(workDirectory.path, 'result'));
      final inpaintedDir = Directory(
        path.join(workDirectory.path, 'inpainted'),
      );
      final maskDir = Directory(path.join(workDirectory.path, 'mask'));
      await resultDir.create();
      await inpaintedDir.create();
      await maskDir.create();
      await File(
        path.join(resultDir.path, '1.png'),
      ).writeAsBytes(_pngBytes(9, 7));
      await File(path.join(inpaintedDir.path, 'data.tmp')).writeAsString('x');
      await File(path.join(maskDir.path, 'data.tmp')).writeAsString('x');

      final replacer = TranslationResultReplacer(provider);
      final plan = await replacer.prepare(illust);
      final summary = await replacer.apply(plan);

      expect(plan.pairs, hasLength(1));
      expect(plan.unmatched, hasLength(1));
      expect(plan.unmatched.single.isOriginal, isTrue);
      expect(summary.successCount, 1);
      expect(summary.intermediateDirectoriesCleaned, isTrue);
      expect(
        await File(path.join(workDirectory.path, '1.png')).exists(),
        isTrue,
      );
      expect(await untranslatedOriginal.exists(), isTrue);
      expect(await resultDir.exists(), isFalse);
      expect(await inpaintedDir.exists(), isFalse);
      expect(await maskDir.exists(), isFalse);
    });

    test('按漫画目录名匹配外部翻译结果目录', () async {
      final original = File(path.join(workDirectory.path, '1.webp'));
      await original.writeAsBytes(_pngBytes(8, 8));
      await _insertImage(provider, 100, 0, '1', '.webp', original);

      final translationRoot = Directory(
        path.join(temporary.path, 'translation-output'),
      );
      final translationComic = Directory(
        path.join(translationRoot.path, path.basename(workDirectory.path)),
      );
      final translated = File(path.join(translationComic.path, '1.png'));
      await _writeImage(translated.path, _pngBytes(9, 7));

      final replacer = TranslationResultReplacer(provider);
      expect(
        await replacer.hasReplacementCandidate(
          illust,
          translationResultRootDirectory: translationRoot.path,
        ),
        isTrue,
      );
      final plan = await replacer.prepare(
        illust,
        translationResultRootDirectory: translationRoot.path,
      );
      expect(plan.pairs, hasLength(1));
      expect(plan.pairs.single.translatedPath, translated.path);

      final translationWorkDirectory = Directory(
        path.join(workDirectory.path, 'manga_translator_work'),
      );
      await File(
        path.join(translationWorkDirectory.path, 'result', 'ignored.png'),
      ).create(recursive: true);

      final summary = await replacer.apply(plan);
      expect(summary.successCount, 1);
      expect(await translated.exists(), isFalse);
      expect(await translationComic.exists(), isFalse);
      expect(await translationWorkDirectory.exists(), isFalse);
    });

    test('外部翻译结果使用非 result 目录名称也可以匹配', () async {
      final original = File(path.join(workDirectory.path, '1.webp'));
      await original.writeAsBytes(_pngBytes(8, 8));
      await _insertImage(provider, 100, 0, '1', '.webp', original);

      final translationRoot = Directory(
        path.join(temporary.path, 'translation-output'),
      );
      final translated = File(
        path.join(
          translationRoot.path,
          path.basename(workDirectory.path),
          '1.jpg',
        ),
      );
      await _writeImage(translated.path, _pngBytes(9, 7));

      final plan = await TranslationResultReplacer(
        provider,
      ).prepare(illust, translationResultRootDirectory: translationRoot.path);
      expect(plan.pairs, hasLength(1));
      expect(plan.pairs.single.translatedPath, translated.path);
    });

    test('外部翻译结果按原漫画相对目录匹配', () async {
      final original = File(path.join(workDirectory.path, 'chapter', '1.webp'));
      await original.create(recursive: true);
      await _writeImage(original.path, _pngBytes(8, 8));
      await _insertImage(provider, 100, 0, 'chapter/1', '.webp', original);

      final translationRoot = Directory(
        path.join(temporary.path, 'translation-output'),
      );
      final translated = File(
        path.join(
          translationRoot.path,
          path.basename(workDirectory.path),
          'chapter',
          '1.png',
        ),
      );
      await _writeImage(translated.path, _pngBytes(9, 7));

      final plan = await TranslationResultReplacer(
        provider,
      ).prepare(illust, translationResultRootDirectory: translationRoot.path);
      expect(plan.pairs, hasLength(1));
      expect(
        path.equals(plan.pairs.single.originalPath, original.path),
        isTrue,
      );
      expect(plan.pairs.single.translatedPath, translated.path);
    });

    test('旧 result 与外部翻译结果可以同时处理', () async {
      final originalOne = File(path.join(workDirectory.path, '1.webp'));
      final originalTwo = File(
        path.join(workDirectory.path, 'chapter', '2.webp'),
      );
      await _writeImage(originalOne.path, _pngBytes(8, 8));
      await originalTwo.create(recursive: true);
      await _writeImage(originalTwo.path, _pngBytes(8, 8));
      await _insertImage(provider, 100, 0, '1', '.webp', originalOne);
      await _insertImage(provider, 100, 1, 'chapter/2', '.webp', originalTwo);

      final legacyTranslated = File(
        path.join(workDirectory.path, 'result', '1.png'),
      );
      await _writeImage(legacyTranslated.path, _pngBytes(9, 7));
      final translationRoot = Directory(
        path.join(temporary.path, 'translation-output'),
      );
      final externalTranslated = File(
        path.join(
          translationRoot.path,
          path.basename(workDirectory.path),
          'chapter',
          '2.png',
        ),
      );
      await _writeImage(externalTranslated.path, _pngBytes(9, 7));

      final replacer = TranslationResultReplacer(provider);
      final plan = await replacer.prepare(
        illust,
        translationResultRootDirectory: translationRoot.path,
      );
      expect(plan.pairs, hasLength(2));

      final summary = await replacer.apply(plan);
      expect(summary.successCount, 2);
      expect(await legacyTranslated.exists(), isFalse);
      expect(await externalTranslated.exists(), isFalse);
    });

    test('外部目录中不同漫画名称不会误匹配', () async {
      final original = File(path.join(workDirectory.path, '1.webp'));
      await _writeImage(original.path, _pngBytes(8, 8));
      await _insertImage(provider, 100, 0, '1', '.webp', original);

      final translationRoot = Directory(
        path.join(temporary.path, 'translation-output'),
      );
      await _writeImage(
        path.join(translationRoot.path, 'another-comic', '1.png'),
        _pngBytes(9, 7),
      );

      final plan = await TranslationResultReplacer(
        provider,
      ).prepare(illust, translationResultRootDirectory: translationRoot.path);
      expect(plan.pairs, isEmpty);
    });

    test('跳过指定图片时保留原图并删除对应译图', () async {
      final originalOne = File(path.join(workDirectory.path, '1.webp'));
      final originalTwo = File(path.join(workDirectory.path, '2.webp'));
      await _writeImage(originalOne.path, _pngBytes(8, 8));
      await _writeImage(originalTwo.path, _pngBytes(8, 8));
      await _insertImage(provider, 100, 0, '1', '.webp', originalOne);
      await _insertImage(provider, 100, 1, '2', '.webp', originalTwo);
      final resultDir = Directory(path.join(workDirectory.path, 'result'));
      await _writeImage(path.join(resultDir.path, '1.png'), _pngBytes(9, 7));
      await _writeImage(path.join(resultDir.path, '2.png'), _pngBytes(9, 7));

      final replacer = TranslationResultReplacer(provider);
      final plan = await replacer.prepare(illust);
      final summary = await replacer.apply(
        plan,
        skippedOriginalPaths: {originalTwo.path},
      );

      expect(summary.successCount, 1);
      expect(summary.skippedCount, 1);
      expect((await provider.getIllustByIllustId(100))?.isTranslated, isTrue);
      expect(summary.translationResultDirectoriesCleaned, isTrue);
      expect(await originalOne.exists(), isFalse);
      expect(
        await File(path.join(workDirectory.path, '1.png')).exists(),
        isTrue,
      );
      expect(await originalTwo.exists(), isTrue);
      expect(await File(path.join(resultDir.path, '2.png')).exists(), isFalse);
      expect(await resultDir.exists(), isFalse);
    });

    test('全部跳过时仍删除翻译结果目录', () async {
      final original = File(path.join(workDirectory.path, '1.webp'));
      await _writeImage(original.path, _pngBytes(8, 8));
      await _insertImage(provider, 100, 0, '1', '.webp', original);
      final resultDir = Directory(path.join(workDirectory.path, 'result'));
      final translated = File(path.join(resultDir.path, '1.png'));
      await _writeImage(translated.path, _pngBytes(9, 7));

      final replacer = TranslationResultReplacer(provider);
      final plan = await replacer.prepare(illust);
      final summary = await replacer.apply(
        plan,
        skippedOriginalPaths: {original.path},
      );

      expect(summary.successCount, 0);
      expect(summary.skippedCount, 1);
      expect((await provider.getIllustByIllustId(100))?.isTranslated, isFalse);
      expect(summary.translationResultDirectoriesCleaned, isTrue);
      expect(await original.exists(), isTrue);
      expect(await translated.exists(), isFalse);
      expect(await resultDir.exists(), isFalse);
    });

    test('清理当前外部作品目录时保留同级其他作品目录', () async {
      final original = File(path.join(workDirectory.path, '1.webp'));
      await _writeImage(original.path, _pngBytes(8, 8));
      await _insertImage(provider, 100, 0, '1', '.webp', original);

      final translationRoot = Directory(
        path.join(temporary.path, 'translation-output'),
      );
      final translationComic = Directory(
        path.join(translationRoot.path, path.basename(workDirectory.path)),
      );
      final otherComic = Directory(path.join(translationRoot.path, '[200]其他'));
      await _writeImage(
        path.join(translationComic.path, '1.png'),
        _pngBytes(9, 7),
      );
      final otherFile = File(path.join(otherComic.path, '1.png'));
      await _writeImage(otherFile.path, _pngBytes(9, 7));

      final replacer = TranslationResultReplacer(provider);
      final plan = await replacer.prepare(
        illust,
        translationResultRootDirectory: translationRoot.path,
      );
      final summary = await replacer.apply(plan);

      expect(summary.translationResultDirectoriesCleaned, isTrue);
      expect(await translationComic.exists(), isFalse);
      expect(await otherFile.exists(), isTrue);
      expect(await otherComic.exists(), isTrue);
    });

    test('清理结果目录时不影响当前作品的其他翻译目录', () async {
      final original = File(path.join(workDirectory.path, '1.webp'));
      await _writeImage(original.path, _pngBytes(8, 8));
      await _insertImage(provider, 100, 0, '1', '.webp', original);
      final resultDir = Directory(path.join(workDirectory.path, 'result'));
      await _writeImage(path.join(resultDir.path, '1.png'), _pngBytes(9, 7));
      final otherDirectory = Directory(
        path.join(workDirectory.path, 'other-translation'),
      );
      final otherFile = File(path.join(otherDirectory.path, 'keep.txt'));
      await otherFile.create(recursive: true);
      await otherFile.writeAsString('keep');

      final replacer = TranslationResultReplacer(provider);
      final plan = await replacer.prepare(illust);
      final summary = await replacer.apply(plan);

      expect(summary.translationResultDirectoriesCleaned, isTrue);
      expect(await resultDir.exists(), isFalse);
      expect(await otherFile.exists(), isTrue);
    });

    test('替换失败时保留目标目录和失败译图', () async {
      final original = File(path.join(workDirectory.path, '1.webp'));
      await _writeImage(original.path, _pngBytes(8, 8));
      await _insertImage(provider, 100, 0, '1', '.webp', original);
      final resultDir = Directory(path.join(workDirectory.path, 'result'));
      final translated = File(path.join(resultDir.path, '1.png'));
      await translated.create(recursive: true);
      await translated.writeAsString('not an image');

      final replacer = TranslationResultReplacer(provider);
      final plan = await replacer.prepare(illust);
      final summary = await replacer.apply(plan);

      expect(summary.failureCount, 1);
      expect((await provider.getIllustByIllustId(100))?.isTranslated, isFalse);
      expect(summary.translationResultDirectoriesCleaned, isFalse);
      expect(await resultDir.exists(), isTrue);
      expect(await translated.exists(), isTrue);
      expect(await original.exists(), isTrue);
    });

    test('一次扫描外部根目录并按插画目录 ID 返回结果', () async {
      final translationRoot = Directory(
        path.join(temporary.path, 'translation-output'),
      );
      await _writeImage(
        path.join(translationRoot.path, '[100]测试', '1.png'),
        _pngBytes(9, 7),
      );
      await _writeImage(
        path.join(translationRoot.path, '[200]其他', 'result', '1.png'),
        _pngBytes(9, 7),
      );
      await _writeImage(
        path.join(translationRoot.path, 'not-an-illust', '1.png'),
        _pngBytes(9, 7),
      );

      final ids = await TranslationResultReplacer(
        provider,
      ).scanExternalTranslationResults(translationRoot.path);

      expect(ids, contains(100));
      expect(ids, isNot(contains(200)));
      expect(ids, isNot(contains(0)));
    });

    test('外部目录存在未匹配译图时仍清理本次目标目录', () async {
      final original = File(path.join(workDirectory.path, '1.webp'));
      await _writeImage(original.path, _pngBytes(8, 8));
      await _insertImage(provider, 100, 0, '1', '.webp', original);

      final translationRoot = Directory(
        path.join(temporary.path, 'translation-output'),
      );
      final translationComic = Directory(
        path.join(translationRoot.path, path.basename(workDirectory.path)),
      );
      await _writeImage(
        path.join(translationComic.path, '1.png'),
        _pngBytes(9, 7),
      );
      await _writeImage(
        path.join(translationComic.path, 'extra.png'),
        _pngBytes(4, 4),
      );
      await File(
        path.join(workDirectory.path, 'manga_translator_work', 'data.tmp'),
      ).create(recursive: true);

      final replacer = TranslationResultReplacer(provider);
      final plan = await replacer.prepare(
        illust,
        translationResultRootDirectory: translationRoot.path,
      );
      final summary = await replacer.apply(plan);

      expect(summary.successCount, 1);
      expect(summary.translationResultDirectoriesCleaned, isTrue);
      expect(summary.intermediateDirectoriesCleaned, isTrue);
      expect(
        await File(path.join(translationComic.path, 'extra.png')).exists(),
        isFalse,
      );
      expect(await translationComic.exists(), isFalse);
      expect(
        await Directory(
          path.join(workDirectory.path, 'manga_translator_work'),
        ).exists(),
        isFalse,
      );
    });

    test('批量计划只保留有匹配译图的目录并统计无结果目录', () async {
      final original = File(path.join(workDirectory.path, '1.webp'));
      await _writeImage(original.path, _pngBytes(8, 8));
      await _insertImage(provider, 100, 0, '1', '.webp', original);
      await _writeImage(
        path.join(workDirectory.path, 'result', '1.png'),
        _pngBytes(9, 7),
      );
      final (withoutResult, _) = await _addIllust(provider, 200);

      final batchPlan = await TranslationResultReplacer(
        provider,
      ).prepareBatch([illust, withoutResult]);

      expect(batchPlan.selectedCount, 2);
      expect(batchPlan.plans, hasLength(1));
      expect(batchPlan.plans.single.illust.illustId, 100);
      expect(batchPlan.noResultCount, 1);
      expect(batchPlan.pairCount, 1);
    });

    test('批量替换多个目录中的全部图片并清理结果目录', () async {
      final originalOne = File(path.join(workDirectory.path, '1.webp'));
      await _writeImage(originalOne.path, _pngBytes(8, 8));
      await _insertImage(provider, 100, 0, '1', '.webp', originalOne);
      final resultOne = File(path.join(workDirectory.path, 'result', '1.png'));
      await _writeImage(resultOne.path, _pngBytes(9, 7));

      final (secondIllust, secondDirectory) = await _addIllust(provider, 200);
      final originalTwo = File(path.join(secondDirectory.path, '1.webp'));
      await _writeImage(originalTwo.path, _pngBytes(8, 8));
      await _insertImage(provider, 200, 0, '1', '.webp', originalTwo);
      final resultTwo = File(
        path.join(secondDirectory.path, 'result', '1.png'),
      );
      await _writeImage(resultTwo.path, _pngBytes(10, 6));

      final replacer = TranslationResultReplacer(provider);
      final batchPlan = await replacer.prepareBatch([illust, secondIllust]);
      final summary = await replacer.applyBatch(batchPlan);

      expect(summary.successCount, 2);
      expect(summary.failureCount, 0);
      expect(summary.failedPlanCount, 0);
      expect(summary.items, hasLength(2));
      expect((await provider.getIllustByIllustId(100))?.isTranslated, isTrue);
      expect((await provider.getIllustByIllustId(200))?.isTranslated, isTrue);
      expect(await originalOne.exists(), isFalse);
      expect(await originalTwo.exists(), isFalse);
      expect(
        await File(path.join(workDirectory.path, '1.png')).exists(),
        isTrue,
      );
      expect(
        await File(path.join(secondDirectory.path, '1.png')).exists(),
        isTrue,
      );
      expect(await resultOne.exists(), isFalse);
      expect(await resultTwo.exists(), isFalse);
    });

    test('批量替换中单个目录失败时继续处理其他目录并保留失败结果', () async {
      final originalOne = File(path.join(workDirectory.path, '1.webp'));
      await _writeImage(originalOne.path, _pngBytes(8, 8));
      await _insertImage(provider, 100, 0, '1', '.webp', originalOne);
      final invalidResult = File(
        path.join(workDirectory.path, 'result', '1.png'),
      );
      await invalidResult.create(recursive: true);
      await invalidResult.writeAsString('not an image');

      final (secondIllust, secondDirectory) = await _addIllust(provider, 200);
      final originalTwo = File(path.join(secondDirectory.path, '1.webp'));
      await _writeImage(originalTwo.path, _pngBytes(8, 8));
      await _insertImage(provider, 200, 0, '1', '.webp', originalTwo);
      final resultTwo = File(
        path.join(secondDirectory.path, 'result', '1.png'),
      );
      await _writeImage(resultTwo.path, _pngBytes(10, 6));

      final replacer = TranslationResultReplacer(provider);
      final batchPlan = await replacer.prepareBatch([illust, secondIllust]);
      final summary = await replacer.applyBatch(batchPlan);

      expect(summary.successCount, 1);
      expect(summary.failureCount, 1);
      expect(summary.failedPlanCount, 0);
      expect(await originalOne.exists(), isTrue);
      expect(await invalidResult.exists(), isTrue);
      expect(await originalTwo.exists(), isFalse);
      expect(
        await File(path.join(secondDirectory.path, '1.png')).exists(),
        isTrue,
      );
      expect(
        await Directory(path.join(workDirectory.path, 'result')).exists(),
        isTrue,
      );
      expect(
        await Directory(path.join(secondDirectory.path, 'result')).exists(),
        isFalse,
      );
    });

    test('批量跳过不同目录的图片时分别保留原图并清理译图', () async {
      final originalOne = File(path.join(workDirectory.path, '1.webp'));
      await _writeImage(originalOne.path, _pngBytes(8, 8));
      await _insertImage(provider, 100, 0, '1', '.webp', originalOne);
      final resultOne = File(path.join(workDirectory.path, 'result', '1.png'));
      await _writeImage(resultOne.path, _pngBytes(9, 7));

      final (secondIllust, secondDirectory) = await _addIllust(provider, 200);
      final originalTwo = File(path.join(secondDirectory.path, '1.webp'));
      await _writeImage(originalTwo.path, _pngBytes(8, 8));
      await _insertImage(provider, 200, 0, '1', '.webp', originalTwo);
      final resultTwo = File(
        path.join(secondDirectory.path, 'result', '1.png'),
      );
      await _writeImage(resultTwo.path, _pngBytes(10, 6));

      final replacer = TranslationResultReplacer(provider);
      final batchPlan = await replacer.prepareBatch([illust, secondIllust]);
      final summary = await replacer.applyBatch(
        batchPlan,
        skippedOriginalPaths: {originalTwo.path},
      );

      expect(summary.successCount, 1);
      expect(summary.skippedCount, 1);
      expect(summary.failureCount, 0);
      expect((await provider.getIllustByIllustId(100))?.isTranslated, isTrue);
      expect((await provider.getIllustByIllustId(200))?.isTranslated, isFalse);
      expect(await originalOne.exists(), isFalse);
      expect(await originalTwo.exists(), isTrue);
      expect(await resultOne.exists(), isFalse);
      expect(await resultTwo.exists(), isFalse);
    });
  });
}

Future<void> _insertImage(
  DownloadDatabaseProvider provider,
  int illustId,
  int part,
  String fileName,
  String extension,
  File file,
) => provider.insertImage(
  DownloadedImage(
    illustId: illustId,
    part: part,
    fileName: fileName,
    extension: extension,
    fileSize: file.lengthSync(),
    originalUrl: '',
  ),
);

Illusts _illust(int id) => Illusts(
  id: id,
  title: '测试$id',
  type: 'illust',
  user: User(id: 1, name: '作者'),
  createDate: DateTime(2025, 1, 1).toIso8601String(),
  pageCount: 2,
  visible: true,
);

Future<(DownloadedIllust, Directory)> _addIllust(
  DownloadDatabaseProvider provider,
  int id,
) async {
  final value = DownloadedIllust.fromIllusts(
    _illust(id),
    path.join('[作者][1]', '[$id]测试$id'),
  );
  await provider.insertIllust(value);
  final directory = Directory(
    provider.getIllustAbsolutePath(value.relativePath),
  );
  await directory.create(recursive: true);
  return (value, directory);
}

List<int> _pngBytes(int width, int height) => image_lib.encodePng(
  image_lib.Image(width: width, height: height)..setPixelRgb(0, 0, 255, 0, 0),
);

Future<void> _writeImage(String filePath, List<int> bytes) async {
  final file = File(filePath);
  await file.create(recursive: true);
  await file.writeAsBytes(bytes);
}
