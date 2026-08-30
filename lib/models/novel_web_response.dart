import 'package:pixez/custom/map_extension.dart';
import 'package:pixez/custom/type_util.dart';

dynamic _cloneNovelWebValue(dynamic value) {
  if (value is Map) {
    return value.map((key, value) => MapEntry(key, _cloneNovelWebValue(value)));
  }
  if (value is List) return value.map(_cloneNovelWebValue).toList();
  return value;
}

class NovelWebResponse {
  final String id;
  final String title;
  final dynamic seriesId;
  final dynamic seriesTitle;
  final dynamic seriesIsWatched;
  final String userId;
  final String coverUrl;
  final List<String> tags;
  final String caption;
  final String cdate;
  final NovelRating rating;
  final String text;
  final dynamic marker;
  final SeriesNavigation? seriesNavigation;
  final List<dynamic>? glossaryItems;
  final List<dynamic>? replaceableItemIds;
  final Map<String, NovelImage>? images;
  final Map<String, NovelIllusts?>? illusts;
  final int? aiType;
  final bool? isOriginal;

  const NovelWebResponse({
    this.id = '',
    this.title = '',
    this.seriesId,
    this.seriesTitle,
    this.seriesIsWatched,
    this.userId = '',
    this.coverUrl = '',
    this.tags = const [],
    this.caption = '',
    this.cdate = '',
    this.rating = const NovelRating(),
    this.text = '',
    this.marker,
    this.seriesNavigation,
    this.glossaryItems,
    this.replaceableItemIds,
    this.images,
    this.illusts,
    this.aiType,
    this.isOriginal,
  });

  factory NovelWebResponse.fromMap(Map<String, dynamic> map) => NovelWebResponse(
        id: map.optString('id'),
        title: map.optString('title'),
        seriesId: _cloneNovelWebValue(map['seriesId']),
        seriesTitle: _cloneNovelWebValue(map['seriesTitle']),
        seriesIsWatched: _cloneNovelWebValue(map['seriesIsWatched']),
        userId: map.optString('userId'),
        coverUrl: map.optString('coverUrl'),
        tags: [...map.optStringList('tags')],
        caption: map.optString('caption'),
        cdate: map.optString('cdate'),
        rating: NovelRating.fromMap(map.optMap('rating')),
        text: map.optString('text'),
        marker: _cloneNovelWebValue(map['marker']),
        seriesNavigation: map.optMapOrNull('seriesNavigation') == null
            ? null
            : SeriesNavigation.fromMap(map.optMap('seriesNavigation')),
        glossaryItems: map['glossaryItems'] == null
            ? null
            : [...map.optDynamicList('glossaryItems').map(_cloneNovelWebValue)],
        replaceableItemIds: map['replaceableItemIds'] == null
            ? null
            : [...map.optDynamicList('replaceableItemIds').map(_cloneNovelWebValue)],
        images: _parseNovelImages(map['images']),
        illusts: _parseNovelIllusts(map['illusts']),
        aiType: map.optIntOrNull('aiType'),
        isOriginal: map.optBoolOrNull('isOriginal'),
      );

  factory NovelWebResponse.fromJson(Map<String, dynamic> json) => NovelWebResponse.fromMap(json);

  Map<String, dynamic> toMap() => {
        'id': id, 'title': title, 'seriesId': _cloneNovelWebValue(seriesId),
        'seriesTitle': _cloneNovelWebValue(seriesTitle),
        'seriesIsWatched': _cloneNovelWebValue(seriesIsWatched),
        'userId': userId, 'coverUrl': coverUrl, 'tags': [...tags],
        'caption': caption, 'cdate': cdate, 'rating': rating.toMap(), 'text': text,
        'marker': _cloneNovelWebValue(marker),
        'seriesNavigation': seriesNavigation?.toMap(),
        'glossaryItems': glossaryItems?.map(_cloneNovelWebValue).toList(),
        'replaceableItemIds': replaceableItemIds?.map(_cloneNovelWebValue).toList(),
        'images': images?.map((key, value) => MapEntry(key, value.toMap())),
        'illusts': illusts?.map((key, value) => MapEntry(key, value?.toMap())),
        'aiType': aiType, 'isOriginal': isOriginal,
      };
  Map<String, dynamic> toJson() => toMap();

  bool get isEmpty => id.isEmpty && title.isEmpty && seriesId == null &&
      seriesTitle == null && seriesIsWatched == null && userId.isEmpty &&
      coverUrl.isEmpty && tags.isEmpty && caption.isEmpty && cdate.isEmpty &&
      rating.isEmpty && text.isEmpty && marker == null &&
      (seriesNavigation == null || seriesNavigation!.isEmpty) &&
      (glossaryItems == null || glossaryItems!.isEmpty) &&
      (replaceableItemIds == null || replaceableItemIds!.isEmpty) &&
      (images == null || images!.isEmpty) && (illusts == null || illusts!.isEmpty) &&
      aiType == null && isOriginal == null;

