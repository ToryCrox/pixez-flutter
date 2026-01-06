/*
 * Copyright (C) 2020. by perol_notsf, All rights reserved
 *
 * This program is free software: you can redistribute it and/or modify it under
 * the terms of the GNU General Public License as published by the Free Software
 * Foundation, either version 3 of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT ANY
 * WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
 *F
 * You should have received a copy of the GNU General Public License along with
 * this program. If not, see <http://www.gnu.org/licenses/>.
 *
 */
import 'package:flutter/foundation.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:pixez/main.dart';

import '../custom/type_util.dart';

part 'illust.g.dart';

//@JsonSerializable(explicitToJson: true)
class MetaPages {
  @JsonKey(name: 'image_urls')
  MetaPagesImageUrls? imageUrls;

  MetaPages({
    this.imageUrls,
  });

  bool get isEmpty => imageUrls == null;

  MetaPages copyWith({
    MetaPagesImageUrls? imageUrls,
  }) {
    return MetaPages(
      imageUrls: imageUrls ?? this.imageUrls,
    );
  }

  factory MetaPages.fromMap(Map<String, dynamic> map) {
    return MetaPages(
      imageUrls: map['image_urls'] == null
          ? null
          : MetaPagesImageUrls.fromMap(TypeUtil.parseMap(map['image_urls'])),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'image_urls': imageUrls?.toMap(),
    };
  }

  factory MetaPages.fromJson(Map<String, dynamic> json) =>
      MetaPages.fromMap(json);

  Map<String, dynamic> toJson() => toMap();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MetaPages &&
          runtimeType == other.runtimeType &&
          imageUrls == other.imageUrls);

  @override
  int get hashCode => imageUrls.hashCode;

  @override
  String toString() {
    return 'MetaPages${TypeUtil.parseString(toMap())}';
  }
}

//@JsonSerializable(explicitToJson: true)
class MetaPagesImageUrls {
  @JsonKey(name: 'square_medium')
  String squareMedium;
  String medium;
  String large;
  String original;

  MetaPagesImageUrls({
    this.squareMedium = '',
    this.medium = '',
    this.large = '',
    this.original = '',
  });

  bool get isEmpty =>
      squareMedium.isEmpty &&
      medium.isEmpty &&
      large.isEmpty &&
      original.isEmpty;

  MetaPagesImageUrls copyWith({
    String? squareMedium,
    String? medium,
    String? large,
    String? original,
  }) {
    return MetaPagesImageUrls(
      squareMedium: squareMedium ?? this.squareMedium,
      medium: medium ?? this.medium,
      large: large ?? this.large,
      original: original ?? this.original,
    );
  }

  factory MetaPagesImageUrls.fromMap(Map<String, dynamic> map) {
    return MetaPagesImageUrls(
      squareMedium: TypeUtil.parseString(map['square_medium']),
      medium: TypeUtil.parseString(map['medium']),
      large: TypeUtil.parseString(map['large']),
      original: TypeUtil.parseString(map['original']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'square_medium': squareMedium,
      'medium': medium,
      'large': large,
      'original': original,
    };
  }

  factory MetaPagesImageUrls.fromJson(Map<String, dynamic> json) =>
      MetaPagesImageUrls.fromMap(json);

  Map<String, dynamic> toJson() => toMap();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MetaPagesImageUrls &&
          runtimeType == other.runtimeType &&
          squareMedium == other.squareMedium &&
          medium == other.medium &&
          large == other.large &&
          original == other.original);

  @override
  int get hashCode =>
      squareMedium.hashCode ^
      medium.hashCode ^
      large.hashCode ^
      original.hashCode;

  @override
  String toString() {
    return 'MetaPagesImageUrls${TypeUtil.parseString(toMap())}';
  }
}

extension IllustsExtension on Illusts {
  String get illustDetailUrl => switch (userSetting.pictureQuality) {
        0 => imageUrls.medium,
        1 => imageUrls.large,
        2 => metaPages.firstOrNull?.imageUrls?.original ??
            metaSinglePage!.originalImageUrl!,
        _ => imageUrls.medium,
      };

  String get managaDetailUrl => switch (userSetting.mangaQuality) {
        0 => imageUrls.medium,
        1 => imageUrls.large,
        2 => metaPages.firstOrNull?.imageUrls?.original ??
            metaSinglePage!.originalImageUrl!,
        _ => imageUrls.medium,
      };

