# Analytics (Google Analytics for Firebase)

Owner, 2026-10-24: see how many players are playing right now, and how levels go. Every player is counted
(under 13 too), minimally: no advertising ID, no ad storage or personalization, never the age group, and in the
EEA/UK no analytics identifier either. Shipped in iOS 1.2.1; Android gets it with its first store release.

## Where it lives

- `lib/platform/analytics.dart`: the `Analytics` interface and `UnavailableAnalytics` (pure Dart).
- `lib/platform/firebase_app_analytics.dart`: the only file that imports `firebase_core` / `firebase_analytics`;
  `createAnalytics()` (Android and iOS). `Firebase.initializeApp()` reads the native config files; without them it
  fails quietly and nothing is sent. Every call is caught and timed out.
- `lib/app/analytics_controller.dart`: `AppServices.analytics`. The event names and parameters, the consent
  decision, a queue (20) for what is logged before it starts.
- Started by the lobby after its first frame (`home_screen.dart`), never on the startup path.
- Native flags keep Firebase off at launch, with every consent type denied, until the controller has set the
  consent and turned collection on (`setAnalyticsCollectionEnabled(true)` persists, the consent too):
  - iOS `ios/Runner/Info.plist`: `FIREBASE_ANALYTICS_COLLECTION_ENABLED`, `FirebaseAutomaticScreenReportingEnabled`,
    `GOOGLE_ANALYTICS_ADID_COLLECTION_ENABLED`, `GOOGLE_ANALYTICS_IDFV_COLLECTION_ENABLED`,
    `GOOGLE_ANALYTICS_REGISTRATION_WITH_AD_NETWORK_ENABLED` and the four `GOOGLE_ANALYTICS_DEFAULT_ALLOW_*`, all
    false.
  - Android `AndroidManifest.xml` meta-data: `firebase_analytics_collection_enabled`,
    `google_analytics_automatic_screen_reporting_enabled`, `google_analytics_adid_collection_enabled`,
    `google_analytics_ssaid_collection_enabled` and the four `google_analytics_default_allow_*`, all false.

## Consent

- Ad storage, ad user data and ad personalization: always denied.
- Analytics storage (the app instance ID): granted, except where privacy choices are required (EEA/UK, the same
  answer that shows Settings → Privacy choices: `RewardedAdsController.privacyRegion`, from Google's UMP consent
  check). The answer is kept in `privacy.consentRegion` (`SettingsRepository.privacyRegion`) for later launches.
- First launch (no answer kept yet): the controller waits for the consent check, at most 10 s, then starts
  without the identifier and grants it once the check says the player is outside the EEA/UK.
- Builds without ads (tests): no consent check, so granted.

## Events

Every game event carries `level` (the level number) and `difficulty` (the string from the manifest, "1".."10").

| Event | Extra parameters | When |
|---|---|---|
| `level_start` | `resumed` 1/0 | A game screen opens (new or a saved game) |
| `level_end` | `success` 1/0, `score`, `seconds`, `pairs` | Won (`onWin`, replays too), or lost with a full tray |
| `level_restart` | | Restart (action bar, Pause, Tray full card, Replay) |
| `revive` | `ad` 1/0 | A revive paid out (after an ad, or free) |
| `action_used` | `action` undo/hint/shuffle | An Undo, Hint or Shuffle was used |
| `action_refill` | `action`, `ad` 1/0 | +1 Undo/Hint/Shuffle paid out (after an ad, or free) |
| `screen_view` | `screen_name` lobby/levels/settings/game | The lobby comes up (and back), Levels, Settings, a game |

Firebase adds `first_open`, `session_start`, `user_engagement` and `app_update` by itself. To break reports down
by level or difficulty, register `level`, `difficulty`, `success` and `action` as event-scoped custom dimensions
(Firebase console → Analytics → Custom definitions). Never add the age group or anything that identifies a player.

## Firebase project

Project "Tile Park", ID `tile-park-6853a` (number 973411839288), in the Firebase console of
contact@sungamestudio.com (`console.firebase.google.com/u/1/` on the owner's Mac), Spark plan (no cost), created
2026-10-25; Google Analytics on, in that account's "Default Account for Firebase"; Gemini in Firebase off.

- iOS app "Tile Park iOS": bundle ID `com.sungamestudio.braintrain`, App Store ID `6823729570`, app ID
  `1:973411839288:ios:580c0542d2dab4006ae5cd`; its `GoogleService-Info.plist` is in `ios/Runner/` and in the Runner
  target's resources (`project.pbxproj`).
- Android app "Tile Park Android": package `com.sungamestudio.braintrain`, app ID
  `1:973411839288:android:a98a7f78f22c41ca6ae5cd`; its `google-services.json` is in `android/app/` (Gradle applies the
  google-services plugin only when that file exists).
- Both files are committed (they identify the project; they are not secrets, and the apps carry them anyway).
- Google Analytics → Admin → Data collection and modification: Data retention 2 months (the privacy policy says so;
  the default) and Google signals off (the default). Keep them so.
- Checked 2026-10-25 on the iPhone 17 Pro simulator: collection off at launch, on after the lobby's first frame;
  DebugView got `screen_view` and `user_engagement` with `non_personalized_ads = 1`; the SDK logged "IDFA will not be
  accessible" and "Ad storage consent is denied".

## Seeing it

- Who plays now: Firebase console → Analytics → Realtime (or analytics.google.com → Reports → Realtime): active
  users in the last 30 minutes, per minute, by country, with the events coming in. The SDK sends events in
  batches (when the app goes to the background, and every so often while it runs), so "now" means within a minute
  or a few.
- Everything else (daily players, retention, level funnels): Reports and Explore in Google Analytics; daily
  reports take up to 24 h.
- Testing a build: DebugView (Firebase console → Analytics → DebugView) shows one device's events within seconds.
  - iOS: in Xcode, Product → Scheme → Edit Scheme → Run → Arguments, add `-FIRDebugEnabled`, then run from Xcode
    (remove it, or add `-FIRDebugDisabled`, afterwards).
  - Android: `adb shell setprop debug.firebase.analytics.app com.sungamestudio.braintrain`, then start the app
    (`adb shell setprop debug.firebase.analytics.app .none.` to stop).

## Store declarations

Google maps Analytics data to these sources
([support article](https://support.google.com/analytics/answer/10285841)): the app instance ID, app activity
(screens, sessions, events) and a general location derived from the masked IP address. No advertising ID (turned
off, and denied as ad storage), no IDFV, no Apple location services.

- App Store Connect → App Privacy: the existing answers already list Device ID, Product Interaction, Coarse
  Location and Other Diagnostic Data with the Analytics purpose (for the ads SDK), not linked to the user. Check
  them at each release that changes analytics; Analytics data is never used for tracking.
- Play Console → Data safety (first Android release): App activity → App interactions, and Device or other IDs,
  for Analytics, collected, not shared, not linked to an account.
- Privacy policy: `website/brain-train/privacy/index.html` section 5 (deploy it to sungamestudio.com).
