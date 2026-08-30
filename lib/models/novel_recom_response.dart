import 'package:pixez/custom/map_extension.dart';
import 'package:pixez/custom/type_util.dart';

class NovelRecomResponse {
  final List<Novel> novels;
  final String? nextUrl;

  const NovelRecomResponse({this.novels = const [], this.nextUrl});

  factory NovelRecomResponse.fromMap(Map<String, dynamic> map) => NovelRecomResponse(
        novels: [
          ...map.optList('novels', (e) => Novel.fromMap(TypeUtil.parseMap(e))),
        ],
        nextUrl: map.optStringOrNull('next_url'),
      );
  factory NovelRecomResponse.fromJson(Map<String, dynamic> json) => NovelRecomResponse.fromMap(json);
  Map<String, dynamic> toMap() => {
        'novels': novels.map((e) => e.toMap()).toList(),
        'next_url': nextUrl,
      };
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => novels.isEmpty && nextUrl == null;
  NovelRecomResponse copyWith({List<Novel>? novels, Object? nextUrl = TypeUtil.unset}) =>
      NovelRecomResponse(
        novels: novels == null ? [...this.novels] : [...novels],
        nextUrl: identical(nextUrl, TypeUtil.unset) ? this.nextUrl : nextUrl as String?,
      );
  @override
  bool operator ==(Object other) => other is NovelRecomResponse && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'NovelRecomResponse(${toMap()})';
}

class Novel {
  final int id;
  final String title;
  final String caption;
  final int restrict;
  final int xRestrict;
  final bool isOriginal;
  final ImageUrls imageUrls;
  final DateTime createDate;
  final List<Tag> tags;
  final int pageCount;
  final int textLength;
  final User user;
  final Series series;
  final bool isBookmarked;
  final int totalBookmarks;
  final int totalView;
  final bool visible;
  final int totalComments;
  final bool isMuted;
  final bool isMypixivOnly;
  final bool isXRestricted;
  final int novelAiType;

  Novel({
    this.id = 0,
    this.title = '',
    this.caption = '',
    this.restrict = 0,
    this.xRestrict = 0,
    this.isOriginal = false,
    this.imageUrls = const ImageUrls(),
    DateTime? createDate,
    this.tags = const [],
    this.pageCount = 0,
    this.textLength = 0,
    this.user = const User(),
    this.series = const Series(),
    this.isBookmarked = false,
    this.totalBookmarks = 0,
    this.totalView = 0,
    this.visible = false,
    this.totalComments = 0,
    this.isMuted = false,
    this.isMypixivOnly = false,
    this.isXRestricted = false,
    this.novelAiType = 0,
  }) : createDate = createDate ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  /// 兼容旧调用方，正式字段使用 lowerCamelCase。
  int get NovelAIType => novelAiType;

