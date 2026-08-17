import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixez/page/downloaded/local_image_viewer_page.dart';

void main() {
  testWidgets('本地图片查看器支持按钮和方向键切换页面', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LocalImageViewerPage(
          imagePath: 'missing-1.png',
          gallery: const [
            LocalImageViewerItem(imagePath: 'missing-1.png', title: 'P1'),
            LocalImageViewerItem(imagePath: 'missing-2.png', title: 'P2'),
            LocalImageViewerItem(imagePath: 'missing-3.png', title: 'P3'),
          ],
        ),
      ),
    );
    await tester.pump();

    expect(find.text('P1'), findsOneWidget);
    expect(find.byTooltip('上一张（← / ↑）'), findsOneWidget);
    expect(find.byTooltip('下一张（→ / ↓）'), findsOneWidget);

    await tester.tap(find.byTooltip('下一张（→ / ↓）'));
    await tester.pump();
    expect(find.text('P2'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(find.text('P3'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(find.text('P2'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(find.text('P1'), findsOneWidget);
  });
}
