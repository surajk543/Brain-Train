# Google Play Games Services and Game Center

Google Play Games on Android, Apple Game Center on iOS (both through the `games_services` plugin), optional: the
game plays the same without them. Android builds without an app ID show no Play Games buttons. Signed out, offline
or without Google Play services the buttons stay, and a tap tries the sign-in (on failure: a short footer notice,
"Couldn't connect to Google Play Games" / "Couldn't connect to Game Center").

13+ only (Play Families policy): for a player under 13 (or before the age screen is answered) neither service is
ever started, nobody is signed in and the lobby shows no buttons. Never on the startup path: the lobby starts the
sign-in after its first frame.

Pieces: 1 sign-in (done), 2 achievements + leaderboards (done, 2026-10-17), 3 cloud save.

## Achievements and leaderboards (piece 2)

Every ID is in `lib/platform/game_services_ids.dart` (`GameAchievement`, `GameLeaderboard`: the Play Games ID and
the Game Center ID of each). Game Center IDs are `bt.ach.<key>` and `bt.lb.<key>`.

| Achievement | Key | Earned by |
|---|---|---|
| First Match | `first_win` | 1 level won |
| Getting Started | `levels_10` | 10 levels won |
| Tile Collector | `levels_50` | 50 levels won |
| Centurion | `levels_100` | 100 levels won |
| Garden Keeper | `levels_250` | 250 levels won |
| Grand Master | `levels_500` | 500 levels won |
| Combo Master | `combo_5` | a best combo of x5 or more |
| Summit | `summit` | a level of difficulty 10 won |
| Pure Skill | `pure_skill` | a level of difficulty 7+ won without Hint, Undo or Shuffle |

| Leaderboard | Key | Value |
|---|---|---|
| Total Score | `total_score` | sum of the best scores of all won levels |
| Levels Completed | `levels` | number of won levels |
| Best Combo | `best_combo` | longest combo of any record |
| Best Score · Difficulty N | `score_d1` .. `score_d10` | a game's score (higher is better) |
| Fastest Time · Difficulty N | `time_d1` .. `time_d10` | a game's time (lower is better) |

Times: Play Games' format is Duration, so the app sends milliseconds; Game Center's is "Elapsed Time - To the
Hundredth of a Second", so the app sends hundredths (ms ~/ 10). `leaderboardTime` picks per platform.

What is reported (`lib/app/play_games_reports.dart`, sent by `PlayGamesController`; fire and forget, one call at a
time, every call caught and timed out, never blocking the win card):

- **Every win** (replays too), when a 13+ player is signed in, once the record is saved (`GameController.onWin`
  -> `PlayGamesController.reportWin`): Best Score and Fastest Time of the level's difficulty (none for a named or
  unknown tier), Total Score, Levels Completed, Best Combo, and the achievements earned (level counts, Combo Master;
  Summit for a difficulty-10 win; Pure Skill for a difficulty 7+ win with no Hint, Undo or Shuffle used).
- **Catch-up**, once per app run at the first successful sign-in (silent or from a lobby button): what the stored
  progress already earned. Per difficulty the best score and fastest time over its won levels (the manifest's
  difficulty per level id), the three totals, the level-count achievements, Combo Master, and Summit if a
  difficulty-10 level was won. Pure Skill needs a game's helper uses, which records do not keep: wins only.
- Each achievement is sent at most once per app run (Game Center would show its banner again); the catch-up
  unlocks without Game Center banners (most were unlocked before), wins with them. A failed unlock is tried again by
  the next win. Not signed in at a win: nothing is queued; the next run's catch-up sends the scores.

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
- `android/admob.properties` — AdMob app ID and rewarded ad unit (docs/ADS.md). Without it the build uses
  Google's test IDs (a release build warns).

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
7. Achievements (9) and leaderboards (23) are created (2026-10-17; IDs above, Fastest Time boards: Duration,
   smallest first). The configuration is published (2026-10-17), so every player sees them.

## Game Center (iOS)

- The Runner target has the Game Center entitlement (`ios/Runner/Runner.entitlements`,
  `com.apple.developer.game-center`, `CODE_SIGN_ENTITLEMENTS` in Debug, Release and Profile). GameKit needs nothing in
  `Info.plist` (no `UIRequiredDeviceCapabilities` entry: that would only limit the devices).
- Sign-in: after the lobby's first frame (13+ only) the app asks GameKit to authenticate (`GameAuth.signIn`):
  Apple's "Welcome back" banner when the device is signed in to Game Center, else Apple's sign-in sheet; GameKit
  offers it at most once per launch, and after a player dismisses it the lobby buttons show the footer notice (sign
  in from the device's Settings). The buttons open Game Center's Achievements / Leaderboards.
- App Store Connect: the app's Game Center achievements (`bt.ach.*`) and leaderboards (`bt.lb.*`, Classic; Best
  Score: Integer, high to low; Fastest Time: Elapsed Time - To the Hundredth of a Second, low to high; Total Score,
  Levels Completed, Best Combo: Integer, high to low), then on the version page turn Game Center on and add them to
  the version so App Review sees them. Test with a sandbox Game Center account on a device or simulator.

## Check on a device

AVD with Google Play (here `Pixel_9`, `google_apis_playstore`), signed in to a tester account:
`flutter run -d emulator-5554`. Expected: Google's sign-in banner at launch, two round buttons top-right in the
lobby that open Google's Achievements / Leaderboards; airplane mode → "Couldn't connect to Google Play Games"
in the footer, no crash. `adb logcat | grep -i "PlayGames\|games_services"` for errors (a SHA-1 or app ID
mismatch shows as a sign-in failure). After a win: First Match unlocks (a Play Games popup) and the scores show on
the leaderboards.
