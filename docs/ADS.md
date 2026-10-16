# Rewarded ads (AdMob)

Revive on the Tray full card plays a Google AdMob **rewarded** ad; the tiles go back only once the reward is earned.
Revive stays unlimited. Since 1.1.0 (owner, 2026-10-17) an Undo, Hint or Shuffle with no use left can be refilled
the same way: a rewarded ad gives +1 of that action. Rewarded ads only, on Revive and on these refills: never
interstitials or banners. Restart never needs an ad. Android and iOS (`google_mobile_ads` 9.1.0, AdMob + Google's
User Messaging Platform, UMP).

## How it behaves

- **Age screen** (once, at first launch, after the logo and before the lobby; also once after updating from a
  version without it): "What year were you born?", picked as decade, then year, with nothing chosen in advance and
  no hint of what the answer is for. Only the derived group is stored, on the phone (SharedPreferences
  `privacy.ageGroup` = `under13` / `13plus`); the year is not kept and nothing is sent anywhere. Only the year is
  asked, so the year someone may still be 12 counts as under 13 (13+ means born at least 14 calendar years ago).
  To answer again: clear the app's data (this also clears progress) or reinstall.
- **Ad requests per group** (`lib/platform/google_mobile_ads_rewarded.dart`):
  - Under 13: `RequestConfiguration(tagForChildDirectedTreatment: yes, tagForUnderAgeOfConsent: yes,
    maxAdContentRating: G)` plus `ageRestrictedTreatment: child` (plugin 9.1.0 deprecates the two tags in favour
    of it; Google applies the most conservative setting when both are set), `AdRequest(nonPersonalizedAds: true)`,
    and UMP `ConsentRequestParameters(tagForUnderAgeOfConsent: true)`.
  - 13+: `maxAdContentRating: PG`, no age tags, the normal UMP flow (`tagForUnderAgeOfConsent: false`).
- **Never on the startup path.** The lobby starts ads after its first frame (like Play Games sign-in): request
  configuration → UMP `requestConsentInfoUpdate` → `loadAndShowConsentFormIfRequired` (a consent form appears over
  the lobby only where one is required, e.g. EEA/UK, until answered) → `canRequestAds` → on iOS, for 13+ only,
  the App Tracking Transparency prompt (below) → `MobileAds.initialize` → load one rewarded ad. Every call is caught and timed out. App measurement is delayed until the SDK starts
  (`DELAY_APP_MEASUREMENT_INIT` / `GADDelayAppMeasurementInit`).
- **Keeping an ad ready**: one ad is kept loaded. A game screen opening, the Tray full card or a refill card appearing and the app
  returning to the foreground each load one if none is (and retry at once after a failure); failures retry by
  themselves after 5 s, 10 s, 20 s, 30 s, then every minute. A new ad loads after each one shown.
- **Revive button** (Tray full card; also for a resumed saved game that was lost with a full tray):

  | Ad state | Revive | Note under it |
  |---|---|---|
  | loaded | on (video icon) | none; "Watch the ad to the end to revive." after an ad closed early |
  | loading / retrying (SDK start, consent, no fill, errors) | off | spinner + "Loading an ad…" |
  | offline (network error, or the network is unreachable) | off | "Connect to the internet to watch an ad and revive" |
  | on screen | off | none |

  Reward earned → the ad closes → the tray tiles fly back (after the app is in the foreground again). Ad closed
  early or failed to show → no revive, the card stays, Revive shows another ad once one is loaded.
