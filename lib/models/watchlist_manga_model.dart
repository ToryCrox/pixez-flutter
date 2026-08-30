import 'package:pixez/custom/map_extension.dart';
import 'package:pixez/custom/type_util.dart';

class WatchlistMangaModel {
  final List<MangaSeriesModel> series;
  final String? nextUrl;

  const WatchlistMangaModel({this.series = const [], this.nextUrl});
  factory WatchlistMangaModel.fromMap(Map<String, dynamic> map) => WatchlistMangaModel(
        series: [
          ...map.optList(
            'series',
            (e) => MangaSeriesModel.fromMap(TypeUtil.parseMap(e)),
          ),
        ],
        nextUrl: map.optStringOrNull('next_url'),
      );
  factory WatchlistMangaModel.fromJson(Map<String, dynamic> json) => WatchlistMangaModel.fromMap(json);
  Map<String, dynamic> toMap() => {'series': series.map((e) => e.toMap()).toList(), 'next_url': nextUrl};
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => series.isEmpty && nextUrl == null;
  WatchlistMangaModel copyWith({List<MangaSeriesModel>? series, Object? nextUrl = TypeUtil.unset}) =>
      WatchlistMangaModel(
        series: series == null ? [...this.series] : [...series],
        nextUrl: identical(nextUrl, TypeUtil.unset) ? this.nextUrl : nextUrl as String?,
      );
  @override
  bool operator ==(Object other) => other is WatchlistMangaModel && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'WatchlistMangaModel(${toMap()})';
}

class MangaSeriesModel {
  final String? maskText;
  final int latestContentId;
  final int id;
  final MangaSeriesUser? user;
  final String title;
  final String lastPublishedContentDatetime;
  final int publishedContentCount;
  final String? url;

  const MangaSeriesModel({
    this.maskText,
    this.latestContentId = 0,
    this.id = 0,
    this.user,
    this.title = '',
    this.lastPublishedContentDatetime = '',
    this.publishedContentCount = 0,
    this.url,
  });
  factory MangaSeriesModel.fromMap(Map<String, dynamic> map) => MangaSeriesModel(
        maskText: map.optStringOrNull('mask_text'),
        latestContentId: map.optInt('latest_content_id'),
        id: map.optInt('id'),
        user: map.optMapOrNull('user') == null ? null : MangaSeriesUser.fromMap(map.optMap('user')),
        title: map.optString('title'),
        lastPublishedContentDatetime: map.optString('last_published_content_datetime'),
        publishedContentCount: map.optInt('published_content_count'),
        url: map.optStringOrNull('url'),
      );
  factory MangaSeriesModel.fromJson(Map<String, dynamic> json) => MangaSeriesModel.fromMap(json);
  Map<String, dynamic> toMap() => {
        'mask_text': maskText, 'latest_content_id': latestContentId, 'id': id,
        'user': user?.toMap(), 'title': title,
        'last_published_content_datetime': lastPublishedContentDatetime,
        'published_content_count': publishedContentCount, 'url': url,
      };
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => maskText == null && latestContentId == 0 && id == 0 &&
      (user == null || user!.isEmpty) && title.isEmpty &&
      lastPublishedContentDatetime.isEmpty && publishedContentCount == 0 && url == null;
  MangaSeriesModel copyWith({
    Object? maskText = TypeUtil.unset, int? latestContentId, int? id,
    Object? user = TypeUtil.unset, String? title, String? lastPublishedContentDatetime,
    int? publishedContentCount, Object? url = TypeUtil.unset,
  }) => MangaSeriesModel(
        maskText: identical(maskText, TypeUtil.unset) ? this.maskText : maskText as String?,
        latestContentId: latestContentId ?? this.latestContentId, id: id ?? this.id,
        user: identical(user, TypeUtil.unset) ? this.user : user as MangaSeriesUser?,
        title: title ?? this.title,
        lastPublishedContentDatetime: lastPublishedContentDatetime ?? this.lastPublishedContentDatetime,
        publishedContentCount: publishedContentCount ?? this.publishedContentCount,
        url: identical(url, TypeUtil.unset) ? this.url : url as String?,
      );
  @override
  bool operator ==(Object other) => other is MangaSeriesModel && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'MangaSeriesModel(${toMap()})';
}

class MangaSeriesUser {
  final int id;
  final String? account;
  final String? name;
  final MangaSeriesUserProfileImageUrls? profileImageUrls;

  const MangaSeriesUser({this.id = 0, this.account, this.name, this.profileImageUrls});
  factory MangaSeriesUser.fromMap(Map<String, dynamic> map) => MangaSeriesUser(
        id: map.optInt('id'),
        account: map.optStringOrNull('account'),
        name: map.optStringOrNull('name'),
        profileImageUrls: map.optMapOrNull('profile_image_urls') == null
            ? null : MangaSeriesUserProfileImageUrls.fromMap(map.optMap('profile_image_urls')),
      );
  factory MangaSeriesUser.fromJson(Map<String, dynamic> json) => MangaSeriesUser.fromMap(json);
  Map<String, dynamic> toMap() => {
        'id': id, 'account': account, 'name': name, 'profile_image_urls': profileImageUrls?.toMap(),
      };
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => id == 0 && account == null && name == null &&
      (profileImageUrls == null || profileImageUrls!.isEmpty);
  MangaSeriesUser copyWith({
    int? id, Object? account = TypeUtil.unset, Object? name = TypeUtil.unset,
    Object? profileImageUrls = TypeUtil.unset,
  }) => MangaSeriesUser(
        id: id ?? this.id,
        account: identical(account, TypeUtil.unset) ? this.account : account as String?,
        name: identical(name, TypeUtil.unset) ? this.name : name as String?,
        profileImageUrls: identical(profileImageUrls, TypeUtil.unset)
            ? this.profileImageUrls : profileImageUrls as MangaSeriesUserProfileImageUrls?,
      );
  @override
  bool operator ==(Object other) => other is MangaSeriesUser && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'MangaSeriesUser(${toMap()})';
}

class MangaSeriesUserProfileImageUrls {
  final String? medium;
  const MangaSeriesUserProfileImageUrls({this.medium});
  factory MangaSeriesUserProfileImageUrls.fromMap(Map<String, dynamic> map) =>
      MangaSeriesUserProfileImageUrls(medium: map.optStringOrNull('medium'));
  factory MangaSeriesUserProfileImageUrls.fromJson(Map<String, dynamic> json) =>
      MangaSeriesUserProfileImageUrls.fromMap(json);
  Map<String, dynamic> toMap() => {'medium': medium};
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => medium == null || medium!.isEmpty;
  MangaSeriesUserProfileImageUrls copyWith({Object? medium = TypeUtil.unset}) =>
      MangaSeriesUserProfileImageUrls(medium: identical(medium, TypeUtil.unset) ? this.medium : medium as String?);
  @override
  bool operator ==(Object other) => other is MangaSeriesUserProfileImageUrls && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'MangaSeriesUserProfileImageUrls(${toMap()})';
}
