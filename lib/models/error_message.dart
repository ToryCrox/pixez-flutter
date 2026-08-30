import 'package:pixez/custom/map_extension.dart';
import 'package:pixez/custom/type_util.dart';

dynamic _cloneErrorValue(dynamic value) {
  if (value is Map) {
    return value.map((key, value) => MapEntry(key, _cloneErrorValue(value)));
  }
  if (value is List) return value.map(_cloneErrorValue).toList();
  return value;
}

class ErrorMessage {
  final Error error;

  const ErrorMessage({this.error = const Error()});

  factory ErrorMessage.fromMap(Map<String, dynamic> map) => ErrorMessage(
        error: Error.fromMap(map.optMap('error')),
      );
  factory ErrorMessage.fromJson(Map<String, dynamic> json) =>
      ErrorMessage.fromMap(json);
  Map<String, dynamic> toMap() => {'error': error.toMap()};
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => error.isEmpty;
  ErrorMessage copyWith({Error? error}) =>
      ErrorMessage(error: error ?? this.error);
  @override
  bool operator ==(Object other) => other is ErrorMessage &&
      TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'ErrorMessage(${toMap()})';
}

class Error {
  final String? userMessage;
  final String? message;
  final String? reason;
  final Object? userMessageDetails;

  const Error({
    this.userMessage,
    this.message,
    this.reason,
    this.userMessageDetails,
  });

  factory Error.fromMap(Map<String, dynamic> map) => Error(
        userMessage: map.optStringOrNull('user_message'),
        message: map.optStringOrNull('message'),
        reason: map.optStringOrNull('reason'),
        userMessageDetails: _cloneErrorValue(map['user_message_details']),
      );
  factory Error.fromJson(Map<String, dynamic> json) => Error.fromMap(json);
  Map<String, dynamic> toMap() => {
        'user_message': userMessage,
        'message': message,
        'reason': reason,
        'user_message_details': _cloneErrorValue(userMessageDetails),
      };
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => TypeUtil.allEmpty([
        userMessage,
        message,
        reason,
        userMessageDetails,
      ]);
  Error copyWith({
    Object? userMessage = TypeUtil.unset,
    Object? message = TypeUtil.unset,
    Object? reason = TypeUtil.unset,
    Object? userMessageDetails = TypeUtil.unset,
  }) => Error(
        userMessage: identical(userMessage, TypeUtil.unset)
            ? this.userMessage
            : userMessage as String?,
        message: identical(message, TypeUtil.unset)
            ? this.message
            : message as String?,
        reason: identical(reason, TypeUtil.unset)
            ? this.reason
            : reason as String?,
        userMessageDetails: identical(userMessageDetails, TypeUtil.unset)
            ? this.userMessageDetails
            : _cloneErrorValue(userMessageDetails),
      );
  @override
  bool operator ==(Object other) =>
      other is Error && TypeUtil.equal(toMap(), other.toMap());
  @override
  int get hashCode => TypeUtil.hash(toMap());
  @override
  String toString() => 'Error(${toMap()})';
}
