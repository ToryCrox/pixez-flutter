/*
 * Copyright (C) 2020. by perol_notsf, All rights reserved
 *
 * This program is free software: you can redistribute it and/or modify it under
 * the terms of the GNU General Public License as published by the Free Software
 * Foundation, either version 3 of the License, or (at your option) any later version.
 */
import 'package:path/path.dart';
import 'package:pixez/custom/map_extension.dart';
import 'package:pixez/custom/type_util.dart';
import 'package:pixez/page/database/database_registry.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class Account {
  final AccountResponse response;

  const Account({this.response = const AccountResponse()});

  factory Account.fromMap(Map<String, dynamic> map) => Account(
        response: AccountResponse.fromMap(map.optMap('response')),
      );

  factory Account.fromJson(Map<String, dynamic> json) => Account.fromMap(json);

  Map<String, dynamic> toMap() => {'response': response.toMap()};
  Map<String, dynamic> toJson() => toMap();

  bool get isEmpty => response.isEmpty;

  Account copyWith({AccountResponse? response}) =>
      Account(response: response ?? this.response);

  @override
  bool operator ==(Object other) =>
      other is Account && TypeUtil.equal(response, other.response);

  @override
  int get hashCode => TypeUtil.hash(response);

  @override
  String toString() => 'Account(${toMap()})';
}

final String tableAccount = 'account';
final String columnId = 'id';
final String columnUserId = 'user_id';
final String columnUserImage = 'user_image';
final String columnPassWord = 'password';
final String columnAccessToken = 'access_token';
final String columnDeviceToken = 'device_token';
final String columnRefreshToken = 'refresh_token';
final String columnName = 'name';
final String columnAccount = 'account';
final String columnMailAddress = 'mail_address';
final String columnIsPremium = 'is_premium';
final String columnXRestrict = 'x_restrict';
final String columnIsMailAuthorized = 'is_mail_authorized';

class AccountProvider {
  late Database db;

  Future open() async {
    final databasesPath = await getDatabasesPath();
    final path = join(databasesPath, 'account.db');
    db = await openDatabase(
      path,
      version: 1,
      onCreate: (Database db, int version) async {
        await db.execute('''
create table $tableAccount ( 
  $columnId integer primary key autoincrement, 
  $columnAccessToken text not null,
  $columnRefreshToken text not null,
  $columnDeviceToken text not null,
  $columnUserId text not null,
  $columnUserImage text not null,
  $columnName text not null,
  $columnPassWord text not null,
  $columnAccount text not null,
  $columnMailAddress text not null,
  $columnIsPremium integer not null,
  $columnXRestrict integer not null,
  $columnIsMailAuthorized integer not null
  )
''');
      },
    );
    DatabaseRegistry.instance.register('账号数据库', path, () => db);
  }

  Future<AccountPersist> insert(AccountPersist todo) async {
    final id = await db.insert(
      tableAccount,
      todo.toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return todo.copyWith(id: id);
  }

  Future<AccountPersist?> getAccount(int id) async {
    final maps = await db.query(
      tableAccount,
      columns: [
        columnId,
        columnUserImage,
        columnAccessToken,
        columnRefreshToken,
        columnDeviceToken,
        columnUserId,
        columnName,
        columnPassWord,
        columnAccount,
        columnMailAddress,
        columnIsPremium,
        columnXRestrict,
        columnIsMailAuthorized,
      ],
      where: '$columnId = ?',
      whereArgs: [id],
    );
    return maps.isEmpty ? null : AccountPersist.fromJson(maps.first);
  }

  Future<List<AccountPersist>> getAllAccount() async {
    final maps = await db.query(
      tableAccount,
      columns: [
        columnId,
        columnUserImage,
        columnAccessToken,
        columnRefreshToken,
        columnDeviceToken,
        columnUserId,
        columnName,
        columnAccount,
        columnMailAddress,
        columnPassWord,
        columnIsPremium,
        columnXRestrict,
        columnIsMailAuthorized,
      ],
    );
    return maps.map(AccountPersist.fromJson).toList();
  }

  Future<int> delete(int id) =>
      db.delete(tableAccount, where: '$columnId = ?', whereArgs: [id]);

  Future<int> deleteByUserId(String userId) => db.delete(
        tableAccount,
        where: '$columnUserId = ?',
        whereArgs: [userId],
      );

  Future<int> deleteAll() => db.delete(tableAccount);

  Future<int> update(AccountPersist todo) => db.update(
        tableAccount,
        todo.toJson(),
        where: '$columnId = ?',
        whereArgs: [todo.id],
      );

  Future close() => db.close();
}

class AccountPersist {
  final int? id;
  final String userId;
  final String userImage;
  final String accessToken;
  final String refreshToken;
  final String deviceToken;
  final String name;
  final String account;
  final String mailAddress;
  final String passWord;
  final int isPremium;
  final int xRestrict;
  final int isMailAuthorized;

