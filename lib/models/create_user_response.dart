import 'dart:convert';

import 'package:pixez/custom/map_extension.dart';
import 'package:pixez/custom/type_util.dart';

CreateUserResponse createUserResponseFromJson(String str) =>
    CreateUserResponse.fromJson(TypeUtil.parseMap(json.decode(str)));

String createUserResponseToJson(CreateUserResponse data) =>
    json.encode(data.toJson());

class CreateUserResponse {
  final bool error;
  final String message;
  final Body body;

  const CreateUserResponse({
    this.error = false,
    this.message = '',
    this.body = const Body(),
  });

  factory CreateUserResponse.fromMap(Map<String, dynamic> map) =>
      CreateUserResponse(
        error: map.optBool('error'),
        message: map.optString('message'),
        body: Body.fromMap(map.optMap('body')),
      );
  factory CreateUserResponse.fromJson(Map<String, dynamic> json) =>
      CreateUserResponse.fromMap(json);
  Map<String, dynamic> toMap() => {
        'error': error,
        'message': message,
        'body': body.toMap(),
      };
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => !error && message.isEmpty && body.isEmpty;
  CreateUserResponse copyWith({bool? error, String? message, Body? body}) =>
      CreateUserResponse(
        error: error ?? this.error,
        message: message ?? this.message,
        body: body ?? this.body,
      );
  @override
  bool operator ==(Object other) => other is CreateUserResponse &&
      TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'CreateUserResponse(${toMap()})';
}

class Body {
  final String userAccount;
  final String password;
  final String deviceToken;

  const Body({this.userAccount = '', this.password = '', this.deviceToken = ''});

  factory Body.fromMap(Map<String, dynamic> map) => Body(
        userAccount: map.optString('user_account'),
        password: map.optString('password'),
        deviceToken: map.optString('device_token'),
      );
  factory Body.fromJson(Map<String, dynamic> json) => Body.fromMap(json);
  Map<String, dynamic> toMap() => {
        'user_account': userAccount,
        'password': password,
        'device_token': deviceToken,
      };
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => TypeUtil.allEmpty([userAccount, password, deviceToken]);
  Body copyWith({String? userAccount, String? password, String? deviceToken}) =>
      Body(
        userAccount: userAccount ?? this.userAccount,
        password: password ?? this.password,
        deviceToken: deviceToken ?? this.deviceToken,
      );
  @override
  bool operator ==(Object other) =>
      other is Body && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'Body(${toMap()})';
}
