import 'package:pixez/custom/map_extension.dart';
import 'package:pixez/custom/type_util.dart';
import 'package:pixez/models/illust.dart';

dynamic _cloneWorkspaceValue(dynamic value) {
  if (value is Map) {
    return value.map((key, value) => MapEntry(key, _cloneWorkspaceValue(value)));
  }
  if (value is List) return value.map(_cloneWorkspaceValue).toList();
  return value;
}

class UserDetail {
  final User user;
  final Profile profile;
  final Profile_publicity profilePublicity;
  final Workspace workspace;

  const UserDetail({
    this.user = const User(),
    this.profile = const Profile(),
    this.profilePublicity = const Profile_publicity(),
    this.workspace = const Workspace(),
  });

  factory UserDetail.fromMap(Map<String, dynamic> map) => UserDetail(
        user: User.fromMap(map.optMap('user')),
        profile: Profile.fromMap(map.optMap('profile')),
        profilePublicity: Profile_publicity.fromMap(map.optMap('profile_publicity')),
        workspace: Workspace.fromMap(map.optMap('workspace')),
      );
  factory UserDetail.fromJson(Map<String, dynamic> json) => UserDetail.fromMap(json);
  Map<String, dynamic> toMap() => {
        'user': user.toMap(),
        'profile': profile.toMap(),
        'profile_publicity': profilePublicity.toMap(),
        'workspace': workspace.toMap(),
      };
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => user.isEmpty && profile.isEmpty &&
      profilePublicity.isEmpty && workspace.isEmpty;
  UserDetail copyWith({
    User? user,
    Profile? profile,
    Profile_publicity? profilePublicity,
    Workspace? workspace,
  }) =>
      UserDetail(
        user: user ?? this.user,
        profile: profile ?? this.profile,
        profilePublicity: profilePublicity ?? this.profilePublicity,
        workspace: workspace ?? this.workspace,
      );
  @override
  bool operator ==(Object other) => other is UserDetail && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'UserDetail(${toMap()})';
}

class Profile {
  final String? webpage;
  final String? gender;
  final String? birth;
  final String? birthDay;
  final int? birthYear;
  final String? region;
  final int? addressId;
  final String? countryCode;
  final String? job;
  final int? jobId;
  final int totalFollowUsers;
  final int totalMypixivUsers;
  final int totalIllusts;
  final int totalManga;
  final int totalNovels;
  final int totalIllustBookmarksPublic;
  final int totalIllustSeries;
  final int totalNovelSeries;
  final String? backgroundImageUrl;
  final String? twitterAccount;
  final String? twitterUrl;
  final String? pawooUrl;
  final bool isPremium;
  final bool isUsingCustomProfileImage;

  const Profile({
    this.webpage,
    this.gender,
    this.birth,
    this.birthDay,
    this.birthYear,
    this.region,
    this.addressId,
    this.countryCode,
    this.job,
    this.jobId,
    this.totalFollowUsers = 0,
    this.totalMypixivUsers = 0,
    this.totalIllusts = 0,
    this.totalManga = 0,
    this.totalNovels = 0,
    this.totalIllustBookmarksPublic = 0,
    this.totalIllustSeries = 0,
    this.totalNovelSeries = 0,
    this.backgroundImageUrl,
    this.twitterAccount,
    this.twitterUrl,
    this.pawooUrl,
    this.isPremium = false,
    this.isUsingCustomProfileImage = false,
  });

