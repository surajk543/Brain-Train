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
7. Before publishing the configuration: at least 5 achievements (piece 2).

## Check on a device

AVD with Google Play (here `Pixel_9`, `google_apis_playstore`), signed in to a tester account:
`flutter run -d emulator-5554`. Expected: Google's sign-in banner at launch, two round buttons top-right in the
lobby that open Google's Achievements / Leaderboards; airplane mode → "Couldn't connect to Google Play Games"
in the footer, no crash. `adb logcat | grep -i "PlayGames\|games_services"` for errors (a SHA-1 or app ID
mismatch shows as a sign-in failure).
