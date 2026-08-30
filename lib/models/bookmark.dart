import 'dart:convert';

import 'package:pixez/custom/map_extension.dart';
import 'package:pixez/custom/type_util.dart';

class BookmarkRsp {
  final Bookmark_detail bookmarkDetail;

  const BookmarkRsp({this.bookmarkDetail = const Bookmark_detail()});

  factory BookmarkRsp.fromMap(Map<String, dynamic> map) => BookmarkRsp(
        bookmarkDetail: Bookmark_detail.fromMap(map.optMap('bookmark_detail')),
      );
  factory BookmarkRsp.fromJson(Map<String, dynamic> json) => BookmarkRsp.fromMap(json);
  Map<String, dynamic> toMap() => {'bookmark_detail': bookmarkDetail.toMap()};
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => bookmarkDetail.isEmpty;
  BookmarkRsp copyWith({Bookmark_detail? bookmarkDetail}) =>
      BookmarkRsp(bookmarkDetail: bookmarkDetail ?? this.bookmarkDetail);
  @override
  bool operator ==(Object other) => other is BookmarkRsp && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => json.encode(toMap());
}

class Bookmark_detail {
  final bool isBookmarked;
  final List<Tags> tags;
  final String restrict;

  const Bookmark_detail({
    this.isBookmarked = false,
    this.tags = const [],
    this.restrict = '',
  });

  factory Bookmark_detail.fromMap(Map<String, dynamic> map) => Bookmark_detail(
        isBookmarked: map.optBool('is_bookmarked'),
        tags: [
          ...map.optList('tags', (e) => Tags.fromMap(TypeUtil.parseMap(e))),
        ],
        restrict: map.optString('restrict'),
      );
  factory Bookmark_detail.fromJson(Map<String, dynamic> json) => Bookmark_detail.fromMap(json);
  Map<String, dynamic> toMap() => {
        'is_bookmarked': isBookmarked,
        'tags': tags.map((e) => e.toMap()).toList(),
        'restrict': restrict,
      };
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => TypeUtil.allEmpty([isBookmarked, tags, restrict]);
  Bookmark_detail copyWith({
    bool? isBookmarked,
    List<Tags>? tags,
    String? restrict,
  }) =>
      Bookmark_detail(
        isBookmarked: isBookmarked ?? this.isBookmarked,
        tags: tags == null ? [...this.tags] : [...tags],
        restrict: restrict ?? this.restrict,
      );
  @override
  bool operator ==(Object other) => other is Bookmark_detail && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => json.encode(toMap());
}

class Tags {
  final String name;
  final bool isRegistered;

  const Tags({this.name = '', this.isRegistered = false});

  factory Tags.fromMap(Map<String, dynamic> map) => Tags(
        name: map.optString('name'),
        isRegistered: map.optBool('is_registered'),
      );
  factory Tags.fromJson(Map<String, dynamic> json) => Tags.fromMap(json);
  Map<String, dynamic> toMap() => {'name': name, 'is_registered': isRegistered};
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => TypeUtil.allEmpty([name, isRegistered]);
  Tags copyWith({String? name, bool? isRegistered}) => Tags(
        name: name ?? this.name,
        isRegistered: isRegistered ?? this.isRegistered,
      );
  @override
  bool operator ==(Object other) => other is Tags && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => json.encode(toMap());
}
