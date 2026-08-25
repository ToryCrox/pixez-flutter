import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// A clickable cursor that follows Flutter's adaptive behavior while keeping
/// the hand cursor for Windows desktop controls.
const WidgetStateMouseCursor appAdaptiveClickable =
    WidgetStateMouseCursor.resolveWith(
      _resolveAppAdaptiveClickable,
      debugDescription: 'WidgetStateMouseCursor(appAdaptiveClickable)',
    );

MouseCursor _resolveAppAdaptiveClickable(Set<WidgetState> states) {
  if (states.contains(WidgetState.disabled)) {
    return SystemMouseCursors.basic;
  }

  return kIsWeb || defaultTargetPlatform == TargetPlatform.windows
      ? SystemMouseCursors.click
      : SystemMouseCursors.basic;
}
