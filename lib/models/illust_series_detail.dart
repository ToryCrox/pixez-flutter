import 'package:pixez/custom/map_extension.dart';
import 'package:pixez/custom/type_util.dart';
import 'package:pixez/models/illust.dart';

class IllustSeriesDetailResponse {
  final IllustSeriesContext? illustSeriesContext;
  final IllustSeriesDetail? illustSeriesDetail;

  const IllustSeriesDetailResponse({this.illustSeriesContext, this.illustSeriesDetail});

  factory IllustSeriesDetailResponse.fromMap(Map<String, dynamic> map) =>
      IllustSeriesDetailResponse(
        illustSeriesContext: map.optMapOrNull('illust_series_context') == null
            ? null
            : IllustSeriesContext.fromMap(map.optMap('illust_series_context')),
        illustSeriesDetail: map.optMapOrNull('illust_series_detail') == null
            ? null
            : IllustSeriesDetail.fromMap(map.optMap('illust_series_detail')),
      );
  factory IllustSeriesDetailResponse.fromJson(Map<String, dynamic> json) => IllustSeriesDetailResponse.fromMap(json);
  Map<String, dynamic> toMap() => {
        'illust_series_context': illustSeriesContext?.toMap(),
        'illust_series_detail': illustSeriesDetail?.toMap(),
      };
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => (illustSeriesContext == null || illustSeriesContext!.isEmpty) &&
      (illustSeriesDetail == null || illustSeriesDetail!.isEmpty);
  IllustSeriesDetailResponse copyWith({
    Object? illustSeriesContext = TypeUtil.unset,
    Object? illustSeriesDetail = TypeUtil.unset,
  }) =>
      IllustSeriesDetailResponse(
        illustSeriesContext: identical(illustSeriesContext, TypeUtil.unset)
            ? this.illustSeriesContext
            : illustSeriesContext as IllustSeriesContext?,
        illustSeriesDetail: identical(illustSeriesDetail, TypeUtil.unset)
            ? this.illustSeriesDetail
            : illustSeriesDetail as IllustSeriesDetail?,
      );
  @override
  bool operator ==(Object other) => other is IllustSeriesDetailResponse && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'IllustSeriesDetailResponse(${toMap()})';
}

class IllustSeriesContext {
  final int? contentOrder;
  final Illusts? next;
  final Illusts? prev;

  const IllustSeriesContext({this.contentOrder, this.next, this.prev});
  factory IllustSeriesContext.fromMap(Map<String, dynamic> map) => IllustSeriesContext(
        contentOrder: map.optIntOrNull('content_order'),
        next: map.optMapOrNull('next') == null ? null : Illusts.fromMap(map.optMap('next')),
        prev: map.optMapOrNull('prev') == null ? null : Illusts.fromMap(map.optMap('prev')),
      );
  factory IllustSeriesContext.fromJson(Map<String, dynamic> json) => IllustSeriesContext.fromMap(json);
  Map<String, dynamic> toMap() => {
        'content_order': contentOrder,
        'next': next?.toMap(),
        'prev': prev?.toMap(),
      };
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => (contentOrder == null || contentOrder == 0) &&
      (next == null || next!.isEmpty) && (prev == null || prev!.isEmpty);
  IllustSeriesContext copyWith({
    Object? contentOrder = TypeUtil.unset,
    Object? next = TypeUtil.unset,
    Object? prev = TypeUtil.unset,
  }) =>
      IllustSeriesContext(
        contentOrder: identical(contentOrder, TypeUtil.unset) ? this.contentOrder : contentOrder as int?,
        next: identical(next, TypeUtil.unset) ? this.next : next as Illusts?,
        prev: identical(prev, TypeUtil.unset) ? this.prev : prev as Illusts?,
      );
  @override
  bool operator ==(Object other) => other is IllustSeriesContext && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'IllustSeriesContext(${toMap()})';
}

class IllustSeriesDetail {
  final int height;
  final int seriesWorkCount;
  final int id;
  final String createDate;
  final String title;
  final int width;
  final CoverImageUrls coverImageUrls;
  final bool watchlistAdded;
  final String caption;
  final IllustSeriesUser? user;

  const IllustSeriesDetail({
    this.height = 0,
    this.seriesWorkCount = 0,
    this.id = 0,
    this.createDate = '',
    this.title = '',
    this.width = 0,
    this.coverImageUrls = const CoverImageUrls(),
    this.watchlistAdded = false,
    this.caption = '',
    this.user,
  });

