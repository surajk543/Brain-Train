# Play Games Sign-in (piece 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Android players are signed in to Google Play Games silently, and two lobby icons open Google's Achievements and Leaderboards screens; without Play Games nothing changes.

**Architecture:** A small `PlayGames` interface (`lib/platform/play_games.dart`) with two implementations: `UnavailablePlayGames` (iOS, tests, builds without an app ID) and `GamesServicesPlayGames` (the only file importing the `games_services` plugin, every call guarded). A `PlayGamesController` (ChangeNotifier, in `lib/app/`) owned by `AppServices` drives the lobby icons and a short footer notice. Gradle turns Play Games on only when an app ID is configured (gitignored `android/play_games.properties`) and signs release builds with an upload key from gitignored `android/key.properties`.

**Tech Stack:** Flutter 3.44.7 / Dart 3.12.2, `games_services` 5.3.0 (Android: `play-services-games-v2` 21.0.0), AGP 9.0.1 Kotlin DSL, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-10-16-play-games-sign-in-design.md`

## Global Constraints

- Android only. iOS shows no icons and behaves as today (only its deployment target rises to 14.0, required by the plugin).
- Play Games is never on the startup path: `AppServices.create` only does a local channel check; sign-in starts after the lobby's first frame.
- Only `lib/platform/games_services_play_games.dart` imports `package:games_services`.
- Nothing Play Games related may throw into the UI; every plugin call is caught, timed out (10 s for screens, 2 min for interactive sign-in) and logged with `debugPrint`.
- Settings does not change. The lobby menu (Play/Continue, Completed Levels, Settings) does not change.
- Rendering rules (CLAUDE.md): no `BackdropFilter`, no `Opacity`/`ColorFilter` layers; static chrome is wrapped in `StaticLayer`.
- Notice text, verbatim: `Couldn't connect to Google Play Games`, shown 4 s.
- Semantics labels, verbatim: `Achievements`, `Leaderboards`.
- `android/key.properties`, `android/play_games.properties`, `*.jks`, `*.keystore` are never committed.
- App ID `com.sungamestudio.braintrain` does not change.
- `flutter analyze` clean and `flutter test` green after every task.
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Findings made while planning (supersede the spec where they differ)

- PGS v2 initialises itself through `PlayGamesInitProvider` (merged from the library manifest). No `PlayGamesSdk.initialize` call is needed. Builds without an app ID disable that provider (`android:enabled="false"` via a manifest placeholder) so it cannot run without an ID.
- The plugin reports every sign-in failure with the same code (`failed_to_authenticate`). A dismissed dialog comes back with an empty message, real failures with a message; we use that to tell "cancelled" (no notice) from "failed" (notice).
- `GameAuth.player` checks `isAuthenticated` once per subscription; `refresh()` therefore cancels and listens again.
- `showAchievements`/`showLeaderboards` return as soon as Google's screen is started (10 s timeout is safe); `signIn` returns after the player finishes Google's dialog (2 min timeout).
- The app ID goes into the manifest as `@string/game_services_project_id` (a numeric literal in `meta-data` would be parsed as a number).
- The `games_services` iOS pod requires iOS 14.0; the project targets 13.0 → raise to 14.0.
- On this machine the Play Store emulator is AVD `Pixel_9` (Android 36, `google_apis_playstore`); `TP_*` AVDs have no Play Store.

## Review Focus

- The silent sign-in check never answers (Play services slow or hung): status stays signed out, icons still work through interactive sign-in. → Task 2 test `stays signed out while the check never answers`.
- Sign-in succeeds but the plugin sends no player event: the screen still opens. → Task 3 test `opens the screen after sign-in even before a status event`.
- The app goes to the background and back while Google's sign-in dialog is open (resume fires a refresh mid sign-in): exactly one screen opens. → Task 3 test `a resume during sign-in still opens one screen`.
- The notice timer fires after the controller is disposed: no exception, no notify. → Task 3 test `notice timer after dispose is harmless`.
- Small phone (360×640) with large text (1.3) and the icon row: lobby lays out without overflow. → Task 4 test `small phone with large text lays out`.

---

### Task 1: Android build — plugin, app ID switch, upload key, platform channel

**Files:**
- Modify: `pubspec.yaml` (dependencies)
- Modify: `android/app/build.gradle.kts`
- Modify: `android/app/src/main/AndroidManifest.xml`
- Modify: `android/app/src/main/kotlin/com/sungamestudio/braintrain/MainActivity.kt`
- Modify: `android/.gitignore`
- Modify: `ios/Podfile` (if it has a `platform :ios` line) and `ios/Runner.xcodeproj/project.pbxproj` (`IPHONEOS_DEPLOYMENT_TARGET`)

**Interfaces:**
- Produces: method channel `brain_train/platform`, method `playGamesConfigured` → `bool` (true when the build has a non-blank Play Games app ID). Android string resource `game_services_project_id` (always defined; empty when unconfigured). Manifest placeholder `playGamesEnabled` (`"true"`/`"false"`).

- [ ] **Step 1: Add the plugin**

In `pubspec.yaml`, under `dependencies:` after `vibration: ^3.2.1`, add:

```yaml
  # Google Play Games Services (Android only; see docs/PLAY_GAMES.md).
  games_services: ^5.3.0
```

Run: `flutter pub get`
Expected: resolves `games_services 5.3.0` and `games_services_platform_interface 5.3.0`.

- [ ] **Step 2: Gradle — app ID switch and upload key**

Replace `android/app/build.gradle.kts` with:

```kotlin
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

/** android/<name> as properties, empty when the file does not exist. */
fun localProperties(name: String): Properties = Properties().apply {
    val file = rootProject.file(name)
    if (file.exists()) file.inputStream().use { load(it) }
}

// Google Play Games Services app ID (docs/PLAY_GAMES.md): android/play_games.properties
// (playGamesAppId=<number>) or -PplayGamesAppId=<number>. Without it Play Games is off.
val playGamesAppId: String =
    ((findProperty("playGamesAppId") as String?)
        ?: localProperties("play_games.properties").getProperty("playGamesAppId")
        ?: "").trim()
require(playGamesAppId.all(Char::isDigit)) { "playGamesAppId must be the numeric Play Games app ID" }

// Release upload key (docs/PLAY_GAMES.md): android/key.properties.
val uploadKey = localProperties("key.properties")

android {
    namespace = "com.sungamestudio.braintrain"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        resValues = true
    }

    defaultConfig {
        applicationId = "com.sungamestudio.braintrain"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Read by the manifest's APP_ID meta-data and by MainActivity.
        resValue("string", "game_services_project_id", playGamesAppId)
        manifestPlaceholders["playGamesEnabled"] = playGamesAppId.isNotEmpty().toString()
    }

    signingConfigs {
        if (!uploadKey.isEmpty()) {
            create("upload") {
                storeFile = rootProject.file(uploadKey.getProperty("storeFile"))
                storePassword = uploadKey.getProperty("storePassword")
                keyAlias = uploadKey.getProperty("keyAlias")
                keyPassword = uploadKey.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (uploadKey.isEmpty()) {
                logger.warn("android/key.properties not found: release builds are signed with the debug key (not for Play).")
                signingConfigs.getByName("debug")
            } else {
                signingConfigs.getByName("upload")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
```