  NovelWebResponse copyWith({
    String? id, String? title, Object? seriesId = TypeUtil.unset,
    Object? seriesTitle = TypeUtil.unset, Object? seriesIsWatched = TypeUtil.unset,
    String? userId, String? coverUrl, List<String>? tags, String? caption,
    String? cdate, NovelRating? rating, String? text, Object? marker = TypeUtil.unset,
    Object? seriesNavigation = TypeUtil.unset, Object? glossaryItems = TypeUtil.unset,
    Object? replaceableItemIds = TypeUtil.unset, Object? images = TypeUtil.unset,
    Object? illusts = TypeUtil.unset, Object? aiType = TypeUtil.unset,
    Object? isOriginal = TypeUtil.unset,
  }) => NovelWebResponse(
        id: id ?? this.id, title: title ?? this.title,
        seriesId: identical(seriesId, TypeUtil.unset) ? this.seriesId : _cloneNovelWebValue(seriesId),
        seriesTitle: identical(seriesTitle, TypeUtil.unset) ? this.seriesTitle : _cloneNovelWebValue(seriesTitle),
        seriesIsWatched: identical(seriesIsWatched, TypeUtil.unset) ? this.seriesIsWatched : _cloneNovelWebValue(seriesIsWatched),
        userId: userId ?? this.userId, coverUrl: coverUrl ?? this.coverUrl,
        tags: tags == null ? [...this.tags] : [...tags], caption: caption ?? this.caption,
        cdate: cdate ?? this.cdate, rating: rating ?? this.rating, text: text ?? this.text,
        marker: identical(marker, TypeUtil.unset) ? this.marker : _cloneNovelWebValue(marker),
        seriesNavigation: identical(seriesNavigation, TypeUtil.unset) ? this.seriesNavigation : seriesNavigation as SeriesNavigation?,
        glossaryItems: _copyNullableList(glossaryItems, this.glossaryItems),
        replaceableItemIds: _copyNullableList(replaceableItemIds, this.replaceableItemIds),
        images: _copyImageMap(images, this.images),
        illusts: _copyIllustMap(illusts, this.illusts),
        aiType: identical(aiType, TypeUtil.unset) ? this.aiType : aiType as int?,
        isOriginal: identical(isOriginal, TypeUtil.unset) ? this.isOriginal : isOriginal as bool?,
      );

  @override
  bool operator ==(Object other) => other is NovelWebResponse && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'NovelWebResponse(${toMap()})';
}

List<dynamic>? _copyNullableList(Object? value, List<dynamic>? original) {
  if (identical(value, TypeUtil.unset)) return original == null ? null : [...original];
  if (value == null) return null;
  return [...value as List<dynamic>];
}

Map<String, NovelImage>? _copyImageMap(Object? value, Map<String, NovelImage>? original) {
  if (identical(value, TypeUtil.unset)) return original?.map((key, value) => MapEntry(key, value));
  if (value == null) return null;
  return (value as Map<String, NovelImage>).map((key, value) => MapEntry(key, value));
}

Map<String, NovelIllusts?>? _copyIllustMap(Object? value, Map<String, NovelIllusts?>? original) {
  if (identical(value, TypeUtil.unset)) return original?.map((key, value) => MapEntry(key, value));
  if (value == null) return null;
  return (value as Map<String, NovelIllusts?>).map((key, value) => MapEntry(key, value));
}

Map<String, NovelImage>? _parseNovelImages(dynamic value) {
  final map = TypeUtil.parseNullableMap(value);
  if (map == null) return null;
  return map.map((key, value) => MapEntry(
        key,
        NovelImage.fromMap(TypeUtil.parseMap(value)),
      ));
}

Map<String, NovelIllusts?>? _parseNovelIllusts(dynamic value) {
  final map = TypeUtil.parseNullableMap(value);
  if (map == null) return null;
  return map.map((key, value) {
    final item = TypeUtil.parseMap(value);
    return MapEntry(key, item['illust'] == null ? null : NovelIllusts.fromMap(item));
  });
}

