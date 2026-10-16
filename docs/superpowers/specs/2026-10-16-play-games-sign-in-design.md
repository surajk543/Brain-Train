# Google Play Games Services — piece 1: sign-in and setup

Date: 2026-10-16 · Branch: `feat/play-games` · Status: spec approved by the owner (2026-10-16)

## Goal

Brain Train gets Google Play Games Services (PGS) on Android: sign-in, achievements, leaderboards and cloud save.
The work is split into three pieces, each with its own spec → plan → implementation:

1. **Sign-in and setup (this spec).** Plugin, Android build config, release signing, silent sign-in, lobby icons
   that open Google's Achievements / Leaderboards screens, and the `PlayGames` interface pieces 2 and 3 build on.
2. Achievements and leaderboards: unlocks and scores from wins (hooked after `ProgressRepository.recordWin`).
3. Cloud save: Saved Games snapshot of progress, load → merge → save. Also carries the owner's
   **two-phones rule** (below).

### What the owner decided

- All four features (sign-in, achievements, leaderboards, cloud save), in the order above.
- **Android only.** iOS shows nothing new and behaves exactly as today. Game Center may be a later project.
- **Silent sign-in + two lobby icons** (Achievements, Leaderboards). Signed out, a tap asks to sign in first.
- **Settings does not change** (still only Sound, Vibration, app version).
- The app is **not in Play Console yet**: the console steps are part of this work (checklist below).
- Wrapper: the `games_services` Flutter package behind our own interface (not a hand-written Kotlin bridge).
- **Two phones, one account (owner, 2026-10-16): progress must never clash.** The owner's aim is that two phones
  signed into the same Google account never overwrite each other's progress — not to stop account sharing. So
  this is handled in piece 3 with no server and no lock:
  - The snapshot records which device saved last and when. On launch, on resume and before a game starts, a
    signed-in phone pulls the snapshot first; if another device played since this phone's last sync, it merges
    that progress before play and shows "Continued from your other device".
  - Merge never loses a win: union of completed levels, fastest time per level (with that time's date).
  - The in-progress game stays per phone. If the other phone has since won the level this phone was in the middle
    of, the local save of it is dropped and Continue moves on to the next level.
  - Not a hard "one phone at a time" lock: Play Games cannot see another device's session, and a lock would need a
    Worker-side session service plus Google auth codes, and would break offline play. Rejected by the owner in
    favour of the merge.

### Success criteria (piece 1)

- On a phone signed into a Play Games tester account, with the console set up: the player is signed in at launch
  with no prompt from us (Google's own banner only), and both lobby icons open Google's screens.
- Signed out: tapping an icon shows Google's sign-in; on success the screen opens.
- Without PGS (iOS, a build without an app ID, no Google Play services, offline, sign-in failed): the game behaves
  exactly as today; the icons are hidden when PGS is unavailable; nothing crashes; startup never waits on PGS.

## Package

`games_services` 5.3.0 (published 2026-08-02; requires Dart ^3.12.0, Flutter >=3.44.0 — the repo is on
3.44.7 / 3.12.2). Android side uses `com.google.android.gms:play-services-games-v2:21.0.0`.

Relevant API: `GameAuth.player` (stream; on listen it checks `GamesSignInClient.isAuthenticated`, i.e. the result
of PGS v2's automatic sign-in at launch), `GameAuth.signIn()` (interactive), `Achievements.showAchievements()`,
`Leaderboards.showLeaderboards()`, plus `Achievements.unlock/increment/setSteps`, `Leaderboards.submitScore`,
`SaveGame.saveGame/loadGame` for pieces 2–3.

Known limits, accepted:
- Saved games open with `RESOLUTION_POLICY_MOST_RECENTLY_MODIFIED` (no custom conflict callback). Piece 3 will
  always load → merge → save; the merge is monotonic (union of completed levels, fastest time per level), so a
  lost concurrent write is re-merged by the other device's next sync. Piece 3's spec revisits this.
- The plugin does not call `PlayGamesSdk.initialize` itself. The plan must verify whether v2 21.0.0 needs an
  explicit `PlayGamesSdk.initialize(context)` (in `MainActivity`/an `Application`) and add it if so — only when
  an app ID is configured.

## Section 1 — Components

### `lib/platform/play_games.dart` (new)

Abstract `PlayGames`, the only PGS type the app depends on:

```dart
sealed class PlayGamesStatus { … }   // Unavailable, SignedOut, SignedIn(displayName)

abstract class PlayGames {
  Stream<PlayGamesStatus> get status;   // replays the latest value to new listeners
  PlayGamesStatus get current;
  Future<void> refresh();               // re-check silent sign-in (on resume)
  Future<bool> signIn();                // interactive; true when signed in afterwards
  Future<bool> showAchievements();      // false if it could not open
  Future<bool> showLeaderboards();
  void dispose();
}
```

Pieces 2 and 3 will add `unlock`, `increment`, `submitScore`, `saveSnapshot`, `loadSnapshot` to this interface;
piece 1 does not declare them (no dead API).

- `UnavailablePlayGames`: always `Unavailable`, every call is a no-op returning false. Used on iOS, in tests that
  do not care, and on Android builds without an app ID.
- `GamesServicesPlayGames` (`lib/platform/games_services_play_games.dart`): the **only** file that imports
  `games_services`. Wraps every call (see Section 2).

`lib/platform/` is new; it holds platform integrations that are not content, rendering or features. Pure Dart
except the `games_services` file.

### `PlayGamesController` (in `lib/app/`, next to `ContentController`)

A `ChangeNotifier` + `WidgetsBindingObserver`, built and owned by `AppServices`, exposed through `AppScope` like
the other services. Holds the `PlayGames`, the latest status, a `busy` flag and a transient `notice` string. It:
- subscribes to `status` after the lobby is shown (never before; startup does not wait);
- calls `refresh()` on `AppLifecycleState.resumed` (same pattern as `ContentController`);
- implements `openAchievements()` / `openLeaderboards()` (Section 2).

`AppServices` picks the implementation: Android **and** `playGamesConfigured` (below) → `GamesServicesPlayGames`;
otherwise `UnavailablePlayGames`. Tests inject a fake.

### Lobby

Two small icon buttons in the lobby (trophy = Achievements, podium = Leaderboards), styled like the existing lobby
chrome (dark-green glass, fine gold border; `FrostedGlass`/`StaticLayer` rules from CLAUDE.md apply — no
`BackdropFilter`, no opacity layers). Exact placement is decided in the plan against the visual captures; they
must not change the menu (Play/Continue, Completed Levels, Settings). Hidden while the status is `Unavailable`.
Semantics labels "Achievements" / "Leaderboards".

### Android build

- `android/play_games.properties` (gitignored) with `playGamesAppId=<number>`. CI may pass the Gradle property
  `playGamesAppId` instead.
- `android/app/build.gradle.kts`: when the ID is set, adds `resValue("string", "play_games_app_id", id)` and a
  manifest placeholder; `AndroidManifest.xml` gets the
  `com.google.android.gms.games.APP_ID` meta-data **only in that case** (via a manifest placeholder / an
  overlay manifest, chosen in the plan). Without an ID nothing PGS-related is in the manifest.
- `MainActivity.kt`: a `MethodChannel("brain_train/platform")` answering `playGamesConfigured` (true when the
  manifest meta-data is present and non-empty). The only native code we write (~15 lines).
- Release signing: read `android/key.properties` (gitignored: `storeFile`, `storePassword`, `keyAlias`,
  `keyPassword`). If present, release builds use it; if absent, they fall back to the debug key and Gradle prints
  a warning (a fresh clone still builds).
- `.gitignore`: add `android/key.properties`, `android/play_games.properties`, `*.jks`, `*.keystore`.

## Section 2 — Data flow and error handling

### Startup

The launch sequence is unchanged (navy native screen → studio video → logo → lobby). PGS v2 signs the player in
on its own at app launch (Google shows its own "Welcome back" banner the first time). When the lobby appears,
`PlayGamesController` starts listening: player present → `SignedIn(name)`; absent or error → `SignedOut`. On
resume it calls `refresh()` (catches a sign-in done in the Play Games app meanwhile).

### Icon tap

- Signed in → open Google's screen.
- Signed out → `signIn()`. Success → open the screen. Cancelled → nothing. Other failure → transient notice
  "Couldn't connect to Google Play Games" in the lobby footer slot (same text style as `LobbyContentFooter`,
  shown ~4 s, then gone; content notices keep their own logic).
- While a call is running (`busy`), further taps are ignored — no stacked sign-in dialogs.

### Failure containment

`GamesServicesPlayGames` catches every `PlatformException` and other error, applies a 10 s timeout to each call,
logs with `debugPrint`, and maps the outcome to a status or a `false` return. Nothing PGS-related can throw into
the UI, block startup, or touch gameplay. Piece 1 stores no PGS state on the device and changes no win, save or
progress code.

### Hooks for later pieces (not built now)

- Piece 2: after `recordWin` succeeds, a `PlayGamesSync` turns the win into unlocks/scores, queued on the device
  while signed out or offline and flushed on sign-in.
- Piece 3: snapshot load → merge → save on sign-in, on launch/resume, before a game starts and after wins
  (the two-phones rule above).

## Section 3 — Testing and checklist

### Automated (no device, no network)

- `FakePlayGames` (controllable status stream, records calls, scripted results).
- Widget tests (lobby + `PlayGamesController`): icons hidden on `Unavailable`, shown on `SignedOut`/`SignedIn`;
  tap signed in → `showAchievements`/`showLeaderboards`; tap signed out → `signIn` then show; cancel → nothing;
  failure → notice appears and clears; double tap → one call; resume → `refresh`.
- `GamesServicesPlayGames` unit tests against a mocked `games_services` method/event channel: errors and
  timeouts become `SignedOut` / `false`, never exceptions.
- `test/visual/` capture includes the lobby with icons at phone sizes.
- `flutter analyze` clean, `flutter test` green.

### Build checks

- `flutter build apk --release` with neither properties file: builds; merged manifest has no PGS meta-data;
  debug-key warning printed.
- With both files: meta-data and `play_games_app_id` present; APK signed with the upload key
  (`apksigner verify --print-certs`).

### On a device (after the console steps)

Emulator image **with Google Play Store** (check `Pixel_6_API_34`; create a Play Store image if it is a Google
APIs image), signed into the tester account. Verify: silent sign-in + Google banner; both icons open Google's
screens; signed-out tap → sign-in → screen; airplane mode → notice, no crash; iOS simulator shows no icons.

### Play Console checklist (goes into new `docs/PLAY_GAMES.md`)

1. Create an upload keystore (`keytool -genkeypair -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048
   -validity 10000 -alias upload`), fill `android/key.properties`. Back up keystore + passwords in the password
   manager (never git/chat/email).
2. Play Console: create the app (game, free); upload a first AAB (`flutter build appbundle`) to **Internal
   testing** — this claims `com.sungamestudio.braintrain`.
3. Play Games Services → Setup and management → Configuration → create a new Games Services project.
4. Credentials → Android credential for the package with SHA-1 of **all three** keys: the Play App Signing key
   (App integrity page; store installs), the upload key, and the debug key (`flutter run`).
5. Copy the PGS app ID (numeric) into `android/play_games.properties`.
6. Add the owner's Google account as a PGS tester (until the PGS configuration is published, only testers can sign
   in).
7. Piece 2 note: PGS needs at least 5 achievements before its configuration can be published.

## Out of scope

Achievements, leaderboards and cloud-save logic (pieces 2–3); iOS / Game Center; any Settings change; a sign-out
button (Google's own screens handle the account); Firebase or any backend.

## Docs to update when done

- `CLAUDE.md`: layout (`lib/platform/`, `PlayGamesController`), commands (release build with the properties
  files), a "Play Games" rule block (Android only, optional, never on the startup path, only
  `games_services_play_games.dart` imports the plugin, the properties files and keystore are gitignored), the
  owner decisions above, and the open work (pieces 2–3, console steps).
- `docs/PLAY_GAMES.md`: the checklist above plus how to verify on a device.
