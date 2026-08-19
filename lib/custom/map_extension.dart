import 'dart:convert';

import 'type_util.dart';

/// 为手写 Model 提供安全的 Map 读取方法。
extension ModelMapExtension on Map<String, dynamic> {
  int optInt(String key, [int defaultValue = 0]) {
    return TypeUtil.parseInt(this[key], defaultValue);
  }

  int? optIntOrNull(String key) {
    return TypeUtil.parseNullableInt(this[key]);
  }

  double optDouble(String key, [double defaultValue = 0.0]) {
    return TypeUtil.parseDouble(this[key], defaultValue);
  }

  double? optDoubleOrNull(String key) {
    return TypeUtil.parseNullableDouble(this[key]);
  }

  bool optBool(String key, [bool defaultValue = false]) {
    return TypeUtil.parseBool(this[key], defaultValue);
  }

  bool? optBoolOrNull(String key) {
    return TypeUtil.parseNullableBool(this[key]);
  }

  String optString(String key, [String defaultValue = '']) {
    return TypeUtil.parseString(this[key], defaultValue);
  }

  String? optStringOrNull(String key) {
    return TypeUtil.parseNullableString(this[key]);
  }

  List<T> optList<T>(String key, T Function(dynamic e) f) {
    return TypeUtil.parseList(this[key], f);
  }

  List<dynamic> optDynamicList(String key) {
    return TypeUtil.parseDynamicList(this[key]);
  }

  List<int> optIntList(String key) {
    return TypeUtil.parseIntList(this[key]);
  }

  List<String> optStringList(String key) {
    return TypeUtil.parseStringList(this[key]);
  }

  List<Map<String, dynamic>> optMapList(String key) {
    return TypeUtil.parseMapList(this[key]);
  }

  Map<String, dynamic> optMap(String key) {
    return TypeUtil.parseMap(this[key]);
  }

  Map<String, dynamic>? optMapOrNull(String key) {
    return TypeUtil.parseNullableMap(this[key]);
  }

  String toJsonString([bool pretty = false]) {
    if (pretty) {
      return const JsonEncoder.withIndent(
        '  ',
        _toEncodableFallback,
      ).convert(this);
    }
    return const JsonEncoder(_toEncodableFallback).convert(this);
  }

  Map<String, dynamic> shrink({bool copy = false}) {
    return TypeUtil.shrinkMap(this, copy: copy);
  }
}

Object? _toEncodableFallback(dynamic object) {
  return object.toString();
}
