import 'dart:convert';

import 'package:pixez/custom/map_extension.dart';
import 'package:pixez/custom/type_util.dart';

AccountEditResponse accountEditResponseFromJson(String str) =>
    AccountEditResponse.fromJson(TypeUtil.parseMap(json.decode(str)));

String accountEditResponseToJson(AccountEditResponse data) =>
    json.encode(data.toJson());

class AccountEditResponse {
  final bool error;
  final String message;
  final Body body;

  const AccountEditResponse({
    this.error = false,
    this.message = '',
    this.body = const Body(),
  });

  factory AccountEditResponse.fromMap(Map<String, dynamic> map) =>
      AccountEditResponse(
        error: map.optBool('error'),
        message: map.optString('message'),
        body: Body.fromMap(map.optMap('body')),
      );

  factory AccountEditResponse.fromJson(Map<String, dynamic> json) =>
      AccountEditResponse.fromMap(json);

  Map<String, dynamic> toMap() => {
        'error': error,
        'message': message,
        'body': body.toMap(),
      };
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => !error && message.isEmpty && body.isEmpty;

  AccountEditResponse copyWith({bool? error, String? message, Body? body}) =>
      AccountEditResponse(
        error: error ?? this.error,
        message: message ?? this.message,
        body: body ?? this.body,
      );

  @override
  bool operator ==(Object other) => other is AccountEditResponse &&
      TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'AccountEditResponse(${toMap()})';
}

class Body {
  final bool isSucceed;
  final ValidationErrors validationErrors;

  const Body({this.isSucceed = false, this.validationErrors = const ValidationErrors()});

  factory Body.fromMap(Map<String, dynamic> map) => Body(
        isSucceed: map.optBool('is_succeed'),
        validationErrors:
            ValidationErrors.fromMap(map.optMap('validation_errors')),
      );

  factory Body.fromJson(Map<String, dynamic> json) => Body.fromMap(json);
  Map<String, dynamic> toMap() => {
        'is_succeed': isSucceed,
        'validation_errors': validationErrors.toMap(),
      };
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => !isSucceed && validationErrors.isEmpty;
  Body copyWith({bool? isSucceed, ValidationErrors? validationErrors}) => Body(
        isSucceed: isSucceed ?? this.isSucceed,
        validationErrors: validationErrors ?? this.validationErrors,
      );
  @override
  bool operator ==(Object other) =>
      other is Body && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'Body(${toMap()})';
}

class ValidationErrors {
  const ValidationErrors();
  factory ValidationErrors.fromMap(Map<String, dynamic> map) =>
      const ValidationErrors();
  factory ValidationErrors.fromJson(Map<String, dynamic> json) =>
      const ValidationErrors();
  Map<String, dynamic> toMap() => {};
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => true;
  ValidationErrors copyWith() => const ValidationErrors();
  @override
  bool operator ==(Object other) => other is ValidationErrors;
  @override
  int get hashCode => runtimeType.hashCode;
  @override
  String toString() => 'ValidationErrors({})';
}
