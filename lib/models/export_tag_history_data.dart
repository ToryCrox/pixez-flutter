import 'package:pixez/custom/map_extension.dart';
import 'package:pixez/custom/type_util.dart';
import 'package:pixez/models/tags.dart';

class ExportData {
  final List<TagsPersist>? tagHistory;
  final List<String>? bookTags;

  const ExportData({
    List<TagsPersist>? tagHistory,
    this.bookTags,
    @Deprecated('Use tagHistory instead') List<TagsPersist>? tagHisotry,
  }) : tagHistory = tagHistory ?? tagHisotry;

  /// 兼容旧代码和已有导出文件中的拼写。
  List<TagsPersist>? get tagHisotry => tagHistory;

  factory ExportData.fromMap(Map<String, dynamic> map) => ExportData(
        tagHistory: [
          ...map.optList(
            'tagHisotry',
            (e) => TagsPersist.fromMap(TypeUtil.parseMap(e)),
          ),
        ],
        bookTags: map['bookTags'] == null
            ? null
            : map.optStringList('bookTags'),
      );
  factory ExportData.fromJson(Map<String, dynamic> json) => ExportData.fromMap(json);

  Map<String, dynamic> toMap() => {
        'tagHisotry': tagHistory?.map((e) => e.toMap()).toList(),
        'bookTags': bookTags == null ? null : [...bookTags!],
      };
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => TypeUtil.allEmpty([tagHistory, bookTags]);

  ExportData copyWith({
    Object? tagHistory = TypeUtil.unset,
    Object? bookTags = TypeUtil.unset,
  }) => ExportData(
        tagHistory: identical(tagHistory, TypeUtil.unset)
            ? (this.tagHistory == null ? null : [...this.tagHistory!])
            : tagHistory == null
                ? null
                : [...tagHistory as List<TagsPersist>],
        bookTags: identical(bookTags, TypeUtil.unset)
            ? (this.bookTags == null ? null : [...this.bookTags!])
            : bookTags == null
                ? null
                : [...bookTags as List<String>],
      );

  @override
  bool operator ==(Object other) =>
      other is ExportData && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'ExportData(${toMap()})';
}