- [ ] **Step 3: Manifest — APP_ID and the init provider switch**

In `android/app/src/main/AndroidManifest.xml`, inside `<application>`, directly after the `flutterEmbedding` `<meta-data>` element, add:

```xml
        <!-- Google Play Games Services (docs/PLAY_GAMES.md). The ID comes from
             android/play_games.properties; without it the library's init
             provider is switched off and the app never calls Play Games. -->
        <meta-data
            android:name="com.google.android.gms.games.APP_ID"
            android:value="@string/game_services_project_id" />
        <provider
            android:name="com.google.android.gms.games.provider.PlayGamesInitProvider"
            android:authorities="${applicationId}.playgamesinitprovider"
            android:exported="false"
            android:enabled="${playGamesEnabled}" />
```

- [ ] **Step 4: MainActivity — `playGamesConfigured`**

Replace `android/app/src/main/kotlin/com/sungamestudio/braintrain/MainActivity.kt` with:

```kotlin
package com.sungamestudio.braintrain

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Tells Dart whether this build has a Play Games app ID (android/app/build.gradle.kts).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "brain_train/platform")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "playGamesConfigured" ->
                        result.success(getString(R.string.game_services_project_id).isNotBlank())
                    else -> result.notImplemented()
                }
            }
    }
}
```

- [ ] **Step 5: gitignore**

In `android/.gitignore`, after the `key.properties` line, add:

```
play_games.properties
```

(`key.properties`, `**/*.keystore`, `**/*.jks` are already listed there.)

- [ ] **Step 6: iOS deployment target 14.0**

Run: `grep -n "platform :ios" ios/Podfile; grep -c "IPHONEOS_DEPLOYMENT_TARGET = 13.0" ios/Runner.xcodeproj/project.pbxproj`
Then set every `IPHONEOS_DEPLOYMENT_TARGET = 13.0;` in `ios/Runner.xcodeproj/project.pbxproj` to `IPHONEOS_DEPLOYMENT_TARGET = 14.0;` (Edit with replace_all), and if the Podfile has `platform :ios, '13.0'` (commented or not), make it `platform :ios, '14.0'` uncommented.