class NovelIllusts {
  final NovelIllust illust;
  const NovelIllusts({this.illust = const NovelIllust()});
  factory NovelIllusts.fromMap(Map<String, dynamic> map) => NovelIllusts(
        illust: NovelIllust.fromMap(map.optMap('illust')),
      );
  factory NovelIllusts.fromJson(Map<String, dynamic> json) => NovelIllusts.fromMap(json);
  Map<String, dynamic> toMap() => {'illust': illust.toMap()};
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => illust.isEmpty;
  NovelIllusts copyWith({NovelIllust? illust}) => NovelIllusts(illust: illust ?? this.illust);
  @override
  bool operator ==(Object other) => other is NovelIllusts && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'NovelIllusts(${toMap()})';
}

class NovelIllust {
  final NovelIllustImages images;
  const NovelIllust({this.images = const NovelIllustImages()});
  factory NovelIllust.fromMap(Map<String, dynamic> map) => NovelIllust(images: NovelIllustImages.fromMap(map.optMap('images')));
  factory NovelIllust.fromJson(Map<String, dynamic> json) => NovelIllust.fromMap(json);
  Map<String, dynamic> toMap() => {'images': images.toMap()};
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => images.isEmpty;
  NovelIllust copyWith({NovelIllustImages? images}) => NovelIllust(images: images ?? this.images);
  @override
  bool operator ==(Object other) => other is NovelIllust && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'NovelIllust(${toMap()})';
}

class NovelIllustImages {
  final String? small;
  final String? medium;
  final String? original;
  const NovelIllustImages({this.small, this.medium, this.original});
  factory NovelIllustImages.fromMap(Map<String, dynamic> map) => NovelIllustImages(
        small: map.optStringOrNull('small'),
        medium: map.optStringOrNull('medium'),
        original: map.optStringOrNull('original'),
      );
  factory NovelIllustImages.fromJson(Map<String, dynamic> json) => NovelIllustImages.fromMap(json);
  Map<String, dynamic> toMap() => {'small': small, 'medium': medium, 'original': original};
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => small == null && medium == null && original == null;
  NovelIllustImages copyWith({Object? small = TypeUtil.unset, Object? medium = TypeUtil.unset, Object? original = TypeUtil.unset}) => NovelIllustImages(
        small: identical(small, TypeUtil.unset) ? this.small : small as String?,
        medium: identical(medium, TypeUtil.unset) ? this.medium : medium as String?,
        original: identical(original, TypeUtil.unset) ? this.original : original as String?,
      );
  @override
  bool operator ==(Object other) => other is NovelIllustImages && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'NovelIllustImages(${toMap()})';
}

class NovelRating {
  final int like;
  final int bookmark;
  final int view;
  const NovelRating({this.like = 0, this.bookmark = 0, this.view = 0});
  factory NovelRating.fromMap(Map<String, dynamic> map) => NovelRating(
        like: map.optInt('like'), bookmark: map.optInt('bookmark'), view: map.optInt('view'),
      );
  factory NovelRating.fromJson(Map<String, dynamic> json) => NovelRating.fromMap(json);
  Map<String, dynamic> toMap() => {'like': like, 'bookmark': bookmark, 'view': view};
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => like == 0 && bookmark == 0 && view == 0;
  NovelRating copyWith({int? like, int? bookmark, int? view}) => NovelRating(
        like: like ?? this.like, bookmark: bookmark ?? this.bookmark, view: view ?? this.view,
      );
  @override
  bool operator ==(Object other) => other is NovelRating && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'NovelRating(${toMap()})';
}

class SeriesNavigation {
  final PrevNovel? nextNovel;
  final PrevNovel? prevNovel;
  const SeriesNavigation({this.nextNovel, this.prevNovel});
  factory SeriesNavigation.fromMap(Map<String, dynamic> map) => SeriesNavigation(
        nextNovel: map.optMapOrNull('nextNovel') == null ? null : PrevNovel.fromMap(map.optMap('nextNovel')),
        prevNovel: map.optMapOrNull('prevNovel') == null ? null : PrevNovel.fromMap(map.optMap('prevNovel')),
      );
  factory SeriesNavigation.fromJson(Map<String, dynamic> json) => SeriesNavigation.fromMap(json);
  Map<String, dynamic> toMap() => {'nextNovel': nextNovel?.toMap(), 'prevNovel': prevNovel?.toMap()};
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => (nextNovel == null || nextNovel!.isEmpty) && (prevNovel == null || prevNovel!.isEmpty);
  SeriesNavigation copyWith({Object? nextNovel = TypeUtil.unset, Object? prevNovel = TypeUtil.unset}) => SeriesNavigation(
        nextNovel: identical(nextNovel, TypeUtil.unset) ? this.nextNovel : nextNovel as PrevNovel?,
        prevNovel: identical(prevNovel, TypeUtil.unset) ? this.prevNovel : prevNovel as PrevNovel?,
      );
  @override
  bool operator ==(Object other) => other is SeriesNavigation && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'SeriesNavigation(${toMap()})';
}