  String illustDetailImageUrl(int index) =>
      switch (userSetting.pictureQuality) {
        0 => metaPages[index].imageUrls!.medium,
        1 => metaPages[index].imageUrls!.large,
        2 => metaPages[index].imageUrls!.original,
        _ => metaPages[index].imageUrls!.medium,
      };

  String managaDetailImageUrl(int index) =>
      switch (userSetting.mangaQuality) {
        0 => metaPages[index].imageUrls!.medium,
        1 => metaPages[index].imageUrls!.large,
        2 => metaPages[index].imageUrls!.original,
        _ => metaPages[index].imageUrls!.medium,
      };
}

@JsonSerializable(explicitToJson: true)
class Illusts {
  int id;
  String title;
  /// illust | manga | ugoira
  String type;
  @JsonKey(name: 'image_urls')
  ImageUrls imageUrls;
  String caption;
  int restrict;
  User user;
  List<Tags> tags;
  List<String> tools;
  @JsonKey(name: 'create_date')
  String createDate;
  @JsonKey(name: 'page_count')
  int pageCount;
  int width;
  int height;
  @JsonKey(name: 'sanity_level')
  int sanityLevel;
  @JsonKey(name: 'x_restrict')
  int xRestrict;
  @JsonKey(name: 'meta_single_page')
  MetaSinglePage? metaSinglePage;
  @JsonKey(name: 'meta_pages')
  List<MetaPages> metaPages;
  @JsonKey(name: 'total_view')
  int totalView;
  @JsonKey(name: 'total_bookmarks')
  int totalBookmarks;
  @JsonKey(name: 'is_bookmarked')
  bool isBookmarked;
  bool visible;
  @JsonKey(name: 'is_muted')
  bool isMuted;
  @JsonKey(name: 'illust_ai_type')
  int illustAIType;
  IllustSeries? series;
  @JsonKey(name: 'illust_book_style')
  int? illustBookStyle;
  @JsonKey(name: 'total_comments')
  int? totalComments;

  /// 对比两个 Illusts 对象在数据库相关字段上是否有变化
  bool hasDataChanged(Illusts other) {
    if (id != other.id) return true;
    if (title != other.title) return true;
    if (caption != other.caption) return true;
    if (totalView != other.totalView) return true;
    if (totalBookmarks != other.totalBookmarks) return true;
    if (user.name != other.user.name) return true;
    if (createDate != other.createDate) return true;
    if (pageCount != other.pageCount) return true;
    if (width != other.width) return true;
    if (height != other.height) return true;
    if (sanityLevel != other.sanityLevel) return true;
    if (xRestrict != other.xRestrict) return true;
    if (type != other.type) return true;
    if (isBookmarked != other.isBookmarked) return true;
    if (!listEquals(tags, other.tags)) return true;
    if (!listEquals(tools, other.tools)) return true;
    if (user != other.user) return true;
    if (!listEquals(metaPages, other.metaPages)) return true;
    if (metaSinglePage != other.metaSinglePage) return true;
    
    return false;
  }

  Illusts({
    this.id = 0,
    this.title = '',
    this.type = '',
    this.imageUrls = const ImageUrls(),
    this.caption = '',
    this.restrict = 0,
    required this.user,
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
    this.illustAIType = 0,
    this.series,
    this.illustBookStyle,
    this.totalComments,
  });

