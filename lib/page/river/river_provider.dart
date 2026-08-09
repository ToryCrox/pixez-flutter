import 'package:pixez/main.dart';
import 'package:pixez/models/illust.dart';
import 'package:pixez/models/recommend.dart';
import 'package:pixez/network/api_client.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'river_provider.g.dart';

class IllustListState {
  final List<Illusts> illusts;
  final int? offset;

  IllustListState(this.illusts, this.offset);
}

@Riverpod(keepAlive: true)
class IllustList extends _$IllustList {
  @override
  IllustListState build() => IllustListState([], null);

  Future<void> fetch({int offset = 0}) async {
    try {
      final response = await apiClient.getBookmarksIllustsOffset(
        int.parse(accountStore.now!.userId),
        "public",
        null,
        offset < 30 ? null : offset,
      );
      Recommend recommend = Recommend.fromJson(response.data);
      final nextCursor =
          recommend.illusts.length < 30
              ? null
              : (offset += recommend.illusts.length);
      state = IllustListState(recommend.illusts, nextCursor);
    } catch (e) {}
  }

  Future<void> next() async {
    try {
      if (state.offset == null) return;
      final response = await apiClient.getBookmarksIllustsOffset(
        int.parse(accountStore.now!.userId),
        "public",
        null,
        state.offset,
      );
      Recommend recommend = Recommend.fromJson(response.data);
      final illusts = [...state.illusts, ...recommend.illusts];
      final nextCursor = recommend.illusts.length < 30 ? null : illusts.length;
      state = IllustListState(illusts, nextCursor);
    } catch (e) {}
  }
}