- **Action refills** (1.1.0; Undo / Hint / Shuffle start each level with 3 / 3 / 1 uses): at 0 uses the button's
  badge shows a play mark; a tap opens a small card "Watch an ad for +1 Hint?" ("You have no hints left in this
  level.", Watch ad / Not now; the clock stops while it is open; Back closes it). The use is granted
  (`GameController.grant`, saved with the game) only once the ad closes with its reward earned and the app is in the
  foreground again; then the card closes and the clock runs again. Nothing else is asked of the player.

  | Ad state | Watch ad | Note under it |
  |---|---|---|
  | loaded | on (video icon) | none; "Watch the ad to the end to get +1 Hint." after an ad closed early |
  | loading / retrying | off | spinner + "Loading an ad…" |
  | offline | off | "Connect to the internet to watch an ad" |
  | on screen | off (Not now too) | none |

  Closed early or failed → no grant, the card stays. Off buttons (intro, tutorial, result cards, nothing to undo, …)
  never offer an ad. Age-group rules are the same as for Revive (child-directed for under 13).
- **While the ad is on screen**: the game clock is already stopped (a full tray, or the refill card, stops it) and stays stopped;
  background music is held (`BackgroundMusic.interrupted`; on Android the app also goes to the background) and
  sound effects are stopped; after the ad the game's audio context is applied again.
- **Privacy choices** (Settings): shown only when UMP's `getPrivacyOptionsRequirementStatus()` is `required`
  (EEA/UK users); opens Google's privacy options form, after which the next ad is requested under the new
  choices. Hidden everywhere else. This is the only addition to Settings (owner).
- **iOS App Tracking Transparency** (owner, 2026-10-17): 13+ players on iOS see Apple's prompt once per install
  ("Allow … to track your activity …"; text from `NSUserTrackingUsageDescription` in `Info.plist`), after consent
  and before the SDK starts (`AdsBackend.requestTracking` → channel `brain_train/platform`,
  `requestTrackingAuthorization` in `AppDelegate.swift`). Allowed: ads may use the IDFA (higher earnings).
  Denied or no answer: ads still play, without the IDFA. **Under-13 players are never asked** (their ads are never
  personalized), and the prompt is never shown again after an answer (iOS rule; the player can change it in
  Settings › Privacy › Tracking). If a UMP "IDFA explainer" message is published in AdMob, UMP shows its explainer
  and the system prompt itself during consent; the app's call then just reads the answer. Android has no such
  prompt.
- A build without the SDK (tests, desktop) has ads "off": Revive needs no ad there, and a refill is granted at once
  (no card; the badge shows "+").

## Where the IDs go

Google's test IDs are the defaults; they only ever show test ads:

| | Android | iOS |
|---|---|---|
| App ID | `ca-app-pub-3940256099942544~3347511713` | `ca-app-pub-3940256099942544~1458002511` |
| Rewarded unit | `ca-app-pub-3940256099942544/5224354917` | `ca-app-pub-3940256099942544/1712485313` |

- **Android**: `android/admob.properties` (gitignored, like `key.properties`; keep a copy in the password manager):
  ```
  admobAppId=ca-app-pub-XXXXXXXXXXXXXXXX~NNNNNNNNNN
  rewardedAdUnitId=ca-app-pub-XXXXXXXXXXXXXXXX/NNNNNNNNNN
  ```
  or `-PadmobAppId=… -PrewardedAdUnitId=…` in CI. Gradle checks the format, writes the app ID into the manifest
  (`com.google.android.gms.ads.APPLICATION_ID`) and the unit into a string resource that Dart reads through
  `MainActivity` (`brain_train/platform` → `rewardedAdUnitId`). A release build that still has a test ID prints
  `WARNING: AdMob TEST IDs in a release build …` (and a warning when the two IDs are from different accounts).
- **iOS**: `ios/Runner/Info.plist` — `GADApplicationIdentifier` (app ID) and `BrainTrainRewardedAdUnitId`
  (rewarded unit, read by Dart through `AppDelegate.swift`; Dart falls back to the test unit without it). These IDs
  are not secrets. The plist also holds Google's `SKAdNetworkItems` list (50 entries, from Google's iOS quick start
  in 2026-10; refresh it from there now and then). The iOS app has never been built: check the channel in
  `AppDelegate.swift` on the first Xcode build.

## Owner setup (once)

1. **AdMob account** at admob.google.com with the Sun Game Studio Google account; payments and tax info.
2. **Add the app**: Apps → Add app → Android, "published on a store" once the Play listing is live (link
   `com.sungamestudio.braintrain`); add iOS later the same way.
3. **Ad unit**: the app → Ad units → Add → **Rewarded**, name "Revive"; reward amount 1, item "revive" (the app
   ignores the amount). Copy the app ID and unit ID into `android/admob.properties` (and the iOS ones into
   Info.plist). Bump the build number and `flutter build appbundle`: the test-ID warning must be gone.
4. **Families / mixed audience** (Google Play Families policy; the audience includes children under 13):
   - AdMob → the app → App settings: answer the Families question ("designed for families" / child-directed
     setting) as mixed audience per the current AdMob help page. The app already tags every under-13 request as
     child-directed; do not set an app-wide child-directed tag unless the app becomes children-only.
   - Blocking controls: keep sensitive categories off; the app caps ratings at G (under 13) and PG (13+) per
     request; an account-level maximum of PG (or G) is a safe extra.
   - No mediation for now. If added later: only Google Play Families self-certified ad networks.