  /// 判断是否为动图
  bool get isUgoira => type == 'ugoira';

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
      metaSinglePage == null &&
      metaPages.isEmpty &&
      totalView == 0 &&
      totalBookmarks == 0 &&
      isBookmarked == false &&
      visible == false &&
      isMuted == false &&
      illustAIType == 0 &&
      series == null &&
      illustBookStyle == null &&
      totalComments == null;

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
    MetaSinglePage? metaSinglePage,
    List<MetaPages>? metaPages,
    int? totalView,
    int? totalBookmarks,
    bool? isBookmarked,
    bool? visible,
    bool? isMuted,
    int? illustAIType,
    IllustSeries? series,
    int? illustBookStyle,
    int? totalComments,
  }) {
    return Illusts(
      id: id ?? this.id,
      title: title ?? this.title,
      type: type ?? this.type,
      imageUrls: imageUrls ?? this.imageUrls,
      caption: caption ?? this.caption,
      restrict: restrict ?? this.restrict,
      user: user ?? this.user,
      tags: tags ?? this.tags,
      tools: tools ?? this.tools,
      createDate: createDate ?? this.createDate,
      pageCount: pageCount ?? this.pageCount,
      width: width ?? this.width,
      height: height ?? this.height,
      sanityLevel: sanityLevel ?? this.sanityLevel,
      xRestrict: xRestrict ?? this.xRestrict,
      metaSinglePage: metaSinglePage ?? this.metaSinglePage,
      metaPages: metaPages ?? this.metaPages,
      totalView: totalView ?? this.totalView,
      totalBookmarks: totalBookmarks ?? this.totalBookmarks,
      isBookmarked: isBookmarked ?? this.isBookmarked,
      visible: visible ?? this.visible,
      isMuted: isMuted ?? this.isMuted,
      illustAIType: illustAIType ?? this.illustAIType,
      series: series ?? this.series,
      illustBookStyle: illustBookStyle ?? this.illustBookStyle,
      totalComments: totalComments ?? this.totalComments,
    );
  }

  factory Illusts.fromMap(Map<String, dynamic> map) {
    return Illusts(
      id: TypeUtil.parseInt(map['id']),
      title: TypeUtil.parseString(map['title']),
      type: TypeUtil.parseString(map['type']),
      imageUrls: ImageUrls.fromMap(TypeUtil.parseMap(map['image_urls'])),
      caption: TypeUtil.parseString(map['caption']),
      restrict: TypeUtil.parseInt(map['restrict']),
      user: User.fromMap(TypeUtil.parseMap(map['user'])),
      tags: TypeUtil.parseList(
          map['tags'], (e) => Tags.fromMap(TypeUtil.parseMap(e))),
      tools: TypeUtil.parseStringList(map['tools']),
      createDate: TypeUtil.parseString(map['create_date']),
      pageCount: TypeUtil.parseInt(map['page_count']),
      width: TypeUtil.parseInt(map['width']),
      height: TypeUtil.parseInt(map['height']),
      sanityLevel: TypeUtil.parseInt(map['sanity_level']),
      xRestrict: TypeUtil.parseInt(map['x_restrict']),
      metaSinglePage: map['meta_single_page'] == null
          ? null
          : MetaSinglePage.fromMap(TypeUtil.parseMap(map['meta_single_page'])),
      metaPages: TypeUtil.parseList(
          map['meta_pages'], (e) => MetaPages.fromMap(TypeUtil.parseMap(e))),
      totalView: TypeUtil.parseInt(map['total_view']),
      totalBookmarks: TypeUtil.parseInt(map['total_bookmarks']),
      isBookmarked: TypeUtil.parseBool(map['is_bookmarked']),
      visible: TypeUtil.parseBool(map['visible']),
      isMuted: TypeUtil.parseBool(map['is_muted']),
      illustAIType: TypeUtil.parseInt(map['illust_ai_type']),
      series: map['series'] == null
          ? null
          : IllustSeries.fromMap(TypeUtil.parseMap(map['series'])),
      illustBookStyle: map['illust_book_style'] == null
          ? null
          : TypeUtil.parseInt(map['illust_book_style']),
      totalComments: map['total_comments'] == null
          ? null
          : TypeUtil.parseInt(map['total_comments']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'type': type,
      'image_urls': imageUrls.toMap(),
      'caption': caption,
      'restrict': restrict,
      'user': user.toMap(),
      'tags': tags.map((e) => e.toMap()).toList(),
      'tools': tools,
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
      'illust_ai_type': illustAIType,
      'series': series?.toMap(),
      'illust_book_style': illustBookStyle,
      'total_comments': totalComments,
    };
  }

  factory Illusts.fromJson(Map<String, dynamic> json) => Illusts.fromMap(json);

  Map<String, dynamic> toJson() => toMap();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Illusts &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          title == other.title &&
          type == other.type &&
          imageUrls == other.imageUrls &&
          caption == other.caption &&
          restrict == other.restrict &&
          user == other.user &&
          TypeUtil.equal(tags, other.tags) &&
          TypeUtil.equal(tools, other.tools) &&
          createDate == other.createDate &&
          pageCount == other.pageCount &&
          width == other.width &&
          height == other.height &&
          sanityLevel == other.sanityLevel &&
          xRestrict == other.xRestrict &&
          metaSinglePage == other.metaSinglePage &&
          TypeUtil.equal(metaPages, other.metaPages) &&
          totalView == other.totalView &&
          totalBookmarks == other.totalBookmarks &&
          isBookmarked == other.isBookmarked &&
          visible == other.visible &&
          isMuted == other.isMuted &&
          illustAIType == other.illustAIType &&
          series == other.series &&
          illustBookStyle == other.illustBookStyle &&
          totalComments == other.totalComments);

  @override
  int get hashCode =>
      id.hashCode ^
      title.hashCode ^
      type.hashCode ^
      imageUrls.hashCode ^
      caption.hashCode ^
      restrict.hashCode ^
      user.hashCode ^
      tags.hashCode ^
      tools.hashCode ^
      createDate.hashCode ^
      pageCount.hashCode ^
      width.hashCode ^
      height.hashCode ^
      sanityLevel.hashCode ^
      xRestrict.hashCode ^
      metaSinglePage.hashCode ^
      metaPages.hashCode ^
      totalView.hashCode ^
      totalBookmarks.hashCode ^
      isBookmarked.hashCode ^
      visible.hashCode ^
      isMuted.hashCode ^
      illustAIType.hashCode ^
      series.hashCode ^
      illustBookStyle.hashCode ^
      totalComments.hashCode;

  @override
  String toString() {
    return 'Illusts${TypeUtil.parseString(toMap())}';
  }
}

