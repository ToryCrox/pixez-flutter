import 'package:pixez/custom/map_extension.dart';
import 'package:pixez/custom/type_util.dart';
import 'package:pixez/models/illust.dart';

class UserPreviewsResponse {
  final List<UserPreviews> userPreviews;
  final String? nextUrl;

  const UserPreviewsResponse({this.userPreviews = const [], this.nextUrl});

  factory UserPreviewsResponse.fromMap(Map<String, dynamic> map) => UserPreviewsResponse(
        userPreviews: [
          ...map.optList(
            'user_previews',
            (e) => UserPreviews.fromMap(TypeUtil.parseMap(e)),
          ),
        ],
        nextUrl: map.optStringOrNull('next_url'),
      );
  factory UserPreviewsResponse.fromJson(Map<String, dynamic> json) => UserPreviewsResponse.fromMap(json);
  Map<String, dynamic> toMap() => {
        'user_previews': userPreviews.map((e) => e.toMap()).toList(),
        'next_url': nextUrl,
      };
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => TypeUtil.allEmpty([userPreviews, nextUrl]);
  UserPreviewsResponse copyWith({List<UserPreviews>? userPreviews, Object? nextUrl = TypeUtil.unset}) =>
      UserPreviewsResponse(
        userPreviews: userPreviews == null ? [...this.userPreviews] : [...userPreviews],
        nextUrl: identical(nextUrl, TypeUtil.unset) ? this.nextUrl : nextUrl as String?,
      );
  @override
  bool operator ==(Object other) => other is UserPreviewsResponse && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'UserPreviewsResponse(${toMap()})';
}

class UserPreviews {
  final User user;
  final List<Illusts> illusts;
  final List<UserPreviewsNovel> novels;
  final bool isMuted;

  const UserPreviews({
    this.user = const User(),
    this.illusts = const [],
    this.novels = const [],
    this.isMuted = false,
  });

  factory UserPreviews.fromMap(Map<String, dynamic> map) => UserPreviews(
        user: User.fromMap(map.optMap('user')),
        illusts: [
          ...map.optList(
            'illusts',
            (e) => Illusts.fromMap(TypeUtil.parseMap(e)),
          ),
        ],
        novels: [
          ...map.optList(
            'novels',
            (e) => UserPreviewsNovel.fromMap(TypeUtil.parseMap(e)),
          ),
        ],
        isMuted: map.optBool('is_muted'),
      );
  factory UserPreviews.fromJson(Map<String, dynamic> json) => UserPreviews.fromMap(json);
  Map<String, dynamic> toMap() => {
        'user': user.toMap(),
        'illusts': illusts.map((e) => e.toMap()).toList(),
        'novels': novels.map((e) => e.toMap()).toList(),
        'is_muted': isMuted,
      };
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => user.isEmpty && illusts.isEmpty && novels.isEmpty && !isMuted;
  UserPreviews copyWith({User? user, List<Illusts>? illusts, List<UserPreviewsNovel>? novels, bool? isMuted}) =>
      UserPreviews(
        user: user ?? this.user,
        illusts: illusts == null ? [...this.illusts] : [...illusts],
        novels: novels == null ? [...this.novels] : [...novels],
        isMuted: isMuted ?? this.isMuted,
      );
  @override
  bool operator ==(Object other) => other is UserPreviews && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'UserPreviews(${toMap()})';
}

class UserPreviewsNovel {
  final int id;
  final String title;
  final String? caption;
  final ImageUrls imageUrls;

  const UserPreviewsNovel({
    this.id = 0,
    this.title = '',
    this.caption,
    this.imageUrls = const ImageUrls(),
  });

  factory UserPreviewsNovel.fromMap(Map<String, dynamic> map) => UserPreviewsNovel(
        id: map.optInt('id'),
        title: map.optString('title'),
        caption: map.optStringOrNull('caption'),
        imageUrls: ImageUrls.fromMap(map.optMap('image_urls')),
      );
  factory UserPreviewsNovel.fromJson(Map<String, dynamic> json) => UserPreviewsNovel.fromMap(json);
  Map<String, dynamic> toMap() => {
        'id': id, 'title': title, 'caption': caption, 'image_urls': imageUrls.toMap(),
      };
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => id == 0 && title.isEmpty && caption == null && imageUrls.isEmpty;
  UserPreviewsNovel copyWith({int? id, String? title, Object? caption = TypeUtil.unset, ImageUrls? imageUrls}) =>
      UserPreviewsNovel(
        id: id ?? this.id,
        title: title ?? this.title,
        caption: identical(caption, TypeUtil.unset) ? this.caption : caption as String?,
        imageUrls: imageUrls ?? this.imageUrls,
      );
  @override
  bool operator ==(Object other) => other is UserPreviewsNovel && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'UserPreviewsNovel(${toMap()})';
}
