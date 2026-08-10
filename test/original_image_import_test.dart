import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as image_lib;
import 'package:path/path.dart' as p;
import 'package:pixez/models/download_record.dart';
import 'package:pixez/models/illust.dart';
import 'package:pixez/models/original_image.dart';
import 'package:pixez/models/original_image_repository.dart';
import 'package:pixez/store/download_store.dart';
import 'package:pixez/store/original_import_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => Directory.systemTemp.path,
        );
  });

  group('原图数据库与显示清单', () {
    late Directory temporary;
    late DownloadDatabaseProvider provider;
    late OriginalImageRepository repository;

    setUp(() async {
      temporary = await Directory.systemTemp.createTemp('pixez_original_test_');
      provider = DownloadDatabaseProvider();
      await provider.open(temporary.path);
      repository = OriginalImageRepository(provider);
    });

    tearDown(() async {
      await provider.db.close();
      if (await temporary.exists()) await temporary.delete(recursive: true);
    });

    test('原图表存在且不进入下载统计', () async {
      final illust = _illust(100, pageCount: 2);
      final record = DownloadedIllust.fromIllusts(
        illust,
        p.join('download', '[作者][1]', '[100]测试'),
      );
      await provider.insertIllust(record);
      expect(await provider.getIllustCount(), 0);

      final originalRelative = p.join('author', 'work', 'edition', '1.png');
      final originalFile = File(
        p.join(provider.originalPath, originalRelative),
      );
      await originalFile.parent.create(recursive: true);
      await originalFile.writeAsBytes(_pngBytes());
      final now = DateTime.now().millisecondsSinceEpoch;
      await repository.insertSetWithContent(
        set: OriginalImageSet(
          illustId: 100,
          editionName: '默认版',
          storageKey: 'storage_100',
          relativePath: p.dirname(originalRelative),
          imageCount: 1,
          totalFileSize: await originalFile.length(),
          enhancedPageCount: 2,
          isDefault: true,
          createdAt: now,
          updatedAt: now,
        ),
        images: [
          OriginalImageDraft(
            sourceOrder: 0,
            fileName: '1',
            relativePath: originalRelative,
            extension: '.png',
            fileSize: await originalFile.length(),
            width: 8,
            height: 8,
            sha256: 'hash',
          ),
        ],
        mappings: const [
          OriginalMappingDraft(
            displayOrder: 0,
            downloadedPart: 0,
            originalSourceOrder: 0,
            relationType: OriginalRelationType.replacement,
          ),
          OriginalMappingDraft(
            displayOrder: 1,
            downloadedPart: 1,
            relationType: OriginalRelationType.downloadFallback,
          ),
        ],
      );

      final stats = await repository.getStats();
      expect(stats['image_count'], 1);
      expect(await provider.getIllustCount(), 0);
      final manifest = await repository.buildDisplayManifest(100);
      expect(manifest.hasOriginal, isTrue);
      expect(manifest.pageCount, 1, reason: '缺失的下载补位页应自动隐藏');
      expect(manifest.pages.single.originalImageInfo?.path, originalFile.path);
      await repository.markDownloadResourcesRemoved(100);
      expect(await provider.getIncompleteIllusts(), isEmpty);
      expect(await provider.getIllustsWithNonWebPImages(), isEmpty);
      expect(await originalFile.exists(), isTrue);
    });

    test('本地作品使用递减负数且可关联 Pixiv 作品', () async {
      await provider.upsertAuthor(1, '作者', '', 0, 0, 0, 0);
      final first = await repository.createLocalIllust(
        userId: 1,
        userName: '作者',
        title: '本地一',
        createDate: DateTime(2025),
      );
      final second = await repository.createLocalIllust(
        userId: 1,
        userName: '作者',
        title: '本地二',
        createDate: DateTime(2025),
      );
      expect(first.illustId, -1);
      expect(second.illustId, -2);

      await provider.insertIllust(
        DownloadedIllust.fromIllusts(_illust(200), 'download/200'),
      );
      await repository.linkLocalToPixiv(first.illustId, 200);
      expect(await provider.getIllustByIllustId(first.illustId), isNull);
      expect(await provider.getIllustByIllustId(200), isNotNull);
    });
  });

  test('Manifest 使用暂存目录且取消不修改来源', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'pixez_manifest_test_',
    );
    final source = Directory(p.join(temporary.path, 'source'));
    await source.create();
    final sourceFile = File(p.join(source.path, '1.png'));
    await sourceFile.writeAsBytes(_pngBytes());
    final provider = DownloadDatabaseProvider();
    await provider.open(p.join(temporary.path, 'downloads'));
    await provider.insertIllust(
      DownloadedIllust.fromIllusts(_illust(300), 'download/300'),
    );
    final service = OriginalImportService(provider);
    final manifest = await service.prepareSingleImport(
      sourceDirectory: source.path,
      targetIllustId: 300,
    );
    final manifestFile = File(
      p.join(
        provider.originalPath,
        '.staging',
        manifest.jobId,
        'manifest.json',
      ),
    );
    expect(await manifestFile.exists(), isTrue);
    expect(await File('${manifestFile.path}.tmp').exists(), isFalse);
    await service.cancel(manifest);
    expect(await sourceFile.exists(), isTrue);
    expect(await manifestFile.exists(), isFalse);
    await provider.db.close();
    await temporary.delete(recursive: true);
  });

  test('同名版本增量更新复用版本并保留来源中消失的图片', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'pixez_update_test_',
    );
    final source = Directory(p.join(temporary.path, 'source'));
    await source.create();
    final firstFile = File(p.join(source.path, '1.png'));
    await firstFile.writeAsBytes(_pngBytes());
    final provider = DownloadDatabaseProvider();
    await provider.open(p.join(temporary.path, 'downloads'));
    await provider.insertIllust(
      DownloadedIllust.fromIllusts(_illust(350), 'download/350'),
    );
    final service = OriginalImportService(provider);
    final first = await service.prepareSingleImport(
      sourceDirectory: source.path,
      targetIllustId: 350,
      editionName: '默认版',
    );
    await service.execute(first);

    final secondFile = File(p.join(source.path, '2.png'));
    final secondImage = image_lib.Image(width: 8, height: 8)
      ..setPixelRgb(0, 0, 0, 255, 0);
    await secondFile.writeAsBytes(image_lib.encodePng(secondImage));
    final update = await service.prepareSingleImport(
      sourceDirectory: source.path,
      targetIllustId: 350,
      editionName: '默认版',
      mode: OriginalImportMode.update,
    );
    expect(update.items.single.existingSetId, isNotNull);
    await service.execute(update);

    await firstFile.delete();
    final retainUpdate = await service.prepareSingleImport(
      sourceDirectory: source.path,
      targetIllustId: 350,
      editionName: '默认版',
      mode: OriginalImportMode.update,
    );
    await service.execute(retainUpdate);
    final repository = OriginalImageRepository(provider);
    final sets = await repository.getSetsForIllust(350);
    expect(sets, hasLength(1));
    expect(sets.single.imageCount, 2);
    final bundle = await repository.getBundle(sets.single.id!);
    expect(bundle!.images, hasLength(2));

    await provider.db.close();
    await temporary.delete(recursive: true);
  });

  test('启动期查询会等待下载数据库完成初始化', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'pixez_download_store_init_test_',
    );
    final store = DownloadStore();
    var queryCompleted = false;
    final pendingQuery = store.getDownloadedIllust(999).then((value) {
      queryCompleted = true;
      return value;
    });

    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(store.isInitialized, isFalse);
    expect(queryCompleted, isFalse);

    await store.init(temporary.path);
    expect(store.isInitialized, isTrue);
    expect(await pendingQuery, isNull);
    expect(queryCompleted, isTrue);

    await store.dbProvider.db.close();
    store.dispose();
    await temporary.delete(recursive: true);
  });

  test('v18 升级会创建 pre_v19 备份和原图表', () async {
    sqfliteFfiInit();
    final temporary = await Directory.systemTemp.createTemp(
      'pixez_migration_test_',
    );
    final dbPath = p.join(temporary.path, 'download.db');
    final db = await databaseFactoryFfi.openDatabase(dbPath);
    await db.execute(
      'CREATE TABLE downloaded_illusts (illust_id INTEGER PRIMARY KEY)',
    );
    await db.execute('PRAGMA user_version = 18');
    await db.close();

    final provider = DownloadDatabaseProvider();
    await provider.open(temporary.path);
    expect(await File('$dbPath.pre_v19.bak').exists(), isTrue);
    final columns = await provider.db.rawQuery(
      'PRAGMA table_info(downloaded_illusts)',
    );
    expect(columns.any((row) => row['name'] == 'source_type'), isTrue);
    final tables = await provider.db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE 'original_%'",
    );
    expect(tables.length, 3);
    await provider.db.close();
    await temporary.delete(recursive: true);
  });
}

Illusts _illust(int id, {int pageCount = 1}) => Illusts(
  id: id,
  title: '测试$id',
  type: pageCount > 1 ? 'manga' : 'illust',
  user: User(id: 1, name: '作者'),
  createDate: DateTime(2025, 1, 1).toIso8601String(),
  pageCount: pageCount,
  visible: true,
);

List<int> _pngBytes() => image_lib.encodePng(
  image_lib.Image(width: 8, height: 8)..setPixelRgb(0, 0, 255, 0, 0),
);
