// The hint's pointing hand (owner's Lottie, recoloured): its geometry, its
// moves (tile, glide, twin), the turn that keeps it on screen, and the
// overlay that draws it with the blinking glow; reduced motion and a hand
// that fails to load.
import 'dart:io';

import 'package:brain_train/content/level_manifest.dart';
import 'package:brain_train/data/progress_repository.dart';
import 'package:brain_train/data/settings_repository.dart';
import 'package:brain_train/features/gameplay/game_controller.dart';
import 'package:brain_train/features/gameplay/widgets/hint_glow.dart';
import 'package:brain_train/features/gameplay/widgets/hint_hand.dart';
import 'package:brain_train/game_engine/state/game_actions.dart';
import 'package:brain_train/rendering/tile_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie/lottie.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers.dart';
import '../helpers/fake_stopwatch.dart';

Duration ms(int value) => Duration(milliseconds: value);

void main() {
  const screen = Rect.fromLTWH(0, 0, 360, 640);
  const tile = Rect.fromLTWH(150, 300, 40, 52);
  const twin = Rect.fromLTWH(230, 360, 40, 52);

  group('the asset', () {
    final bytes = File('assets/lottie/hint_hand.json').readAsBytesSync();
    final text = String.fromCharCodes(bytes);

    test('is the owner\'s hand, recoloured gold with a dark-green outline, still minified', () {
      final composition = LottieComposition.parseJsonBytes(bytes);
      expect((composition.bounds.width, composition.bounds.height), (512, 512));
      expect(composition.duration, HintHand.tap);
      expect(text, isNot(contains('\n')));
      // Fill #F2C96B (3 shapes), outline #183D2D (8 strokes); none of the
      // light greens that vanish on the felt.
      expect('"k":[0.949,0.7882,0.4196,1]'.allMatches(text), hasLength(3));
      expect('"k":[0.0941,0.2392,0.1765,1]'.allMatches(text), hasLength(8));
      expect(text, isNot(contains('0.6832,0.9968,0.7041')));
      expect(text, isNot(contains('0.0078,0.5882,0.0431')));
    });
  });

  group('geometry', () {
    test('the fingertip goes on the face, a little towards the hand from its centre', () {
      final tip = HintHand.tipOn(tile, const Offset(1, 1));
      expect(tile.contains(tip), isTrue);
      expect(tip.dx, lessThan(tile.center.dx));
      expect(tip.dy, lessThan(tile.center.dy));
      expect((tip - tile.center).distance, closeTo(HintHand.tipInset * tile.width, 0.01));
      final mirrored = HintHand.tipOn(tile, const Offset(-1, -1));
      expect(mirrored.dx, greaterThan(tile.center.dx));
      expect(mirrored.dy, greaterThan(tile.center.dy));
    });

    test('the hand is about 1.3 face widths wide and reaches up and left of the fingertip', () {
      final scale = HintHand.scaleFor(tile.width);
      expect(HintHand.handWidth * scale, closeTo(1.3 * tile.width, 0.01));
      final reach = HintHand.reachAt(const Offset(100, 100), scale, const Offset(1, 1));
      expect(reach.right, closeTo(100 + 17 * scale, 0.01), reason: 'only the pad of the finger passes the point');
      expect(reach.left, lessThan(100 - 250 * scale));
      expect(reach.top, lessThan(100 - 250 * scale));
    });

    test('above and left of the tiles when it fits; mirrored near the left and top edges', () {
      expect(HintHand.flipsFor([tile, twin], screen), [const Offset(1, 1), const Offset(1, 1)]);
      const left = Rect.fromLTWH(4, 300, 40, 52);
      expect(HintHand.flipsFor([left], screen), [const Offset(-1, 1)]);
      const top = Rect.fromLTWH(150, 6, 40, 52);
      expect(HintHand.flipsFor([top], screen), [const Offset(1, -1)]);
      const corner = Rect.fromLTWH(4, 6, 40, 52);
      expect(HintHand.flipsFor([corner], screen), [const Offset(-1, -1)]);
      // One turn for both when one fits both.
      expect(HintHand.flipsFor([left, twin], screen), [const Offset(-1, 1), const Offset(-1, 1)]);
      for (final face in [tile, left, top, corner]) {
        final flip = HintHand.flipsFor([face], screen).single;
        final box = HintHand.reachAt(HintHand.tipOn(face, flip), HintHand.scaleFor(face.width), flip);
        expect(screen.contains(box.topLeft) && screen.contains(box.bottomRight), isTrue, reason: '$face');
      }
    });
  });

  group('moves', () {
    final both = HintHandMotion.forFaces(tile: tile, twin: twin, bounds: screen, total: HintGlowOverlay.duration);
    final alone = HintHandMotion.forFaces(tile: tile, bounds: screen, total: HintGlowOverlay.duration);
    final size = HintHand.scaleFor(tile.width);

    test('taps the tile twice, glides to the twin, taps it, glides back', () {
      expect(HintHandMotion.round, ms(2800));
      final pressed = both.at(ms(350));
      expect(pressed.tip, both.first);
      expect(tile.contains(pressed.tip), isTrue);
      expect(pressed.progress, closeTo(HintHand.pressedProgress, 0.01));
      expect(pressed.scale, size);
      expect(both.at(ms(1050)).tip, both.first, reason: 'the second tap');
      final gliding = both.at(ms(1575));
      expect(gliding.progress, 0, reason: 'resting pose while it moves');
      expect(gliding.tip.dx, inExclusiveRange(both.first.dx, both.second!.dx));
      final onTwin = both.at(ms(2100));
      expect(onTwin.tip, both.second);
      expect(twin.contains(onTwin.tip), isTrue);
      expect(onTwin.progress, closeTo(HintHand.pressedProgress, 0.01));
      expect(both.at(ms(2625)).tip.dx, inExclusiveRange(both.first.dx, both.second!.dx), reason: 'gliding back');
      expect(both.at(ms(2800 + 350)).tip, both.first, reason: 'the next round');
    });

    test('with no twin on the board, it keeps tapping the tile', () {
      for (final t in [350, 1575, 2100, 3000]) {
        expect(alone.at(ms(t)).tip, alone.first);
      }
      expect(alone.at(ms(2450)).progress, closeTo(HintHand.pressedProgress, 0.01), reason: 'its fourth tap');
    });

    test('pops in, then shrinks away at the end', () {
      expect(both.at(Duration.zero).scale, 0);
      expect(both.at(ms(90)).scale, inExclusiveRange(0, size * 1.2));
      expect(both.at(ms(4300)).scale, inExclusiveRange(0, size));
      expect(both.at(HintGlowOverlay.duration).scale, 0);
    });

    test('with reduced motion it rests pressed on the tile', () {
      final still = both.still;
      expect(still.tip, both.first);
      expect(still.progress, HintHand.pressedProgress);
      expect(still.scale, size);
    });
  });

  group('overlay', () {
    // a1/a2 (a safe pair), b1/b2: all free.
    final board = level([('a1', 'A', 0, 0, 0), ('b1', 'B', 4, 0, 0), ('a2', 'A', 8, 0, 0), ('b2', 'B', 12, 0, 0)]);
    const entry = LevelManifestEntry(levelId: 'test-level', order: 1, title: 'Test', ref: ContentRef(url: 'l.json'));
    // Faces on the screen; the overlay sits 20 px in and 30 px down.
    const inset = Offset(20, 30);
    final faces = {
      'a1': const Rect.fromLTWH(140, 330, 40, 52),
      'b1': const Rect.fromLTWH(185, 330, 40, 52),
      'a2': const Rect.fromLTWH(230, 390, 40, 52),
      'b2': const Rect.fromLTWH(275, 390, 40, 52),
    };

    late GameController game;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      game = GameController(
        entry: entry,
        level: board,
        registry: registry(['A', 'B']),
        progress: await ProgressRepository.open(),
        settings: await SettingsRepository.open(),
        stopwatch: FakeStopwatch(),
      );
    });

    tearDown(() => game.dispose());

    Future<HintGlowOverlayState> pump(WidgetTester tester, {bool reduceMotion = false, String? asset}) async {
      tester.view
        ..physicalSize = const Size(360, 640)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(size: Size(360, 640)),
          child: Padding(
            padding: EdgeInsets.only(left: inset.dx, top: inset.dy),
            child: HintGlowOverlay(
              controller: game,
              tileRect: (id) => faces[id],
              trayRect: (id) => game.state.tray.contains(id) ? const Rect.fromLTWH(100, 100, 30, 39) : null,
              style: const TileStyle(),
              reduceMotion: reduceMotion,
              handAsset: asset ?? HintHand.asset,
            ),
          ),
        ),
      );
      await tester.pump();
      return tester.state<HintGlowOverlayState>(find.byType(HintGlowOverlay));
    }

    /// Uses a hint and pumps until the overlay's ticker has its first tick
    /// (elapsed 0).
    Future<Hint> showHint(WidgetTester tester) async {
      final hint = game.useHint()!;
      await tester.pump();
      await tester.pump();
      return hint;
    }

    RenderBox paintBox(WidgetTester tester) => tester.renderObject<RenderBox>(
      find.descendant(of: find.byType(HintGlowOverlay), matching: find.byType(CustomPaint)),
    );

    testWidgets('the hand taps the tile, then its twin, while both blink; the next tap clears it', (tester) async {
      final overlay = await pump(tester);
      expect(overlay.hasHand, isTrue);
      expect(paintBox(tester), paintsNothing);
      final hint = await showHint(tester);
      expect((hint.tileId, hint.partnerTileId), ('a1', 'a2'));
      expect(overlay.animating, isTrue);
      expect(overlay.litFaces, [faces['a1']!.shift(-inset), faces['a2']!.shift(-inset)]);

      await tester.pump(ms(350));
      final onTile = overlay.handPose!;
      expect(faces['a1']!.shift(-inset).contains(onTile.tip), isTrue, reason: 'the fingertip on the tile');
      expect(onTile.progress, closeTo(HintHand.pressedProgress, 0.02));
      expect(onTile.flip, const Offset(1, 1));
      // The hand is drawn (Lottie paths) over the glow.
      expect(paintBox(tester), paints..rrect()..path());
      final bright = overlay.strength;

      await tester.pump(ms(200));
      expect(overlay.strength, lessThan(bright - 0.5), reason: 'a blink: 2.5 a second');
      await tester.pump(ms(200));
      expect(overlay.strength, closeTo(bright, 0.05));

      await tester.pump(ms(2100 - 750));
      expect(faces['a2']!.shift(-inset).contains(overlay.handPose!.tip), isTrue, reason: 'then on its twin');

      game.tapTile('b1');
      await tester.pump();
      expect(overlay.hint, isNull, reason: 'the next tap clears it');
      expect(overlay.handPose, isNull);
      expect(overlay.animating, isFalse);
      expect(paintBox(tester), paintsNothing);
    });

    testWidgets('a twin in the tray blinks there; the hand stays on the tile', (tester) async {
      final overlay = await pump(tester);
      game.tapTile('a1');
      await tester.pump();
      final hint = await showHint(tester);
      expect((hint.tileId, hint.partnerTileId, hint.reason), ('a2', 'a1', HintReason.completesPair));
      expect(overlay.litFaces.last, const Rect.fromLTWH(100, 100, 30, 39).shift(-inset));
      var at = 0;
      for (final t in [350, 1575, 2100, 3200]) {
        await tester.pump(ms(t - at));
        at = t;
        expect(faces['a2']!.shift(-inset).contains(overlay.handPose!.tip), isTrue, reason: '$t ms');
      }
      await tester.pump(HintGlowOverlay.duration);
      expect(overlay.hint, isNull, reason: 'gone after 4.5 s');
    });

    testWidgets('reduced motion: the hand rests pressed on the tile, the glow is still', (tester) async {
      final overlay = await pump(tester, reduceMotion: true);
      await showHint(tester);
      expect(overlay.animating, isFalse);
      final pose = overlay.handPose!;
      expect(pose.progress, HintHand.pressedProgress);
      expect(faces['a1']!.shift(-inset).contains(pose.tip), isTrue);
      expect(overlay.strength, 1);
      expect(paintBox(tester), paints..rrect()..path());
      await tester.pump(ms(1000));
      expect(overlay.handPose!.tip, pose.tip);
      expect(overlay.strength, 1);
      await tester.pump(HintGlowOverlay.duration);
      expect(overlay.hint, isNull);
    });

    testWidgets('without the hand (its file fails to load) the glow alone breathes as before', (tester) async {
      final overlay = await pump(tester, asset: 'assets/lottie/missing.json');
      await showHint(tester);
      await tester.pump(ms(350));
      expect(overlay.hasHand, isFalse);
      expect(overlay.hint, isNotNull);
      expect(overlay.handPose, isNull);
      expect(overlay.strength, greaterThan(0.6));
      expect(paintBox(tester), paints..rrect());
      expect(paintBox(tester), isNot(paints..path()));
      await tester.pump(HintGlowOverlay.duration);
      expect(overlay.hint, isNull);
    });
  });
}