5. **Consent message** (EEA/UK): AdMob → Privacy & messaging → create and publish a GDPR message for the app
   (and, optionally, a US state regulations message). Without a published message UMP shows no form and EEA/UK
   ad serving is limited. Publish the privacy policy URL there and in Play Console.
6. **app-ads.txt**: on the developer website set in the Play Console store listing (sungamestudio.com), serve
   `https://sungamestudio.com/app-ads.txt` containing
   `google.com, pub-XXXXXXXXXXXXXXXX, DIRECT, f08c47fec0942fa0` (your publisher ID from AdMob → Settings). AdMob
   → Apps → app-ads.txt shows when it is found (can take a day).
7. **Play Console → App content**:
   - Ads: "Yes, my app contains ads".
   - Advertising ID: used for advertising (the AD_ID permission stays; the app never reads the ID itself;
     under-13 requests are tagged child-directed, which Google's SDK honours).
   - Target audience and content: include the under-13 age groups (mixed audience) → the Families policy
     applies (AdMob is a Families self-certified SDK; the neutral age screen is in place).
   - Data safety: add what the Google Mobile Ads SDK and UMP collect, following Google's "Google Mobile Ads SDK
     data disclosure" page (at the time of writing: device or other IDs, app interactions, diagnostics, approximate
     location from IP; collected and shared for advertising, analytics and fraud prevention; encrypted in transit).
     The app itself sends no age or personal data (the age group stays on the phone).
8. **iOS (later)**: App Store privacy labels from the same Google disclosure, declaring "Device ID … used to track
   you" (App Tracking Transparency is used for 13+). Do not put the app in the App Store Kids category: Kids-category
   apps may not use tracking or third-party ads like this.

## Testing

- Debug builds without `android/admob.properties` use the test IDs: ads carry a "Test Ad" label. Fill a tray →
  Tray full → Revive → watch to the end → the tiles fly back; close the ad early → no revive, the card stays;
  airplane mode → "Connect to the internet …", Revive off; back online → the ad loads within a minute (at once
  when a game opens or the app returns to the foreground). Music pauses during the ad and resumes after it.
- With real IDs never tap your own ads: add the phone in AdMob → Settings → Test devices, or run with
  `--dart-define=ADS_TEST_DEVICE_ID=<hashed id>` (from the logcat line "Use RequestConfiguration.Builder()
  .setTestDeviceIds(…)"; debug/profile builds only).
- Consent form and the Privacy choices row outside Europe:
  `flutter run --dart-define=UMP_TEST_DEVICE_ID=<hashed id> --dart-define=ADS_DEBUG_EEA=true` (the id from the
  UMP logcat line "Use new ConsentDebugSettings.Builder().addTestDeviceHashedId(…)"). Clear the app's data to see
  the consent form (and the age screen) again.
- Logs: `adb logcat | grep -i "Rewarded ads\|Ads\|UserMessagingPlatform"`.
- Tests (no SDK, no network): `test/platform/managed_rewarded_ads_test.dart` (flow, backoff, timeouts, privacy),
  `test/platform/google_mobile_ads_rewarded_test.dart` (request settings per age group),
  `test/features/revive_ad_test.dart`, `age_screen_test.dart`, `settings_privacy_test.dart`; captures of the age
  screen, the privacy row and the Tray full card per ad state in `test/visual/`.

## Code map

- `lib/platform/rewarded_ads.dart` — pure Dart: `RewardedAds`, `RewardedAdStatus`, `RewardedAdResult`,
  `AdAudience` (per age group), `UnavailableRewardedAds`.
- `lib/platform/managed_rewarded_ads.dart` — `ManagedRewardedAds` over an `AdsBackend`: start order, consent,
  one ad kept loaded, backoff, timeouts, privacy options.
- `lib/platform/google_mobile_ads_rewarded.dart` — the only file importing `google_mobile_ads`:
  `GoogleMobileAdsBackend`, request settings per audience, `createRewardedAds()`.
- `lib/app/rewarded_ads_controller.dart` — `RewardedAdsController` (`AppServices.ads`): started by the lobby,
  reloads on app resume, holds music and sound effects around `show()`.
- `lib/data/age_group.dart`, `lib/features/intro/age_screen.dart`, the gate in `lib/app/app.dart`.
- `lib/features/gameplay/game_screen.dart` — `_revive` and the Tray full card; `lib/features/settings/` — the
  Privacy choices row.