  factory Profile.fromMap(Map<String, dynamic> map) => Profile(
        webpage: map.optStringOrNull('webpage'),
        gender: map.optStringOrNull('gender'),
        birth: map.optStringOrNull('birth'),
        birthDay: map.optStringOrNull('birth_day'),
        birthYear: map.optIntOrNull('birth_year'),
        region: map.optStringOrNull('region'),
        addressId: map.optIntOrNull('address_id'),
        countryCode: map.optStringOrNull('country_code'),
        job: map.optStringOrNull('job'),
        jobId: map.optIntOrNull('job_id'),
        totalFollowUsers: map.optInt('total_follow_users'),
        totalMypixivUsers: map.optInt('total_mypixiv_users'),
        totalIllusts: map.optInt('total_illusts'),
        totalManga: map.optInt('total_manga'),
        totalNovels: map.optInt('total_novels'),
        totalIllustBookmarksPublic: map.optInt('total_illust_bookmarks_public'),
        totalIllustSeries: map.optInt('total_illust_series'),
        totalNovelSeries: map.optInt('total_novel_series'),
        backgroundImageUrl: map.optStringOrNull('background_image_url'),
        twitterAccount: map.optStringOrNull('twitter_account'),
        twitterUrl: map.optStringOrNull('twitter_url'),
        pawooUrl: map.optStringOrNull('pawoo_url'),
        isPremium: map.optBool('is_premium'),
        isUsingCustomProfileImage: map.optBool('is_using_custom_profile_image'),
      );
  factory Profile.fromJson(Map<String, dynamic> json) => Profile.fromMap(json);
  Map<String, dynamic> toMap() => {
        'webpage': webpage,
        'gender': gender,
        'birth': birth,
        'birth_day': birthDay,
        'birth_year': birthYear,
        'region': region,
        'address_id': addressId,
        'country_code': countryCode,
        'job': job,
        'job_id': jobId,
        'total_follow_users': totalFollowUsers,
        'total_mypixiv_users': totalMypixivUsers,
        'total_illusts': totalIllusts,
        'total_manga': totalManga,
        'total_novels': totalNovels,
        'total_illust_bookmarks_public': totalIllustBookmarksPublic,
        'total_illust_series': totalIllustSeries,
        'total_novel_series': totalNovelSeries,
        'background_image_url': backgroundImageUrl,
        'twitter_account': twitterAccount,
        'twitter_url': twitterUrl,
        'pawoo_url': pawooUrl,
        'is_premium': isPremium,
        'is_using_custom_profile_image': isUsingCustomProfileImage,
      };
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => TypeUtil.allEmpty([
        webpage, gender, birth, birthDay, birthYear, region, addressId,
        countryCode, job, jobId, totalFollowUsers, totalMypixivUsers,
        totalIllusts, totalManga, totalNovels, totalIllustBookmarksPublic,
        totalIllustSeries, totalNovelSeries, backgroundImageUrl, twitterAccount,
        twitterUrl, pawooUrl, isPremium, isUsingCustomProfileImage,
      ]);
  Profile copyWith({
    Object? webpage = TypeUtil.unset,
    Object? gender = TypeUtil.unset,
    Object? birth = TypeUtil.unset,
    Object? birthDay = TypeUtil.unset,
    Object? birthYear = TypeUtil.unset,
    Object? region = TypeUtil.unset,
    Object? addressId = TypeUtil.unset,
    Object? countryCode = TypeUtil.unset,
    Object? job = TypeUtil.unset,
    Object? jobId = TypeUtil.unset,
    int? totalFollowUsers,
    int? totalMypixivUsers,
    int? totalIllusts,
    int? totalManga,
    int? totalNovels,
    int? totalIllustBookmarksPublic,
    int? totalIllustSeries,
    int? totalNovelSeries,
    Object? backgroundImageUrl = TypeUtil.unset,
    Object? twitterAccount = TypeUtil.unset,
    Object? twitterUrl = TypeUtil.unset,
    Object? pawooUrl = TypeUtil.unset,
    bool? isPremium,
    bool? isUsingCustomProfileImage,
  }) =>
      Profile(
        webpage: identical(webpage, TypeUtil.unset) ? this.webpage : webpage as String?,
        gender: identical(gender, TypeUtil.unset) ? this.gender : gender as String?,
        birth: identical(birth, TypeUtil.unset) ? this.birth : birth as String?,
        birthDay: identical(birthDay, TypeUtil.unset) ? this.birthDay : birthDay as String?,
        birthYear: identical(birthYear, TypeUtil.unset) ? this.birthYear : birthYear as int?,
        region: identical(region, TypeUtil.unset) ? this.region : region as String?,
        addressId: identical(addressId, TypeUtil.unset) ? this.addressId : addressId as int?,
        countryCode: identical(countryCode, TypeUtil.unset) ? this.countryCode : countryCode as String?,
        job: identical(job, TypeUtil.unset) ? this.job : job as String?,
        jobId: identical(jobId, TypeUtil.unset) ? this.jobId : jobId as int?,
        totalFollowUsers: totalFollowUsers ?? this.totalFollowUsers,
        totalMypixivUsers: totalMypixivUsers ?? this.totalMypixivUsers,
        totalIllusts: totalIllusts ?? this.totalIllusts,
        totalManga: totalManga ?? this.totalManga,
        totalNovels: totalNovels ?? this.totalNovels,
        totalIllustBookmarksPublic: totalIllustBookmarksPublic ?? this.totalIllustBookmarksPublic,
        totalIllustSeries: totalIllustSeries ?? this.totalIllustSeries,
        totalNovelSeries: totalNovelSeries ?? this.totalNovelSeries,
        backgroundImageUrl: identical(backgroundImageUrl, TypeUtil.unset) ? this.backgroundImageUrl : backgroundImageUrl as String?,
        twitterAccount: identical(twitterAccount, TypeUtil.unset) ? this.twitterAccount : twitterAccount as String?,
        twitterUrl: identical(twitterUrl, TypeUtil.unset) ? this.twitterUrl : twitterUrl as String?,
        pawooUrl: identical(pawooUrl, TypeUtil.unset) ? this.pawooUrl : pawooUrl as String?,
        isPremium: isPremium ?? this.isPremium,
        isUsingCustomProfileImage: isUsingCustomProfileImage ?? this.isUsingCustomProfileImage,
      );
  @override
  bool operator ==(Object other) => other is Profile && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'Profile(${toMap()})';
}