  const AccountPersist({
    this.id,
    this.userId = '',
    this.userImage = '',
    this.accessToken = '',
    this.refreshToken = '',
    this.deviceToken = '',
    this.passWord = '',
    this.name = '',
    this.account = '',
    this.mailAddress = '',
    this.isPremium = 0,
    this.xRestrict = 0,
    this.isMailAuthorized = 0,
  });

  factory AccountPersist.fromMap(Map<String, dynamic> map) => AccountPersist(
        id: map.optIntOrNull('id'),
        userId: map.optString('user_id'),
        userImage: map.optString('user_image'),
        accessToken: map.optString('access_token'),
        refreshToken: map.optString('refresh_token'),
        deviceToken: map.optString('device_token'),
        passWord: map.optString('password'),
        name: map.optString('name'),
        account: map.optString('account'),
        mailAddress: map.optString('mail_address'),
        isPremium: map.optInt('is_premium'),
        xRestrict: map.optInt('x_restrict'),
        isMailAuthorized: map.optInt('is_mail_authorized'),
      );

  factory AccountPersist.fromJson(Map<String, dynamic> json) =>
      AccountPersist.fromMap(json);

  Map<String, dynamic> toMap() => {
        'id': id,
        'user_id': userId,
        'user_image': userImage,
        'access_token': accessToken,
        'refresh_token': refreshToken,
        'device_token': deviceToken,
        'name': name,
        'account': account,
        'mail_address': mailAddress,
        'password': passWord,
        'is_premium': isPremium,
        'x_restrict': xRestrict,
        'is_mail_authorized': isMailAuthorized,
      };

  Map<String, dynamic> toJson() => toMap();

  bool get isEmpty => TypeUtil.allEmpty([
        id,
        userId,
        userImage,
        accessToken,
        refreshToken,
        deviceToken,
        name,
        account,
        mailAddress,
        passWord,
        isPremium,
        xRestrict,
        isMailAuthorized,
      ]);

  AccountPersist copyWith({
    Object? id = TypeUtil.unset,
    String? userId,
    String? userImage,
    String? accessToken,
    String? refreshToken,
    String? deviceToken,
    String? name,
    String? account,
    String? mailAddress,
    String? passWord,
    int? isPremium,
    int? xRestrict,
    int? isMailAuthorized,
  }) => AccountPersist(
        id: identical(id, TypeUtil.unset) ? this.id : id as int?,
        userId: userId ?? this.userId,
        userImage: userImage ?? this.userImage,
        accessToken: accessToken ?? this.accessToken,
        refreshToken: refreshToken ?? this.refreshToken,
        deviceToken: deviceToken ?? this.deviceToken,
        name: name ?? this.name,
        account: account ?? this.account,
        mailAddress: mailAddress ?? this.mailAddress,
        passWord: passWord ?? this.passWord,
        isPremium: isPremium ?? this.isPremium,
        xRestrict: xRestrict ?? this.xRestrict,
        isMailAuthorized: isMailAuthorized ?? this.isMailAuthorized,
      );