Run: `flutter build ios --no-codesign --debug`
Expected: `✓ Built build/ios/iphoneos/Runner.app` (if Xcode/CocoaPods are missing on the machine, record that and continue; the iOS build is then checked on the owner's Mac).

- [ ] **Step 7: Verify the unconfigured release build**

With neither `android/play_games.properties` nor `android/key.properties` present:

Run: `flutter build apk --release`
Expected: builds; Gradle output contains `android/key.properties not found`.

Run:
```bash
SDK=/opt/homebrew/share/android-commandlinetools; BT=$(ls -d $SDK/build-tools/* | tail -1)
$BT/aapt2 dump xmltree --file AndroidManifest.xml build/app/outputs/flutter-apk/app-release.apk | grep -A6 "PlayGamesInitProvider"
```
Expected: the provider element shows `android:enabled(0x0101000e)=false`.

- [ ] **Step 8: Verify the configured release build**

Create a throwaway key and config (removed afterwards; scratch dir = the session scratchpad):

```bash
SCRATCH=/private/tmp/claude-501/-Users-suraj-kum-Code-Brain-Train/7565078f-55a3-459a-a0c7-58622b3c038b/scratchpad
keytool -genkeypair -v -keystore $SCRATCH/throwaway.jks -keyalg RSA -keysize 2048 -validity 1 -alias upload \
  -storepass throwaway -keypass throwaway -dname "CN=Throwaway"
printf 'storeFile=%s\nstorePassword=throwaway\nkeyAlias=upload\nkeyPassword=throwaway\n' "$SCRATCH/throwaway.jks" > android/key.properties
printf 'playGamesAppId=123456789012\n' > android/play_games.properties
flutter build apk --release
$BT/aapt2 dump xmltree --file AndroidManifest.xml build/app/outputs/flutter-apk/app-release.apk | grep -A6 "PlayGamesInitProvider"
$BT/aapt2 dump resources build/app/outputs/flutter-apk/app-release.apk | grep -A1 "game_services_project_id"
$BT/apksigner verify --print-certs build/app/outputs/flutter-apk/app-release.apk | grep "Signer #1 certificate DN"
rm android/key.properties android/play_games.properties
git status --short android/
```
Expected: provider `android:enabled(...)=true`; resource value `"123456789012"`; signer DN `CN=Throwaway`; `git status` shows no `.properties` files (they are ignored and now deleted anyway).

- [ ] **Step 9: Run on the Play Store emulator**

Run: `flutter run -d emulator-5554` (AVD `Pixel_9`), let it reach the lobby, quit with `q`.
Expected: the app starts and plays as before; `adb logcat -d | grep -i "FATAL\|PlayGames"` shows no crash.

- [ ] **Step 10: Analyze, test, commit**

Run: `flutter analyze` → `No issues found!`; `flutter test` → all pass.

```bash
git add pubspec.yaml pubspec.lock android/app/build.gradle.kts android/app/src/main/AndroidManifest.xml \
  android/app/src/main/kotlin/com/sungamestudio/braintrain/MainActivity.kt android/.gitignore ios/
git commit -m "$(printf 'Add games_services; Play Games app ID switch and upload key signing\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>')"
```

---

### Task 2: `PlayGames` interface and the `games_services` implementation

**Files:**
- Create: `lib/platform/play_games.dart`
- Create: `lib/platform/games_services_play_games.dart`
- Create: `test/platform/fake_play_games.dart`
- Test: `test/platform/games_services_play_games_test.dart`

**Interfaces:**
- Consumes: channel `brain_train/platform` / `playGamesConfigured` (Task 1).
- Produces:
  - `sealed class PlayGamesStatus`; `PlayGamesUnavailable()`, `PlayGamesSignedOut()`, `PlayGamesSignedIn(String displayName)` (value equality).
  - `enum PlayGamesSignIn { signedIn, cancelled, failed }`
  - `abstract class PlayGames { Stream<PlayGamesStatus> get status; PlayGamesStatus get current; void refresh(); Future<PlayGamesSignIn> signIn(); Future<bool> showAchievements(); Future<bool> showLeaderboards(); void dispose(); }`
  - `class UnavailablePlayGames implements PlayGames` (const constructor)
  - `class PlayGamesBackend` (const; `Stream<String?> get players`, `Future<void> signIn()`, `Future<void> showAchievements()`, `Future<void> showLeaderboards()`)
  - `class GamesServicesPlayGames implements PlayGames` — `GamesServicesPlayGames({PlayGamesBackend backend = const PlayGamesBackend(), Duration callTimeout = const Duration(seconds: 10), Duration signInTimeout = const Duration(minutes: 2)})`
  - `Future<PlayGames> createPlayGames()`
  - Test helper `FakePlayGames implements PlayGames` (used by Tasks 3 and 4).

- [ ] **Step 1: Write the interface**

Create `lib/platform/play_games.dart`:

```dart
/// Google Play Games Services as the app sees it (Android only). Optional:
/// the game plays the same signed out, offline or without it, and nothing
/// here is on the startup path.
library;

/// Whether the player is signed in to Play Games.
sealed class PlayGamesStatus {
  const PlayGamesStatus();
}

/// No Play Games here (iOS, a build without an app ID): the lobby shows no
/// Play Games buttons.
final class PlayGamesUnavailable extends PlayGamesStatus {
  const PlayGamesUnavailable();
}

final class PlayGamesSignedOut extends PlayGamesStatus {
  const PlayGamesSignedOut();
}

final class PlayGamesSignedIn extends PlayGamesStatus {
  const PlayGamesSignedIn(this.displayName);

  final String displayName;

  @override
  bool operator ==(Object other) => other is PlayGamesSignedIn && other.displayName == displayName;

  @override
  int get hashCode => displayName.hashCode;
}

/// How an interactive sign-in ended.
enum PlayGamesSignIn { signedIn, cancelled, failed }

abstract class PlayGames {
  /// Status changes; [current] is the latest.
  Stream<PlayGamesStatus> get status;
  PlayGamesStatus get current;

  /// Starts (or restarts) the silent sign-in check.
  void refresh();

  /// Google's sign-in dialog, when the player asks for Play Games.
  Future<PlayGamesSignIn> signIn();

  /// Opens Google's screen; false when it could not be opened.
  Future<bool> showAchievements();
  Future<bool> showLeaderboards();

  void dispose();
}

/// Play Games where there is none: always [PlayGamesUnavailable].
class UnavailablePlayGames implements PlayGames {
  const UnavailablePlayGames();

  @override
  Stream<PlayGamesStatus> get status => const Stream.empty();

  @override
  PlayGamesStatus get current => const PlayGamesUnavailable();

  @override
  void refresh() {}

  @override
  Future<PlayGamesSignIn> signIn() async => PlayGamesSignIn.failed;

  @override
  Future<bool> showAchievements() async => false;

  @override
  Future<bool> showLeaderboards() async => false;

  @override
  void dispose() {}
}
```

- [ ] **Step 2: Write the fake (shared by later tests)**

Create `test/platform/fake_play_games.dart`:

```dart
import 'dart:async';

import 'package:brain_train/platform/play_games.dart';

/// Scriptable [PlayGames]: records calls, can hold them open with [gate].
class FakePlayGames implements PlayGames {
  FakePlayGames([this._current = const PlayGamesSignedOut()]);

  final _status = StreamController<PlayGamesStatus>.broadcast();
  PlayGamesStatus _current;

  final List<String> calls = [];
  int refreshes = 0;
  bool disposed = false;

  PlayGamesSignIn signInResult = PlayGamesSignIn.signedIn;

  /// Whether a successful [signIn] also reports the player (as the plugin does).
  bool emitOnSignIn = true;
  bool showResult = true;

  /// When set, every call waits for it.
  Completer<void>? gate;

  void emit(PlayGamesStatus status) {
    _current = status;
    _status.add(status);
  }

  @override
  Stream<PlayGamesStatus> get status => _status.stream;

  @override
  PlayGamesStatus get current => _current;

  @override
  void refresh() => refreshes++;

  @override
  Future<PlayGamesSignIn> signIn() async {
    calls.add('signIn');
    await gate?.future;
    if (signInResult == PlayGamesSignIn.signedIn && emitOnSignIn) emit(const PlayGamesSignedIn('Tester'));
    return signInResult;
  }

  @override
  Future<bool> showAchievements() async {
    calls.add('achievements');
    await gate?.future;
    return showResult;
  }

  @override
  Future<bool> showLeaderboards() async {
    calls.add('leaderboards');
    await gate?.future;
    return showResult;
  }

  @override
  void dispose() => disposed = true;
}
```

- [ ] **Step 3: Write the failing tests**

Create `test/platform/games_services_play_games_test.dart`:

```dart
import 'dart:async';

import 'package:brain_train/platform/games_services_play_games.dart';
import 'package:brain_train/platform/play_games.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stands in for the plugin: every listen to [players] is a new check.
class _FakeBackend implements PlayGamesBackend {
  int listens = 0;
  int cancels = 0;
  StreamController<String?>? check;

  Future<void> Function() onSignIn = () async {};
  Future<void> Function() onShow = () async {};

  @override
  Stream<String?> get players {
    listens++;
    final controller = StreamController<String?>(onCancel: () => cancels++);
    check = controller;
    return controller.stream;
  }

  @override
  Future<void> signIn() => onSignIn();

  @override
  Future<void> showAchievements() => onShow();

  @override
  Future<void> showLeaderboards() => onShow();
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  late _FakeBackend backend;
  late GamesServicesPlayGames playGames;

  setUp(() {
    backend = _FakeBackend();
    playGames = GamesServicesPlayGames(
      backend: backend,
      callTimeout: const Duration(milliseconds: 20),
      signInTimeout: const Duration(milliseconds: 20),
    );
  });

  tearDown(() => playGames.dispose());

  test('starts signed out', () {
    expect(playGames.current, const PlayGamesSignedOut());
  });

  group('silent sign-in', () {
    test('a player means signed in, and the change is announced', () async {
      final seen = <PlayGamesStatus>[];
      playGames.status.listen(seen.add);
      playGames.refresh();
      backend.check!.add('Ann');
      await _settle();
      expect(playGames.current, const PlayGamesSignedIn('Ann'));
      expect(seen, [const PlayGamesSignedIn('Ann')]);
    });

    test('no player or an error means signed out', () async {
      playGames.refresh();
      backend.check!.add('Ann');
      await _settle();
      backend.check!.add(null);
      await _settle();
      expect(playGames.current, const PlayGamesSignedOut());
      backend.check!.add('Ann');
      await _settle();
      backend.check!.addError(PlatformException(code: 'failed_to_authenticate'));
      await _settle();
      expect(playGames.current, const PlayGamesSignedOut());
    });

    test('refresh checks again on a new subscription', () async {
      playGames.refresh();
      playGames.refresh();
      await _settle();
      expect(backend.listens, 2);
      expect(backend.cancels, 1);
    });

    test('stays signed out while the check never answers', () async {
      playGames.refresh();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(playGames.current, const PlayGamesSignedOut());
      expect(await playGames.signIn(), PlayGamesSignIn.signedIn);
    });
  });

  group('signIn', () {
    test('success signs in and checks the player again', () async {
      expect(await playGames.signIn(), PlayGamesSignIn.signedIn);
      expect(backend.listens, 1);
    });

    test('a dismissed dialog (empty message) is a cancel', () async {
      backend.onSignIn = () async => throw PlatformException(code: 'failed_to_authenticate', message: '');
      expect(await playGames.signIn(), PlayGamesSignIn.cancelled);
      backend.onSignIn = () async => throw PlatformException(code: 'failed_to_authenticate');
      expect(await playGames.signIn(), PlayGamesSignIn.cancelled);
    });

    test('an error with a message, a timeout or anything else is a failure', () async {
      backend.onSignIn = () async => throw PlatformException(code: 'failed_to_authenticate', message: 'Network error');
      expect(await playGames.signIn(), PlayGamesSignIn.failed);
      backend.onSignIn = () => Completer<void>().future;
      expect(await playGames.signIn(), PlayGamesSignIn.failed);
      backend.onSignIn = () async => throw StateError('boom');
      expect(await playGames.signIn(), PlayGamesSignIn.failed);
    });
  });

  group('screens', () {
    test('open: true', () async {
      expect(await playGames.showAchievements(), isTrue);
      expect(await playGames.showLeaderboards(), isTrue);
    });

    test('an error or a timeout: false, never a throw', () async {
      backend.onShow = () async => throw PlatformException(code: 'failed_to_show_achievements', message: 'x');
      expect(await playGames.showAchievements(), isFalse);
      backend.onShow = () => Completer<void>().future;
      expect(await playGames.showLeaderboards(), isFalse);
    });
  });

  test('after dispose, refresh and late events are ignored', () async {
    playGames.refresh();
    final check = backend.check!;
    playGames.dispose();
    playGames.refresh();
    expect(backend.listens, 1);
    check.add('Ann');
    await _settle();
    expect(playGames.current, const PlayGamesSignedOut());
  });

  test('createPlayGames: unavailable off Android', () async {
    expect(await createPlayGames(), isA<UnavailablePlayGames>());
  });
}
```

- [ ] **Step 4: Run to see them fail**

Run: `flutter test test/platform/games_services_play_games_test.dart`
Expected: FAIL — `games_services_play_games.dart` does not exist.

- [ ] **Step 5: Implement**

Create `lib/platform/games_services_play_games.dart`:

```dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:games_services/games_services.dart';

import 'play_games.dart';

/// The plugin calls [GamesServicesPlayGames] makes, so tests can stand in.
class PlayGamesBackend {
  const PlayGamesBackend();

  /// The signed-in player's name, or null. Each subscription runs one silent
  /// sign-in check; an error means signed out.
  Stream<String?> get players => GameAuth.player.map((player) => player?.displayName);

  Future<void> signIn() => GameAuth.signIn();

  Future<void> showAchievements() => Achievements.showAchievements();

  Future<void> showLeaderboards() => Leaderboards.showLeaderboards();
}

/// [PlayGames] on the `games_services` plugin. The only file that imports
/// it; no call can throw, hang or block the app.
class GamesServicesPlayGames implements PlayGames {
  GamesServicesPlayGames({
    this.backend = const PlayGamesBackend(),
    this.callTimeout = const Duration(seconds: 10),
    this.signInTimeout = const Duration(minutes: 2),
  });

  final PlayGamesBackend backend;

  /// For opening a screen (the plugin answers once it is started).
  final Duration callTimeout;

  /// For sign-in, which waits for the player in Google's dialog.
  final Duration signInTimeout;

  final _status = StreamController<PlayGamesStatus>.broadcast();
  PlayGamesStatus _current = const PlayGamesSignedOut();
  StreamSubscription<String?>? _players;
  bool _disposed = false;

  @override
  Stream<PlayGamesStatus> get status => _status.stream;

  @override
  PlayGamesStatus get current => _current;

  @override
  void refresh() {
    if (_disposed) return;
    // The plugin checks once per subscription: listen again to check again.
    unawaited(_players?.cancel());
    try {
      _players = backend.players.listen(
        (name) => _set(name == null ? const PlayGamesSignedOut() : PlayGamesSignedIn(name)),
        onError: (Object error) {
          debugPrint('Play Games: not signed in ($error)');
          _set(const PlayGamesSignedOut());
        },
      );
    } on Object catch (error) {
      debugPrint('Play Games: sign-in check failed ($error)');
      _set(const PlayGamesSignedOut());
    }
  }

  void _set(PlayGamesStatus status) {
    if (_disposed || status == _current) return;
    _current = status;
    _status.add(status);
  }

  @override
  Future<PlayGamesSignIn> signIn() async {
    try {
      await backend.signIn().timeout(signInTimeout);
      refresh();
      return PlayGamesSignIn.signedIn;
    } on PlatformException catch (error) {
      // The plugin reports a dismissed dialog with an empty message, and real
      // failures (network, configuration) with one.
      debugPrint('Play Games: sign-in ended (${error.code}: ${error.message})');
      return (error.message ?? '').isEmpty ? PlayGamesSignIn.cancelled : PlayGamesSignIn.failed;
    } on Object catch (error) {
      debugPrint('Play Games: sign-in failed ($error)');
      return PlayGamesSignIn.failed;
    }
  }

  @override
  Future<bool> showAchievements() => _show('achievements', backend.showAchievements);

  @override
  Future<bool> showLeaderboards() => _show('leaderboards', backend.showLeaderboards);

  Future<bool> _show(String screen, Future<void> Function() open) async {
    try {
      await open().timeout(callTimeout);
      return true;
    } on Object catch (error) {
      debugPrint('Play Games: could not open $screen ($error)');
      return false;
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(_players?.cancel());
    unawaited(_status.close());
  }
}

/// Play Games when this build and device have it (Android with an app ID,
/// see docs/PLAY_GAMES.md), else [UnavailablePlayGames]. Only a local
/// channel call: never waits for the network.
Future<PlayGames> createPlayGames() async {
  if (!Platform.isAndroid) return const UnavailablePlayGames();
  try {
    final configured = await const MethodChannel('brain_train/platform').invokeMethod<bool>('playGamesConfigured');
    return configured == true ? GamesServicesPlayGames() : const UnavailablePlayGames();
  } on Object catch (error) {
    debugPrint('Play Games: configuration check failed ($error)');
    return const UnavailablePlayGames();
  }
}
```

- [ ] **Step 6: Run the tests**

Run: `flutter test test/platform/games_services_play_games_test.dart`
Expected: all PASS.

- [ ] **Step 7: Analyze, full tests, commit**

Run: `flutter analyze` → clean; `flutter test` → all pass.

```bash
git add lib/platform/ test/platform/
git commit -m "$(printf 'Add the PlayGames interface and its games_services implementation\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>')"
```

---

### Task 3: `PlayGamesController` and wiring into `AppServices`

**Files:**
- Create: `lib/app/play_games_controller.dart`
- Modify: `lib/app/app_services.dart` (constructor, field, `create`)
- Modify: `test/features/lobby_support.dart` (`testServices` takes a controller)
- Test: `test/app/play_games_controller_test.dart`

**Interfaces:**
- Consumes: `PlayGames`, `PlayGamesStatus`, `PlayGamesSignIn`, `UnavailablePlayGames`, `createPlayGames()` (Task 2); `FakePlayGames` (Task 2, test).
- Produces:
  - `class PlayGamesController extends ChangeNotifier with WidgetsBindingObserver` — `PlayGamesController(PlayGames playGames, {Duration noticeDuration = const Duration(seconds: 4)})`; `static const failedNotice = "Couldn't connect to Google Play Games"`; getters `PlayGamesStatus status`, `bool available`, `bool busy`, `String? notice`; methods `void start()`, `Future<void> openAchievements()`, `Future<void> openLeaderboards()`, `void dispose()`.
  - `AppServices.playGames` (`PlayGamesController`, never null; defaults to a controller over `UnavailablePlayGames`).
  - `testServices({PlayGamesController? playGames})`.

- [ ] **Step 1: Write the failing tests**

Create `test/app/play_games_controller_test.dart`:

```dart
import 'dart:async';

import 'package:brain_train/app/play_games_controller.dart';
import 'package:brain_train/platform/play_games.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../platform/fake_play_games.dart';

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakePlayGames fake;
  late PlayGamesController controller;

  setUp(() {
    fake = FakePlayGames();
    controller = PlayGamesController(fake, noticeDuration: const Duration(milliseconds: 30));
  });

  tearDown(() => controller.dispose());

  test('unavailable: not available, start does nothing', () {
    final none = PlayGamesController(const UnavailablePlayGames());
    expect(none.available, isFalse);
    none.start();
    none.dispose();
  });

  test('start runs the silent check once and follows the status', () async {
    var notified = 0;
    controller.addListener(() => notified++);
    controller
      ..start()
      ..start();
    expect(fake.refreshes, 1);
    fake.emit(const PlayGamesSignedIn('Ann'));
    await _settle();
    expect(controller.status, const PlayGamesSignedIn('Ann'));
    expect(notified, 1);
  });

  test('resume checks again', () {
    controller.start();
    controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
    controller.didChangeAppLifecycleState(AppLifecycleState.paused);
    expect(fake.refreshes, 2);
  });

  test('signed in: opens the screen', () async {
    fake.emit(const PlayGamesSignedIn('Ann'));
    await controller.openAchievements();
    await controller.openLeaderboards();
    expect(fake.calls, ['achievements', 'leaderboards']);
    expect(controller.notice, isNull);
  });

  test('signed out: signs in, then opens the screen', () async {
    await controller.openAchievements();
    expect(fake.calls, ['signIn', 'achievements']);
  });

  test('opens the screen after sign-in even before a status event', () async {
    fake.emitOnSignIn = false;
    await controller.openLeaderboards();
    expect(fake.calls, ['signIn', 'leaderboards']);
  });

  test('cancelled sign-in: nothing else, no notice', () async {
    fake.signInResult = PlayGamesSignIn.cancelled;
    await controller.openAchievements();
    expect(fake.calls, ['signIn']);
    expect(controller.notice, isNull);
  });

  test('failed sign-in or screen: notice, then it clears', () async {
    fake.signInResult = PlayGamesSignIn.failed;
    await controller.openAchievements();
    expect(fake.calls, ['signIn']);
    expect(controller.notice, PlayGamesController.failedNotice);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(controller.notice, isNull);

    fake
      ..signInResult = PlayGamesSignIn.signedIn
      ..showResult = false;
    await controller.openLeaderboards();
    expect(controller.notice, PlayGamesController.failedNotice);
  });

  test('taps during a call are ignored', () async {
    fake.gate = Completer<void>();
    final first = controller.openAchievements();
    expect(controller.busy, isTrue);
    unawaited(controller.openAchievements());
    unawaited(controller.openLeaderboards());
    fake.gate!.complete();
    await first;
    expect(fake.calls, ['signIn', 'achievements']);
    expect(controller.busy, isFalse);
  });

  test('a resume during sign-in still opens one screen', () async {
    controller.start();
    fake.gate = Completer<void>();
    final open = controller.openAchievements();
    await _settle();
    controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
    fake.gate!.complete();
    await open;
    expect(fake.calls, ['signIn', 'achievements']);
    expect(fake.refreshes, 2);
  });

  test('notice timer after dispose is harmless', () async {
    final local = PlayGamesController(FakePlayGames()..signInResult = PlayGamesSignIn.failed,
        noticeDuration: const Duration(milliseconds: 10));
    await local.openAchievements();
    expect(local.notice, isNotNull);
    local.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 30));
  });

  test('dispose disposes the PlayGames', () {
    final local = FakePlayGames();
    PlayGamesController(local).dispose();
    expect(local.disposed, isTrue);
  });
}
```

- [ ] **Step 2: Run to see them fail**

Run: `flutter test test/app/play_games_controller_test.dart`
Expected: FAIL — `play_games_controller.dart` does not exist.

- [ ] **Step 3: Implement the controller**

Create `lib/app/play_games_controller.dart`:

```dart
import 'dart:async';

import 'package:flutter/widgets.dart';

import '../platform/play_games.dart';

/// Play Games for the lobby: the sign-in status, the Achievements and
/// Leaderboards actions, and a short notice when one fails. Started by the
/// lobby after its first frame (never on the startup path); checks the
/// sign-in again when the app comes back to the foreground.
class PlayGamesController extends ChangeNotifier with WidgetsBindingObserver {
  PlayGamesController(this.playGames, {this.noticeDuration = const Duration(seconds: 4)});

  final PlayGames playGames;
  final Duration noticeDuration;

  static const failedNotice = "Couldn't connect to Google Play Games";

  StreamSubscription<PlayGamesStatus>? _statuses;
  Timer? _noticeTimer;
  String? _notice;
  bool _started = false;
  bool _observing = false;
  bool _busy = false;
  bool _disposed = false;

  PlayGamesStatus get status => playGames.current;

  /// False without Play Games (iOS, no app ID): the lobby shows no buttons.
  bool get available => status is! PlayGamesUnavailable;

  /// True while a sign-in or a screen is opening; taps are ignored meanwhile.
  bool get busy => _busy;

  /// A short failure message for the lobby footer, or null.
  String? get notice => _notice;

  /// Runs the silent sign-in check. Safe to call more than once.
  void start() {
    if (_started || _disposed || !available) return;
    _started = true;
    _statuses = playGames.status.listen((_) => notifyListeners());
    playGames.refresh();
    try {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    } on Object {
      // No binding (a pure Dart test): nothing to observe.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_disposed) playGames.refresh();
  }

  Future<void> openAchievements() => _open(playGames.showAchievements);

  Future<void> openLeaderboards() => _open(playGames.showLeaderboards);

  /// Signs in first when needed (Google's dialog), then opens the screen.
  Future<void> _open(Future<bool> Function() show) async {
    if (_busy || _disposed || !available) return;
    _busy = true;
    notifyListeners();
    try {
      if (status is! PlayGamesSignedIn) {
        switch (await playGames.signIn()) {
          case PlayGamesSignIn.cancelled:
            return;
          case PlayGamesSignIn.failed:
            _showNotice(failedNotice);
            return;
          case PlayGamesSignIn.signedIn:
            break;
        }
      }
      if (!await show()) _showNotice(failedNotice);
    } finally {
      _busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  void _showNotice(String text) {
    if (_disposed) return;
    _notice = text;
    _noticeTimer?.cancel();
    _noticeTimer = Timer(noticeDuration, () {
      if (_disposed) return;
      _notice = null;
      notifyListeners();
    });
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _noticeTimer?.cancel();
    unawaited(_statuses?.cancel());
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    playGames.dispose();
    super.dispose();
  }
}
```

- [ ] **Step 4: Run the controller tests**

Run: `flutter test test/app/play_games_controller_test.dart`
Expected: all PASS.

- [ ] **Step 5: Wire into `AppServices`**

In `lib/app/app_services.dart`:

Add imports (keep the existing alphabetical grouping):

```dart
import '../platform/games_services_play_games.dart';
import '../platform/play_games.dart';
import 'play_games_controller.dart';
```

Replace the `AppServices` constructor and add the field — the constructor becomes:

```dart
  AppServices({
    required this.content,
    required this.progress,
    required this.settings,
    required this.symbolArt,
    this.sounds,
    this.music,
    PlayGamesController? playGames,
  }) : playGames = playGames ?? PlayGamesController(const UnavailablePlayGames()) {
    // The level window follows this player's progress.
    content.attachProgress(progress);
  }
```

and after `final BackgroundMusic? music;` add:

```dart

  /// Google Play Games (Android builds with an app ID); unavailable elsewhere.
  final PlayGamesController playGames;
```

In `create`, replace the `return AppServices(` block with:

```dart
    return AppServices(
      content: content,
      progress: progress,
      settings: settings,
      symbolArt: SymbolArtCache(),
      sounds: sounds,
      music: BackgroundMusic(settings),
      // A local check only; sign-in starts from the lobby.
      playGames: PlayGamesController(await createPlayGames()),
    );
```

- [ ] **Step 6: Let lobby tests inject a controller**

In `test/features/lobby_support.dart`, change the signature and the return of `testServices`:

```dart
/// Services on the bundled content with the network unreachable.
Future<AppServices> testServices({PlayGamesController? playGames}) async {
```

```dart
  return AppServices(
    content: content,
    progress: await ProgressRepository.open(),
    settings: await SettingsRepository.open(),
    symbolArt: SymbolArtCache(),
    playGames: playGames,
  );
```

and add `import 'package:brain_train/app/play_games_controller.dart';` to its imports.

- [ ] **Step 7: Analyze, full tests, commit**

Run: `flutter analyze` → clean; `flutter test` → all pass.

```bash
git add lib/app/play_games_controller.dart lib/app/app_services.dart test/app/ test/features/lobby_support.dart
git commit -m "$(printf 'Add PlayGamesController and wire Play Games into AppServices\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>')"
```

---

### Task 4: Lobby — Achievements / Leaderboards buttons and the notice

**Files:**
- Modify: `lib/features/home/widgets/lobby_buttons.dart` (add `LobbyRoundButton`)
- Create: `lib/features/home/widgets/lobby_play_games.dart`
- Modify: `lib/features/home/widgets/lobby_footer.dart` (extract `LobbyNoticeText`)
- Modify: `lib/features/home/home_screen.dart`
- Test: `test/features/lobby_play_games_test.dart`
- Modify: `test/visual/lobby_capture_test.dart`

**Interfaces:**
- Consumes: `AppServices.playGames` / `PlayGamesController` (Task 3); `FakePlayGames` (Task 2); `testServices({PlayGamesController? playGames})`, `pumpLobby`, `smallPhone`, `captureLobby` (test support).
- Produces: `LobbyRoundButton({Key? key, required IconData icon, required String semanticLabel, required VoidCallback? onPressed, double size = 48})`; `LobbyPlayGamesButtons({Key? key, required PlayGamesController controller, double size = 48})`; `LobbyNoticeText(String text, {Key? key})`. Widget keys `lobby-achievements`, `lobby-leaderboards`.

- [ ] **Step 1: Write the failing widget tests**

Create `test/features/lobby_play_games_test.dart`:

```dart
import 'package:brain_train/app/app_services.dart';
import 'package:brain_train/app/play_games_controller.dart';
import 'package:brain_train/features/home/home_screen.dart';
import 'package:brain_train/platform/play_games.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../platform/fake_play_games.dart';
import 'lobby_support.dart';

const _achievements = ValueKey('lobby-achievements');
const _leaderboards = ValueKey('lobby-leaderboards');

Future<AppServices> _services(WidgetTester tester, PlayGames playGames) async {
  late AppServices services;
  await tester.runAsync(() async {
    services = await testServices(playGames: PlayGamesController(playGames));
  });
  return services;
}

Future<void> _tap(WidgetTester tester, Key key) async {
  await tester.tap(find.byKey(key));
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

Future<void> _leave(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'Brain Train',
      packageName: 'com.sungamestudio.braintrain',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  testWidgets('no Play Games: no buttons', (tester) async {
    final services = await _services(tester, const UnavailablePlayGames());
    await pumpLobby(tester, services: services, home: const HomeScreen());
    expect(find.byKey(_achievements), findsNothing);
    expect(find.byKey(_leaderboards), findsNothing);
    await _leave(tester);
  });

  testWidgets('signed out or in: both buttons, with labels; the lobby starts the check', (tester) async {
    final fake = FakePlayGames();
    final services = await _services(tester, fake);
    await pumpLobby(tester, services: services, home: const HomeScreen());
    expect(find.byKey(_achievements), findsOneWidget);
    expect(find.byKey(_leaderboards), findsOneWidget);
    expect(find.bySemanticsLabel('Achievements'), findsOneWidget);
    expect(find.bySemanticsLabel('Leaderboards'), findsOneWidget);
    expect(fake.refreshes, 1);
    fake.emit(const PlayGamesSignedIn('Ann'));
    await tester.pump();
    expect(find.byKey(_achievements), findsOneWidget);
    await _leave(tester);
  });

  testWidgets('signed in: a tap opens the screen', (tester) async {
    final fake = FakePlayGames(const PlayGamesSignedIn('Ann'));
    final services = await _services(tester, fake);
    await pumpLobby(tester, services: services, home: const HomeScreen());
    await _tap(tester, _achievements);
    await _tap(tester, _leaderboards);
    expect(fake.calls, ['achievements', 'leaderboards']);
    await _leave(tester);
  });

  testWidgets('signed out: a tap signs in, then opens the screen', (tester) async {
    final fake = FakePlayGames();
    final services = await _services(tester, fake);
    await pumpLobby(tester, services: services, home: const HomeScreen());
    await _tap(tester, _leaderboards);
    expect(fake.calls, ['signIn', 'leaderboards']);
    await _leave(tester);
  });

  testWidgets('a failure shows the notice in the footer, then it goes', (tester) async {
    final fake = FakePlayGames()..signInResult = PlayGamesSignIn.failed;
    final services = await _services(tester, fake);
    await pumpLobby(tester, services: services, home: const HomeScreen());
    await _tap(tester, _achievements);
    expect(find.text(PlayGamesController.failedNotice), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    expect(find.text(PlayGamesController.failedNotice), findsNothing);
    await _leave(tester);
  });

  testWidgets('a cancelled sign-in shows nothing', (tester) async {
    final fake = FakePlayGames()..signInResult = PlayGamesSignIn.cancelled;
    final services = await _services(tester, fake);
    await pumpLobby(tester, services: services, home: const HomeScreen());
    await _tap(tester, _achievements);
    expect(fake.calls, ['signIn']);
    expect(find.text(PlayGamesController.failedNotice), findsNothing);
    await _leave(tester);
  });

  testWidgets('small phone with large text lays out', (tester) async {
    final services = await _services(tester, FakePlayGames());
    await pumpLobby(tester, services: services, home: const HomeScreen(), phone: smallPhone, textScale: 1.3);
    expect(tester.takeException(), isNull);
    expect(find.byKey(_achievements), findsOneWidget);
    expect(find.byKey(const ValueKey('lobby-play')), findsOneWidget);
    await _leave(tester);
  });
}
```

- [ ] **Step 2: Run to see them fail**

Run: `flutter test test/features/lobby_play_games_test.dart`
Expected: FAIL — no widget with key `lobby-achievements` (the "no Play Games" test passes).

- [ ] **Step 3: `LobbyRoundButton`**

Append to `lib/features/home/widgets/lobby_buttons.dart`:

```dart

/// Small round lobby action (Achievements, Leaderboards): the secondary
/// button's green glass and thin gold border as a circle with a gold icon.
class LobbyRoundButton extends StatelessWidget {
  const LobbyRoundButton({
    super.key,
    required this.icon,
    required this.semanticLabel,
    required this.onPressed,
    this.size = 48,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback? onPressed;
  final double size;

  @override
  Widget build(BuildContext context) {
    final lobby = LobbyTheme.of(context);
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: semanticLabel,
      onTap: onPressed,
      excludeSemantics: true,
      // Rendered once (and again only while its ink animates).
      child: StaticLayer(
        overflow: const EdgeInsets.all(24),
        child: DecoratedBox(
          decoration: ShapeDecoration(
            shape: CircleBorder(side: BorderSide(color: lobby.secondaryBorder, width: 1.2)),
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: lobby.secondaryFill),
            shadows: [BoxShadow(color: lobby.secondaryShadow, blurRadius: 10, offset: const Offset(0, 4))],
          ),
          child: Material(
            type: MaterialType.transparency,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onPressed,
              splashColor: lobby.secondaryIcon.withValues(alpha: 0.22),
              highlightColor: lobby.secondaryIcon.withValues(alpha: 0.1),
              child: SizedBox.square(
                dimension: size,
                child: Icon(icon, size: size * 0.5, color: lobby.secondaryIcon),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: `LobbyPlayGamesButtons`**

Create `lib/features/home/widgets/lobby_play_games.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/play_games_controller.dart';
import 'lobby_buttons.dart';

/// Achievements and Leaderboards (Google Play Games): two small round
/// buttons at the top of the lobby. Nothing without Play Games.
class LobbyPlayGamesButtons extends StatelessWidget {
  const LobbyPlayGamesButtons({super.key, required this.controller, this.size = 48});

  final PlayGamesController controller;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (!controller.available) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        LobbyRoundButton(
          key: const ValueKey('lobby-achievements'),
          icon: Icons.military_tech_rounded,
          semanticLabel: 'Achievements',
          size: size,
          onPressed: () => unawaited(controller.openAchievements()),
        ),
        SizedBox(width: size * 0.3),
        LobbyRoundButton(
          key: const ValueKey('lobby-leaderboards'),
          icon: Icons.leaderboard_rounded,
          semanticLabel: 'Leaderboards',
          size: size,
          onPressed: () => unawaited(controller.openLeaderboards()),
        ),
      ],
    );
  }
}
```

(The trophy `Icons.emoji_events_rounded` is already the Completed Levels icon, so Achievements uses the medal.)

- [ ] **Step 5: `LobbyNoticeText`**

In `lib/features/home/widgets/lobby_footer.dart`, replace `LobbyContentFooter.build` and add the new widget below the class:

```dart
  @override
  Widget build(BuildContext context) {
    final text = label(snapshot, status);
    if (text == null) return const SizedBox.shrink();
    return LobbyNoticeText(text);
  }
}