//@JsonSerializable()
class IllustSeries {
  int id;
  String? title;

  IllustSeries({
    this.id = 0,
    this.title,
  });

  bool get isEmpty => id == 0 && title == null;

  IllustSeries copyWith({
    int? id,
    String? title,
  }) {
    return IllustSeries(
      id: id ?? this.id,
      title: title ?? this.title,
    );
  }

  factory IllustSeries.fromMap(Map<String, dynamic> map) {
    return IllustSeries(
      id: TypeUtil.parseInt(map['id']),
      title: map['title'] == null ? null : TypeUtil.parseString(map['title']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
    };
  }

  factory IllustSeries.fromJson(Map<String, dynamic> json) =>
      IllustSeries.fromMap(json);

  Map<String, dynamic> toJson() => toMap();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is IllustSeries &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          title == other.title);

  @override
  int get hashCode => id.hashCode ^ title.hashCode;

  @override
  String toString() {
    return 'IllustSeries${TypeUtil.parseString(toMap())}';
  }
}

//@JsonSerializable()
class ImageUrls {
  @JsonKey(name: 'square_medium')
  final String squareMedium;
  final String medium;
  final String large;

  const ImageUrls({
    this.squareMedium = '',
    this.medium = '',
    this.large = '',
  });

  bool get isEmpty => squareMedium.isEmpty && medium.isEmpty && large.isEmpty;

  ImageUrls copyWith({
    String? squareMedium,
    String? medium,
    String? large,
  }) {
    return ImageUrls(
      squareMedium: squareMedium ?? this.squareMedium,
      medium: medium ?? this.medium,
      large: large ?? this.large,
    );
  }

  factory ImageUrls.fromMap(Map<String, dynamic> map) {
    return ImageUrls(
      squareMedium: TypeUtil.parseString(map['square_medium']),
      medium: TypeUtil.parseString(map['medium']),
      large: TypeUtil.parseString(map['large']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'square_medium': squareMedium,
      'medium': medium,
      'large': large,
    };
  }

  factory ImageUrls.fromJson(Map<String, dynamic> json) =>
      ImageUrls.fromMap(json);

  Map<String, dynamic> toJson() => toMap();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ImageUrls &&
          runtimeType == other.runtimeType &&
          squareMedium == other.squareMedium &&
          medium == other.medium &&
          large == other.large);

  @override
  int get hashCode => squareMedium.hashCode ^ medium.hashCode ^ large.hashCode;

  @override
  String toString() {
    return 'ImageUrls${TypeUtil.parseString(toMap())}';
  }
}