  factory IllustSeriesDetail.fromMap(Map<String, dynamic> map) => IllustSeriesDetail(
        height: map.optInt('height'),
        seriesWorkCount: map.optInt('series_work_count'),
        id: map.optInt('id'),
        createDate: map.optString('create_date'),
        title: map.optString('title'),
        width: map.optInt('width'),
        coverImageUrls: CoverImageUrls.fromMap(map.optMap('cover_image_urls')),
        watchlistAdded: map.optBool('watchlist_added'),
        caption: map.optString('caption'),
        user: map.optMapOrNull('user') == null ? null : IllustSeriesUser.fromMap(map.optMap('user')),
      );
  factory IllustSeriesDetail.fromJson(Map<String, dynamic> json) => IllustSeriesDetail.fromMap(json);
  Map<String, dynamic> toMap() => {
        'height': height,
        'series_work_count': seriesWorkCount,
        'id': id,
        'create_date': createDate,
        'title': title,
        'width': width,
        'cover_image_urls': coverImageUrls.toMap(),
        'watchlist_added': watchlistAdded,
        'caption': caption,
        'user': user?.toMap(),
      };
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => height == 0 && seriesWorkCount == 0 && id == 0 &&
      createDate.isEmpty && title.isEmpty && width == 0 &&
      coverImageUrls.isEmpty && !watchlistAdded && caption.isEmpty &&
      (user == null || user!.isEmpty);
  IllustSeriesDetail copyWith({
    int? height,
    int? seriesWorkCount,
    int? id,
    String? createDate,
    String? title,
    int? width,
    CoverImageUrls? coverImageUrls,
    bool? watchlistAdded,
    String? caption,
    Object? user = TypeUtil.unset,
  }) =>
      IllustSeriesDetail(
        height: height ?? this.height,
        seriesWorkCount: seriesWorkCount ?? this.seriesWorkCount,
        id: id ?? this.id,
        createDate: createDate ?? this.createDate,
        title: title ?? this.title,
        width: width ?? this.width,
        coverImageUrls: coverImageUrls ?? this.coverImageUrls,
        watchlistAdded: watchlistAdded ?? this.watchlistAdded,
        caption: caption ?? this.caption,
        user: identical(user, TypeUtil.unset) ? this.user : user as IllustSeriesUser?,
      );
  @override
  bool operator ==(Object other) => other is IllustSeriesDetail && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'IllustSeriesDetail(${toMap()})';
}

class IllustSeriesUser {
  final int id;
  final String account;
  final String name;
  final IllustSeriesProfileImageUrls? profileImageUrls;
  final bool isFollowed;

  const IllustSeriesUser({
    this.id = 0,
    this.account = '',
    this.name = '',
    this.profileImageUrls,
    this.isFollowed = false,
  });

  factory IllustSeriesUser.fromMap(Map<String, dynamic> map) => IllustSeriesUser(
        id: map.optInt('id'),
        account: map.optString('account'),
        name: map.optString('name'),
        profileImageUrls: map.optMapOrNull('profile_image_urls') == null
            ? null
            : IllustSeriesProfileImageUrls.fromMap(map.optMap('profile_image_urls')),
        isFollowed: map.optBool('is_followed'),
      );
  factory IllustSeriesUser.fromJson(Map<String, dynamic> json) => IllustSeriesUser.fromMap(json);
  Map<String, dynamic> toMap() => {
        'id': id,
        'account': account,
        'name': name,
        'profile_image_urls': profileImageUrls?.toMap(),
        'is_followed': isFollowed,
      };
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => id == 0 && account.isEmpty && name.isEmpty &&
      (profileImageUrls == null || profileImageUrls!.isEmpty) && !isFollowed;
  IllustSeriesUser copyWith({
    int? id,
    String? account,
    String? name,
    Object? profileImageUrls = TypeUtil.unset,
    bool? isFollowed,
  }) =>
      IllustSeriesUser(
        id: id ?? this.id,
        account: account ?? this.account,
        name: name ?? this.name,
        profileImageUrls: identical(profileImageUrls, TypeUtil.unset)
            ? this.profileImageUrls
            : profileImageUrls as IllustSeriesProfileImageUrls?,
        isFollowed: isFollowed ?? this.isFollowed,
      );
  @override
  bool operator ==(Object other) => other is IllustSeriesUser && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'IllustSeriesUser(${toMap()})';
}

class IllustSeriesProfileImageUrls {
  final String? medium;
  const IllustSeriesProfileImageUrls({this.medium});
  factory IllustSeriesProfileImageUrls.fromMap(Map<String, dynamic> map) =>
      IllustSeriesProfileImageUrls(medium: map.optStringOrNull('medium'));
  factory IllustSeriesProfileImageUrls.fromJson(Map<String, dynamic> json) => IllustSeriesProfileImageUrls.fromMap(json);
  Map<String, dynamic> toMap() => {'medium': medium};
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => medium == null || medium!.isEmpty;
  IllustSeriesProfileImageUrls copyWith({Object? medium = TypeUtil.unset}) =>
      IllustSeriesProfileImageUrls(medium: identical(medium, TypeUtil.unset) ? this.medium : medium as String?);
  @override
  bool operator ==(Object other) => other is IllustSeriesProfileImageUrls && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'IllustSeriesProfileImageUrls(${toMap()})';
}

class CoverImageUrls {
  final String? medium;
  const CoverImageUrls({this.medium});
  factory CoverImageUrls.fromMap(Map<String, dynamic> map) => CoverImageUrls(medium: map.optStringOrNull('medium'));
  factory CoverImageUrls.fromJson(Map<String, dynamic> json) => CoverImageUrls.fromMap(json);
  Map<String, dynamic> toMap() => {'medium': medium};
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => medium == null || medium!.isEmpty;
  CoverImageUrls copyWith({Object? medium = TypeUtil.unset}) =>
      CoverImageUrls(medium: identical(medium, TypeUtil.unset) ? this.medium : medium as String?);
  @override
  bool operator ==(Object other) => other is CoverImageUrls && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'CoverImageUrls(${toMap()})';
}
