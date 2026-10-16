import 'package:brain_train/app/tablet_scale.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<({MediaQueryData media, RenderBox box})> _pump(WidgetTester tester, Size screen, {double dpr = 2}) async {
  tester.view
    ..physicalSize = screen * dpr
    ..devicePixelRatio = dpr;
  addTearDown(tester.view.reset);
  late MediaQueryData seen;
  final key = GlobalKey();
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => TabletScale(child: child!),
      home: Builder(
        builder: (context) {
          seen = MediaQuery.of(context);
          return Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 100, top: 50),
              child: SizedBox(key: key, width: 10, height: 10),
            ),
          );
        },
      ),
    ),
  );
  return (media: seen, box: key.currentContext!.findRenderObject()! as RenderBox);
}

void main() {
  test('scale: 1 on phones, the shortest side over 600 on tablets, at most 1.75', () {
    expect(TabletScale.scaleFor(const Size(430, 932)), 1);
    expect(TabletScale.scaleFor(const Size(599, 900)), 1);
    expect(TabletScale.scaleFor(const Size(820, 1180)), closeTo(820 / 600, 1e-9));
    expect(TabletScale.scaleFor(const Size(1032, 1376)), 1.72);
    expect(TabletScale.scaleFor(const Size(1366, 2000)), 1.75);
  });

  testWidgets('phones are untouched: same size, ratio and global coordinates', (tester) async {
    final r = await _pump(tester, const Size(411, 914), dpr: 2.625);
    expect(r.media.size, const Size(411, 914));
    expect(r.media.devicePixelRatio, 2.625);
    expect(TabletScale.canvasAbove(r.box), isNull);
    expect(r.box.localToGlobal(Offset.zero), const Offset(100, 50));
  });

  testWidgets('a 13-inch iPad lays out on a 600-wide canvas scaled to fill the screen', (tester) async {
    final r = await _pump(tester, const Size(1032, 1376));
    expect(r.media.size.width, closeTo(600, 1e-9));
    expect(r.media.size.height, closeTo(1376 / 1.72, 1e-9));
    expect(r.media.devicePixelRatio, closeTo(2 * 1.72, 1e-9));
    final canvas = TabletScale.canvasAbove(r.box);
    expect(canvas, isNotNull);
    // Canvas coordinates stay in the app's logical units; the screen sees them scaled.
    expect(r.box.localToGlobal(Offset.zero, ancestor: canvas), const Offset(100, 50));
    final onScreen = r.box.localToGlobal(Offset.zero);
    expect(onScreen.dx, closeTo(172, 1e-6));
    expect(onScreen.dy, closeTo(86, 1e-6));
    // Taps land where the scaled widget is drawn.
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => TabletScale(child: child!),
        home: Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.only(left: 100, top: 50),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => tapped = true,
              child: const SizedBox(width: 40, height: 40),
            ),
          ),
        ),
      ),
    );
    await tester.tapAt(const Offset(172 + 30, 86 + 30));
    expect(tapped, isTrue);
  });
}
