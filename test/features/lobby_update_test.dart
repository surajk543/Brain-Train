import 'dart:convert';

import 'package:brain_train/app/app_services.dart';
import 'package:brain_train/app/app_update_controller.dart';
import 'package:brain_train/content/app_update_config.dart';
import 'package:brain_train/features/home/home_screen.dart';
import 'package:brain_train/features/home/widgets/lobby_update_card.dart';
import 'package:brain_train/features/levels/level_loader.dart';
import 'package:brain_train/features/settings/settings_screen.dart';
import 'package:brain_train/platform/app_updates.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../platform/fake_app_updater.dart';
import 'lobby_support.dart';

const _play = ValueKey('lobby-play');
const _levels = ValueKey('lobby-levels');
const _settings = ValueKey('lobby-settings');
const _update = ValueKey('update-now');
const _later = ValueKey('update-later');

/// The notice the host serves; tests change it between checks.
Map<String, Object?> _served = androidNotice(latest: 4, min: 1);

Future<(AppServices, AppUpdateController, FakeAppUpdater)> _start(WidgetTester tester) async {
  final updater = FakeAppUpdater(build: 4);
  final updates = AppUpdateController(
    updater: updater,
    fetch: () async => AppUpdateFetch.found(AppUpdateConfig.tryParse(_served)!, jsonEncode(_served)),
  );
  addTearDown(updates.dispose);
  late AppServices services;
  await tester.runAsync(() async {
    services = await testServices(updates: updates);
  });
  return (services, updates, updater);
}