/// One line in the lobby footer's style (content notices, Play Games).
class LobbyNoticeText extends StatelessWidget {
  const LobbyNoticeText(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final lobby = LobbyTheme.of(context);
    return Semantics(
      liveRegion: true,
      // Shadowed text: rendered once, not on every frame of the scene.
      child: StaticLayer(
        overflow: const EdgeInsets.all(6),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: lobby.footerText,
            letterSpacing: 0.3,
            shadows: [Shadow(color: lobby.textShadow, blurRadius: 4, offset: const Offset(0, 1))],
          ),
        ),
      ),
    );
  }
}
```

(The old body of `LobbyContentFooter.build` moves into `LobbyNoticeText.build`; the closing brace of `LobbyContentFooter` is the `}` before the new class.)

- [ ] **Step 6: Home screen**

In `lib/features/home/home_screen.dart`:

Add the import:

```dart
import 'widgets/lobby_play_games.dart';
```

In `_HomeScreenState`, before `build`, add:

```dart
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final playGames = AppScope.of(context).playGames;
    // After the first frame: the lobby never waits for Play Games.
    WidgetsBinding.instance.addPostFrameCallback((_) => playGames.start());
  }
```

In `build`, change the listenable to:

```dart
              listenable: Listenable.merge([services.content, services.progress, services.playGames]),