  @override
  bool operator ==(Object other) =>
      other is AccountPersist && TypeUtil.equal(toMap(), other.toMap());

  @override
  int get hashCode => TypeUtil.hash(toMap());

  @override
  String toString() => 'AccountPersist(${toMap()})';
}

extension AccountPersistEx on AccountPersist {
  String hiddenEmail() {
    final splits = mailAddress.split('@');
    if (splits.length < 2) return mailAddress;
    final hidden = List.filled(splits[0].length, '*').join();
    return '$hidden@${splits.sublist(1).join('@')}';
  }
}

class AccountResponse {
  final String accessToken;
  final int expiresIn;
  final String tokenType;
  final String scope;
  final String refreshToken;
  final User user;

  const AccountResponse({
    this.accessToken = '',
    this.expiresIn = 0,
    this.tokenType = '',
    this.scope = '',
    this.refreshToken = '',
    this.user = const User(),
  });

  factory AccountResponse.fromMap(Map<String, dynamic> map) => AccountResponse(
        accessToken: map.optString('access_token'),
        expiresIn: map.optInt('expires_in'),
        tokenType: map.optString('token_type'),
        scope: map.optString('scope'),
        refreshToken: map.optString('refresh_token'),
        user: User.fromMap(map.optMap('user')),
      );

  factory AccountResponse.fromJson(Map<String, dynamic> json) =>
      AccountResponse.fromMap(json);

  Map<String, dynamic> toMap() => {
        'access_token': accessToken,
        'expires_in': expiresIn,
        'token_type': tokenType,
        'scope': scope,
        'refresh_token': refreshToken,
        'user': user.toMap(),
      };

  Map<String, dynamic> toJson() => toMap();

  bool get isEmpty =>
      TypeUtil.isEmpty(accessToken) &&
      TypeUtil.isEmpty(expiresIn) &&
      TypeUtil.isEmpty(tokenType) &&
      TypeUtil.isEmpty(scope) &&
      TypeUtil.isEmpty(refreshToken) &&
      user.isEmpty;

  AccountResponse copyWith({
    String? accessToken,
    int? expiresIn,
    String? tokenType,
    String? scope,
    String? refreshToken,
    User? user,
  }) => AccountResponse(
        accessToken: accessToken ?? this.accessToken,
        expiresIn: expiresIn ?? this.expiresIn,
        tokenType: tokenType ?? this.tokenType,
        scope: scope ?? this.scope,
        refreshToken: refreshToken ?? this.refreshToken,
        user: user ?? this.user,
      );

  @override
  bool operator ==(Object other) =>
      other is AccountResponse && TypeUtil.equal(toMap(), other.toMap());

  @override
  int get hashCode => TypeUtil.hash(toMap());

  @override
  String toString() => 'AccountResponse(${toMap()})';
}

class User {
  final ProfileImageUrls profileImageUrls;
  final String id;
  final String name;
  final String account;
  final String mailAddress;
  final bool isPremium;
  final int xRestrict;
  final bool isMailAuthorized;
  final bool? requirePolicyAgreement;

  const User({
    this.profileImageUrls = const ProfileImageUrls(),
    this.id = '',
    this.name = '',
    this.account = '',
    this.mailAddress = '',
    this.isPremium = false,
    this.xRestrict = 0,
    this.isMailAuthorized = false,
    this.requirePolicyAgreement,
  });

  factory User.fromMap(Map<String, dynamic> map) => User(
        profileImageUrls:
            ProfileImageUrls.fromMap(map.optMap('profile_image_urls')),
        id: map.optString('id'),
        name: map.optString('name'),
        account: map.optString('account'),
        mailAddress: map.optString('mail_address'),
        isPremium: map.optBool('is_premium'),
        xRestrict: map.optInt('x_restrict'),
        isMailAuthorized: map.optBool('is_mail_authorized'),
        requirePolicyAgreement: map.optBoolOrNull('require_policy_agreement'),
      );

