import 'dart:convert';

import 'package:pixez/custom/map_extension.dart';
import 'package:pixez/custom/type_util.dart';

class BookMarkDetailResponse {
  final BookmarkDetail bookmarkDetail;

  const BookMarkDetailResponse({this.bookmarkDetail = const BookmarkDetail()});

  factory BookMarkDetailResponse.fromMap(Map<String, dynamic> map) =>
      BookMarkDetailResponse(
        bookmarkDetail: BookmarkDetail.fromMap(map.optMap('bookmark_detail')),
      );
  factory BookMarkDetailResponse.fromJson(Map<String, dynamic> json) =>
      BookMarkDetailResponse.fromMap(json);
  Map<String, dynamic> toMap() => {'bookmark_detail': bookmarkDetail.toMap()};
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => bookmarkDetail.isEmpty;
  BookMarkDetailResponse copyWith({BookmarkDetail? bookmarkDetail}) =>
      BookMarkDetailResponse(bookmarkDetail: bookmarkDetail ?? this.bookmarkDetail);
  @override
  bool operator ==(Object other) => other is BookMarkDetailResponse &&
      TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => json.encode(toMap());
}

class BookmarkDetail {
  final bool isBookmarked;
  final List<TagsR> tags;
  final String restrict;

  const BookmarkDetail({
    this.isBookmarked = false,
    this.tags = const [],
    this.restrict = '',
  });

  factory BookmarkDetail.fromMap(Map<String, dynamic> map) => BookmarkDetail(
        isBookmarked: map.optBool('is_bookmarked'),
        tags: [
          ...map.optList('tags', (e) => TagsR.fromMap(TypeUtil.parseMap(e))),
        ],
        restrict: map.optString('restrict'),
      );
  factory BookmarkDetail.fromJson(Map<String, dynamic> json) =>
      BookmarkDetail.fromMap(json);
  Map<String, dynamic> toMap() => {
        'is_bookmarked': isBookmarked,
        'tags': tags.map((e) => e.toMap()).toList(),
        'restrict': restrict,
      };
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => TypeUtil.allEmpty([isBookmarked, tags, restrict]);
  BookmarkDetail copyWith({
    bool? isBookmarked,
    List<TagsR>? tags,
    String? restrict,
  }) =>
      BookmarkDetail(
        isBookmarked: isBookmarked ?? this.isBookmarked,
        tags: tags == null ? [...this.tags] : [...tags],
        restrict: restrict ?? this.restrict,
      );
  @override
  bool operator ==(Object other) =>
      other is BookmarkDetail && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => json.encode(toMap());
}

class TagsR {
  final String name;
  final bool isRegistered;

  const TagsR({this.name = '', this.isRegistered = false});

  factory TagsR.fromMap(Map<String, dynamic> map) => TagsR(
        name: map.optString('name'),
        isRegistered: map.optBool('is_registered'),
      );
  factory TagsR.fromJson(Map<String, dynamic> json) => TagsR.fromMap(json);
  Map<String, dynamic> toMap() => {'name': name, 'is_registered': isRegistered};
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => TypeUtil.allEmpty([name, isRegistered]);
  TagsR copyWith({String? name, bool? isRegistered}) => TagsR(
        name: name ?? this.name,
        isRegistered: isRegistered ?? this.isRegistered,
      );
  @override
  bool operator ==(Object other) => other is TagsR && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => json.encode(toMap());
}
