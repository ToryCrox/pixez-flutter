import 'package:pixez/custom/map_extension.dart';
import 'package:pixez/custom/type_util.dart';
import 'package:pixez/models/novel_recom_response.dart';

class NovelSeriesSeries {
  final int id;
  final String title;
  const NovelSeriesSeries({this.id = 0, this.title = ''});
  factory NovelSeriesSeries.fromMap(Map<String, dynamic> map) => NovelSeriesSeries(
        id: map.optInt('id'), title: map.optString('title'),
      );
  factory NovelSeriesSeries.fromJson(Map<String, dynamic> json) => NovelSeriesSeries.fromMap(json);
  Map<String, dynamic> toMap() => {'id': id, 'title': title};
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => id == 0 && title.isEmpty;
  NovelSeriesSeries copyWith({int? id, String? title}) => NovelSeriesSeries(id: id ?? this.id, title: title ?? this.title);
  @override
  bool operator ==(Object other) => other is NovelSeriesSeries && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'NovelSeriesSeries(${toMap()})';
}

class NovelSeriesNovelTag {
  final String name;
  final String? translatedName;
  final bool addedByUploadedUser;
  const NovelSeriesNovelTag({this.name = '', this.translatedName, this.addedByUploadedUser = false});
  factory NovelSeriesNovelTag.fromMap(Map<String, dynamic> map) => NovelSeriesNovelTag(
        name: map.optString('name'),
        translatedName: map.optStringOrNull('translated_name'),
        addedByUploadedUser: map.optBool('added_by_uploaded_user'),
      );
  factory NovelSeriesNovelTag.fromJson(Map<String, dynamic> json) => NovelSeriesNovelTag.fromMap(json);
  Map<String, dynamic> toMap() => {
        'name': name, 'translated_name': translatedName,
        'added_by_uploaded_user': addedByUploadedUser,
      };
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => name.isEmpty && translatedName == null && !addedByUploadedUser;
  NovelSeriesNovelTag copyWith({String? name, Object? translatedName = TypeUtil.unset, bool? addedByUploadedUser}) => NovelSeriesNovelTag(
        name: name ?? this.name,
        translatedName: identical(translatedName, TypeUtil.unset) ? this.translatedName : translatedName as String?,
        addedByUploadedUser: addedByUploadedUser ?? this.addedByUploadedUser,
      );
  @override
  bool operator ==(Object other) => other is NovelSeriesNovelTag && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'NovelSeriesNovelTag(${toMap()})';
}

class NovelSeriesNovel {
  final int id;
  final String title;
  final String? caption;
  final int restrict;
  final int xRestrict;
  final bool? isOriginal;
  final NovelSeriesImageUrls imageUrls;
  final DateTime createDate;
  final List<NovelSeriesNovelTag> tags;
  final int pageCount;
  final int textLength;
  final NovelSeriesUser user;
  final NovelSeriesSeries series;
  final bool isBookmarked;
  final int totalBookmarks;
  final int totalView;
  final bool visible;
  final int totalComments;
  final bool isMuted;
  final bool isMypixivOnly;
  final bool isXRestricted;
  final int novelAiType;

