import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie/lottie.dart';

import 'package:brain_train/features/gameplay/widgets/premium_chrome.dart';
import 'package:brain_train/features/gameplay/widgets/win_trophy.dart';

Widget _host({bool reduceMotion = false, String? assetName}) => MaterialApp(
  home: Scaffold(
    body: MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: Center(child: WinTrophy(assetName: assetName ?? WinTrophy.asset)),
    ),
  ),
);

Future<void> _load(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
  }
}

double _value(WidgetTester tester) => tester.widget<Lottie>(find.byType(Lottie)).controller!.value;

void main() {
  testWidgets('shows a 210x140 Lottie', (tester) async {
    await tester.pumpWidget(_host());
    await _load(tester);
    expect(find.byType(Lottie), findsOneWidget);
    expect(tester.getSize(find.byType(WinTrophy)), const Size(210, 140));
  });

  testWidgets('loops while shown and stops when removed', (tester) async {
    await tester.pumpWidget(_host());
    await _load(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(_value(tester), inExclusiveRange(0, 1));
    await tester.pump(const Duration(milliseconds: 4100));
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pump(const Duration(seconds: 1));
    expect(_value(tester), inExclusiveRange(0, 1));
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('reduce motion shows the last frame at once', (tester) async {
    await tester.pumpWidget(_host(reduceMotion: true));
    await _load(tester);
    expect(_value(tester), 1);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('a missing asset falls back to the emblem', (tester) async {
    await tester.pumpWidget(_host(assetName: 'assets/lottie/nope.json'));
    await _load(tester);
    expect(find.byType(PremiumEmblem), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('is decorative: excluded from semantics', (tester) async {
    await tester.pumpWidget(_host());
    await _load(tester);
    expect(find.descendant(of: find.byType(WinTrophy), matching: find.byType(ExcludeSemantics)), findsOneWidget);
  });
}
