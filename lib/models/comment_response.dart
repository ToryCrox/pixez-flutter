import 'package:pixez/custom/map_extension.dart';
import 'package:pixez/custom/type_util.dart';

class CommentResponse {
  final int? totalComments;
  final List<Comment> comments;
  final String? nextUrl;

  const CommentResponse({
    this.totalComments,
    this.comments = const [],
    this.nextUrl,
  });

  factory CommentResponse.fromMap(Map<String, dynamic> map) => CommentResponse(
        totalComments: map.optIntOrNull('total_comments'),
        comments: [
          ...map.optList(
            'comments',
            (e) => Comment.fromMap(TypeUtil.parseMap(e)),
          ),
        ],
        nextUrl: map.optStringOrNull('next_url'),
      );
  factory CommentResponse.fromJson(Map<String, dynamic> json) => CommentResponse.fromMap(json);
  Map<String, dynamic> toMap() => {
        'total_comments': totalComments,
        'comments': comments.map((e) => e.toMap()).toList(),
        'next_url': nextUrl,
      };
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => TypeUtil.allEmpty([totalComments, comments, nextUrl]);
  CommentResponse copyWith({
    Object? totalComments = TypeUtil.unset,
    List<Comment>? comments,
    Object? nextUrl = TypeUtil.unset,
  }) =>
      CommentResponse(
        totalComments: identical(totalComments, TypeUtil.unset)
            ? this.totalComments
            : totalComments as int?,
        comments: comments == null ? [...this.comments] : [...comments],
        nextUrl: identical(nextUrl, TypeUtil.unset) ? this.nextUrl : nextUrl as String?,
      );
  @override
  bool operator ==(Object other) => other is CommentResponse && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'CommentResponse(${toMap()})';
}

class Comment {
  final int? id;
  final String? comment;
  final DateTime? date;
  final User? user;
  final Comment? parentComment;
  final bool? hasReplies;
  final Stamp? stamp;

  const Comment({
    this.id,
    this.comment,
    this.date,
    this.user,
    this.parentComment,
    this.hasReplies,
    this.stamp,
  });

  factory Comment.fromMap(Map<String, dynamic> map) => Comment(
        id: map.optIntOrNull('id'),
        comment: map.optStringOrNull('comment'),
        date: map.optDateTimeOrNull('date'),
        user: map.optMapOrNull('user') == null
            ? null
            : User.fromMap(map.optMap('user')),
        parentComment: map.optMapOrNull('parent_comment') == null
            ? null
            : Comment.fromMap(map.optMap('parent_comment')),
        hasReplies: map.optBoolOrNull('has_replies'),
        stamp: map.optMapOrNull('stamp') == null
            ? null
            : Stamp.fromMap(map.optMap('stamp')),
      );
  factory Comment.fromJson(Map<String, dynamic> json) => Comment.fromMap(json);
  Map<String, dynamic> toMap() => {
        'id': id,
        'comment': comment,
        'date': date?.toIso8601String(),
        'user': user?.toMap(),
        'parent_comment': parentComment?.toMap(),
        'has_replies': hasReplies,
        'stamp': stamp?.toMap(),
      };
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty =>
      TypeUtil.isEmpty(id) &&
      TypeUtil.isEmpty(comment) &&
      TypeUtil.isEmpty(date) &&
      (user == null || user!.isEmpty) &&
      (parentComment == null || parentComment!.isEmpty) &&
      TypeUtil.isEmpty(hasReplies) &&
      (stamp == null || stamp!.isEmpty);
  Comment copyWith({
    Object? id = TypeUtil.unset,
    Object? comment = TypeUtil.unset,
    Object? date = TypeUtil.unset,
    Object? user = TypeUtil.unset,
    Object? parentComment = TypeUtil.unset,
    Object? hasReplies = TypeUtil.unset,
    Object? stamp = TypeUtil.unset,
  }) =>
      Comment(
        id: identical(id, TypeUtil.unset) ? this.id : id as int?,
        comment: identical(comment, TypeUtil.unset) ? this.comment : comment as String?,
        date: identical(date, TypeUtil.unset) ? this.date : date as DateTime?,
        user: identical(user, TypeUtil.unset) ? this.user : user as User?,
        parentComment: identical(parentComment, TypeUtil.unset)
            ? this.parentComment
            : parentComment as Comment?,
        hasReplies: identical(hasReplies, TypeUtil.unset)
            ? this.hasReplies
            : hasReplies as bool?,
        stamp: identical(stamp, TypeUtil.unset) ? this.stamp : stamp as Stamp?,
      );
  @override
  bool operator ==(Object other) => other is Comment && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'Comment(${toMap()})';
}