  factory User.fromJson(Map<String, dynamic> json) => User.fromMap(json);

  Map<String, dynamic> toMap() => {
        'profile_image_urls': profileImageUrls.toMap(),
        'id': id,
        'name': name,
        'account': account,
        'mail_address': mailAddress,
        'is_premium': isPremium,
        'x_restrict': xRestrict,
        'is_mail_authorized': isMailAuthorized,
        'require_policy_agreement': requirePolicyAgreement,
      };

  Map<String, dynamic> toJson() => toMap();

  bool get isEmpty =>
      profileImageUrls.isEmpty &&
      TypeUtil.isEmpty(id) &&
      TypeUtil.isEmpty(name) &&
      TypeUtil.isEmpty(account) &&
      TypeUtil.isEmpty(mailAddress) &&
      TypeUtil.isEmpty(isPremium) &&
      TypeUtil.isEmpty(xRestrict) &&
      TypeUtil.isEmpty(isMailAuthorized) &&
      TypeUtil.isEmpty(requirePolicyAgreement);

  User copyWith({
    ProfileImageUrls? profileImageUrls,
    String? id,
    String? name,
    String? account,
    String? mailAddress,
    bool? isPremium,
    int? xRestrict,
    bool? isMailAuthorized,
    Object? requirePolicyAgreement = TypeUtil.unset,
  }) => User(
        profileImageUrls: profileImageUrls ?? this.profileImageUrls,
        id: id ?? this.id,
        name: name ?? this.name,
        account: account ?? this.account,
        mailAddress: mailAddress ?? this.mailAddress,
        isPremium: isPremium ?? this.isPremium,
        xRestrict: xRestrict ?? this.xRestrict,
        isMailAuthorized: isMailAuthorized ?? this.isMailAuthorized,
        requirePolicyAgreement: identical(
          requirePolicyAgreement,
          TypeUtil.unset,
        )
            ? this.requirePolicyAgreement
            : requirePolicyAgreement as bool?,
      );

  @override
  bool operator ==(Object other) =>
      other is User && TypeUtil.equal(toMap(), other.toMap());

  @override
  int get hashCode => TypeUtil.hash(toMap());

  @override
  String toString() => 'User(${toMap()})';
}

class ProfileImageUrls {
  final String px16x16;
  final String px50x50;
  final String px170x170;

  const ProfileImageUrls({
    this.px16x16 = '',
    this.px50x50 = '',
    this.px170x170 = '',
  });

  factory ProfileImageUrls.fromMap(Map<String, dynamic> map) =>
      ProfileImageUrls(
        px16x16: map.optString('px_16x16'),
        px50x50: map.optString('px_50x50'),
        px170x170: map.optString('px_170x170'),
      );

  factory ProfileImageUrls.fromJson(Map<String, dynamic> json) =>
      ProfileImageUrls.fromMap(json);

  Map<String, dynamic> toMap() => {
        'px_16x16': px16x16,
        'px_50x50': px50x50,
        'px_170x170': px170x170,
      };

  Map<String, dynamic> toJson() => toMap();

  bool get isEmpty => TypeUtil.allEmpty([px16x16, px50x50, px170x170]);

  ProfileImageUrls copyWith({
    String? px16x16,
    String? px50x50,
    String? px170x170,
  }) => ProfileImageUrls(
        px16x16: px16x16 ?? this.px16x16,
        px50x50: px50x50 ?? this.px50x50,
        px170x170: px170x170 ?? this.px170x170,
      );

  @override
  bool operator ==(Object other) =>
      other is ProfileImageUrls && TypeUtil.equal(toMap(), other.toMap());

  @override
  int get hashCode => TypeUtil.hash(toMap());

  @override
  String toString() => 'ProfileImageUrls(${toMap()})';
}
