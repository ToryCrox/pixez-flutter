import 'package:pixez/custom/map_extension.dart';
import 'package:pixez/custom/type_util.dart';

class FollowDetail {
  final bool isFollowed;
  final String restrict;

  const FollowDetail({this.isFollowed = false, this.restrict = ''});

  factory FollowDetail.fromMap(Map<String, dynamic> map) => FollowDetail(
        isFollowed: map.optBool('is_followed'),
        restrict: map.optString('restrict'),
      );
  factory FollowDetail.fromJson(Map<String, dynamic> json) =>
      FollowDetail.fromMap(json);
  Map<String, dynamic> toMap() => {
        'is_followed': isFollowed,
        'restrict': restrict,
      };
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => TypeUtil.allEmpty([isFollowed, restrict]);
  FollowDetail copyWith({bool? isFollowed, String? restrict}) => FollowDetail(
        isFollowed: isFollowed ?? this.isFollowed,
        restrict: restrict ?? this.restrict,
      );
  @override
  bool operator ==(Object other) =>
      other is FollowDetail && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'FollowDetail(${toMap()})';
}
