import 'package:pixez/custom/map_extension.dart';
import 'package:pixez/custom/type_util.dart';

class OnezeroResponse {
  final List<OnezeroAnswer> answer;

  const OnezeroResponse({this.answer = const []});

  factory OnezeroResponse.fromMap(Map<String, dynamic> map) => OnezeroResponse(
        answer: [
          ...map.optList(
            'Answer',
            (e) => OnezeroAnswer.fromMap(TypeUtil.parseMap(e)),
          ),
        ],
      );
  factory OnezeroResponse.fromJson(Map<String, dynamic> json) => OnezeroResponse.fromMap(json);
  Map<String, dynamic> toMap() => {'Answer': answer.map((e) => e.toMap()).toList()};
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => TypeUtil.isEmpty(answer);
  OnezeroResponse copyWith({List<OnezeroAnswer>? answer}) => OnezeroResponse(
        answer: answer == null ? [...this.answer] : [...answer],
      );
  @override
  bool operator ==(Object other) => other is OnezeroResponse && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'OnezeroResponse(${toMap()})';
}

class OnezeroAnswer {
  final String name;
  final int type;
  final String data;
  final int ttl;

  const OnezeroAnswer({this.name = '', this.type = 0, this.data = '', this.ttl = 0});

  factory OnezeroAnswer.fromMap(Map<String, dynamic> map) => OnezeroAnswer(
        name: map.optString('name'),
        type: map.optInt('type'),
        data: map.optString('data'),
        ttl: map.optInt('TTL'),
      );
  factory OnezeroAnswer.fromJson(Map<String, dynamic> json) => OnezeroAnswer.fromMap(json);
  Map<String, dynamic> toMap() => {'name': name, 'type': type, 'data': data, 'TTL': ttl};
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => TypeUtil.allEmpty([name, type, data, ttl]);
  OnezeroAnswer copyWith({String? name, int? type, String? data, int? ttl}) => OnezeroAnswer(
        name: name ?? this.name,
        type: type ?? this.type,
        data: data ?? this.data,
        ttl: ttl ?? this.ttl,
      );
  @override
  bool operator ==(Object other) => other is OnezeroAnswer && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'OnezeroAnswer(${toMap()})';
}
