/*
 * Copyright (C) 2020. by perol_notsf, All rights reserved
 */
import 'package:pixez/constants.dart';
import 'package:pixez/custom/map_extension.dart';
import 'package:pixez/custom/type_util.dart';
import 'package:pixez/main.dart';

class MetaPages {
  final MetaPagesImageUrls? imageUrls;

  const MetaPages({this.imageUrls});

  bool get isEmpty => imageUrls == null || imageUrls!.isEmpty;

  MetaPages copyWith({Object? imageUrls = TypeUtil.unset}) => MetaPages(
        imageUrls: identical(imageUrls, TypeUtil.unset)
            ? this.imageUrls
            : imageUrls as MetaPagesImageUrls?,
      );

  factory MetaPages.fromMap(Map<String, dynamic> map) => MetaPages(
        imageUrls: map.optMapOrNull('image_urls') == null
            ? null
            : MetaPagesImageUrls.fromMap(map.optMap('image_urls')),
      );

  factory MetaPages.fromJson(Map<String, dynamic> json) => MetaPages.fromMap(json);
  Map<String, dynamic> toMap() => {'image_urls': imageUrls?.toMap()};
  Map<String, dynamic> toJson() => toMap();

  @override
  bool operator ==(Object other) => other is MetaPages &&
      TypeUtil.equal(imageUrls, other.imageUrls);
  @override
  int get hashCode => TypeUtil.hash(imageUrls);
  @override
  String toString() => 'MetaPages(${toMap()})';
}

class MetaPagesImageUrls {
  final String squareMedium;
  final String medium;
  final String large;
  final String original;

  const MetaPagesImageUrls({
    this.squareMedium = '',
    this.medium = '',
    this.large = '',
    this.original = '',
  });

  bool get isEmpty => TypeUtil.allEmpty([squareMedium, medium, large, original]);

  MetaPagesImageUrls copyWith({
    String? squareMedium,
    String? medium,
    String? large,
    String? original,
  }) => MetaPagesImageUrls(
        squareMedium: squareMedium ?? this.squareMedium,
        medium: medium ?? this.medium,
        large: large ?? this.large,
        original: original ?? this.original,
      );

  factory MetaPagesImageUrls.fromMap(Map<String, dynamic> map) =>
      MetaPagesImageUrls(
        squareMedium: map.optString('square_medium'),
        medium: map.optString('medium'),
        large: map.optString('large'),
        original: map.optString('original'),
      );

  factory MetaPagesImageUrls.fromJson(Map<String, dynamic> json) =>
      MetaPagesImageUrls.fromMap(json);
  Map<String, dynamic> toMap() => {
        'square_medium': squareMedium,
        'medium': medium,
        'large': large,
        'original': original,
      };
  Map<String, dynamic> toJson() => toMap();

  @override
  bool operator ==(Object other) => other is MetaPagesImageUrls &&
      TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'MetaPagesImageUrls(${toMap()})';
}

extension IllustsExtension on Illusts {
  String get illustDetailUrl => switch (userSetting.pictureQuality) {
        0 => imageUrls.medium,
        1 => imageUrls.large,
        2 => metaPages.firstOrNull?.imageUrls?.original ??
            metaSinglePage?.originalImageUrl ??
            '',
        _ => imageUrls.medium,
      };

  String get managaDetailUrl => switch (userSetting.mangaQuality) {
        0 => imageUrls.medium,
        1 => imageUrls.large,
        2 => metaPages.firstOrNull?.imageUrls?.original ??
            metaSinglePage?.originalImageUrl ??
            '',
        _ => imageUrls.medium,
      };

  String illustDetailImageUrl(int index) => switch (userSetting.pictureQuality) {
        0 => metaPages[index].imageUrls?.medium ?? '',
        1 => metaPages[index].imageUrls?.large ?? '',
        2 => metaPages[index].imageUrls?.original ?? '',
        _ => metaPages[index].imageUrls?.medium ?? '',
      };