```

In `_layout`, make the Play Games row the first child of the `Column` (before `const Spacer(flex: 2),`):

```dart
                Align(
                  alignment: Alignment.centerRight,
                  child: LobbyPlayGamesButtons(controller: services.playGames),
                ),
```

and replace the footer line `LobbyContentFooter(snapshot: services.content.snapshot, status: services.content.status),` with:

```dart
                if (services.playGames.notice case final notice?)
                  LobbyNoticeText(notice)
                else
                  LobbyContentFooter(snapshot: services.content.snapshot, status: services.content.status),
```

- [ ] **Step 7: Run the widget tests**

Run: `flutter test test/features/lobby_play_games_test.dart test/features/lobby_home_test.dart`
Expected: all PASS.

- [ ] **Step 8: Visual capture with the buttons**

In `test/visual/lobby_capture_test.dart`, add imports:

```dart
import 'package:brain_train/app/play_games_controller.dart';
import 'package:brain_train/platform/play_games.dart';

import '../platform/fake_play_games.dart';
```

and inside `main()`, after the existing `for (final phone in [...])` loop, add:

```dart
  for (final phone in [largePhone, smallPhone, tallPhone]) {
    testWidgets('lobby ${phone.name}: Play Games buttons', (tester) async {
      late AppServices services;
      await tester.runAsync(() async {
        services = await testServices(
          playGames: PlayGamesController(FakePlayGames(const PlayGamesSignedIn('Tester'))),
        );
        await _midway(services);
      });
      await pumpLobby(tester, services: services, home: const HomeScreen(), phone: phone);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('lobby-achievements')), findsOneWidget);
      await captureLobby(tester, 'lobby-play-games-${phone.name}', phone.dpr);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  }