class PrevNovel {
  final int id;
  final bool viewable;
  final String contentOrder;
  final String title;
  final String coverUrl;
  const PrevNovel({this.id = 0, this.viewable = false, this.contentOrder = '', this.title = '', this.coverUrl = ''});
  factory PrevNovel.fromMap(Map<String, dynamic> map) => PrevNovel(
        id: map.optInt('id'), viewable: map.optBool('viewable'),
        contentOrder: map.optString('contentOrder'), title: map.optString('title'), coverUrl: map.optString('coverUrl'),
      );
  factory PrevNovel.fromJson(Map<String, dynamic> json) => PrevNovel.fromMap(json);
  Map<String, dynamic> toMap() => {'id': id, 'viewable': viewable, 'contentOrder': contentOrder, 'title': title, 'coverUrl': coverUrl};
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => id == 0 && !viewable && contentOrder.isEmpty && title.isEmpty && coverUrl.isEmpty;
  PrevNovel copyWith({int? id, bool? viewable, String? contentOrder, String? title, String? coverUrl}) => PrevNovel(
        id: id ?? this.id, viewable: viewable ?? this.viewable, contentOrder: contentOrder ?? this.contentOrder,
        title: title ?? this.title, coverUrl: coverUrl ?? this.coverUrl,
      );
  @override
  bool operator ==(Object other) => other is PrevNovel && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'PrevNovel(${toMap()})';
}

class NovelImage {
  final String? novelImageId;
  final String sl;
  final NovelUrls urls;
  const NovelImage({this.novelImageId, this.sl = '', this.urls = const NovelUrls()});
  factory NovelImage.fromMap(Map<String, dynamic> map) => NovelImage(
        novelImageId: map.optStringOrNull('novelImageId'),
        sl: map.optString('sl'), urls: NovelUrls.fromMap(map.optMap('urls')),
      );
  factory NovelImage.fromJson(Map<String, dynamic> json) => NovelImage.fromMap(json);
  Map<String, dynamic> toMap() => {'novelImageId': novelImageId, 'sl': sl, 'urls': urls.toMap()};
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => novelImageId == null && sl.isEmpty && urls.isEmpty;
  NovelImage copyWith({Object? novelImageId = TypeUtil.unset, String? sl, NovelUrls? urls}) => NovelImage(
        novelImageId: identical(novelImageId, TypeUtil.unset) ? this.novelImageId : novelImageId as String?,
        sl: sl ?? this.sl, urls: urls ?? this.urls,
      );
  @override
  bool operator ==(Object other) => other is NovelImage && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'NovelImage(${toMap()})';
}

class NovelUrls {
  final String? the240Mw;
  final String? the480Mw;
  final String? the1200X1200;
  final String? the128X128;
  final String? original;
  const NovelUrls({this.the240Mw, this.the480Mw, this.the1200X1200, this.the128X128, this.original});
  factory NovelUrls.fromMap(Map<String, dynamic> map) => NovelUrls(
        the240Mw: map.optStringOrNull('the240Mw'), the480Mw: map.optStringOrNull('the480Mw'),
        the1200X1200: map.optStringOrNull('the1200X1200'), the128X128: map.optStringOrNull('the128X128'),
        original: map.optStringOrNull('original'),
      );
  factory NovelUrls.fromJson(Map<String, dynamic> json) => NovelUrls.fromMap(json);
  Map<String, dynamic> toMap() => {
        'the240Mw': the240Mw, 'the480Mw': the480Mw, 'the1200X1200': the1200X1200,
        'the128X128': the128X128, 'original': original,
      };
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => the240Mw == null && the480Mw == null && the1200X1200 == null && the128X128 == null && original == null;
  NovelUrls copyWith({Object? the240Mw = TypeUtil.unset, Object? the480Mw = TypeUtil.unset, Object? the1200X1200 = TypeUtil.unset, Object? the128X128 = TypeUtil.unset, Object? original = TypeUtil.unset}) => NovelUrls(
        the240Mw: identical(the240Mw, TypeUtil.unset) ? this.the240Mw : the240Mw as String?,
        the480Mw: identical(the480Mw, TypeUtil.unset) ? this.the480Mw : the480Mw as String?,
        the1200X1200: identical(the1200X1200, TypeUtil.unset) ? this.the1200X1200 : the1200X1200 as String?,
        the128X128: identical(the128X128, TypeUtil.unset) ? this.the128X128 : the128X128 as String?,
        original: identical(original, TypeUtil.unset) ? this.original : original as String?,
      );
  @override
  bool operator ==(Object other) => other is NovelUrls && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'NovelUrls(${toMap()})';
}
