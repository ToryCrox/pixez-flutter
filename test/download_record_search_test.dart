import 'dart:io';

import 'package:flutter_test/flutter_test.dart' hide Tags;
import 'package:pixez/models/download_record.dart';
import 'package:pixez/models/illust.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('下载作品搜索', () {
    late Directory temporary;
    late DownloadDatabaseProvider provider;

    setUp(() async {
      temporary = await Directory.systemTemp.createTemp('pixez_search_test_');
      provider = DownloadDatabaseProvider();
      await provider.open(temporary.path);
    });

    tearDown(() async {
      await provider.db.close();
      if (await temporary.exists()) {
        await temporary.delete(recursive: true);
      }
    });

    test('纯数字关键词按插画 ID 精确匹配', () async {
      await provider.insertIllust(
        _record(
          123,
          title: '标题包含 123',
          userName: '作者 123',
          tags: ['tag123'],
          downloadedImageCount: 2,
          totalFileSize: 200,
        ),
      );
      await provider.insertIllust(
        _record(1234, title: '另一个作品', userName: '普通作者'),
      );
      await provider.insertIllust(
        _record(567, title: '不相关作品', userName: '普通作者'),
      );

      final results = await provider.searchIllusts(' 123 ');

      expect(results.map((e) => e.illustId), [123]);

      final stats = await provider.getFilteredStats(
        filterType: 'search',
        searchKeyword: ' 123 ',
      );
      expect(stats, {'illust_count': 1, 'image_count': 2, 'file_size': 200});
    });

    test('非数字关键词仍按标题、作者名和标签模糊匹配', () async {
      await provider.insertIllust(
        _record(123, title: '目标标题', userName: '普通作者'),
      );
      await provider.insertIllust(
        _record(456, title: '普通标题', userName: '目标作者'),
      );
      await provider.insertIllust(
        _record(789, title: '普通标题', userName: '普通作者', tags: ['目标标签']),
      );

      final results = await provider.searchIllusts('目标');

      expect(results.map((e) => e.illustId).toSet(), {123, 456, 789});
    });
  });

  group('下载作者搜索', () {
    late Directory temporary;
    late DownloadDatabaseProvider provider;

    setUp(() async {
      temporary = await Directory.systemTemp.createTemp(
        'pixez_author_search_test_',
      );
      provider = DownloadDatabaseProvider();
      await provider.open(temporary.path);
    });

    tearDown(() async {
      await provider.db.close();
      if (await temporary.exists()) {
        await temporary.delete(recursive: true);
      }
    });

    test('纯数字关键词按作者 ID 精确匹配', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await provider.upsertAuthor(123, '作者123', null, 2, 3, 300, now);
      await provider.upsertAuthor(1234, '普通作者', null, 1, 1, 100, now);
      await provider.upsertAuthor(567, 'artist123', null, 1, 1, 100, now);
      await provider.updateAuthorBookmark(123, 1);

      final results = await provider.getAuthorsWithStats(
        searchKeyword: ' 123 ',
        filterBookmarks: true,
        filterUserIds: [123, 1234, 567],
        limit: 1,
      );

      expect(results.map((e) => e.userId), [123]);
    });

    test('非数字关键词仍按作者名模糊匹配', () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await provider.upsertAuthor(123, '目标作者', null, 1, 1, 100, now);
      await provider.upsertAuthor(456, '普通作者', null, 1, 1, 100, now);

      final results = await provider.getAuthorsWithStats(searchKeyword: '目标');

      expect(results.map((e) => e.userId), [123]);
    });
  });
}

DownloadedIllust _record(
  int id, {
  required String title,
  required String userName,
  List<String> tags = const [],
  int downloadedImageCount = 1,
  int totalFileSize = 100,
}) {
  final illust = Illusts(
    id: id,
    title: title,
    type: 'illust',
    user: User(id: id, name: userName),
    tags: tags.map((name) => Tags(name: name)).toList(),
    pageCount: 2,
    visible: true,
  );
  return DownloadedIllust.fromIllusts(
    illust,
    'download/$id',
    downloadedImageCount: downloadedImageCount,
    totalFileSize: totalFileSize,
  );
}
