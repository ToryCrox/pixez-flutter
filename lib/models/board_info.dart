import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:pixez/constants.dart';
import 'package:pixez/custom/map_extension.dart';
import 'package:pixez/custom/type_util.dart';
import 'package:pixez/custom/log.dart';

class BoardInfo {
  final String title;
  final String content;
  final String startDate;
  final String? endDate;

  const BoardInfo({
    this.title = '',
    this.content = '',
    this.startDate = '',
    this.endDate,
  });

  factory BoardInfo.fromMap(Map<String, dynamic> map) => BoardInfo(
        title: map.optString('title'),
        content: map.optString('content'),
        startDate: map.optString('start_date'),
        endDate: map.optStringOrNull('end_date'),
      );
  factory BoardInfo.fromJson(Map<String, dynamic> json) => BoardInfo.fromMap(json);
  Map<String, dynamic> toMap() => {
        'title': title,
        'content': content,
        'start_date': startDate,
        'end_date': endDate,
      };
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => TypeUtil.allEmpty([title, content, startDate, endDate]);
  BoardInfo copyWith({
    String? title,
    String? content,
    String? startDate,
    Object? endDate = TypeUtil.unset,
  }) =>
      BoardInfo(
        title: title ?? this.title,
        content: content ?? this.content,
        startDate: startDate ?? this.startDate,
        endDate: identical(endDate, TypeUtil.unset) ? this.endDate : endDate as String?,
      );
  @override
  bool operator ==(Object other) => other is BoardInfo && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'BoardInfo(${toMap()})';

  static bool boardDataLoaded = false;
  static List<BoardInfo> boardList = [];

  static String path() {
    if (kDebugMode) return 'android.json';
    if (Platform.isAndroid) return Constants.isGooglePlay ? 'android_play.json' : 'android.json';
    if (Platform.isIOS) return 'ios.json';
    return '';
  }

  static Future<List<BoardInfo>> load() async {
    Log.d('Loading board data from: ${path()}');
    final request = await Dio().get(
      'https://raw.githubusercontent.com/Notsfsssf/pixez-flutter/refs/heads/master/.github/board/${path()}',
    );
    final raw = request.data is String ? jsonDecode(request.data) : request.data;
    final list = TypeUtil.parseList<BoardInfo>(
      raw,
      (e) => BoardInfo.fromMap(TypeUtil.parseMap(e)),
    );
    boardList = list;
    return list;
  }
}