  String managaDetailImageUrl(int index) => switch (userSetting.mangaQuality) {
        0 => metaPages[index].imageUrls?.medium ?? '',
        1 => metaPages[index].imageUrls?.large ?? '',
        2 => metaPages[index].imageUrls?.original ?? '',
        _ => metaPages[index].imageUrls?.medium ?? '',
      };
}

class Illusts {
  final int id;
  final String title;
  final String type;
  final ImageUrls imageUrls;
  final String caption;
  final int restrict;
  final User user;
  final List<Tags> tags;
  final List<String> tools;
  final String createDate;
  final int pageCount;
  final int width;
  final int height;
  final int sanityLevel;
  final int xRestrict;
  final MetaSinglePage? metaSinglePage;
  final List<MetaPages> metaPages;
  final int totalView;
  final int totalBookmarks;
  final bool isBookmarked;
  final bool visible;
  final bool isMuted;
  final int illustAiType;
  final IllustSeries? series;
  final int? illustBookStyle;
  final int? totalComments;

  const Illusts({
    this.id = 0,
    this.title = '',
    this.type = '',
    this.imageUrls = const ImageUrls(),
    this.caption = '',
    this.restrict = 0,
    this.user = const User(),
    this.tags = const [],
    this.tools = const [],
    this.createDate = '',
    this.pageCount = 0,
    this.width = 0,
    this.height = 0,
    this.sanityLevel = 0,
    this.xRestrict = 0,
    this.metaSinglePage,
    this.metaPages = const [],
    this.totalView = 0,
    this.totalBookmarks = 0,
    this.isBookmarked = false,
    this.visible = false,
    this.isMuted = false,
    this.illustAiType = 0,
    this.series,
    this.illustBookStyle,
    this.totalComments,
  });

  bool get isUgoira => type == Constants.ugoira;

  bool get isEmpty =>
      id == 0 &&
      title.isEmpty &&
      type.isEmpty &&
      imageUrls.isEmpty &&
      caption.isEmpty &&
      restrict == 0 &&
      user.isEmpty &&
      tags.isEmpty &&
      tools.isEmpty &&
      createDate.isEmpty &&
      pageCount == 0 &&
      width == 0 &&
      height == 0 &&
      sanityLevel == 0 &&
      xRestrict == 0 &&
      (metaSinglePage == null || metaSinglePage!.isEmpty) &&
      metaPages.isEmpty &&
      totalView == 0 &&
      totalBookmarks == 0 &&
      !isBookmarked &&
      !visible &&
      !isMuted &&
      illustAiType == 0 &&
      (series == null || series!.isEmpty) &&
      illustBookStyle == null &&
      totalComments == null;

  bool hasDataChanged(Illusts other) {
    return id != other.id ||
        title != other.title ||
        caption != other.caption ||
        totalView != other.totalView ||
        totalBookmarks != other.totalBookmarks ||
        user.name != other.user.name ||
        createDate != other.createDate ||
        pageCount != other.pageCount ||
        width != other.width ||
        height != other.height ||
        sanityLevel != other.sanityLevel ||
        xRestrict != other.xRestrict ||
        type != other.type ||
        isBookmarked != other.isBookmarked ||
        !TypeUtil.equal(tags, other.tags) ||
        !TypeUtil.equal(tools, other.tools) ||
        user != other.user ||
        !TypeUtil.equal(metaPages, other.metaPages) ||
        metaSinglePage != other.metaSinglePage;
  }

