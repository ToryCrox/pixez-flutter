import 'package:flutter_test/flutter_test.dart';
import 'package:pixez/page/downloaded/downloaded_authors_page_store.dart';
import 'package:pixez/page/downloaded/downloaded_page_store.dart';

void main() {
  test('空搜索词进入和退出搜索模式不会触发加载', () async {
    final store = DownloadedPageStore();
    addTearDown(store.dispose);

    expect(store.loading, isTrue);

    store.toggleSearch(isSearching: true);
    store.toggleSearch(isSearching: false, onClear: () {});
    await Future<void>.delayed(Duration.zero);

    expect(store.isSearching, isFalse);
    expect(store.searchKeyword, isNull);
    expect(store.loading, isTrue);
  });

  test('下载作者页空搜索词进入和退出不会残留搜索状态', () async {
    final store = DownloadedAuthorsPageStore();
    addTearDown(store.dispose);

    store.toggleSearch(isSearching: true);
    store.toggleSearch(isSearching: false, onClear: () {});
    await Future<void>.delayed(Duration.zero);

    expect(store.isSearching, isFalse);
    expect(store.searchKeyword, isNull);
  });

  test('下载作者页退出搜索会取消待执行的搜索防抖', () async {
    final store = DownloadedAuthorsPageStore();
    addTearDown(store.dispose);

    store.toggleSearch(isSearching: true);
    store.onSearchChanged('123');
    store.toggleSearch(
      isSearching: false,
      onClear: () => store.onSearchChanged(''),
    );
    await Future<void>.delayed(const Duration(milliseconds: 350));

    expect(store.isSearching, isFalse);
    expect(store.searchKeyword, isNull);
  });
}
