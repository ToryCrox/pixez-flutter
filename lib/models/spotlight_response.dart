import 'package:pixez/custom/map_extension.dart';
import 'package:pixez/custom/type_util.dart';

class SpotlightResponse {
  final List<SpotlightArticle> spotlightArticles;
  final String? nextUrl;

  const SpotlightResponse({this.spotlightArticles = const [], this.nextUrl});

  factory SpotlightResponse.fromMap(Map<String, dynamic> map) => SpotlightResponse(
        spotlightArticles: [
          ...map.optList(
            'spotlight_articles',
            (e) => SpotlightArticle.fromMap(TypeUtil.parseMap(e)),
          ),
        ],
        nextUrl: map.optStringOrNull('next_url'),
      );
  factory SpotlightResponse.fromJson(Map<String, dynamic> json) => SpotlightResponse.fromMap(json);
  Map<String, dynamic> toMap() => {
        'spotlight_articles': spotlightArticles.map((e) => e.toMap()).toList(),
        'next_url': nextUrl,
      };
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => TypeUtil.allEmpty([spotlightArticles, nextUrl]);
  SpotlightResponse copyWith({List<SpotlightArticle>? spotlightArticles, Object? nextUrl = TypeUtil.unset}) =>
      SpotlightResponse(
        spotlightArticles: spotlightArticles == null
            ? [...this.spotlightArticles]
            : [...spotlightArticles],
        nextUrl: identical(nextUrl, TypeUtil.unset) ? this.nextUrl : nextUrl as String?,
      );
  @override
  bool operator ==(Object other) => other is SpotlightResponse && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'SpotlightResponse(${toMap()})';
}

class SpotlightArticle {
  final int id;
  final String title;
  final String pureTitle;
  final String thumbnail;
  final String articleUrl;
  final DateTime publishDate;

  SpotlightArticle({
    this.id = 0,
    this.title = '',
    this.pureTitle = '',
    this.thumbnail = '',
    this.articleUrl = '',
    DateTime? publishDate,
  }) : publishDate = publishDate ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  factory SpotlightArticle.fromMap(Map<String, dynamic> map) => SpotlightArticle(
        id: map.optInt('id'),
        title: map.optString('title'),
        pureTitle: map.optString('pure_title'),
        thumbnail: map.optString('thumbnail'),
        articleUrl: map.optString('article_url'),
        publishDate: map.optDateTime('publish_date'),
      );
  factory SpotlightArticle.fromJson(Map<String, dynamic> json) => SpotlightArticle.fromMap(json);
  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'pure_title': pureTitle,
        'thumbnail': thumbnail,
        'article_url': articleUrl,
        'publish_date': publishDate.toIso8601String(),
      };
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => TypeUtil.allEmpty([id, title, pureTitle, thumbnail, articleUrl, publishDate]);
  SpotlightArticle copyWith({int? id, String? title, String? pureTitle, String? thumbnail, String? articleUrl, DateTime? publishDate}) =>
      SpotlightArticle(
        id: id ?? this.id,
        title: title ?? this.title,
        pureTitle: pureTitle ?? this.pureTitle,
        thumbnail: thumbnail ?? this.thumbnail,
        articleUrl: articleUrl ?? this.articleUrl,
        publishDate: publishDate ?? this.publishDate,
      );
  @override
  bool operator ==(Object other) => other is SpotlightArticle && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'SpotlightArticle(${toMap()})';
}
