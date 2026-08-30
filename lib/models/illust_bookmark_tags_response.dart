import 'package:pixez/custom/map_extension.dart';
import 'package:pixez/custom/type_util.dart';

class IllustBookmarkTagsResponse {
  final List<BookmarkTag> bookmarkTags;
  final String? nextUrl;

  const IllustBookmarkTagsResponse({this.bookmarkTags = const [], this.nextUrl});

  factory IllustBookmarkTagsResponse.fromMap(Map<String, dynamic> map) =>
      IllustBookmarkTagsResponse(
        bookmarkTags: map.optList(
          'bookmark_tags',
          (e) => BookmarkTag.fromMap(TypeUtil.parseMap(e)),
        ),
        nextUrl: map.optStringOrNull('next_url'),
      );
  factory IllustBookmarkTagsResponse.fromJson(Map<String, dynamic> json) =>
      IllustBookmarkTagsResponse.fromMap(json);
  Map<String, dynamic> toMap() => {
        'bookmark_tags': bookmarkTags.map((e) => e.toMap()).toList(),
        'next_url': nextUrl,
      };
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => TypeUtil.allEmpty([bookmarkTags, nextUrl]);
  IllustBookmarkTagsResponse copyWith({
    List<BookmarkTag>? bookmarkTags,
    Object? nextUrl = TypeUtil.unset,
  }) => IllustBookmarkTagsResponse(
        bookmarkTags: bookmarkTags == null
            ? [...this.bookmarkTags]
            : [...bookmarkTags],
        nextUrl: identical(nextUrl, TypeUtil.unset)
            ? this.nextUrl
            : nextUrl as String?,
      );
  @override
  bool operator ==(Object other) => other is IllustBookmarkTagsResponse &&
      TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'IllustBookmarkTagsResponse(${toMap()})';
}

class BookmarkTag {
  final String name;
  final int count;

  const BookmarkTag({this.name = '', this.count = 0});
  factory BookmarkTag.fromMap(Map<String, dynamic> map) => BookmarkTag(
        name: map.optString('name'),
        count: map.optInt('count'),
      );
  factory BookmarkTag.fromJson(Map<String, dynamic> json) =>
      BookmarkTag.fromMap(json);
  Map<String, dynamic> toMap() => {'name': name, 'count': count};
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => TypeUtil.allEmpty([name, count]);
  BookmarkTag copyWith({String? name, int? count}) => BookmarkTag(
        name: name ?? this.name,
        count: count ?? this.count,
      );
  @override
  bool operator ==(Object other) =>
      other is BookmarkTag && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'BookmarkTag(${toMap()})';
}