```

Run: `CAPTURE_DIR=/private/tmp/claude-501/-Users-suraj-kum-Code-Brain-Train/7565078f-55a3-459a-a0c7-58622b3c038b/scratchpad/shots flutter test test/visual/lobby_capture_test.dart`
Expected: PASS; open `lobby-play-games-360x640.png`, `-411x914.png`, `-430x932.png` in the scratchpad `shots/` folder and check: the two round buttons sit top-right, do not touch the tagline, match the secondary buttons' green/gold, and the menu is unchanged. If they crowd the tagline on 360×640, reduce `size` to 44 in `LobbyPlayGamesButtons(...)` on small heights (`size: h < 700 ? 44 : 48`) and re-capture.

- [ ] **Step 9: Analyze, full tests, commit**

Run: `flutter analyze` → clean; `flutter test` → all pass.

```bash
git add lib/features/home/ test/features/lobby_play_games_test.dart test/visual/lobby_capture_test.dart
git commit -m "$(printf 'Lobby: Achievements and Leaderboards buttons, Play Games notice\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>')"
```

---

### Task 5: Docs, emulator check, spec notes

**Files:**
- Create: `docs/PLAY_GAMES.md`
- Modify: `CLAUDE.md`
- Modify: `docs/superpowers/specs/2026-10-16-play-games-sign-in-design.md` (planning findings)

**Interfaces:**
- Consumes: everything above.
- Produces: owner-facing setup checklist; CLAUDE.md rules for later pieces.

- [ ] **Step 1: Write `docs/PLAY_GAMES.md`**

```markdown
# Google Play Games Services