extension IllustExtension on Illusts {
  String get feedPreviewUrl => (userSetting.feedPreviewQuality == 0)
      ? imageUrls.medium
      : (userSetting.feedPreviewQuality == 1)
          ? this.imageUrls.large
          : this.metaSinglePage?.originalImageUrl ??
              this.metaPages[0].imageUrls!.original;
}

//@JsonSerializable(explicitToJson: true)
class User {
  final int id;
  final String name;
  final String account;
  @JsonKey(name: 'profile_image_urls')
  final ProfileImageUrls profileImageUrls;
  final String? comment;
  @JsonKey(name: 'is_followed')
  bool? isFollowed;

   User({
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
    String? comment,
    bool? isFollowed,
  }) {
    return User(
      id: id ?? this.id,
      name: name ?? this.name,
      account: account ?? this.account,
      profileImageUrls: profileImageUrls ?? this.profileImageUrls,
      comment: comment ?? this.comment,
      isFollowed: isFollowed ?? this.isFollowed,
    );
  }

  factory User.fromMap(Map<String, dynamic> map) {
    return User(
      id: TypeUtil.parseInt(map['id']),
      name: TypeUtil.parseString(map['name']),
      account: TypeUtil.parseString(map['account']),
      profileImageUrls: ProfileImageUrls.fromMap(
          TypeUtil.parseMap(map['profile_image_urls'])),
      comment:
          map['comment'] == null ? null : TypeUtil.parseString(map['comment']),
      isFollowed: map['is_followed'] == null
          ? null
          : TypeUtil.parseBool(map['is_followed']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'account': account,
      'profile_image_urls': profileImageUrls.toMap(),
      'comment': comment,
      'is_followed': isFollowed,
    };
  }

  factory User.fromJson(Map<String, dynamic> json) => User.fromMap(json);

  Map<String, dynamic> toJson() => toMap();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is User &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          account == other.account &&
          profileImageUrls == other.profileImageUrls &&
          comment == other.comment &&
          isFollowed == other.isFollowed);

  @override
  int get hashCode =>
      id.hashCode ^
      name.hashCode ^
      account.hashCode ^
      profileImageUrls.hashCode ^
      comment.hashCode ^
      isFollowed.hashCode;

  @override
  String toString() {
    return 'User${TypeUtil.parseString(toMap())}';
  }
}

//@JsonSerializable()
class ProfileImageUrls {
  final String medium;

  const ProfileImageUrls({
    this.medium = '',
  });

  bool get isEmpty => medium.isEmpty;

  ProfileImageUrls copyWith({
    String? medium,
  }) {
    return ProfileImageUrls(
      medium: medium ?? this.medium,
    );
  }

  factory ProfileImageUrls.fromMap(Map<String, dynamic> map) {
    return ProfileImageUrls(
      medium: TypeUtil.parseString(map['medium']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'medium': medium,
    };
  }

  factory ProfileImageUrls.fromJson(Map<String, dynamic> json) =>
      ProfileImageUrls.fromMap(json);

  Map<String, dynamic> toJson() => toMap();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProfileImageUrls &&
          runtimeType == other.runtimeType &&
          medium == other.medium);

  @override
  int get hashCode => medium.hashCode;

  @override
  String toString() {
    return 'ProfileImageUrls${TypeUtil.parseString(toMap())}';
  }
}

//@JsonSerializable()
class Tags {
  String name;
  @JsonKey(name: 'translated_name')
  String? translatedName;

  Tags({
    this.name = '',
    this.translatedName,
  });

  bool get isEmpty => name.isEmpty && translatedName == null;

  Tags copyWith({
    String? name,
    String? translatedName,
  }) {
    return Tags(
      name: name ?? this.name,
      translatedName: translatedName ?? this.translatedName,
    );
  }

  factory Tags.fromMap(Map<String, dynamic> map) {
    return Tags(
      name: TypeUtil.parseString(map['name']),
      translatedName: map['translated_name'] == null
          ? null
          : TypeUtil.parseString(map['translated_name']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'translated_name': translatedName,
    };
  }

  factory Tags.fromJson(Map<String, dynamic> json) => Tags.fromMap(json);

  Map<String, dynamic> toJson() => toMap();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Tags &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          translatedName == other.translatedName);

  @override
  int get hashCode => name.hashCode ^ translatedName.hashCode;

  @override
  String toString() {
    return 'Tags${TypeUtil.parseString(toMap())}';
  }
}

