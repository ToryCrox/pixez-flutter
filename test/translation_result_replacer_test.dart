import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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

    test('仅替换同名译图并保留未匹配及中间目录', () async {
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
      expect(summary.intermediateDirectoriesCleaned, isFalse);
      expect(await originalOne.exists(), isFalse);
      expect(
        await File(path.join(workDirectory.path, '1.png')).exists(),
        isTrue,
      );
      expect(await originalTwo.exists(), isTrue);
      expect(await File(path.join(resultDir.path, '1.png')).exists(), isFalse);
      expect(
        await File(path.join(resultDir.path, 'extra.png')).exists(),
        isTrue,
      );
      expect(await inpaintedDir.exists(), isTrue);
      expect(await maskDir.exists(), isTrue);

      final image = await provider.getImage(100, 0);
      expect(image?.extension, '.png');
      expect(image?.width, 12);
      expect(image?.height, 10);
      expect(
        image?.fileSize,
        await File(path.join(workDirectory.path, '1.png')).length(),
      );
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

    test('外部目录存在未匹配译图时保留目录和中间目录', () async {
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
      expect(summary.intermediateDirectoriesCleaned, isFalse);
      expect(
        await File(path.join(translationComic.path, 'extra.png')).exists(),
        isTrue,
      );
      expect(await translationComic.exists(), isTrue);
      expect(
        await Directory(
          path.join(workDirectory.path, 'manga_translator_work'),
        ).exists(),
        isTrue,
      );
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

List<int> _pngBytes(int width, int height) => image_lib.encodePng(
  image_lib.Image(width: width, height: height)..setPixelRgb(0, 0, 255, 0, 0),
);

Future<void> _writeImage(String filePath, List<int> bytes) async {
  final file = File(filePath);
  await file.create(recursive: true);
  await file.writeAsBytes(bytes);
}