  factory Novel.fromMap(Map<String, dynamic> map) => Novel(
        id: map.optInt('id'),
        title: map.optString('title'),
        caption: map.optString('caption'),
        restrict: map.optInt('restrict'),
        xRestrict: map.optInt('x_restrict'),
        isOriginal: map.optBool('is_original'),
        imageUrls: ImageUrls.fromMap(map.optMap('image_urls')),
        createDate: map.optDateTime('create_date'),
        tags: [
          ...map.optList('tags', (e) => Tag.fromMap(TypeUtil.parseMap(e))),
        ],
        pageCount: map.optInt('page_count'),
        textLength: map.optInt('text_length'),
        user: User.fromMap(map.optMap('user')),
        series: Series.fromMap(map.optMap('series')),
        isBookmarked: map.optBool('is_bookmarked'),
        totalBookmarks: map.optInt('total_bookmarks'),
        totalView: map.optInt('total_view'),
        visible: map.optBool('visible'),
        totalComments: map.optInt('total_comments'),
        isMuted: map.optBool('is_muted'),
        isMypixivOnly: map.optBool('is_mypixiv_only'),
        isXRestricted: map.optBool('is_x_restricted'),
        novelAiType: map.optInt('novel_ai_type'),
      );
  factory Novel.fromJson(Map<String, dynamic> json) => Novel.fromMap(json);
  Map<String, dynamic> toMap() => {
        'id': id, 'title': title, 'caption': caption, 'restrict': restrict,
        'x_restrict': xRestrict, 'is_original': isOriginal,
        'image_urls': imageUrls.toMap(), 'create_date': createDate.toIso8601String(),
        'tags': tags.map((e) => e.toMap()).toList(), 'page_count': pageCount,
        'text_length': textLength, 'user': user.toMap(), 'series': series.toMap(),
        'is_bookmarked': isBookmarked, 'total_bookmarks': totalBookmarks,
        'total_view': totalView, 'visible': visible, 'total_comments': totalComments,
        'is_muted': isMuted, 'is_mypixiv_only': isMypixivOnly,
        'is_x_restricted': isXRestricted, 'novel_ai_type': novelAiType,
      };
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => id == 0 && title.isEmpty && caption.isEmpty && restrict == 0 &&
      xRestrict == 0 && !isOriginal && imageUrls.isEmpty &&
      createDate.millisecondsSinceEpoch == 0 && tags.isEmpty && pageCount == 0 &&
      textLength == 0 && user.isEmpty && series.isEmpty && !isBookmarked &&
      totalBookmarks == 0 && totalView == 0 && !visible && totalComments == 0 &&
      !isMuted && !isMypixivOnly && !isXRestricted && novelAiType == 0;
  Novel copyWith({
    int? id, String? title, String? caption, int? restrict, int? xRestrict,
    bool? isOriginal, ImageUrls? imageUrls, DateTime? createDate, List<Tag>? tags,
    int? pageCount, int? textLength, User? user, Series? series,
    bool? isBookmarked, int? totalBookmarks, int? totalView, bool? visible,
    int? totalComments, bool? isMuted, bool? isMypixivOnly, bool? isXRestricted,
    int? novelAiType,
  }) => Novel(
        id: id ?? this.id, title: title ?? this.title, caption: caption ?? this.caption,
        restrict: restrict ?? this.restrict, xRestrict: xRestrict ?? this.xRestrict,
        isOriginal: isOriginal ?? this.isOriginal, imageUrls: imageUrls ?? this.imageUrls,
        createDate: createDate ?? this.createDate,
        tags: tags == null ? [...this.tags] : [...tags],
        pageCount: pageCount ?? this.pageCount, textLength: textLength ?? this.textLength,
        user: user ?? this.user, series: series ?? this.series,
        isBookmarked: isBookmarked ?? this.isBookmarked,
        totalBookmarks: totalBookmarks ?? this.totalBookmarks,
        totalView: totalView ?? this.totalView, visible: visible ?? this.visible,
        totalComments: totalComments ?? this.totalComments, isMuted: isMuted ?? this.isMuted,
        isMypixivOnly: isMypixivOnly ?? this.isMypixivOnly,
        isXRestricted: isXRestricted ?? this.isXRestricted,
        novelAiType: novelAiType ?? this.novelAiType,
      );
  @override
  bool operator ==(Object other) => other is Novel && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'Novel(${toMap()})';
}

class ImageUrls {
  final String squareMedium;
  final String medium;
  final String large;

  const ImageUrls({this.squareMedium = '', this.medium = '', this.large = ''});
  factory ImageUrls.fromMap(Map<String, dynamic> map) => ImageUrls(
        squareMedium: map.optString('square_medium'),
        medium: map.optString('medium'),
        large: map.optString('large'),
      );
  factory ImageUrls.fromJson(Map<String, dynamic> json) => ImageUrls.fromMap(json);
  Map<String, dynamic> toMap() => {'square_medium': squareMedium, 'medium': medium, 'large': large};
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => TypeUtil.allEmpty([squareMedium, medium, large]);
  ImageUrls copyWith({String? squareMedium, String? medium, String? large}) => ImageUrls(
        squareMedium: squareMedium ?? this.squareMedium,
        medium: medium ?? this.medium, large: large ?? this.large,
      );
  @override
  bool operator ==(Object other) => other is ImageUrls && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'ImageUrls(${toMap()})';
}