//@JsonSerializable()
class MetaSinglePage {
  @JsonKey(name: 'original_image_url')
  String? originalImageUrl;

  MetaSinglePage({
    this.originalImageUrl,
  });

  bool get isEmpty => originalImageUrl == null;

  MetaSinglePage copyWith({
    String? originalImageUrl,
  }) {
    return MetaSinglePage(
      originalImageUrl: originalImageUrl ?? this.originalImageUrl,
    );
  }

  factory MetaSinglePage.fromMap(Map<String, dynamic> map) {
    return MetaSinglePage(
      originalImageUrl: map['original_image_url'] == null
          ? null
          : TypeUtil.parseString(map['original_image_url']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'original_image_url': originalImageUrl,
    };
  }

  factory MetaSinglePage.fromJson(Map<String, dynamic> json) =>
      MetaSinglePage.fromMap(json);

  Map<String, dynamic> toJson() => toMap();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MetaSinglePage &&
          runtimeType == other.runtimeType &&
          originalImageUrl == other.originalImageUrl);

  @override
  int get hashCode => originalImageUrl.hashCode;

  @override
  String toString() {
    return 'MetaSinglePage${TypeUtil.parseString(toMap())}';
  }
}
// {"illust":{"id":125547965,"title":"X'max Present 下篇","type":"manga","image_urls":{"square_medium":"https://i.pximg.net/c/360x360_70/img-master/img/2024/12/26/01/27/47/125547965_p0_square1200.jpg","medium":"https://i.pximg.net/c/540x540_70/img-master/img/2024/12/26/01/27/47/125547965_p0_master1200.jpg","large":"https://i.pximg.net/c/600x1200_90/img-master/img/2024/12/26/01/27/47/125547965_p0_master1200.jpg"},"caption":"テメェ...アロナ！！💢","restrict":0,"user":{"id":4004637,"name":"幻羽","account":"9365710x","profile_image_urls":{"medium":"https://i.pximg.net/user-profile/img/2023/09/15/12/22/50/24938498_0b12205fb7799c6445233c446333cd43_170.jpg"},"is_followed":false},"tags":[{"name":"R-18","translated_name":null},{"name":"漫画","translated_name":"manga"},{"name":"ブルーアーカイブ","translated_name":"碧蓝档案"},{"name":"ブルアカ","translated_name":null},{"name":"BlueArchive","translated_name":null},{"name":"アロナ(ブルーアーカイブ)","translated_name":"Alona (Blue Archive)"},{"name":"プラナ(ブルーアーカイブ)","translated_name":"Plana (Blue Archive)"}],"tools":[],"create_date":"2024-12-26T01:27:47+09:00","page_count":2,"width":3031,"height":4238,"sanity_level":6,"x_restrict":1,"series":{"id":266067,"title":"X'max Present"},"meta_single_page":{},"meta_pages":[{"image_urls":{"square_medium":"https://i.pximg.net/c/360x360_70/img-master/img/2024/12/26/01/27/47/125547965_p0_square1200.jpg","medium":"https://i.pximg.net/c/540x540_70/img-master/img/2024/12/26/01/27/47/125547965_p0_master1200.jpg","large":"https://i.pximg.net/c/600x1200_90/img-master/img/2024/12/26/01/27/47/125547965_p0_master1200.jpg","original":"https://i.pximg.net/img-original/img/2024/12/26/01/27/47/125547965_p0.jpg"}},{"image_urls":{"square_medium":"https://i.pximg.net/c/360x360_70/img-master/img/2024/12/26/01/27/47/125547965_p1_square1200.jpg","medium":"https://i.pximg.net/c/540x540_70/img-master/img/2024/12/26/01/27/47/125547965_p1_master1200.jpg","large":"https://i.pximg.net/c/600x1200_90/img-master/img/2024/12/26/01/27/47/125547965_p1_master1200.jpg","original":"https://i.pximg.net/img-original/img/2024/12/26/01/27/47/125547965_p1.jpg"}}],"total_view":12394,"total_bookmarks":1298,"is_bookmarked":true,"visible":true,"is_muted":false,"total_comments":11,"illust_ai_type":1,"illust_book_style":0,"restriction_attributes":["restricted_mode"],"comment_access_control":0}}