  NovelSeriesNovel({
    this.id = 0,
    this.title = '',
    this.caption,
    this.restrict = 0,
    this.xRestrict = 0,
    this.isOriginal,
    this.imageUrls = const NovelSeriesImageUrls(),
    DateTime? createDate,
    this.tags = const [],
    this.pageCount = 0,
    this.textLength = 0,
    this.user = const NovelSeriesUser(),
    this.series = const NovelSeriesSeries(),
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

  factory NovelSeriesNovel.fromMap(Map<String, dynamic> map) => NovelSeriesNovel(
        id: map.optInt('id'),
        title: map.optString('title'),
        caption: map.optStringOrNull('caption'),
        restrict: map.optInt('restrict'),
        xRestrict: map.optInt('x_restrict'),
        isOriginal: map.optBoolOrNull('is_original'),
        imageUrls: NovelSeriesImageUrls.fromMap(map.optMap('image_urls')),
        createDate: map.optDateTime('create_date'),
        tags: [
          ...map.optList(
            'tags',
            (e) => NovelSeriesNovelTag.fromMap(TypeUtil.parseMap(e)),
          ),
        ],
        pageCount: map.optInt('page_count'),
        textLength: map.optInt('text_length'),
        user: NovelSeriesUser.fromMap(map.optMap('user')),
        series: NovelSeriesSeries.fromMap(map.optMap('series')),
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
  factory NovelSeriesNovel.fromJson(Map<String, dynamic> json) => NovelSeriesNovel.fromMap(json);
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
  bool get isEmpty => id == 0 && title.isEmpty && caption == null && restrict == 0 &&
      xRestrict == 0 && isOriginal == null && imageUrls.isEmpty &&
      createDate.millisecondsSinceEpoch == 0 && tags.isEmpty && pageCount == 0 &&
      textLength == 0 && user.isEmpty && series.isEmpty && !isBookmarked &&
      totalBookmarks == 0 && totalView == 0 && !visible && totalComments == 0 &&
      !isMuted && !isMypixivOnly && !isXRestricted && novelAiType == 0;
  NovelSeriesNovel copyWith({
    int? id, String? title, Object? caption = TypeUtil.unset, int? restrict,
    int? xRestrict, Object? isOriginal = TypeUtil.unset, NovelSeriesImageUrls? imageUrls,
    DateTime? createDate, List<NovelSeriesNovelTag>? tags, int? pageCount,
    int? textLength, NovelSeriesUser? user, NovelSeriesSeries? series,
    bool? isBookmarked, int? totalBookmarks, int? totalView, bool? visible,
    int? totalComments, bool? isMuted, bool? isMypixivOnly, bool? isXRestricted,
    int? novelAiType,
  }) => NovelSeriesNovel(
        id: id ?? this.id, title: title ?? this.title,
        caption: identical(caption, TypeUtil.unset) ? this.caption : caption as String?,
        restrict: restrict ?? this.restrict, xRestrict: xRestrict ?? this.xRestrict,
        isOriginal: identical(isOriginal, TypeUtil.unset) ? this.isOriginal : isOriginal as bool?,
        imageUrls: imageUrls ?? this.imageUrls, createDate: createDate ?? this.createDate,
        tags: tags == null ? [...this.tags] : [...tags],
        pageCount: pageCount ?? this.pageCount, textLength: textLength ?? this.textLength,
        user: user ?? this.user, series: series ?? this.series,
        isBookmarked: isBookmarked ?? this.isBookmarked,
        totalBookmarks: totalBookmarks ?? this.totalBookmarks, totalView: totalView ?? this.totalView,
        visible: visible ?? this.visible, totalComments: totalComments ?? this.totalComments,
        isMuted: isMuted ?? this.isMuted, isMypixivOnly: isMypixivOnly ?? this.isMypixivOnly,
        isXRestricted: isXRestricted ?? this.isXRestricted, novelAiType: novelAiType ?? this.novelAiType,
      );
  @override
  bool operator ==(Object other) => other is NovelSeriesNovel && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'NovelSeriesNovel(${toMap()})';
}

class NovelSeriesDetail {
  final int id;
  final String title;
  final String? caption;
  final bool isOriginal;
  final bool isConcluded;
  final int contentCount;
  final int totalCharacterCount;
  final NovelSeriesUser user;
  final String displayText;
  final int novelAiType;
  final bool? watchlistAdded;

  const NovelSeriesDetail({
    this.id = 0,
    this.title = '',
    this.caption,
    this.isOriginal = false,
    this.isConcluded = false,
    this.contentCount = 0,
    this.totalCharacterCount = 0,
    this.user = const NovelSeriesUser(),
    this.displayText = '',
    this.novelAiType = 0,
    this.watchlistAdded,
  });
  factory NovelSeriesDetail.fromMap(Map<String, dynamic> map) => NovelSeriesDetail(
        id: map.optInt('id'), title: map.optString('title'),
        caption: map.optStringOrNull('caption'), isOriginal: map.optBool('is_original'),
        isConcluded: map.optBool('is_concluded'), contentCount: map.optInt('content_count'),
        totalCharacterCount: map.optInt('total_character_count'),
        user: NovelSeriesUser.fromMap(map.optMap('user')),
        displayText: map.optString('display_text'), novelAiType: map.optInt('novel_ai_type'),
        watchlistAdded: map.optBoolOrNull('watchlist_added'),
      );
  factory NovelSeriesDetail.fromJson(Map<String, dynamic> json) => NovelSeriesDetail.fromMap(json);
  Map<String, dynamic> toMap() => {
        'id': id, 'title': title, 'caption': caption, 'is_original': isOriginal,
        'is_concluded': isConcluded, 'content_count': contentCount,
        'total_character_count': totalCharacterCount, 'user': user.toMap(),
        'display_text': displayText, 'novel_ai_type': novelAiType,
        'watchlist_added': watchlistAdded,
      };
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => id == 0 && title.isEmpty && caption == null && !isOriginal &&
      !isConcluded && contentCount == 0 && totalCharacterCount == 0 &&
      user.isEmpty && displayText.isEmpty && novelAiType == 0 && watchlistAdded == null;
  NovelSeriesDetail copyWith({
    int? id, String? title, Object? caption = TypeUtil.unset, bool? isOriginal,
    bool? isConcluded, int? contentCount, int? totalCharacterCount, NovelSeriesUser? user,
    String? displayText, int? novelAiType, Object? watchlistAdded = TypeUtil.unset,
  }) => NovelSeriesDetail(
        id: id ?? this.id, title: title ?? this.title,
        caption: identical(caption, TypeUtil.unset) ? this.caption : caption as String?,
        isOriginal: isOriginal ?? this.isOriginal, isConcluded: isConcluded ?? this.isConcluded,
        contentCount: contentCount ?? this.contentCount,
        totalCharacterCount: totalCharacterCount ?? this.totalCharacterCount,
        user: user ?? this.user, displayText: displayText ?? this.displayText,
        novelAiType: novelAiType ?? this.novelAiType,
        watchlistAdded: identical(watchlistAdded, TypeUtil.unset)
            ? this.watchlistAdded : watchlistAdded as bool?,
      );
  @override
  bool operator ==(Object other) => other is NovelSeriesDetail && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'NovelSeriesDetail(${toMap()})';
}

class NovelSeriesUser {
  final int id;
  final String name;
  final String account;
  final NovelSeriesProfileImageUrls profileImageUrls;
  final bool isFollowed;
  final bool isAccessBlockingUser;

  const NovelSeriesUser({
    this.id = 0, this.name = '', this.account = '',
    this.profileImageUrls = const NovelSeriesProfileImageUrls(),
    this.isFollowed = false, this.isAccessBlockingUser = false,
  });
  factory NovelSeriesUser.fromMap(Map<String, dynamic> map) => NovelSeriesUser(
        id: map.optInt('id'), name: map.optString('name'), account: map.optString('account'),
        profileImageUrls: NovelSeriesProfileImageUrls.fromMap(map.optMap('profile_image_urls')),
        isFollowed: map.optBool('is_followed'),
        isAccessBlockingUser: map.optBool('is_access_blocking_user'),
      );
  factory NovelSeriesUser.fromJson(Map<String, dynamic> json) => NovelSeriesUser.fromMap(json);
  Map<String, dynamic> toMap() => {
        'id': id, 'name': name, 'account': account,
        'profile_image_urls': profileImageUrls.toMap(),
        'is_followed': isFollowed, 'is_access_blocking_user': isAccessBlockingUser,
      };
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => id == 0 && name.isEmpty && account.isEmpty &&
      profileImageUrls.isEmpty && !isFollowed && !isAccessBlockingUser;
  NovelSeriesUser copyWith({
    int? id, String? name, String? account, NovelSeriesProfileImageUrls? profileImageUrls,
    bool? isFollowed, bool? isAccessBlockingUser,
  }) => NovelSeriesUser(
        id: id ?? this.id, name: name ?? this.name, account: account ?? this.account,
        profileImageUrls: profileImageUrls ?? this.profileImageUrls,
        isFollowed: isFollowed ?? this.isFollowed,
        isAccessBlockingUser: isAccessBlockingUser ?? this.isAccessBlockingUser,
      );
  @override
  bool operator ==(Object other) => other is NovelSeriesUser && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'NovelSeriesUser(${toMap()})';
}

class NovelSeriesProfileImageUrls {
  final String medium;
  const NovelSeriesProfileImageUrls({this.medium = ''});
  factory NovelSeriesProfileImageUrls.fromMap(Map<String, dynamic> map) =>
      NovelSeriesProfileImageUrls(medium: map.optString('medium'));
  factory NovelSeriesProfileImageUrls.fromJson(Map<String, dynamic> json) => NovelSeriesProfileImageUrls.fromMap(json);
  Map<String, dynamic> toMap() => {'medium': medium};
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => medium.isEmpty;
  NovelSeriesProfileImageUrls copyWith({String? medium}) => NovelSeriesProfileImageUrls(medium: medium ?? this.medium);
  @override
  bool operator ==(Object other) => other is NovelSeriesProfileImageUrls && medium == other.medium;
  @override
  int get hashCode => medium.hashCode;
  @override
  String toString() => 'NovelSeriesProfileImageUrls(${toMap()})';
}

class NovelSeriesFirstNovel {
  final int id;
  final String title;
  final String caption;
  final int restrict;
  final int xRestrict;
  final bool isOriginal;
  final NovelSeriesImageUrls imageUrls;
  final String createDate;
  final List<NovelSeriesNovelTag> tags;
  final int pageCount;
  final int textLength;
  final NovelSeriesUser user;
  final NovelSeriesSeries series;
  final bool isBookmarked;
  final int totalBookmarks;
  final int totalView;
  final bool visible;
  final int totalComments;
  final bool? isMuted;
  final bool? isMypixivOnly;
  final bool? isXRestricted;
  final int novelAiType;

  const NovelSeriesFirstNovel({
    this.id = 0, this.title = '', this.caption = '', this.restrict = 0,
    this.xRestrict = 0, this.isOriginal = false,
    this.imageUrls = const NovelSeriesImageUrls(), this.createDate = '',
    this.tags = const [], this.pageCount = 0, this.textLength = 0,
    this.user = const NovelSeriesUser(), this.series = const NovelSeriesSeries(),
    this.isBookmarked = false, this.totalBookmarks = 0, this.totalView = 0,
    this.visible = false, this.totalComments = 0, this.isMuted,
    this.isMypixivOnly, this.isXRestricted, this.novelAiType = 0,
  });
  factory NovelSeriesFirstNovel.fromMap(Map<String, dynamic> map) => NovelSeriesFirstNovel(
        id: map.optInt('id'), title: map.optString('title'), caption: map.optString('caption'),
        restrict: map.optInt('restrict'), xRestrict: map.optInt('x_restrict'),
        isOriginal: map.optBool('is_original'), imageUrls: NovelSeriesImageUrls.fromMap(map.optMap('image_urls')),
        createDate: map.optString('create_date'),
        tags: [
          ...map.optList(
            'tags',
            (e) => NovelSeriesNovelTag.fromMap(TypeUtil.parseMap(e)),
          ),
        ],
        pageCount: map.optInt('page_count'), textLength: map.optInt('text_length'),
        user: NovelSeriesUser.fromMap(map.optMap('user')), series: NovelSeriesSeries.fromMap(map.optMap('series')),
        isBookmarked: map.optBool('is_bookmarked'), totalBookmarks: map.optInt('total_bookmarks'),
        totalView: map.optInt('total_view'), visible: map.optBool('visible'),
        totalComments: map.optInt('total_comments'), isMuted: map.optBoolOrNull('is_muted'),
        isMypixivOnly: map.optBoolOrNull('is_my_pixiv_only'),
        isXRestricted: map.optBoolOrNull('is_X_restricted'), novelAiType: map.optInt('novel_ai_type'),
      );
  factory NovelSeriesFirstNovel.fromJson(Map<String, dynamic> json) => NovelSeriesFirstNovel.fromMap(json);
  Map<String, dynamic> toMap() => {
        'id': id, 'title': title, 'caption': caption, 'restrict': restrict, 'x_restrict': xRestrict,
        'is_original': isOriginal, 'image_urls': imageUrls.toMap(), 'create_date': createDate,
        'tags': tags.map((e) => e.toMap()).toList(), 'page_count': pageCount, 'text_length': textLength,
        'user': user.toMap(), 'series': series.toMap(), 'is_bookmarked': isBookmarked,
        'total_bookmarks': totalBookmarks, 'total_view': totalView, 'visible': visible,
        'total_comments': totalComments, 'is_muted': isMuted, 'is_my_pixiv_only': isMypixivOnly,
        'is_X_restricted': isXRestricted, 'novel_ai_type': novelAiType,
      };
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => id == 0 && title.isEmpty && caption.isEmpty && restrict == 0 &&
      xRestrict == 0 && !isOriginal && imageUrls.isEmpty && createDate.isEmpty &&
      tags.isEmpty && pageCount == 0 && textLength == 0 && user.isEmpty && series.isEmpty &&
      !isBookmarked && totalBookmarks == 0 && totalView == 0 && !visible && totalComments == 0 &&
      isMuted == null && isMypixivOnly == null && isXRestricted == null && novelAiType == 0;
  NovelSeriesFirstNovel copyWith({
    int? id, String? title, String? caption, int? restrict, int? xRestrict, bool? isOriginal,
    NovelSeriesImageUrls? imageUrls, String? createDate, List<NovelSeriesNovelTag>? tags,
    int? pageCount, int? textLength, NovelSeriesUser? user, NovelSeriesSeries? series,
    bool? isBookmarked, int? totalBookmarks, int? totalView, bool? visible, int? totalComments,
    Object? isMuted = TypeUtil.unset, Object? isMypixivOnly = TypeUtil.unset,
    Object? isXRestricted = TypeUtil.unset, int? novelAiType,
  }) => NovelSeriesFirstNovel(
        id: id ?? this.id, title: title ?? this.title, caption: caption ?? this.caption,
        restrict: restrict ?? this.restrict, xRestrict: xRestrict ?? this.xRestrict,
        isOriginal: isOriginal ?? this.isOriginal, imageUrls: imageUrls ?? this.imageUrls,
        createDate: createDate ?? this.createDate, tags: tags == null ? [...this.tags] : [...tags],
        pageCount: pageCount ?? this.pageCount, textLength: textLength ?? this.textLength,
        user: user ?? this.user, series: series ?? this.series,
        isBookmarked: isBookmarked ?? this.isBookmarked, totalBookmarks: totalBookmarks ?? this.totalBookmarks,
        totalView: totalView ?? this.totalView, visible: visible ?? this.visible,
        totalComments: totalComments ?? this.totalComments,
        isMuted: identical(isMuted, TypeUtil.unset) ? this.isMuted : isMuted as bool?,
        isMypixivOnly: identical(isMypixivOnly, TypeUtil.unset) ? this.isMypixivOnly : isMypixivOnly as bool?,
        isXRestricted: identical(isXRestricted, TypeUtil.unset) ? this.isXRestricted : isXRestricted as bool?,
        novelAiType: novelAiType ?? this.novelAiType,
      );
  @override
  bool operator ==(Object other) => other is NovelSeriesFirstNovel && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'NovelSeriesFirstNovel(${toMap()})';
}

class NovelSeriesImageUrls {
  final String squareMedium;
  final String medium;
  final String large;
  const NovelSeriesImageUrls({this.squareMedium = '', this.medium = '', this.large = ''});
  factory NovelSeriesImageUrls.fromMap(Map<String, dynamic> map) => NovelSeriesImageUrls(
        squareMedium: map.optString('square_medium'), medium: map.optString('medium'), large: map.optString('large'),
      );
  factory NovelSeriesImageUrls.fromJson(Map<String, dynamic> json) => NovelSeriesImageUrls.fromMap(json);
  Map<String, dynamic> toMap() => {'square_medium': squareMedium, 'medium': medium, 'large': large};
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => TypeUtil.allEmpty([squareMedium, medium, large]);
  NovelSeriesImageUrls copyWith({String? squareMedium, String? medium, String? large}) => NovelSeriesImageUrls(
        squareMedium: squareMedium ?? this.squareMedium, medium: medium ?? this.medium, large: large ?? this.large,
      );
  @override
  bool operator ==(Object other) => other is NovelSeriesImageUrls && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'NovelSeriesImageUrls(${toMap()})';
}

class NovelSeriesResponse {
  final NovelSeriesDetail novelSeriesDetail;
  final NovelSeriesFirstNovel novelSeriesFirstNovel;
  final NovelSeriesFirstNovel? novelSeriesLatestNovel;
  final List<Novel> novels;
  final String? nextUrl;

  const NovelSeriesResponse({
    this.novelSeriesDetail = const NovelSeriesDetail(),
    this.novelSeriesFirstNovel = const NovelSeriesFirstNovel(),
    this.novelSeriesLatestNovel,
    this.novels = const [],
    this.nextUrl,
  });
  factory NovelSeriesResponse.fromMap(Map<String, dynamic> map) => NovelSeriesResponse(
        novelSeriesDetail: NovelSeriesDetail.fromMap(map.optMap('novel_series_detail')),
        novelSeriesFirstNovel: NovelSeriesFirstNovel.fromMap(map.optMap('novel_series_first_novel')),
        novelSeriesLatestNovel: map.optMapOrNull('novel_series_latest_novel') == null
            ? null : NovelSeriesFirstNovel.fromMap(map.optMap('novel_series_latest_novel')),
        novels: [
          ...map.optList('novels', (e) => Novel.fromMap(TypeUtil.parseMap(e))),
        ],
        nextUrl: map.optStringOrNull('next_url'),
      );
  factory NovelSeriesResponse.fromJson(Map<String, dynamic> json) => NovelSeriesResponse.fromMap(json);
  Map<String, dynamic> toMap() => {
        'novel_series_detail': novelSeriesDetail.toMap(),
        'novel_series_first_novel': novelSeriesFirstNovel.toMap(),
        'novel_series_latest_novel': novelSeriesLatestNovel?.toMap(),
        'novels': novels.map((e) => e.toMap()).toList(),
        'next_url': nextUrl,
      };
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => novelSeriesDetail.isEmpty && novelSeriesFirstNovel.isEmpty &&
      (novelSeriesLatestNovel == null || novelSeriesLatestNovel!.isEmpty) &&
      novels.isEmpty && nextUrl == null;
  NovelSeriesResponse copyWith({
    NovelSeriesDetail? novelSeriesDetail, NovelSeriesFirstNovel? novelSeriesFirstNovel,
    Object? novelSeriesLatestNovel = TypeUtil.unset, List<Novel>? novels,
    Object? nextUrl = TypeUtil.unset,
  }) => NovelSeriesResponse(
        novelSeriesDetail: novelSeriesDetail ?? this.novelSeriesDetail,
        novelSeriesFirstNovel: novelSeriesFirstNovel ?? this.novelSeriesFirstNovel,
        novelSeriesLatestNovel: identical(novelSeriesLatestNovel, TypeUtil.unset)
            ? this.novelSeriesLatestNovel : novelSeriesLatestNovel as NovelSeriesFirstNovel?,
        novels: novels == null ? [...this.novels] : [...novels],
        nextUrl: identical(nextUrl, TypeUtil.unset) ? this.nextUrl : nextUrl as String?,
      );
  @override
  bool operator ==(Object other) => other is NovelSeriesResponse && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'NovelSeriesResponse(${toMap()})';
}
