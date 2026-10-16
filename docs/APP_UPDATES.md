# App updates: lobby update card and force update

The lobby tells players about a new app version, and can require one (owner, 2026-10-16). It reads a small
mutable JSON notice on the content host, compares it with the installed build number and shows one of two cards:

| Installed build | Card | Buttons | Dismiss |
|---|---|---|---|
| `>= latest` | none | | |
| `>= min` and `< latest` | **Update available**: "A new version of Brain Train is ready." | Update (gold), Later | Later or Android back: hidden until the next app launch; Update also hides it |
| `< min` | **Update required**: "This version of Brain Train is no longer supported. Please update to keep playing." | Update | nothing: no Later, the scrim takes every tap, Android back does nothing |

A platform block's optional `message` replaces the body text. The cards show only in the lobby (never over a game,
Completed Levels or Settings: they appear when the player is back in the lobby). While the required card is up,
Play / Continue, Completed Levels, Settings and the Play Games buttons cannot be reached; coming back from the store
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

## Announce an update

1. Ship the new build on Google Play (and let it go through review and roll out).
2. **Only once it is live on Play**, set `android.latestVersionCode` to the new `versionCode`.
3. Publish the notice (below).

Caveat: raise `latestVersionCode` only after the build is live for everyone. Before that (in review, staged
rollout), players see "Update available", but Google Play has nothing to install for them: the in-app update is not
offered, the store page opens and shows "Open" instead of "Update".

## Force an update

Raise `android.minVersionCode` (`ios.minBuild`) above the builds that must go: every build below it gets the
blocking card. Same caveat: raise it only once the replacement build is live on Play, or players are locked out with
nothing to update to. To lift a force update, lower `minVersionCode` again and publish.

## Publish

`tool/publish.dart` uploads `content-src/app-update.json` to `brain-train/app-update.json` (a mutable key like
`manifest.json`, short cache; wired by a separate change). Edit the file, commit, publish, then check
`https://braintrain-assets.surajk543.workers.dev/brain-train/app-update.json`. It needs no `contentVersion` bump of
its own.

The Worker (`infra/cloudflare/braintrain-assets/worker.js`) must list `brain-train/app-update.json` in
`MUTABLE_PUBLIC_KEYS`; otherwise it is served `immutable` like level files. (The app's HTTP client keeps no cache, so
the app still sees changes, but proxies and browsers may not.)

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
