import 'package:pixez/custom/map_extension.dart';
import 'package:pixez/custom/type_util.dart';

class NovelWatchListModel {
  final List<NovelSeriesModel> series;
  final String? nextUrl;

  const NovelWatchListModel({this.series = const [], this.nextUrl});
  factory NovelWatchListModel.fromMap(Map<String, dynamic> map) => NovelWatchListModel(
        series: [
          ...map.optList(
            'series',
            (e) => NovelSeriesModel.fromMap(TypeUtil.parseMap(e)),
          ),
        ],
        nextUrl: map.optStringOrNull('next_url'),
      );
  factory NovelWatchListModel.fromJson(Map<String, dynamic> json) => NovelWatchListModel.fromMap(json);
  Map<String, dynamic> toMap() => {
        'series': series.map((e) => e.toMap()).toList(),
        'next_url': nextUrl,
      };
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => series.isEmpty && nextUrl == null;
  NovelWatchListModel copyWith({List<NovelSeriesModel>? series, Object? nextUrl = TypeUtil.unset}) =>
      NovelWatchListModel(
        series: series == null ? [...this.series] : [...series],
        nextUrl: identical(nextUrl, TypeUtil.unset) ? this.nextUrl : nextUrl as String?,
      );
  @override
  bool operator ==(Object other) => other is NovelWatchListModel && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'NovelWatchListModel(${toMap()})';
}

class NovelSeriesModel {
  final int id;
  final String title;
  final String? url;
  final String? maskText;
  final int publishedContentCount;
  final String lastPublishedContentDatetime;
  final int latestContentId;
  final NovelSeriesUser? user;

  const NovelSeriesModel({
    this.id = 0,
    this.title = '',
    this.url,
    this.maskText,
    this.publishedContentCount = 0,
    this.lastPublishedContentDatetime = '',
    this.latestContentId = 0,
    this.user,
  });
  factory NovelSeriesModel.fromMap(Map<String, dynamic> map) => NovelSeriesModel(
        id: map.optInt('id'),
        title: map.optString('title'),
        url: map.optStringOrNull('url'),
        maskText: map.optStringOrNull('mask_text'),
        publishedContentCount: map.optInt('published_content_count'),
        lastPublishedContentDatetime: map.optString('last_published_content_datetime'),
        latestContentId: map.optInt('latest_content_id'),
        user: map.optMapOrNull('user') == null ? null : NovelSeriesUser.fromMap(map.optMap('user')),
      );
  factory NovelSeriesModel.fromJson(Map<String, dynamic> json) => NovelSeriesModel.fromMap(json);
  Map<String, dynamic> toMap() => {
        'id': id, 'title': title, 'url': url, 'mask_text': maskText,
        'published_content_count': publishedContentCount,
        'last_published_content_datetime': lastPublishedContentDatetime,
        'latest_content_id': latestContentId, 'user': user?.toMap(),
      };
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => id == 0 && title.isEmpty && url == null && maskText == null &&
      publishedContentCount == 0 && lastPublishedContentDatetime.isEmpty &&
      latestContentId == 0 && (user == null || user!.isEmpty);
  NovelSeriesModel copyWith({
    int? id, String? title, Object? url = TypeUtil.unset, Object? maskText = TypeUtil.unset,
    int? publishedContentCount, String? lastPublishedContentDatetime, int? latestContentId,
    Object? user = TypeUtil.unset,
  }) => NovelSeriesModel(
        id: id ?? this.id, title: title ?? this.title,
        url: identical(url, TypeUtil.unset) ? this.url : url as String?,
        maskText: identical(maskText, TypeUtil.unset) ? this.maskText : maskText as String?,
        publishedContentCount: publishedContentCount ?? this.publishedContentCount,
        lastPublishedContentDatetime: lastPublishedContentDatetime ?? this.lastPublishedContentDatetime,
        latestContentId: latestContentId ?? this.latestContentId,
        user: identical(user, TypeUtil.unset) ? this.user : user as NovelSeriesUser?,
      );
  @override
  bool operator ==(Object other) => other is NovelSeriesModel && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'NovelSeriesModel(${toMap()})';
}

class NovelSeriesUser {
  final int id;
  final String name;
  final String account;
  final NovelSeriesUserProfileImageUrls? profileImageUrls;
  final bool isAcceptRequest;

  const NovelSeriesUser({
    this.id = 0, this.name = '', this.account = '', this.profileImageUrls, this.isAcceptRequest = false,
  });
  factory NovelSeriesUser.fromMap(Map<String, dynamic> map) => NovelSeriesUser(
        id: map.optInt('id'),
        name: map.optString('name'),
        account: map.optString('account'),
        profileImageUrls: map.optMapOrNull('profile_image_urls') == null
            ? null : NovelSeriesUserProfileImageUrls.fromMap(map.optMap('profile_image_urls')),
        isAcceptRequest: map.optBool('is_accept_request'),
      );
  factory NovelSeriesUser.fromJson(Map<String, dynamic> json) => NovelSeriesUser.fromMap(json);
  Map<String, dynamic> toMap() => {
        'id': id, 'name': name, 'account': account,
        'profile_image_urls': profileImageUrls?.toMap(),
        'is_accept_request': isAcceptRequest,
      };
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => id == 0 && name.isEmpty && account.isEmpty &&
      (profileImageUrls == null || profileImageUrls!.isEmpty) && !isAcceptRequest;
  NovelSeriesUser copyWith({
    int? id, String? name, String? account,
    Object? profileImageUrls = TypeUtil.unset, bool? isAcceptRequest,
  }) => NovelSeriesUser(
        id: id ?? this.id, name: name ?? this.name, account: account ?? this.account,
        profileImageUrls: identical(profileImageUrls, TypeUtil.unset)
            ? this.profileImageUrls : profileImageUrls as NovelSeriesUserProfileImageUrls?,
        isAcceptRequest: isAcceptRequest ?? this.isAcceptRequest,
      );
  @override
  bool operator ==(Object other) => other is NovelSeriesUser && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'NovelSeriesUser(${toMap()})';
}

class NovelSeriesUserProfileImageUrls {
  final String? medium;
  const NovelSeriesUserProfileImageUrls({this.medium});
  factory NovelSeriesUserProfileImageUrls.fromMap(Map<String, dynamic> map) =>
      NovelSeriesUserProfileImageUrls(medium: map.optStringOrNull('medium'));
  factory NovelSeriesUserProfileImageUrls.fromJson(Map<String, dynamic> json) =>
      NovelSeriesUserProfileImageUrls.fromMap(json);
  Map<String, dynamic> toMap() => {'medium': medium};
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => medium == null || medium!.isEmpty;
  NovelSeriesUserProfileImageUrls copyWith({Object? medium = TypeUtil.unset}) =>
      NovelSeriesUserProfileImageUrls(medium: identical(medium, TypeUtil.unset) ? this.medium : medium as String?);
  @override
  bool operator ==(Object other) => other is NovelSeriesUserProfileImageUrls && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'NovelSeriesUserProfileImageUrls(${toMap()})';
}