  Illusts copyWith({
    int? id,
    String? title,
    String? type,
    ImageUrls? imageUrls,
    String? caption,
    int? restrict,
    User? user,
    List<Tags>? tags,
    List<String>? tools,
    String? createDate,
    int? pageCount,
    int? width,
    int? height,
    int? sanityLevel,
    int? xRestrict,
    Object? metaSinglePage = TypeUtil.unset,
    List<MetaPages>? metaPages,
    int? totalView,
    int? totalBookmarks,
    bool? isBookmarked,
    bool? visible,
    bool? isMuted,
    int? illustAiType,
    Object? series = TypeUtil.unset,
    Object? illustBookStyle = TypeUtil.unset,
    Object? totalComments = TypeUtil.unset,
  }) => Illusts(
        id: id ?? this.id,
        title: title ?? this.title,
        type: type ?? this.type,
        imageUrls: imageUrls ?? this.imageUrls,
        caption: caption ?? this.caption,
        restrict: restrict ?? this.restrict,
        user: user ?? this.user,
        tags: tags == null ? [...this.tags] : [...tags],
        tools: tools == null ? [...this.tools] : [...tools],
        createDate: createDate ?? this.createDate,
        pageCount: pageCount ?? this.pageCount,
        width: width ?? this.width,
        height: height ?? this.height,
        sanityLevel: sanityLevel ?? this.sanityLevel,
        xRestrict: xRestrict ?? this.xRestrict,
        metaSinglePage: identical(metaSinglePage, TypeUtil.unset)
            ? this.metaSinglePage
            : metaSinglePage as MetaSinglePage?,
        metaPages: metaPages == null ? [...this.metaPages] : [...metaPages],
        totalView: totalView ?? this.totalView,
        totalBookmarks: totalBookmarks ?? this.totalBookmarks,
        isBookmarked: isBookmarked ?? this.isBookmarked,
        visible: visible ?? this.visible,
        isMuted: isMuted ?? this.isMuted,
        illustAiType: illustAiType ?? this.illustAiType,
        series: identical(series, TypeUtil.unset) ? this.series : series as IllustSeries?,
        illustBookStyle: identical(illustBookStyle, TypeUtil.unset)
            ? this.illustBookStyle
            : illustBookStyle as int?,
        totalComments: identical(totalComments, TypeUtil.unset)
            ? this.totalComments
            : totalComments as int?,
      );

  factory Illusts.fromMap(Map<String, dynamic> map) => Illusts(
        id: map.optInt('id'),
        title: map.optString('title'),
        type: map.optString('type'),
        imageUrls: ImageUrls.fromMap(map.optMap('image_urls')),
        caption: map.optString('caption'),
        restrict: map.optInt('restrict'),
        user: User.fromMap(map.optMap('user')),
        tags: [
          ...map.optList('tags', (e) => Tags.fromMap(TypeUtil.parseMap(e))),
        ],
        tools: [...map.optStringList('tools')],
        createDate: map.optString('create_date'),
        pageCount: map.optInt('page_count'),
        width: map.optInt('width'),
        height: map.optInt('height'),
        sanityLevel: map.optInt('sanity_level'),
        xRestrict: map.optInt('x_restrict'),
        metaSinglePage: map.optMapOrNull('meta_single_page') == null
            ? null
            : MetaSinglePage.fromMap(map.optMap('meta_single_page')),
        metaPages: [
          ...map.optList(
            'meta_pages',
            (e) => MetaPages.fromMap(TypeUtil.parseMap(e)),
          ),
        ],
        totalView: map.optInt('total_view'),
        totalBookmarks: map.optInt('total_bookmarks'),
        isBookmarked: map.optBool('is_bookmarked'),
        visible: map.optBool('visible'),
        isMuted: map.optBool('is_muted'),
        illustAiType: map.optInt('illust_ai_type'),
        series: map.optMapOrNull('series') == null
            ? null
            : IllustSeries.fromMap(map.optMap('series')),
        illustBookStyle: map.optIntOrNull('illust_book_style'),
        totalComments: map.optIntOrNull('total_comments'),
      );

  factory Illusts.fromJson(Map<String, dynamic> json) => Illusts.fromMap(json);

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'type': type,
        'image_urls': imageUrls.toMap(),
        'caption': caption,
        'restrict': restrict,
        'user': user.toMap(),
        'tags': tags.map((e) => e.toMap()).toList(),
        'tools': [...tools],
        'create_date': createDate,
        'page_count': pageCount,
        'width': width,
        'height': height,
        'sanity_level': sanityLevel,
        'x_restrict': xRestrict,
        'meta_single_page': metaSinglePage?.toMap(),
        'meta_pages': metaPages.map((e) => e.toMap()).toList(),
        'total_view': totalView,
        'total_bookmarks': totalBookmarks,
        'is_bookmarked': isBookmarked,
        'visible': visible,
        'is_muted': isMuted,
        'illust_ai_type': illustAiType,
        'series': series?.toMap(),
        'illust_book_style': illustBookStyle,
        'total_comments': totalComments,
      };

  Map<String, dynamic> toJson() => toMap();

  /// 兼容旧调用方，正式字段使用 lowerCamelCase。
  @Deprecated('Use illustAiType instead')
  int get illustAIType => illustAiType;

  @override
  bool operator ==(Object other) => other is Illusts &&
      TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'Illusts${TypeUtil.parseString(toMap())}';
}

