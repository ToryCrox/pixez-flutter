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
      final untranslatedOriginal = File(path.join(workDirectory.path, '2.webp'));
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