class Profile_publicity {
  final String gender;
  final String region;
  final String birthDay;
  final String birthYear;
  final String job;
  final bool pawoo;

  const Profile_publicity({
    this.gender = '',
    this.region = '',
    this.birthDay = '',
    this.birthYear = '',
    this.job = '',
    this.pawoo = false,
  });

  factory Profile_publicity.fromMap(Map<String, dynamic> map) => Profile_publicity(
        gender: map.optString('gender'),
        region: map.optString('region'),
        birthDay: map.optString('birth_day'),
        birthYear: map.optString('birth_year'),
        job: map.optString('job'),
        pawoo: map.optBool('pawoo'),
      );
  factory Profile_publicity.fromJson(Map<String, dynamic> json) => Profile_publicity.fromMap(json);
  Map<String, dynamic> toMap() => {
        'gender': gender,
        'region': region,
        'birth_day': birthDay,
        'birth_year': birthYear,
        'job': job,
        'pawoo': pawoo,
      };
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => TypeUtil.allEmpty([gender, region, birthDay, birthYear, job, pawoo]);
  Profile_publicity copyWith({String? gender, String? region, String? birthDay, String? birthYear, String? job, bool? pawoo}) =>
      Profile_publicity(
        gender: gender ?? this.gender,
        region: region ?? this.region,
        birthDay: birthDay ?? this.birthDay,
        birthYear: birthYear ?? this.birthYear,
        job: job ?? this.job,
        pawoo: pawoo ?? this.pawoo,
      );
  @override
  bool operator ==(Object other) => other is Profile_publicity && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'Profile_publicity(${toMap()})';
}

class Workspace {
  final String pc;
  final String monitor;
  final String tool;
  final String scanner;
  final String tablet;
  final String mouse;
  final String printer;
  final String desktop;
  final String music;
  final String desk;
  final String chair;
  final String comment;
  final Object? workspaceImageUrl;

  const Workspace({
    this.pc = '',
    this.monitor = '',
    this.tool = '',
    this.scanner = '',
    this.tablet = '',
    this.mouse = '',
    this.printer = '',
    this.desktop = '',
    this.music = '',
    this.desk = '',
    this.chair = '',
    this.comment = '',
    this.workspaceImageUrl,
  });

  factory Workspace.fromMap(Map<String, dynamic> map) => Workspace(
        pc: map.optString('pc'),
        monitor: map.optString('monitor'),
        tool: map.optString('tool'),
        scanner: map.optString('scanner'),
        tablet: map.optString('tablet'),
        mouse: map.optString('mouse'),
        printer: map.optString('printer'),
        desktop: map.optString('desktop'),
        music: map.optString('music'),
        desk: map.optString('desk'),
        chair: map.optString('chair'),
        comment: map.optString('comment'),
        workspaceImageUrl: _cloneWorkspaceValue(map['workspace_image_url']),
      );
  factory Workspace.fromJson(Map<String, dynamic> json) => Workspace.fromMap(json);
  Map<String, dynamic> toMap() => {
        'pc': pc, 'monitor': monitor, 'tool': tool, 'scanner': scanner,
        'tablet': tablet, 'mouse': mouse, 'printer': printer, 'desktop': desktop,
        'music': music, 'desk': desk, 'chair': chair, 'comment': comment,
        'workspace_image_url': _cloneWorkspaceValue(workspaceImageUrl),
      };
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => TypeUtil.allEmpty([
        pc, monitor, tool, scanner, tablet, mouse, printer, desktop, music,
        desk, chair, comment, workspaceImageUrl,
      ]);
  Workspace copyWith({
    String? pc, String? monitor, String? tool, String? scanner, String? tablet,
    String? mouse, String? printer, String? desktop, String? music,
    String? desk, String? chair, String? comment,
    Object? workspaceImageUrl = TypeUtil.unset,
  }) =>
      Workspace(
        pc: pc ?? this.pc, monitor: monitor ?? this.monitor, tool: tool ?? this.tool,
        scanner: scanner ?? this.scanner, tablet: tablet ?? this.tablet,
        mouse: mouse ?? this.mouse, printer: printer ?? this.printer,
        desktop: desktop ?? this.desktop, music: music ?? this.music,
        desk: desk ?? this.desk, chair: chair ?? this.chair, comment: comment ?? this.comment,
        workspaceImageUrl: identical(workspaceImageUrl, TypeUtil.unset)
            ? this.workspaceImageUrl
            : _cloneWorkspaceValue(workspaceImageUrl),
      );
  @override
  bool operator ==(Object other) => other is Workspace && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'Workspace(${toMap()})';
}