class Series {
  final int? id;
  final String? title;
  const Series({this.id, this.title});
  factory Series.fromMap(Map<String, dynamic> map) => Series(
        id: map.optIntOrNull('id'), title: map.optStringOrNull('title'),
      );
  factory Series.fromJson(Map<String, dynamic> json) => Series.fromMap(json);
  Map<String, dynamic> toMap() => {'id': id, 'title': title};
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => id == null && title == null;
  Series copyWith({Object? id = TypeUtil.unset, Object? title = TypeUtil.unset}) => Series(
        id: identical(id, TypeUtil.unset) ? this.id : id as int?,
        title: identical(title, TypeUtil.unset) ? this.title : title as String?,
      );
  @override
  bool operator ==(Object other) => other is Series && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'Series(${toMap()})';
}

class Tag {
  final String name;
  final String? translatedName;
  final bool addedByUploadedUser;
  const Tag({this.name = '', this.translatedName, this.addedByUploadedUser = false});
  factory Tag.fromMap(Map<String, dynamic> map) => Tag(
        name: map.optString('name'),
        translatedName: map.optStringOrNull('translated_name'),
        addedByUploadedUser: map.optBool('added_by_uploaded_user'),
      );
  factory Tag.fromJson(Map<String, dynamic> json) => Tag.fromMap(json);
  Map<String, dynamic> toMap() => {
        'name': name, 'translated_name': translatedName,
        'added_by_uploaded_user': addedByUploadedUser,
      };
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => name.isEmpty && translatedName == null && !addedByUploadedUser;
  Tag copyWith({String? name, Object? translatedName = TypeUtil.unset, bool? addedByUploadedUser}) => Tag(
        name: name ?? this.name,
        translatedName: identical(translatedName, TypeUtil.unset) ? this.translatedName : translatedName as String?,
        addedByUploadedUser: addedByUploadedUser ?? this.addedByUploadedUser,
      );
  @override
  bool operator ==(Object other) => other is Tag && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'Tag(${toMap()})';
}

class User {
  final int id;
  final String name;
  final String account;
  final ProfileImageUrls profileImageUrls;
  final bool isFollowed;
  const User({this.id = 0, this.name = '', this.account = '', this.profileImageUrls = const ProfileImageUrls(), this.isFollowed = false});
  factory User.fromMap(Map<String, dynamic> map) => User(
        id: map.optInt('id'), name: map.optString('name'), account: map.optString('account'),
        profileImageUrls: ProfileImageUrls.fromMap(map.optMap('profile_image_urls')),
        isFollowed: map.optBool('is_followed'),
      );
  factory User.fromJson(Map<String, dynamic> json) => User.fromMap(json);
  Map<String, dynamic> toMap() => {
        'id': id, 'name': name, 'account': account,
        'profile_image_urls': profileImageUrls.toMap(), 'is_followed': isFollowed,
      };
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => id == 0 && name.isEmpty && account.isEmpty &&
      profileImageUrls.isEmpty && !isFollowed;
  User copyWith({int? id, String? name, String? account, ProfileImageUrls? profileImageUrls, bool? isFollowed}) => User(
        id: id ?? this.id, name: name ?? this.name, account: account ?? this.account,
        profileImageUrls: profileImageUrls ?? this.profileImageUrls,
        isFollowed: isFollowed ?? this.isFollowed,
      );
  @override
  bool operator ==(Object other) => other is User && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'User(${toMap()})';
}

class ProfileImageUrls {
  final String medium;
  const ProfileImageUrls({this.medium = ''});
  factory ProfileImageUrls.fromMap(Map<String, dynamic> map) => ProfileImageUrls(medium: map.optString('medium'));
  factory ProfileImageUrls.fromJson(Map<String, dynamic> json) => ProfileImageUrls.fromMap(json);
  Map<String, dynamic> toMap() => {'medium': medium};
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => medium.isEmpty;
  ProfileImageUrls copyWith({String? medium}) => ProfileImageUrls(medium: medium ?? this.medium);
  @override
  bool operator ==(Object other) => other is ProfileImageUrls && medium == other.medium;
  @override
  int get hashCode => medium.hashCode;
  @override
  String toString() => 'ProfileImageUrls(${toMap()})';
}