class User {
  final int? id;
  final String name;
  final String account;
  final ProfileImageUrls profileImageUrls;

  const User({
    this.id,
    this.name = '',
    this.account = '',
    this.profileImageUrls = const ProfileImageUrls(),
  });

  factory User.fromMap(Map<String, dynamic> map) => User(
        id: map.optIntOrNull('id'),
        name: map.optString('name'),
        account: map.optString('account'),
        profileImageUrls: ProfileImageUrls.fromMap(map.optMap('profile_image_urls')),
      );
  factory User.fromJson(Map<String, dynamic> json) => User.fromMap(json);
  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'account': account,
        'profile_image_urls': profileImageUrls.toMap(),
      };
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty =>
      TypeUtil.isEmpty(id) &&
      TypeUtil.isEmpty(name) &&
      TypeUtil.isEmpty(account) &&
      profileImageUrls.isEmpty;
  User copyWith({Object? id = TypeUtil.unset, String? name, String? account, ProfileImageUrls? profileImageUrls}) =>
      User(
        id: identical(id, TypeUtil.unset) ? this.id : id as int?,
        name: name ?? this.name,
        account: account ?? this.account,
        profileImageUrls: profileImageUrls ?? this.profileImageUrls,
      );
  @override
  bool operator ==(Object other) => other is User && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'User(${toMap()})';
}

class Stamp {
  final int? stampId;
  final String? stampUrl;

  const Stamp({this.stampId, this.stampUrl});
  int? get stamp_id => stampId;
  String? get stamp_url => stampUrl;
  factory Stamp.fromMap(Map<String, dynamic> map) => Stamp(
        stampId: map.optIntOrNull('stamp_id'),
        stampUrl: map.optStringOrNull('stamp_url'),
      );
  factory Stamp.fromJson(Map<String, dynamic> json) => Stamp.fromMap(json);
  Map<String, dynamic> toMap() => {'stamp_id': stampId, 'stamp_url': stampUrl};
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => TypeUtil.allEmpty([stampId, stampUrl]);
  Stamp copyWith({Object? stampId = TypeUtil.unset, Object? stampUrl = TypeUtil.unset}) =>
      Stamp(
        stampId: identical(stampId, TypeUtil.unset) ? this.stampId : stampId as int?,
        stampUrl: identical(stampUrl, TypeUtil.unset) ? this.stampUrl : stampUrl as String?,
      );
  @override
  bool operator ==(Object other) => other is Stamp && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'Stamp(${toMap()})';
}

class ProfileImageUrls {
  final String medium;
  const ProfileImageUrls({this.medium = ''});
  factory ProfileImageUrls.fromMap(Map<String, dynamic> map) =>
      ProfileImageUrls(medium: map.optString('medium'));
  factory ProfileImageUrls.fromJson(Map<String, dynamic> json) => ProfileImageUrls.fromMap(json);
  Map<String, dynamic> toMap() => {'medium': medium};
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => medium.isEmpty;
  ProfileImageUrls copyWith({String? medium}) => ProfileImageUrls(medium: medium ?? this.medium);
  @override
  bool operator ==(Object other) => other is ProfileImageUrls && medium == other.medium;
  @override
  int get hashCode => medium.hashCode;
  @override
  String toString() => 'ProfileImageUrls(${toMap()})';
}