Future<void> _pump(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _leave(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

void main() {
  // Real glyphs: realistic text sizes for the layout checks (and captures
  // with CAPTURE_DIR set).
  setUpAll(loadCaptureFonts);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'Brain Train',
      packageName: 'com.sungamestudio.braintrain',
      version: '1.0.0',
      buildNumber: '4',
      buildSignature: '',
    );
  });

  testWidgets('up to date: no card, the lobby works', (tester) async {
    _served = androidNotice(latest: 4, min: 1);
    final (services, _, _) = await _start(tester);
    await pumpLobby(tester, services: services, home: const HomeScreen());
    expect(find.byType(LobbyUpdateCard), findsNothing);
    expect(find.text(LobbyUpdateCard.optionalTitle), findsNothing);
    expect(find.text(LobbyUpdateCard.requiredTitle), findsNothing);
    await tester.tap(find.byKey(_settings));
    await _pump(tester);
    expect(find.byType(SettingsScreen), findsOneWidget);
    await _leave(tester);
  });

  testWidgets('optional: shown once; Later dismisses it for this launch', (tester) async {
    _served = androidNotice(latest: 5, min: 1);
    final (services, updates, updater) = await _start(tester);
    await pumpLobby(tester, services: services, home: const HomeScreen());
    expect(find.text(LobbyUpdateCard.optionalTitle), findsOneWidget);
    expect(find.text(LobbyUpdateCard.optionalBody), findsOneWidget);
    expect(find.byKey(_later), findsOneWidget);

    await tester.tap(find.byKey(_later));
    await _pump(tester);
    expect(find.byType(LobbyUpdateCard), findsNothing);
    expect(updater.launches, isEmpty);

    // Back from the background: checked again, still not shown.
    updates.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await _pump(tester);
    expect(find.byType(LobbyUpdateCard), findsNothing);
    await tester.tap(find.byKey(_settings));
    await _pump(tester);
    expect(find.byType(SettingsScreen), findsOneWidget);
    await _leave(tester);
  });

  testWidgets('optional: Update opens the store and the card goes; back is Later', (tester) async {
    _served = androidNotice(latest: 5, min: 1, message: 'New levels inside.');
    final (services, _, updater) = await _start(tester);
    await pumpLobby(tester, services: services, home: const HomeScreen());
    expect(find.text('New levels inside.'), findsOneWidget);
    await tester.tap(find.byKey(_update));
    await _pump(tester);
    expect(updater.launches, [kTestStoreUrl]);
    expect(find.byType(LobbyUpdateCard), findsNothing);
    await _leave(tester);

    // Another launch: Android back closes the optional card.
    final (services2, _, _) = await _start(tester);
    await pumpLobby(tester, services: services2, home: const HomeScreen());
    expect(find.byType(LobbyUpdateCard), findsOneWidget);
    await tester.binding.handlePopRoute();
    await _pump(tester);
    expect(find.byType(LobbyUpdateCard), findsNothing);
    await _leave(tester);
  });

  testWidgets('required: blocks the lobby; no Later; back and taps do not close it', (tester) async {
    _served = androidNotice(latest: 6, min: 5);
    final (services, updates, updater) = await _start(tester);
    await pumpLobby(tester, services: services, home: const HomeScreen());
    expect(find.text(LobbyUpdateCard.requiredTitle), findsOneWidget);
    expect(find.text(LobbyUpdateCard.requiredBody), findsOneWidget);
    expect(find.byKey(_later), findsNothing);

    // Play, Completed Levels and Settings sit under the scrim: no tap
    // reaches them.
    for (final key in [_play, _levels, _settings]) {
      expect(find.byKey(key), findsOneWidget);
      expect(find.byKey(key).hitTestable(), findsNothing, reason: '$key');
    }
    await tester.tapAt(const Offset(30, 300));
    await _pump(tester);
    expect(find.byType(LevelLoaderScreen), findsNothing);
    expect(find.byType(SettingsScreen), findsNothing);
    expect(find.byType(LobbyUpdateCard), findsOneWidget);

    // Android back.
    expect(await tester.binding.handlePopRoute(), isTrue, reason: 'handled: the app does not close either');
    await _pump(tester);
    expect(find.text(LobbyUpdateCard.requiredTitle), findsOneWidget);

    // Update, then back from the store without updating.
    await tester.tap(find.byKey(_update));
    await _pump(tester);
    expect(updater.launches, [kTestStoreUrl]);
    updates.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await _pump(tester);
    expect(find.text(LobbyUpdateCard.requiredTitle), findsOneWidget);
    await _leave(tester);
  });

  testWidgets('required: nothing opened shows a note', (tester) async {
    _served = androidNotice(latest: 6, min: 5);
    final (services, _, updater) = await _start(tester);
    updater.result = AppUpdateLaunch.failed;
    await pumpLobby(tester, services: services, home: const HomeScreen());
    await tester.tap(find.byKey(_update));
    await _pump(tester);
    expect(find.text(LobbyUpdateCard.failedNote), findsOneWidget);
    expect(find.text(LobbyUpdateCard.requiredTitle), findsOneWidget);
    await _leave(tester);
  });

  testWidgets('never over another screen: it waits for the lobby', (tester) async {
    _served = androidNotice(latest: 4, min: 1);
    final (services, updates, _) = await _start(tester);
    await pumpLobby(tester, services: services, home: const HomeScreen());
    await tester.tap(find.byKey(_settings));
    await _pump(tester);
    expect(find.byType(SettingsScreen), findsOneWidget);

    _served = androidNotice(latest: 6, min: 5);
    await updates.check();
    await _pump(tester);
    expect(find.text(LobbyUpdateCard.requiredTitle), findsNothing);
    expect(find.byType(SettingsScreen), findsOneWidget);

    await tester.binding.handlePopRoute();
    await _pump(tester);
    expect(find.byType(SettingsScreen), findsNothing);
    expect(find.text(LobbyUpdateCard.requiredTitle), findsOneWidget);
    await _leave(tester);
  });

  testWidgets('small phone, large text: the card lays out', (tester) async {
    _served = androidNotice(latest: 6, min: 5);
    final (services, _, _) = await _start(tester);
    await pumpLobby(tester, services: services, home: const HomeScreen(), phone: smallPhone, textScale: 1.3);
    expect(tester.takeException(), isNull);
    expect(find.text(LobbyUpdateCard.requiredTitle), findsOneWidget);
    expect(find.byKey(_update).hitTestable(), findsOneWidget);
    await captureLobby(tester, 'update-required-360x640', smallPhone.dpr);
    await _leave(tester);
  });

  testWidgets('optional card on a large phone', (tester) async {
    _served = androidNotice(latest: 5, min: 1);
    final (services, _, _) = await _start(tester);
    await pumpLobby(tester, services: services, home: const HomeScreen());
    expect(tester.takeException(), isNull);
    await captureLobby(tester, 'update-optional-411x914', largePhone.dpr);
    await _leave(tester);
  });
}
