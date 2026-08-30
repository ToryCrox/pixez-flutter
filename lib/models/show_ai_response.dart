import 'package:pixez/custom/map_extension.dart';

class ShowAIResponse {
  final bool showAI;

  const ShowAIResponse({this.showAI = false});

  factory ShowAIResponse.fromMap(Map<String, dynamic> map) =>
      ShowAIResponse(showAI: map.optBool('show_ai'));
  factory ShowAIResponse.fromJson(Map<String, dynamic> json) => ShowAIResponse.fromMap(json);
  Map<String, dynamic> toMap() => {'show_ai': showAI};
  Map<String, dynamic> toJson() => toMap();
  bool get isEmpty => !showAI;
  ShowAIResponse copyWith({bool? showAI}) => ShowAIResponse(showAI: showAI ?? this.showAI);
  @override
  bool operator ==(Object other) => other is ShowAIResponse && showAI == other.showAI;
  @override
  int get hashCode => showAI.hashCode;
  @override
  String toString() => 'ShowAIResponse(${toMap()})';
}
