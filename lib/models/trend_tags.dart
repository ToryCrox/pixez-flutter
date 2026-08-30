import 'package:pixez/custom/map_extension.dart';
import 'package:pixez/custom/type_util.dart';
import 'package:pixez/models/illust.dart';

class TrendingTag {
  final List<TrendTags> trendTags;

  const TrendingTag({this.trendTags = const []});
  factory TrendingTag.fromMap(Map<String, dynamic> map) => TrendingTag(
        trendTags: [
          ...map.optList(
            'trend_tags',
            (e) => TrendTags.fromMap(TypeUtil.parseMap(e)),
          ),
        ],
      );
  factory TrendingTag.fromJson(Map<String, dynamic> json) => TrendingTag.fromMap(json);
  Map<String, dynamic> toMap() => {'trend_tags': trendTags.map((e) => e.toMap()).toList()};
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => trendTags.isEmpty;
  TrendingTag copyWith({List<TrendTags>? trendTags}) => TrendingTag(
        trendTags: trendTags == null ? [...this.trendTags] : [...trendTags],
      );
  @override
  bool operator ==(Object other) => other is TrendingTag && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'TrendingTag(${toMap()})';
}

class TrendTags {
  final String tag;
  final String? translatedName;
  final TrendTagsIllust illust;

  const TrendTags({this.tag = '', this.translatedName, this.illust = const TrendTagsIllust()});
  factory TrendTags.fromMap(Map<String, dynamic> map) => TrendTags(
        tag: map.optString('tag'),
        translatedName: map.optStringOrNull('translated_name'),
        illust: TrendTagsIllust.fromMap(map.optMap('illust')),
      );
  factory TrendTags.fromJson(Map<String, dynamic> json) => TrendTags.fromMap(json);
  Map<String, dynamic> toMap() => {
        'tag': tag,
        'translated_name': translatedName,
        'illust': illust.toMap(),
      };
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => tag.isEmpty && translatedName == null && illust.isEmpty;
  TrendTags copyWith({String? tag, Object? translatedName = TypeUtil.unset, TrendTagsIllust? illust}) => TrendTags(
        tag: tag ?? this.tag,
        translatedName: identical(translatedName, TypeUtil.unset) ? this.translatedName : translatedName as String?,
        illust: illust ?? this.illust,
      );
  @override
  bool operator ==(Object other) => other is TrendTags && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'TrendTags(${toMap()})';
}

class TrendTagsIllust {
  final int id;
  final ImageUrls imageUrls;

  const TrendTagsIllust({this.id = 0, this.imageUrls = const ImageUrls()});
  factory TrendTagsIllust.fromMap(Map<String, dynamic> map) => TrendTagsIllust(
        id: map.optInt('id'),
        imageUrls: ImageUrls.fromMap(map.optMap('image_urls')),
      );
  factory TrendTagsIllust.fromJson(Map<String, dynamic> json) => TrendTagsIllust.fromMap(json);
  Map<String, dynamic> toMap() => {'id': id, 'image_urls': imageUrls.toMap()};
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => id == 0 && imageUrls.isEmpty;
  TrendTagsIllust copyWith({int? id, ImageUrls? imageUrls}) => TrendTagsIllust(
        id: id ?? this.id,
        imageUrls: imageUrls ?? this.imageUrls,
      );
  @override
  bool operator ==(Object other) => other is TrendTagsIllust && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'TrendTagsIllust(${toMap()})';
}