class IllustSeries {
  final int id;
  final String? title;

  const IllustSeries({this.id = 0, this.title});

  bool get isEmpty => id == 0 && title == null;
  IllustSeries copyWith({int? id, Object? title = TypeUtil.unset}) => IllustSeries(
        id: id ?? this.id,
        title: identical(title, TypeUtil.unset) ? this.title : title as String?,
      );

  factory IllustSeries.fromMap(Map<String, dynamic> map) => IllustSeries(
        id: map.optInt('id'),
        title: map.optStringOrNull('title'),
      );
  factory IllustSeries.fromJson(Map<String, dynamic> json) => IllustSeries.fromMap(json);
  Map<String, dynamic> toMap() => {'id': id, 'title': title};
  Map<String, dynamic> toJson() => toMap();
  @override
  bool operator ==(Object other) => other is IllustSeries && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'IllustSeries${TypeUtil.parseString(toMap())}';
}

class ImageUrls {
  final String squareMedium;
  final String medium;
  final String large;

  const ImageUrls({this.squareMedium = '', this.medium = '', this.large = ''});

  bool get isEmpty => TypeUtil.allEmpty([squareMedium, medium, large]);
  ImageUrls copyWith({String? squareMedium, String? medium, String? large}) => ImageUrls(
        squareMedium: squareMedium ?? this.squareMedium,
        medium: medium ?? this.medium,
        large: large ?? this.large,
      );
  factory ImageUrls.fromMap(Map<String, dynamic> map) => ImageUrls(
        squareMedium: map.optString('square_medium'),
        medium: map.optString('medium'),
        large: map.optString('large'),
      );
  factory ImageUrls.fromJson(Map<String, dynamic> json) => ImageUrls.fromMap(json);
  Map<String, dynamic> toMap() => {
        'square_medium': squareMedium,
        'medium': medium,
        'large': large,
      };
  Map<String, dynamic> toJson() => toMap();
  @override
  bool operator ==(Object other) => other is ImageUrls && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'ImageUrls${TypeUtil.parseString(toMap())}';
}

extension IllustExtension on Illusts {
  String get feedPreviewUrl => userSetting.feedPreviewQuality == 0
      ? imageUrls.medium
      : userSetting.feedPreviewQuality == 1
          ? imageUrls.large
          : metaSinglePage?.originalImageUrl ??
              (metaPages.isEmpty ? '' : metaPages[0].imageUrls?.original ?? '');

  String get previewUrl => userSetting.useWaterfallFlow ? feedPreviewUrl : imageUrls.squareMedium;
  String get previewQuality => userSetting.previewQuality;
}

class User {
  final int id;
  final String name;
  final String account;
  final ProfileImageUrls profileImageUrls;
  final String? comment;
  final bool? isFollowed;

  const User({
    this.id = 0,
    this.name = '',
    this.account = '',
    this.profileImageUrls = const ProfileImageUrls(),
    this.comment,
    this.isFollowed,
  });

  bool get isEmpty =>
      id == 0 &&
      name.isEmpty &&
      account.isEmpty &&
      profileImageUrls.isEmpty &&
      comment == null &&
      isFollowed == null;

  User copyWith({
    int? id,
    String? name,
    String? account,
    ProfileImageUrls? profileImageUrls,
    Object? comment = TypeUtil.unset,
    Object? isFollowed = TypeUtil.unset,
  }) => User(
        id: id ?? this.id,
        name: name ?? this.name,
        account: account ?? this.account,
        profileImageUrls: profileImageUrls ?? this.profileImageUrls,
        comment: identical(comment, TypeUtil.unset) ? this.comment : comment as String?,
        isFollowed: identical(isFollowed, TypeUtil.unset) ? this.isFollowed : isFollowed as bool?,
      );

