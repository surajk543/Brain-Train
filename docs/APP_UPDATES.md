# App updates: lobby update card and force update

The lobby tells players about a new app version, and can require one (owner, 2026-10-16). It reads a small
mutable JSON notice on the content host, compares it with the installed build number and shows one of two cards:

| Installed build | Card | Buttons | Dismiss |
|---|---|---|---|
| `>= latest` | none | | |
| `>= min` and `< latest` | **Update available**: "A new version of Brain Train is ready." | Update (gold), Later | Later or Android back: hidden until the next app launch; Update also hides it |
| `< min` | **Update required**: "This version of Brain Train is no longer supported. Please update to keep playing." | Update | nothing: no Later, the scrim takes every tap, Android back does nothing |

A platform block's optional `message` replaces the body text. The cards show only in the lobby (never over a game,
Levels or Settings: they appear when the player is back in the lobby). While the required card is up,
Play / Continue, Levels, Settings and the Play Games buttons cannot be reached; coming back from the store
without updating, the card is still there.

## The notice

Source: `content-src/app-update.json`. Published key: `brain-train/app-update.json`, next to `manifest.json`
(the app fetches it relative to the content base URL, `ContentConfig.production`, through the content client:
host allow-list, size cap, retries).

```json
{
  "schemaVersion": 1,
  "android": {
    "latestVersionCode": 4,
    "minVersionCode": 1,
    "storeUrl": "https://play.google.com/store/apps/details?id=com.sungamestudio.braintrain"
  },
  "ios": { "latestBuild": 0, "minBuild": 0, "storeUrl": "" }
}
```

- Build numbers are the `+N` of the pubspec version: Android `versionCode`, iOS `CFBundleVersion` (must be a plain
  integer; anything else = no card).
- `storeUrl`: `https` only (anything else is dropped). The optional card needs one (iOS with an empty `storeUrl`
  never shows it); the required card shows without one (its Update button then can only try Google Play on Android,
  else says "Couldn't open the store").
- `message` (optional, per platform, at most 400 characters): shown instead of the default body text.
- Unknown fields are ignored. A malformed platform block counts as missing (no card on that platform).
- `schemaVersion`: this build understands `1` only; a file with another value is ignored (no card). Bump it only for
  an incompatible change, and remember older builds then stop reading the notice, so they can no longer be forced.

## Step by step: tell players to update

Follow these steps in order. Steps 1 and 2 are the same for an optional and a forced update.

1. **Release the new build.** Bump the version in `pubspec.yaml` (for example `1.0.1+6`; the number after `+` is
   the `versionCode`), run `flutter build appbundle`, upload it on Google Play, and wait until the release is
   **live for everyone** (review passed, rollout at 100%). Never do step 2 before that: players would be sent to a
   store page with nothing to install, and a forced player could not play at all.
2. **Edit `content-src/app-update.json`.**
   - Optional update ("Update available", with Later): set `latestVersionCode` to the new `versionCode`, keep
     `minVersionCode` lower.
   - Forced update ("Update required", no way around it): set **both** `latestVersionCode` and `minVersionCode` to
     the new `versionCode` (every older build is blocked in the lobby).
   - Optional `message`: your own text for the card (at most 400 characters).

   Example, forcing everyone onto versionCode 6:

   ```json
   {
     "schemaVersion": 1,
     "android": {
       "latestVersionCode": 6,
       "minVersionCode": 6,
       "storeUrl": "https://play.google.com/store/apps/details?id=com.sungamestudio.braintrain",
       "message": "A new version is ready with important fixes. Please update to keep playing."
     },
     "ios": { "latestBuild": 0, "minBuild": 0, "storeUrl": "" }
   }
   ```

3. **Publish the notice** (needs `.env`; only uploads this one file, no content rebuild, no `contentVersion` bump):

   ```bash
   dart run tool/publish.dart --app-update-only --dry-run   # check: "would put brain-train/app-update.json"
   dart run tool/publish.dart --app-update-only             # upload
   curl -s https://braintrain-cdn.sungamestudio.com/brain-train/app-update.json   # see what players get
   ```

   The file is cached for at most 60 s, so within about a minute every player on an older build sees the card the
   next time the lobby opens or the app comes back to the foreground.
4. **Commit and push** the edited file, so the repo matches what is live:

   ```bash
   git checkout -b chore/app-update-6
   git add content-src/app-update.json
   git commit -m "App update notice: latest 6, min 6 (force)"
   git push -u origin chore/app-update-6
   gh pr create --fill
   ```

To lift a forced update, lower `minVersionCode` again and repeat steps 3 and 4. A full content publish
(`dart run tool/publish.dart`) also uploads the notice, after the manifest.

Only builds that contain this feature (versionCode 5 and later) read the notice. Builds 1–4 never show a card.

## Notes on the fields

- Raising `latestVersionCode` before the build is live (still in review, staged rollout): players see "Update
  available", but Google Play has nothing to install for them, so the in-app update is not offered and the store page
  shows "Open" instead of "Update".
- `minVersionCode` (`ios.minBuild`) blocks every build below it. Players are locked out until they update, also
  offline (the app keeps the last notice it saw).
- The notice is served from `https://braintrain-cdn.sungamestudio.com/brain-train/app-update.json` (bucket
  `braintrain-public`, `Cache-Control: public, max-age=60, must-revalidate`, set by `tool/publish.dart`).

## How the app checks

- Never on the startup path: the lobby starts the check after its first frame (like Play Games and ads), and again
  each time the app comes back to the foreground.
- First the notice kept on the device (`SharedPreferences` key `appUpdate.notice.v1`, the last good one) applies at
  once, so a required update holds offline. Then the current notice is fetched (5 s timeout, every failure caught):
  - found and valid: used and kept on the device;
  - HTTP 404 (no notice on the host): no card, the kept copy is forgotten;
  - malformed, unsupported schema, too large: ignored, the last good copy stays;
  - offline, timeout, server error: the last good copy stays.
- "Update" on Android: Google Play In-App Updates (`in_app_update`), immediate flow, when Play has an update for this
  install; Play declined → nothing else (the required card stays). Play unavailable (sideloaded or debug build,
  emulator without Play, no update known to Play yet, an error) → the store page: `market://details?id=…` in the Play
  Store app, else the https page (MainActivity, channel `brain_train/platform`, method `openUrl`). iOS: the `storeUrl`
  (AppDelegate, same channel).

## Code

- `lib/content/app_update_config.dart` — pure Dart: notice parsing (`AppUpdateConfig`), the decision
  (`decideAppUpdate` → none / optional / required) and the fetch (`AppUpdateConfigService`).
- `lib/data/app_update_cache.dart` — the kept notice.
- `lib/app/app_update_controller.dart` — `AppServices.updates`: check, cache, Later, Update.
- `lib/platform/app_updates.dart` — `AppUpdater` interface, `UnavailableAppUpdater` (tests, desktop), store links.
- `lib/platform/play_in_app_update.dart` — the only file importing `in_app_update`; build number via
  `package_info_plus`; `createAppUpdater()`.
- `lib/features/home/widgets/lobby_update_card.dart` — the cards (premium panel, gold border, serif title).

## Check on a device

The in-app update flow only runs for a build installed from Google Play (internal testing works: install an older
`versionCode` from the testing track, then promote a newer one). A debug build or an emulator without Play falls back
to the store page. To see the cards without publishing, run the widget tests
(`CAPTURE_DIR=/tmp/x flutter test test/features/lobby_update_test.dart` writes screenshots).
