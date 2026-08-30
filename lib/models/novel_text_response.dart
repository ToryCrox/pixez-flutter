import 'package:pixez/custom/map_extension.dart';
import 'package:pixez/custom/type_util.dart';

class NovelTextResponse {
  final NovelMarker novelMarker;
  final String novelText;
  final TextNovel? seriesPrev;
  final TextNovel? seriesNext;

  const NovelTextResponse({
    this.novelMarker = const NovelMarker(),
    this.novelText = '',
    this.seriesPrev,
    this.seriesNext,
  });
  factory NovelTextResponse.fromMap(Map<String, dynamic> map) => NovelTextResponse(
        novelMarker: NovelMarker.fromMap(map.optMap('novel_marker')),
        novelText: map.optString('novel_text'),
        seriesPrev: map.optMapOrNull('series_prev') == null ? null : TextNovel.fromMap(map.optMap('series_prev')),
        seriesNext: map.optMapOrNull('series_next') == null ? null : TextNovel.fromMap(map.optMap('series_next')),
      );
  factory NovelTextResponse.fromJson(Map<String, dynamic> json) => NovelTextResponse.fromMap(json);
  Map<String, dynamic> toMap() => {
        'novel_marker': novelMarker.toMap(), 'novel_text': novelText,
        'series_prev': seriesPrev?.toMap(), 'series_next': seriesNext?.toMap(),
      };
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => novelMarker.isEmpty && novelText.isEmpty &&
      (seriesPrev == null || seriesPrev!.isEmpty) && (seriesNext == null || seriesNext!.isEmpty);
  NovelTextResponse copyWith({
    NovelMarker? novelMarker, String? novelText,
    Object? seriesPrev = TypeUtil.unset, Object? seriesNext = TypeUtil.unset,
  }) => NovelTextResponse(
        novelMarker: novelMarker ?? this.novelMarker, novelText: novelText ?? this.novelText,
        seriesPrev: identical(seriesPrev, TypeUtil.unset) ? this.seriesPrev : seriesPrev as TextNovel?,
        seriesNext: identical(seriesNext, TypeUtil.unset) ? this.seriesNext : seriesNext as TextNovel?,
      );
  @override
  bool operator ==(Object other) => other is NovelTextResponse && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'NovelTextResponse(${toMap()})';
}

class NovelMarker {
  final int? page;
  const NovelMarker({this.page});
  factory NovelMarker.fromMap(Map<String, dynamic> map) => NovelMarker(page: map.optIntOrNull('page'));
  factory NovelMarker.fromJson(Map<String, dynamic> json) => NovelMarker.fromMap(json);
  Map<String, dynamic> toMap() => {'page': page};
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => page == null || page == 0;
  NovelMarker copyWith({Object? page = TypeUtil.unset}) =>
      NovelMarker(page: identical(page, TypeUtil.unset) ? this.page : page as int?);
  @override
  bool operator ==(Object other) => other is NovelMarker && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'NovelMarker(${toMap()})';
}

class TextNovel {
  final int? id;
  final String? title;
  const TextNovel({this.id, this.title});
  factory TextNovel.fromMap(Map<String, dynamic> map) => TextNovel(
        id: map.optIntOrNull('id'), title: map.optStringOrNull('title'),
      );
  factory TextNovel.fromJson(Map<String, dynamic> json) => TextNovel.fromMap(json);
  Map<String, dynamic> toMap() => {'id': id, 'title': title};
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => id == null && title == null;
  TextNovel copyWith({Object? id = TypeUtil.unset, Object? title = TypeUtil.unset}) => TextNovel(
        id: identical(id, TypeUtil.unset) ? this.id : id as int?,
        title: identical(title, TypeUtil.unset) ? this.title : title as String?,
      );
  @override
  bool operator ==(Object other) => other is TextNovel && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'TextNovel(${toMap()})';
}