  factory User.fromMap(Map<String, dynamic> map) => User(
        id: map.optInt('id'),
        name: map.optString('name'),
        account: map.optString('account'),
        profileImageUrls: ProfileImageUrls.fromMap(map.optMap('profile_image_urls')),
        comment: map.optStringOrNull('comment'),
        isFollowed: map.optBoolOrNull('is_followed'),
      );
  factory User.fromJson(Map<String, dynamic> json) => User.fromMap(json);
  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'account': account,
        'profile_image_urls': profileImageUrls.toMap(),
        'comment': comment,
        'is_followed': isFollowed,
      };
  Map<String, dynamic> toJson() => toMap();
  @override
  bool operator ==(Object other) => other is User && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'User${TypeUtil.parseString(toMap())}';
}

class ProfileImageUrls {
  final String medium;

  const ProfileImageUrls({this.medium = ''});
  bool get isEmpty => medium.isEmpty;
  ProfileImageUrls copyWith({String? medium}) => ProfileImageUrls(medium: medium ?? this.medium);
  factory ProfileImageUrls.fromMap(Map<String, dynamic> map) => ProfileImageUrls(medium: map.optString('medium'));
  factory ProfileImageUrls.fromJson(Map<String, dynamic> json) => ProfileImageUrls.fromMap(json);
  Map<String, dynamic> toMap() => {'medium': medium};
  Map<String, dynamic> toJson() => toMap();
  @override
  bool operator ==(Object other) => other is ProfileImageUrls && medium == other.medium;
  @override
  int get hashCode => medium.hashCode;
  @override
  String toString() => 'ProfileImageUrls${TypeUtil.parseString(toMap())}';
}

class Tags {
  final String name;
  final String? translatedName;

  const Tags({this.name = '', this.translatedName});
  bool get isEmpty => name.isEmpty && translatedName == null;
  Tags copyWith({String? name, Object? translatedName = TypeUtil.unset}) => Tags(
        name: name ?? this.name,
        translatedName: identical(translatedName, TypeUtil.unset)
            ? this.translatedName
            : translatedName as String?,
      );
  factory Tags.fromMap(Map<String, dynamic> map) => Tags(
        name: map.optString('name'),
        translatedName: map.optStringOrNull('translated_name'),
      );
  factory Tags.fromJson(Map<String, dynamic> json) => Tags.fromMap(json);
  Map<String, dynamic> toMap() => {'name': name, 'translated_name': translatedName};
  Map<String, dynamic> toJson() => toMap();
  @override
  bool operator ==(Object other) => other is Tags && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'Tags${TypeUtil.parseString(toMap())}';
}

class MetaSinglePage {
  final String? originalImageUrl;
  const MetaSinglePage({this.originalImageUrl});
  bool get isEmpty => originalImageUrl == null;
  MetaSinglePage copyWith({Object? originalImageUrl = TypeUtil.unset}) => MetaSinglePage(
        originalImageUrl: identical(originalImageUrl, TypeUtil.unset)
            ? this.originalImageUrl
            : originalImageUrl as String?,
      );
  factory MetaSinglePage.fromMap(Map<String, dynamic> map) => MetaSinglePage(
        originalImageUrl: map.optStringOrNull('original_image_url'),
      );
  factory MetaSinglePage.fromJson(Map<String, dynamic> json) => MetaSinglePage.fromMap(json);
  Map<String, dynamic> toMap() => {'original_image_url': originalImageUrl};
  Map<String, dynamic> toJson() => toMap();
  @override
  bool operator ==(Object other) => other is MetaSinglePage && originalImageUrl == other.originalImageUrl;
  @override
  int get hashCode => originalImageUrl.hashCode;
  @override
  String toString() => 'MetaSinglePage${TypeUtil.parseString(toMap())}';
}
