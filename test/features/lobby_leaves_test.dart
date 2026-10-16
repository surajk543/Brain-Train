import 'package:brain_train/app/theme.dart';
import 'package:brain_train/features/common/flowing_leaves.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'lobby_support.dart';

/// Pumps [child] full-screen and lets the leaf atlas decode.
Future<void> _pump(WidgetTester tester, Widget child, {Phone phone = largePhone}) async {
  tester.view
    ..physicalSize = Size(phone.width * phone.dpr, phone.height * phone.dpr)
    ..devicePixelRatio = phone.dpr;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildBrainTrainTheme(),
      home: Scaffold(body: child),
    ),
  );
  await settleLobby(tester);
}

Finder get _painter => find.descendant(of: find.byType(FlowingLeaves), matching: find.byType(CustomPaint));

void main() {
  for (final phone in [smallPhone, largePhone]) {
    testWidgets('leaves load, drift and paint without errors at ${phone.name}', (tester) async {
      await _pump(tester, const FlowingLeaves(), phone: phone);
      expect(_painter, findsOneWidget, reason: 'atlas decoded, painter in place');
      expect(tester.binding.transientCallbackCount, greaterThan(0), reason: 'drifting');
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('leaves pause when their route is covered (TickerMode off)', (tester) async {
    await _pump(tester, const TickerMode(enabled: false, child: FlowingLeaves()));
    expect(_painter, findsOneWidget);
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('with reduced motion the leaves are a still scatter', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await _pump(tester, const FlowingLeaves());
    expect(_painter, findsOneWidget, reason: 'still painted');
    expect(tester.binding.transientCallbackCount, 0, reason: 'not animating');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('leaves never take taps meant for content below them', (tester) async {
    var taps = 0;
    await _pump(
      tester,
      Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: ElevatedButton(onPressed: () => taps++, child: const Text('Below')),
          ),
          const FlowingLeaves(count: 40),
        ],
      ),
    );
    await tester.tap(find.text('Below'));
    expect(taps, 1);
    await tester.pumpWidget(const SizedBox());
  });
}
