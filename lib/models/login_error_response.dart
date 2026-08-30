import 'dart:convert';

import 'package:pixez/custom/map_extension.dart';
import 'package:pixez/custom/type_util.dart';

LoginErrorResponse loginErrorResponseFromJson(String str) =>
    LoginErrorResponse.fromJson(TypeUtil.parseMap(json.decode(str)));

String loginErrorResponseToJson(LoginErrorResponse data) =>
    json.encode(data.toJson());

class LoginErrorResponse {
  final bool hasError;
  final Errors errors;

  const LoginErrorResponse({this.hasError = false, this.errors = const Errors()});

  factory LoginErrorResponse.fromMap(Map<String, dynamic> map) =>
      LoginErrorResponse(
        hasError: map.optBool('has_error'),
        errors: Errors.fromMap(map.optMap('errors')),
      );
  factory LoginErrorResponse.fromJson(Map<String, dynamic> json) =>
      LoginErrorResponse.fromMap(json);
  Map<String, dynamic> toMap() => {
        'has_error': hasError,
        'errors': errors.toMap(),
      };
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => !hasError && errors.isEmpty;
  LoginErrorResponse copyWith({bool? hasError, Errors? errors}) =>
      LoginErrorResponse(
        hasError: hasError ?? this.hasError,
        errors: errors ?? this.errors,
      );
  @override
  bool operator ==(Object other) => other is LoginErrorResponse &&
      TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'LoginErrorResponse(${toMap()})';
}

class Errors {
  final System system;

  const Errors({this.system = const System()});
  factory Errors.fromMap(Map<String, dynamic> map) =>
      Errors(system: System.fromMap(map.optMap('system')));
  factory Errors.fromJson(Map<String, dynamic> json) => Errors.fromMap(json);
  Map<String, dynamic> toMap() => {'system': system.toMap()};
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => system.isEmpty;
  Errors copyWith({System? system}) => Errors(system: system ?? this.system);
  @override
  bool operator ==(Object other) =>
      other is Errors && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'Errors(${toMap()})';
}

class System {
  final String message;
  final int code;

  const System({this.message = '', this.code = 0});
  factory System.fromMap(Map<String, dynamic> map) =>
      System(message: map.optString('message'), code: map.optInt('code'));
  factory System.fromJson(Map<String, dynamic> json) => System.fromMap(json);
  Map<String, dynamic> toMap() => {'message': message, 'code': code};
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => TypeUtil.allEmpty([message, code]);
  System copyWith({String? message, int? code}) =>
      System(message: message ?? this.message, code: code ?? this.code);
  @override
  bool operator ==(Object other) =>
      other is System && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'System(${toMap()})';
}