Android only and optional: the game plays the same without it. Builds without an app ID (and iOS) show no Play
Games buttons. Signed out, offline or without Google Play services the buttons stay, and a tap tries Google's
sign-in (on failure: a short footer notice).

## Local files (gitignored, keep copies in the password manager)

- `android/key.properties` — release upload key:
  ```
  storeFile=/absolute/path/to/upload-keystore.jks
  storePassword=...
  keyAlias=upload
  keyPassword=...
  ```
  Without it, release builds are signed with the debug key (Gradle warns) and cannot go to Play.
- `android/play_games.properties` — `playGamesAppId=<numeric app ID>` (or `-PplayGamesAppId=` in CI). Without
  it the build has Play Games switched off (init provider disabled, `playGamesConfigured` false).

## One-time Play Console setup

1. Upload key: `keytool -genkeypair -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000
   -alias upload`; keep the file outside the repo; fill `android/key.properties`.
2. Play Console → Create app (Brain Train, game, free). Build `flutter build appbundle` and upload it to
   Testing → Internal testing (this claims `com.sungamestudio.braintrain`; Play App Signing on).
3. Play Games Services → Setup and management → Configuration → create a new Games Services project.
4. Credentials → add an Android credential for `com.sungamestudio.braintrain` with SHA-1 of: the Play App
   Signing key (Setup → App integrity), the upload key (`keytool -list -v -keystore upload-keystore.jks`), and the
   debug key (`keytool -list -v -keystore ~/.android/debug.keystore -storepass android`).
