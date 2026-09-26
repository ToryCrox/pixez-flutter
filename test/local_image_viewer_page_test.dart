import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixez/er/prefer.dart';
import 'package:pixez/page/downloaded/local_image_viewer_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const comparisonSplitPreferenceKey = 'local_image_viewer_comparison_split';

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefer.init();
  });

  setUp(() async {
    await (await Prefer.getInstance()).clear();
  });

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
    expect(find.byTooltip('开启左右对比'), findsNothing);
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

  testWidgets('本地图片查看器支持切换图片和左右对比', (tester) async {
    const leftPath = 'missing-left.png';
    const rightPath = 'missing-right.png';

    await tester.pumpWidget(
      MaterialApp(
        home: LocalImageViewerPage(
          imagePath: leftPath,
          comparison: LocalImageViewerComparison(
            leftImagePath: leftPath,
            rightImagePath: rightPath,
            leftTitle: '原图',
            rightTitle: '翻译后',
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byTooltip('切换原图和译图'), findsOneWidget);
    expect(find.byTooltip('开启左右对比'), findsOneWidget);
    expect(find.text('原图'), findsOneWidget);

    await tester.tap(find.byTooltip('切换原图和译图'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('翻译后'), findsOneWidget);

    await tester.tap(find.byTooltip('开启左右对比'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byTooltip('退出左右对比'), findsOneWidget);
  });

  test('大图对比分隔比例支持浮点偏好读写', () async {
    expect(Prefer.getDouble(comparisonSplitPreferenceKey), isNull);

    await Prefer.setDouble(comparisonSplitPreferenceKey, 0.6);

    expect(
      Prefer.getDouble(comparisonSplitPreferenceKey),
      closeTo(0.6, 0.0001),
    );
    await (await Prefer.getInstance()).reload();
    expect(
      Prefer.getDouble(comparisonSplitPreferenceKey),
      closeTo(0.6, 0.0001),
    );
  });
}
