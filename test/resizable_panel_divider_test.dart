import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixez/component/resizable_panel_divider.dart';

void main() {
  testWidgets('拖拽宽度会受限并吸附到最近预设值', (tester) async {
    final changedWidths = <double>[];
    final resizingStates = <bool>[];
    double? committedWidth;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 28,
            height: 400,
            child: ResizablePanelDivider(
              panelWidth: 350,
              minPanelWidth: 320,
              maxPanelWidth: 450,
              snapPoints: const [400],
              onWidthChanged: changedWidths.add,
              onWidthCommitted: (width) => committedWidth = width,
              onResizingChanged: resizingStates.add,
            ),
          ),
        ),
      ),
    );

    await tester.dragFrom(
      tester.getCenter(find.byType(ResizablePanelDivider)),
      const Offset(-46, 0),
    );

    expect(changedWidths, contains(396));
    expect(changedWidths.last, 400);
    expect(committedWidth, 400);
    expect(resizingStates, [true, false]);
  });
}
