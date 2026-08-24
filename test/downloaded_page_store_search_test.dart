import 'package:flutter_test/flutter_test.dart';
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
}
