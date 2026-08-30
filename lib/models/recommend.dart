import 'package:pixez/custom/map_extension.dart';
import 'package:pixez/custom/type_util.dart';
import 'package:pixez/models/illust.dart';

class Recommend {
  final List<Illusts> illusts;
  final List<Illusts>? rankingIllusts;
  final bool? contestExists;
  final PrivacyPolicy? privacyPolicy;
  final String? nextUrl;

  const Recommend({
    this.illusts = const [],
    this.rankingIllusts,
    this.contestExists,
    this.privacyPolicy,
    this.nextUrl,
  });

  factory Recommend.fromMap(Map<String, dynamic> map) => Recommend(
        illusts: [
          ...map.optList('illusts', (e) => Illusts.fromMap(TypeUtil.parseMap(e))),
        ],
        rankingIllusts: map['ranking_illusts'] == null
            ? null
            : [
                ...map.optList(
                  'ranking_illusts',
                  (e) => Illusts.fromMap(TypeUtil.parseMap(e)),
                ),
              ],
        contestExists: map.optBoolOrNull('contest_exists'),
        privacyPolicy: map.optMapOrNull('privacy_policy') == null
            ? null
            : PrivacyPolicy.fromMap(map.optMap('privacy_policy')),
        nextUrl: map.optStringOrNull('next_url'),
      );
  factory Recommend.fromJson(Map<String, dynamic> json) => Recommend.fromMap(json);
  Map<String, dynamic> toMap() => {
        'illusts': illusts.map((e) => e.toMap()).toList(),
        'ranking_illusts': rankingIllusts?.map((e) => e.toMap()).toList(),
        'contest_exists': contestExists,
        'privacy_policy': privacyPolicy?.toMap(),
        'next_url': nextUrl,
      };
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => illusts.isEmpty &&
      (rankingIllusts == null || rankingIllusts!.isEmpty) &&
      contestExists == null &&
      (privacyPolicy == null || privacyPolicy!.isEmpty) &&
      nextUrl == null;
  Recommend copyWith({
    List<Illusts>? illusts,
    Object? rankingIllusts = TypeUtil.unset,
    Object? contestExists = TypeUtil.unset,
    Object? privacyPolicy = TypeUtil.unset,
    Object? nextUrl = TypeUtil.unset,
  }) =>
      Recommend(
        illusts: illusts == null ? [...this.illusts] : [...illusts],
        rankingIllusts: identical(rankingIllusts, TypeUtil.unset)
            ? (this.rankingIllusts == null ? null : [...this.rankingIllusts!])
            : rankingIllusts == null
                ? null
                : [...rankingIllusts as List<Illusts>],
        contestExists: identical(contestExists, TypeUtil.unset)
            ? this.contestExists
            : contestExists as bool?,
        privacyPolicy: identical(privacyPolicy, TypeUtil.unset)
            ? this.privacyPolicy
            : privacyPolicy as PrivacyPolicy?,
        nextUrl: identical(nextUrl, TypeUtil.unset) ? this.nextUrl : nextUrl as String?,
      );
  @override
  bool operator ==(Object other) => other is Recommend && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'Recommend(${toMap()})';
}

class PrivacyPolicy {
  const PrivacyPolicy();
  factory PrivacyPolicy.fromMap(Map<String, dynamic> map) => const PrivacyPolicy();
  factory PrivacyPolicy.fromJson(Map<String, dynamic> json) => const PrivacyPolicy();
  Map<String, dynamic> toMap() => {};
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => true;
  PrivacyPolicy copyWith() => const PrivacyPolicy();
  @override
  bool operator ==(Object other) => other is PrivacyPolicy;
  @override
  int get hashCode => runtimeType.hashCode;
  @override
  String toString() => 'PrivacyPolicy({})';
}