5. Copy the Play Games app ID (the number under the project name) to `android/play_games.properties`.
6. Testers → add the Google accounts that test sign-in (only testers can sign in until the configuration is
   published).
7. Before publishing the configuration: at least 5 achievements (piece 2).

## Check on a device

AVD with Google Play (here `Pixel_9`, `google_apis_playstore`), signed in to a tester account:
`flutter run -d emulator-5554`. Expected: Google's sign-in banner at launch, two round buttons top-right in the
lobby that open Google's Achievements / Leaderboards; airplane mode → "Couldn't connect to Google Play Games"
in the footer, no crash. `adb logcat | grep -i "PlayGames\|games_services"` for errors (a SHA-1 or app ID
mismatch shows as a sign-in failure).
```

- [ ] **Step 2: Update `CLAUDE.md`**

Edit these places:

1. Commands block, after the `flutter run` line, add:
   ```
   flutter build appbundle                 # Play upload; needs android/key.properties (+ play_games.properties for Play Games)
   ```
2. Layout: after the `lib/app/` bullet's `sound_effects.dart`, add `` `play_games_controller.dart` (lobby Play Games state) ``; and add a new bullet:
   ```
   - `lib/platform/` — `play_games.dart` (`PlayGames` interface, statuses, `UnavailablePlayGames`, pure Dart);
     `games_services_play_games.dart` (the only file importing `games_services`; `createPlayGames()`).
   ```
3. "Rules that are easy to break": add a bullet:
   ```
   - Play Games (Android only, docs/PLAY_GAMES.md): optional and never on the startup path (a local channel check in
     `AppServices.create`; sign-in starts after the lobby's first frame). Only `games_services_play_games.dart`
     imports the plugin; every call is caught and timed out. The app ID comes from gitignored
     `android/play_games.properties`; without it `PlayGamesInitProvider` is disabled and Dart sees
     `UnavailablePlayGames`. Release signing reads gitignored `android/key.properties`. iOS min is 14.0 (plugin).
   ```
4. "Product decisions": add a bullet:
   ```
   - Google Play Games (owner, 2026-10-16): Android only; silent sign-in; two round lobby buttons top-right
     (Achievements, Leaderboards) open Google's screens, signing in first when needed; no Settings entry.
     Pieces: 1 sign-in (done), 2 achievements + leaderboards, 3 cloud save. Two phones on one account must never
     clash: piece 3 merges (union of wins, fastest time) before play; no hard one-device lock.
   ```
5. "Working on another machine": change the AVD sentence to mention `Pixel_9` (Play Store image) for Play Games
   checks, and add `android/key.properties` + `android/play_games.properties` + the upload keystore to the
   secrets line ("copy by a secure channel").
6. "Open work": add "Play Console setup (docs/PLAY_GAMES.md) and Play Games pieces 2–3".

- [ ] **Step 3: Note the planning findings in the spec**

In `docs/superpowers/specs/2026-10-16-play-games-sign-in-design.md`, replace the bullet that begins
`- The plugin does not call \`PlayGamesSdk.initialize\` itself.` with:

```markdown
- PGS v2 initialises itself through the library's `PlayGamesInitProvider`; no `PlayGamesSdk.initialize` call.
  Builds without an app ID disable that provider (`android:enabled="${playGamesEnabled}"`).
- The plugin reports every sign-in failure with one code; an empty message means the player dismissed the
  dialog (no notice), a message means a real failure (notice). Sign-in timeout is 2 min (it waits for the
  player); screen calls 10 s. iOS deployment target rises to 14.0 (plugin requirement).
```

- [ ] **Step 4: Final verification**

Run: `flutter analyze` → `No issues found!`
Run: `flutter test` → all pass.
Run: `flutter build apk --release` → builds (debug-key warning, Play Games off).
Run: `flutter run -d emulator-5554` on AVD `Pixel_9` → lobby as before, no Play Games buttons (this build has no
app ID), no crash in `adb logcat -d | grep FATAL`.

- [ ] **Step 5: Commit**

```bash
git add docs/PLAY_GAMES.md CLAUDE.md docs/superpowers/specs/2026-10-16-play-games-sign-in-design.md
git commit -m "$(printf 'Docs: Play Games setup checklist, CLAUDE.md rules\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>')"
```

---

## After the plan (owner, with Claude in the browser)

Play Console steps 2–6 of `docs/PLAY_GAMES.md` need the owner's Google developer account. Claude can drive them in
the owner's Chrome, pausing for confirmation before creating the app, uploading the first bundle, and publishing
anything. Then the on-device check with the real app ID closes piece 1.
