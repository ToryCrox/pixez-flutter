import 'package:pixez/custom/map_extension.dart';
import 'package:pixez/custom/type_util.dart';

class AmWork {
  final String? title;
  final String? user;
  final String? arworkLink;
  final String? userLink;
  final String? userImage;
  final String? showImage;

  const AmWork({
    this.title,
    this.user,
    this.arworkLink,
    this.userLink,
    this.userImage,
    this.showImage,
  });

  factory AmWork.fromMap(Map<String, dynamic> map) => AmWork(
        title: map.optStringOrNull('title'),
        user: map.optStringOrNull('user'),
        arworkLink: map.optStringOrNull('arworkLink'),
        userLink: map.optStringOrNull('userLink'),
        userImage: map.optStringOrNull('userImage'),
        showImage: map.optStringOrNull('showImage'),
      );
  factory AmWork.fromJson(Map<String, dynamic> json) => AmWork.fromMap(json);
  Map<String, dynamic> toMap() => {
        'title': title,
        'user': user,
        'arworkLink': arworkLink,
        'userLink': userLink,
        'userImage': userImage,
        'showImage': showImage,
      };
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => TypeUtil.allEmpty([title, user, arworkLink, userLink, userImage, showImage]);
  AmWork copyWith({
    Object? title = TypeUtil.unset,
    Object? user = TypeUtil.unset,
    Object? arworkLink = TypeUtil.unset,
    Object? userLink = TypeUtil.unset,
    Object? userImage = TypeUtil.unset,
    Object? showImage = TypeUtil.unset,
  }) => AmWork(
        title: identical(title, TypeUtil.unset) ? this.title : title as String?,
        user: identical(user, TypeUtil.unset) ? this.user : user as String?,
        arworkLink: identical(arworkLink, TypeUtil.unset) ? this.arworkLink : arworkLink as String?,
        userLink: identical(userLink, TypeUtil.unset) ? this.userLink : userLink as String?,
        userImage: identical(userImage, TypeUtil.unset) ? this.userImage : userImage as String?,
        showImage: identical(showImage, TypeUtil.unset) ? this.showImage : showImage as String?,
      );
  @override
  bool operator ==(Object other) => other is AmWork && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'AmWork(${toMap()})';
}
