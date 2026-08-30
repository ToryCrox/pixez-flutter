import 'package:pixez/custom/map_extension.dart';
import 'package:pixez/custom/type_util.dart';
import 'package:pixez/models/illust.dart';
import 'package:pixez/models/illust_series_detail.dart'
    show CoverImageUrls, IllustSeriesUser;

class IllustSeriesWithIdModel {
  final IllustSeriesDetail? illustSeriesDetail;
  final Illusts? illustSeriesFirstIllust;
  final List<Illusts>? illusts;
  final String? nextUrl;

  const IllustSeriesWithIdModel({
    this.illustSeriesDetail,
    this.illustSeriesFirstIllust,
    this.illusts,
    this.nextUrl,
  });

  factory IllustSeriesWithIdModel.fromMap(Map<String, dynamic> map) =>
      IllustSeriesWithIdModel(
        illustSeriesDetail: map.optMapOrNull('illust_series_detail') == null
            ? null
            : IllustSeriesDetail.fromMap(map.optMap('illust_series_detail')),
        illustSeriesFirstIllust: map.optMapOrNull('illust_series_first_illust') == null
            ? null
            : Illusts.fromMap(map.optMap('illust_series_first_illust')),
        illusts: map['illusts'] == null
            ? null
            : [
                ...map.optList(
                  'illusts',
                  (e) => Illusts.fromMap(TypeUtil.parseMap(e)),
                ),
              ],
        nextUrl: map.optStringOrNull('next_url'),
      );
  factory IllustSeriesWithIdModel.fromJson(Map<String, dynamic> json) =>
      IllustSeriesWithIdModel.fromMap(json);
  Map<String, dynamic> toMap() => {
        'illust_series_detail': illustSeriesDetail?.toMap(),
        'illust_series_first_illust': illustSeriesFirstIllust?.toMap(),
        'illusts': illusts?.map((e) => e.toMap()).toList(),
        'next_url': nextUrl,
      };
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => (illustSeriesDetail == null || illustSeriesDetail!.isEmpty) &&
      (illustSeriesFirstIllust == null || illustSeriesFirstIllust!.isEmpty) &&
      (illusts == null || illusts!.isEmpty) && nextUrl == null;
  IllustSeriesWithIdModel copyWith({
    Object? illustSeriesDetail = TypeUtil.unset,
    Object? illustSeriesFirstIllust = TypeUtil.unset,
    Object? illusts = TypeUtil.unset,
    Object? nextUrl = TypeUtil.unset,
  }) =>
      IllustSeriesWithIdModel(
        illustSeriesDetail: identical(illustSeriesDetail, TypeUtil.unset)
            ? this.illustSeriesDetail
            : illustSeriesDetail as IllustSeriesDetail?,
        illustSeriesFirstIllust: identical(illustSeriesFirstIllust, TypeUtil.unset)
            ? this.illustSeriesFirstIllust
            : illustSeriesFirstIllust as Illusts?,
        illusts: identical(illusts, TypeUtil.unset)
            ? (this.illusts == null ? null : [...this.illusts!])
            : illusts == null
                ? null
                : [...illusts as List<Illusts>],
        nextUrl: identical(nextUrl, TypeUtil.unset) ? this.nextUrl : nextUrl as String?,
      );
  @override
  bool operator ==(Object other) => other is IllustSeriesWithIdModel &&
      TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'IllustSeriesWithIdModel(${toMap()})';
}

class IllustSeriesDetail {
  final int id;
  final String title;
  final String createDate;
  final String caption;
  final IllustSeriesUser? user;
  final CoverImageUrls? coverImageUrls;
  final int seriesWorkCount;
  final bool watchlistAdded;

  const IllustSeriesDetail({
    this.id = 0,
    this.title = '',
    this.createDate = '',
    this.caption = '',
    this.user,
    this.coverImageUrls,
    this.seriesWorkCount = 0,
    this.watchlistAdded = false,
  });

  factory IllustSeriesDetail.fromMap(Map<String, dynamic> map) => IllustSeriesDetail(
        id: map.optInt('id'),
        title: map.optString('title'),
        createDate: map.optString('create_date'),
        caption: map.optString('caption'),
        user: map.optMapOrNull('user') == null
            ? null
            : IllustSeriesUser.fromMap(map.optMap('user')),
        coverImageUrls: map.optMapOrNull('cover_image_urls') == null
            ? null
            : CoverImageUrls.fromMap(map.optMap('cover_image_urls')),
        seriesWorkCount: map.optInt('series_work_count'),
        watchlistAdded: map.optBool('watchlist_added'),
      );
  factory IllustSeriesDetail.fromJson(Map<String, dynamic> json) =>
      IllustSeriesDetail.fromMap(json);
  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'create_date': createDate,
        'caption': caption,
        'user': user?.toMap(),
        'cover_image_urls': coverImageUrls?.toMap(),
        'series_work_count': seriesWorkCount,
        'watchlist_added': watchlistAdded,
      };
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => id == 0 && title.isEmpty && createDate.isEmpty &&
      caption.isEmpty && (user == null || user!.isEmpty) &&
      (coverImageUrls == null || coverImageUrls!.isEmpty) &&
      seriesWorkCount == 0 && !watchlistAdded;
  IllustSeriesDetail copyWith({
    int? id,
    String? title,
    String? createDate,
    String? caption,
    Object? user = TypeUtil.unset,
    Object? coverImageUrls = TypeUtil.unset,
    int? seriesWorkCount,
    bool? watchlistAdded,
  }) =>
      IllustSeriesDetail(
        id: id ?? this.id,
        title: title ?? this.title,
        createDate: createDate ?? this.createDate,
        caption: caption ?? this.caption,
        user: identical(user, TypeUtil.unset) ? this.user : user as IllustSeriesUser?,
        coverImageUrls: identical(coverImageUrls, TypeUtil.unset)
            ? this.coverImageUrls
            : coverImageUrls as CoverImageUrls?,
        seriesWorkCount: seriesWorkCount ?? this.seriesWorkCount,
        watchlistAdded: watchlistAdded ?? this.watchlistAdded,
      );
  @override
  bool operator ==(Object other) => other is IllustSeriesDetail &&
      TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'IllustSeriesDetail(${toMap()})';
}
