# Brain Train — notes for Claude

Flutter Mahjong Solitaire game. Android + iOS. App ID `com.sungamestudio.braintrain` (do not change).
Levels, symbols and artwork are data. Cloudflare R2 is the source of truth: the app downloads level files and
the art they use on demand (the next 5 levels are kept on the phone) and bundles only a starter pack (levels 1–5).

## Commands (run from repo root)

```bash
flutter pub get
flutter analyze                         # must be clean
flutter test                            # unit + widget tests, no network
flutter run -d emulator-5554            # AVDs (this Mac): Pixel_9 (Play Store), TP_API36/TP_Small/TP_Tall
flutter build appbundle                 # Play upload; needs android/key.properties (+ play_games.properties for Play Games,
                                        #   admob.properties for real ads: warns while it uses AdMob test IDs)
dart run tool/content.dart build        # content-src/ -> content/brain-train/ (campaign: generate + solve + simulate + hash)
dart run tool/content.dart validate     # check content/brain-train/ like the app, plus solver
dart run tool/content.dart stats        # simulated tray-player win rates per tier of the built tree
dart run tool/publish.dart --dry-run    # then without --dry-run to upload to R2 (parallel, manifest last)
dart run tool/r2_prune.dart             # list R2 objects the live manifest no longer uses (--delete: owner only)
dart run tool/r2_art.dart push|pull     # symbol masters art/masters/ <-> R2 (private keys art/masters/..., not in git)
python3 tool/assets/prepare_symbols.py [--placeholders]   # art -> WebP symbols
python3 tool/assets/make_app_icon.py    # launcher icons from the logo emblem (Android + iOS)
python3 tool/assets/make_foliage.py     # gameplay edge foliage -> assets/decor/
python3 tool/assets/make_lobby_art.py   # lobby night art -> assets/lobby/
python3 tool/assets/make_sounds.py      # sound effects -> assets/sounds/
CAPTURE_DIR=/tmp/x flutter test test/visual/   # write screenshots of lobby/gameplay at phone sizes
dart run tool/smoke_remote.dart         # live check: app's content client vs production R2 (+ first/middle/last level)
```

## Layout

- `lib/game_engine/` — pure Dart, no Flutter imports (tools import it). Models, geometry
  (`BoardGeometry`, `TileAvailabilityCalculator`, `BoardProjection`, `TileHitTester`), rules
  (`MatchRules`), `GameEngine`, `MahjongSolver`, `LevelValidator`, `LevelGenerator` (hand layouts),
  `TraySimulator` (simulated tray player). `scoring/`: `ScoringRules`, `ScoreKeeper`, `formatScore` (pure Dart). `campaign/`: `CampaignConfig` (tiers from the catalog),
  `scheduleTiers`, `board_shapes.dart` (22 symmetric shape families + stacking programs),
  `CampaignGenerator`, `LevelDecor` (titles, backdrops), `SeededRandom`/`stableHash` (pinned PRNG).
- `lib/content/` — pure Dart except `file_content_store.dart` (dart:io). Manifest, registry and
  level loading; permanent disk cache (`ContentCache`, with the ready-level index); `ContentCoordinator`
  (known-good / starter pack, gated version switch, 5-level window, on-demand `ensureLevel`, offline fallback to
  older cached level files); `content_files.dart` (level file encoding, content-addressed keys);
  `app_update_config.dart` (app update notice: parse, `decideAppUpdate` → none / optional / required, fetch).
- `lib/rendering/` — tile body rasterizer, symbol art cache, board painter, effects.
- `lib/features/` — screens. `levels/` Completed Levels (`LevelSelectScreen`), `LevelLoaderScreen`
  (`level_loader.dart`: every game opens through it — the game at once when the level is on the device, else
  "Downloading level…", or offline "Connect to the internet to download this level"), `DifficultyStyle`; `home/` lobby (hero tiles, title, footer widgets; `widgets/lobby_buttons.dart` glass buttons via `_LobbyGlass`;
  `widgets/lobby_play_games.dart` round Play Games buttons; `widgets/lobby_update_card.dart` update card);
  `gameplay/` (`game_controller.dart` glues engine + UI; `widgets/premium_chrome.dart` HUD, felt
  backdrop, dialogs; `widgets/tray_view.dart` tray + `TrayController`; `widgets/tile_flight_overlay.dart`
  board↔tray flights + `TrayFlightDirector`; `widgets/tile_shatter.dart` match strike + shards;
  `widgets/tile_art.dart` single-tile art; `widgets/board_intro.dart` level-start intro; `widgets/win_trophy.dart` trophy Lottie
  on the win card; `widgets/combo_badge.dart`, `widgets/score_popups.dart`); `common/` shared lobby chrome, `glass_painters.dart` (`GlassRimPainter`/`GlassShadowPainter`), `PremiumMahjongTile`,
  lobby background + fireflies; `intro/` studio video + logo screen + `age_screen.dart` (neutral age screen).
- `lib/app/` — `AppServices` (wiring), `AppScope` (above `MaterialApp`), `theme.dart`
  (`BrainTrainPalette.night`, `LobbyTheme.night`), `brand.dart` (serif display font, gold),
  `sound_effects.dart`, `play_games_controller.dart` (lobby Play Games state), `rewarded_ads_controller.dart`
  (`AppServices.ads`: Revive's ad state, show with music/SFX held, privacy options), `app_update_controller.dart`
  (`AppServices.updates`: the lobby's update card, its check, kept notice, Update / Later).
- `lib/data/` — `ProgressRepository`, `SettingsRepository` (also the stored `AgeGroup`), `age_group.dart`,
  `app_update_cache.dart` (last good update notice).
- `lib/platform/` — `play_games.dart` (`PlayGames` interface, statuses, `UnavailablePlayGames`, pure Dart);
  `games_services_play_games.dart` (the only file importing `games_services`; `createPlayGames()`);
  `rewarded_ads.dart` (`RewardedAds` interface, statuses, `AdAudience` per age group, `UnavailableRewardedAds`, pure
  Dart); `managed_rewarded_ads.dart` (`ManagedRewardedAds` over an `AdsBackend`: consent, one ad kept loaded,
  backoff, timeouts); `google_mobile_ads_rewarded.dart` (the only file importing `google_mobile_ads`;
  `createRewardedAds()`); `app_updates.dart` (`AppUpdater` interface, `UnavailableAppUpdater`, store links, pure
  Dart); `play_in_app_update.dart` (the only file importing `in_app_update`; `createAppUpdater()`).
- `content-src/` — authoring: `catalog.json` (`campaign`: seed, tiers, counts, bands). `layouts/*.layout.json`
  are the old hand layouts (not in the catalog; the tool still accepts catalog `levels` entries).
  `app-update.json` is the app update notice (mutable key `brain-train/app-update.json`, docs/APP_UPDATES.md).
- `content/brain-train/` — generated, published tree (not in git; local output of `tool/content.dart build`,
  uploaded by `tool/publish.dart`). Mirrors R2 keys `brain-train/...`.
- `content/starter/` — the starter pack, committed and the only content in pubspec: the full manifest and the
  registry (metadata of all levels), levels 1–5 and only their art (~2 MB). Written by `tool/content.dart build`.
- `art/` — `asset_sources.json` (IconScout attribution + status), review sheets. `art/masters/` (full-size symbol
  PNGs) is gitignored and lives in R2 (`tool/r2_art.dart`).
  `art/source/` (licensed originals) is gitignored.
- `infra/cloudflare/braintrain-assets/worker.js` — the deployed Worker's source of truth.
- `docs/` — `level-design-rules.md` (all level rules: difficulty 1–10, tray 2–5, 85/15, batches),
  `CONTENT_PUBLISHING.md`, `ASSET_PIPELINE.md`, `PLAY_GAMES.md`, `ADS.md` (AdMob setup, IDs, age screen, consent),
  `APP_UPDATES.md` (update card, force update, the notice).

## Rules that are easy to break

- Geometry: tile `(x, y)` = top-left of footprint in logical units; footprint = `board.tileWidth × tileHeight`
  (levels use 2×2 so half offsets are integers). Layer offsets are rendering-only.
  Renderer, hit tester and rules must all use `BoardGeometry`/`BoardProjection`.
- Free tile = no remaining higher-layer tile overlaps it AND left or right same-layer side is open.
- Matching uses symbol codes / match groups, never artwork.
- Rendering: Impeller has no raster cache, so while anything animates (leaves, fireflies, Lottie) every layer
  on screen is redrawn each frame. No `BackdropFilter`, `Opacity`/`ColorFilter` layers, per-frame mask blurs
  or blend-mode passes behind ambient animation: flatten static subtrees with `StaticLayer` (no repaint
  boundaries inside it) and use `FrostedGlass` (blurred copy from a `FrostSource`) for glass. The board caches
  itself (`BoardLayers`: static image + moving symbols via `SymbolFrameAtlas`).
- Play goes through a tray whose size is per level: `rules.trayCapacity` 2–5, tied to difficulty (5 for the easiest,
  2 for the hardest; docs/level-design-rules.md), 4 when absent; the validator allows 2–5 (`kAllowedTrayCapacities`),
  and `GameEngine`/`GameController`/`TrayController` take it from the level (2/3 slots need content schema 3). A tapped free tile leaves the board for the tray; if it matches a tray tile both clear;
  `capacity` tiles without a match lose (`GameStatus.trayFull`) and show a Revive / Restart card. Revive
  (`GameEngine.revive`, unlimited, not a move) puts all the tray tiles back in their board places, only after a
  rewarded ad's reward (see Ads below). Saves store the tap sequence plus `GameEngine.reviveMarker` entries
  (`progress.current.v2`); a tray-full game is saved so it can be revived later. Only the first level not won is saved:
  `saveGame` skips already-won levels (replays), `clearSavedGame(levelId:)` clears only that level's save, so a replay
  never wipes the highest level's game (an unfinished replay is dropped). Solver/generator still prove
  pair-removal orders, which are valid tray orders (tap a, then b). Screen: tray at the top, board, HUD at the
  bottom. The board drops a tile at the tap; `TileFlightOverlay` draws it until it lands (ticks only during
  flights); revived tiles fly back one by one, slowly (owner: 700 ms each, 300 ms apart, lower tiles first) and
  stay hidden on the board until they land. A matched pair
  strikes and shatters in `TileShatterOverlay` (tiles rasterized once via `TrayViewState.snapshot`, shards
  drawn with `drawVertices` + `ImageShader`, ticks only while running); match/win sound plays at impact
  (`GameController.pairImpact`). The tray draws animated symbols through its own `SymbolFrameAtlas`; result
  cards wait until flights, the tray and shatters are still.
- Level intro (`widgets/board_intro.dart`): every game start (new, Restart, resumed save; not Revive; skipped with
  reduce-motion) flies the board tiles in from all four sides, mixes them, then settles them by layer onto the
  board. Length by tier (`IntroTiming`: difficulty 1 2.0 s to 10 3.0 s in even steps; named tiers easy 2.0 s,
  medium 2.3, hard 2.6, very hard 3.0; by tile count without a tier); fly-in always 0.8 s, the extra time goes to the mix and a calmer settle; mix style per level
  (`IntroStyle.forLevel`: swirl / figure-8 weave / spiral / row waves; neighbouring level numbers differ),
  seeded by level id. `GameController(playIntro: true)` blocks taps and holds the clock until `endIntro()`; the
  board paints nothing meanwhile (`BoardPainter.hidden`). The overlay draws every tile with one `drawRawAtlas`
  from a `BoardSpriteAtlas` (the board's own tile drawing, rendered once, disposed at the end); the last 50 ms
  are exactly the board, so the hand-over has no jump. Ticks only while it runs.
- Published object keys are immutable. Levels and the registry are content-addressed
  (`levels/level-0001-<sha12>.json`, `registries/symbols-<sha12>.json`): changed bytes get a new key by
  themselves, unchanged ones keep theirs. `tool/content.dart build` and `tool/publish.dart` refuse to overwrite
  (publish checks every key before writing any). Only `manifest.json` is mutable, and it is uploaded last.
- Bump `contentVersion` in `content-src/catalog.json` for every publish.
- Symbols: only entries with `"status": "integrated"` (and a processed file) in `art/asset_sources.json` /
  `art/animated_sources.json` enter the registry. Another agent may be editing `art/**` and `tool/assets/**`:
  do not edit them; the build reads them fresh.
- Level design rules (owner) live in **docs/level-design-rules.md**; read it before creating or changing levels.
  85/15 rule: each level has `floor(15% of pairs)` animated pairs (at least 1; `animatedShare` 0.15, the code caps
  it at 0.3), the rest static; at most 12 distinct animated symbols per level (`SymbolFrameAtlas` renders each once
  per frame step); at most 2 pairs of one symbol per level (`maxPairsPerSymbol`). Codes per level: least used so far
  first (ties by a hash of level × code), so every integrated symbol is on some level (the build fails otherwise);
  new symbols change codes, never boards, tiers, trays, titles or win rates.
- Tiers are data (`campaign.tiers`): difficulty `1`..`10` (1 very easy, 10 hardest), stored as the string
  `difficulty` in levels and manifest; the app shows `7/10` on a green-to-red badge (`difficultyLabel`,
  `DifficultyStyle`; named ids like `veryHard` still work). `campaign.batches` lists levels per tier; each batch is
  a seeded shuffle (level 1 is difficulty 1, never 3 of a tier in a row) that depends only on earlier batches:
  add levels by appending a batch, never by editing one.
- Content delivery (owner): R2 is the source of truth; static and animated symbol files live only there (plus the
  starter pack's). The app downloads the manifest (every level's title, tier, tile count and `trayCapacity`, so
  lists and panels never need level files) and the registry in the background, and keeps a rolling window of the
  next 5 levels (first level not won + the 4 after it) on disk: level file + only the art it uses, a symbol shared
  by several levels once. Top-ups: at start, after every win, on app resume, and while any window level is missing (offline, 5xx, 429
  rate limit, 408) every 5/10/15/30 s then every 30 s until all 5 are on the device; paused in the background
  (`ContentController`, `ContentException.isTransient`). Nothing is ever evicted; a level that was ever ready replays offline, after a content
  update too (from its older cached file, `CachedLevel` index, until the new file is cached). Other levels download
  on demand when opened. A newer manifest becomes active only once its registry and its window are cached; never a
  downgrade. Startup never waits for the network (`loadInitial` + `warmUp` read only cache and bundle).
- Play Games (Android only, docs/PLAY_GAMES.md): optional and never on the startup path (a local channel check in
  `AppServices.create`; sign-in starts after the lobby's first frame). Only `games_services_play_games.dart`
  imports the plugin; every call is caught and timed out. The app ID comes from gitignored
  `android/play_games.properties`; without it `PlayGamesInitProvider` is disabled and Dart sees
  `UnavailablePlayGames`. Release signing reads gitignored `android/key.properties`. iOS min is 14.0 (plugin).
- Ads (owner, docs/ADS.md): Revive shows an AdMob rewarded ad (`GameScreen._revive`); the revive runs only once the
  ad has closed with its reward earned (and the app is in the foreground). Closed early / failed → no revive, the card
  stays. No ad loaded (loading, no fill, errors) → Revive off with "Loading an ad…"; offline → off with "Connect to the
  internet to watch an ad and revive"; Restart always works; a resumed tray-full save needs an ad too. Never on the
  startup path: the lobby starts ads after its first frame (configuration by age group → UMP consent → `initialize` →
  load); a game opening, the Tray full card and app resume preload; failures retry 5/10/20/30 s then every minute.
  Only `google_mobile_ads_rewarded.dart` imports the plugin; every call is caught and timed out. While an ad shows the
  clock stays stopped (a full tray stops it), music is held (`BackgroundMusic.interrupted`) and SFX stop. Builds
  without the SDK (tests) have ads `off`: Revive needs no ad. Under 13: TFCD + TFUA + `ageRestrictedTreatment.child`,
  rated G, non-personalized, UMP `tagForUnderAgeOfConsent`; 13+: rated PG, normal UMP flow. IDs: Android
  `android/admob.properties` (gitignored; Gradle → manifest + `rewardedAdUnitId` on the `brain_train/platform`
  channel), iOS `Info.plist` (`GADApplicationIdentifier`, `BrainTrainRewardedAdUnitId`); Google's test IDs otherwise.
- App updates (owner, docs/APP_UPDATES.md): never on the startup path; the lobby checks after its first frame and on
  app resume: the kept notice (`appUpdate.notice.v1`, last good) applies at once (a force update holds offline), then
  `brain-train/app-update.json` is fetched (content client, 5 s timeout, every failure caught: 404 forgets the kept
  copy, malformed/offline keep it). Build numbers: Android `versionCode`, iOS `CFBundleVersion` (`package_info_plus`).
  The card lives in the lobby route's own Stack (inside `LobbyBackground` for its frost, `StaticLayer`-flattened), so
  it never shows over a game. Update: Play In-App Updates (immediate) when Play has one, else `storeUrl`
  (`market://` first; `openUrl` on the `brain_train/platform` channel). Only `play_in_app_update.dart` imports the
  plugin; builds without it (tests) use `UnavailableAppUpdater` (never asks). Raise `latestVersionCode` /
  `minVersionCode` only once the new build is live on Play.
- Scoring (owner): a match scores `100 x min(combo, 5)` + speed bonus (+50 gap < 1 s, +25 < 2 s, +10 for 2-4 s);
  combo window 4 s on the game clock (pauses with it), every match restarts it from that match, a gap > 4 s starts over
  at x1; only `TapOutcome.matched` scores; a blocked-tile tap costs 1 (never below 0) and ends the combo; Revive ends
  the combo; Restart resets. State is `SavedGame.scoring`; `LevelRecord.bestScore/bestCombo` only go up. The combo badge
  floats on the tray's bottom edge: never add layout space between tray and board (31-px faces).
- The app never holds R2 keys or `ASSET_TOKEN_SECRET`. `.env` is gitignored and used only by tools.
- Content host (versionCode 5+) is `ContentConfig.production` = `https://braintrain-cdn.sungamestudio.com/`: the R2
  bucket `braintrain-public` on a custom domain (min TLS 1.2), which holds ONLY `brain-train/` (everything in it is
  public; never put private files there). `tool/publish.dart` and `tool/r2_prune.dart` target it (`contentBucket`);
  publish sets `Cache-Control` (manifest 60 s, everything else immutable). Zone `sungamestudio.com` (free plan):
  cache rule "Brain Train content cache" (host eligible for cache, query strings ignored) and rate limiting rule
  "Brain Train content per-IP limit" (300 requests / 10 s per IP, block 10 s); R2 budget alert at $1. Not
  `assets.sungamestudio.com` (that is the king-teenpatti bucket's public domain).
- R2 bucket `braintrain` is private: symbol masters (`art/masters/`, `tool/r2_art.dart`) and a frozen copy of content
  2026.10.16.12 for builds before versionCode 5, served by Worker `braintrain-assets`
  (`braintrain-assets.surajk543.workers.dev`, `brain-train/*` public GET/HEAD; other keys need an HMAC token,
  `aud: "bt-assets"`, max 10 min). The `.env` R2 token covers both buckets (Object Read & Write).

## Product decisions (from the owner)

- Night look only: no day mode, no theme setting. `MaterialApp` is always dark.
- Settings contains only Sound, Vibration and the app version. Do not add other options. One exception (owner):
  a "Privacy choices" row (Google's UMP privacy options form) shown only when UMP says the entry point is required
  (EEA/UK); hidden everywhere else.
- Rewarded ads on Revive (owner, 2026-10-16): every Revive plays an AdMob rewarded ad (Revive stays unlimited); no
  ad, no revive. The audience includes children under 13 (Play Families policy, mixed audience): neutral age screen,
  child-directed ads for under 13. No other ads anywhere.
- Background music `assets/music/water_flowing.mp3` loops at volume 0.6 (`lib/app/background_music.dart`),
  starts after the studio intro, pauses in background and while a rewarded ad shows, and follows the Sound switch
  (no separate music toggle).
- Sounds: `assets/sounds/tap.wav` (one tap cut from the owner's Tap.mp3) on every playable tap; `assets/sounds/strike.wav` (one hit cut from the owner's strike.mp3, 0.95 s) is `Sfx.match`, played when a matched pair strikes in the tray; the last pair's strike is followed by `Sfx.win` 450 ms later.
- No Undo and no Hint in the game; Restart is the only action (the engine has no undo). Reachable from the round HUD
  icon (`PremiumRoundIconButton`, right end; only while playing, not during the intro or result cards) with a confirm
  card "Restart this level?" / "Your score and time start over." (Restart / Keep playing; clock paused, Android back
  closes it), from the Tray full card and from the win card (Replay).
- HUD shows SCORE where Moves was (owner); the win card and Completed Levels show score, best score and best combo.
- Win card ("Level complete!"): `assets/lottie/trophy_cup_rays.json` (LottieFiles, owner's premium licence) via `WinTrophy`, looping while the card is open
  (owner), last frame with reduce motion, `PremiumEmblem` fallback if it fails to load.
- Lobby update card and force update (owner, 2026-10-16): installed build below the notice's latest → "Update
  available" / "A new version of Brain Train is ready." (or the notice's `message`) with Update (gold) and Later, at
  most once per launch (Later or back hides it until the next launch; needs a `storeUrl`). Below its min → "Update
  required" / "This version of Brain Train is no longer supported. Please update to keep playing.", Update only, not
  dismissible (back does nothing), Play / Continue / Completed Levels unreachable; still there after a trip to the
  store. Lobby only, never over a game. The initial notice (latest 4, min 1) prompts nobody on build 4.
- Google Play Games (owner, 2026-10-16): Android only; silent sign-in; two round lobby buttons top-right
  (Achievements, Leaderboards) open Google's screens, signing in first when needed; no Settings entry.
  Pieces: 1 sign-in (done), 2 achievements + leaderboards, 3 cloud save. Two phones on one account must never
  clash: piece 3 merges (union of wins, fastest time) before play; no hard one-device lock.
- Every launch: navy native screen (no icon) → `assets/video/sun_game_studio_intro.mp4`
  (Sun Game Studio) → Brain Train logo on white (`assets/branding/brain_train_logo.jpg`, at least
  2.2 s and until content is loaded) → lobby. Sequence lives in `lib/app/app.dart`. Once, at first launch (and
  once after updating from a version without it), the neutral age screen (`AgeScreen`: "What year were you born?",
  decade then year, nothing preselected, no hint of why) comes between the logo and the lobby; only the derived group
  (`privacy.ageGroup` = `under13` / `13plus`; the year someone may still be 12 counts as under 13) is stored, on the
  phone, never sent.
- App icon = the round emblem of the official logo (`art/branding/brain-train-logo.jpg`), adaptive on
  Android 8+. Regenerate with `python3 tool/assets/make_app_icon.py`.
- No "Mahjong Solitaire" subtitle on the lobby.
- Look: emerald felt + botanical foliage, dark-green panels with fine gold borders, serif display
  type (`brand.dart`), warm ivory tiles with olive-green underside. Lobby buttons are frosted glass with fine gold
  rims (`FrostedGlass` + `StaticLayer`): Play/Continue warm gold with dark green label and soft gold glow
  (`LobbyTheme.primaryGlass*`), Completed Levels / Settings / round Play Games buttons clear (`secondaryGlass*`);
  `primaryFill/Edge/Text` stay for the Completed Levels panel button. Level `backdrop.colors` only tints
  the gameplay ambient light. Tune tiles in `TileStyle`, never the art.
- Every tile everywhere (board, lobby hero) uses `MahjongTileRenderer`; no second tile renderer.

## Current state (2026-10-16)

- Published content 2026.10.16.12 (manifest `minClientContentSchema: 3`, from branch `feat/campaign-v2`): a fresh
  campaign of 100 levels, one batch of 10 per difficulty 1–10 (`catalog.json` `campaign`, seed 20261641, chosen so
  levels 1–10 open 1 2 1 4 4 5 2 6 1 1), trays 2–5, 85/15 symbols, at most 2 pairs per symbol; rules in
  docs/level-design-rules.md. The registry (`registries/symbols-c49aee2044e5.json`) holds 314 symbols: 203 static
  (set v1) and 111 animated, every one on some level (static 10–11 levels each, animated 3–4). .12 = .11 minus 4 tiles
  unsuitable for a 6+ audience (CINEMA_NO_SMOKING, TRIP_COCKTAIL, MONSTER_POOP, EMOJI_KNIFE: tobacco, alcohol, crude
  humour, weapon; IARC rating). Apps built before
  schema 3 (master, Play versionCode 1/2) reject this manifest and keep their known-good content, whose old level files
  are still on R2 until `tool/r2_prune.dart --delete` runs (455 unreferenced objects: 345 old levels, 7 registries,
  85 `symbols/v4/`, 18 old `shapes-loader-*` animations).
- Simulated random-player win rate per difficulty (200 games per level): 1 98%, 2 90%, 3 68%, 4 52%, 5 29%, 6 12%,
  7 2%, 8–10 0% (a pair-seeking player still wins ~50% of 8–10). Every level is solver-proven and keeps tile faces
  >= 31 px wide on a 360x640 phone.
- Rebuild after new symbols: bump `contentVersion`, `dart run tool/content.dart build` (the registry key and the
  levels that rank a new code change by themselves), `validate`, `flutter test`, `publish --dry-run`, `publish`,
  `smoke_remote`.
- The app bundles only `content/starter/` (54 files, ~2.0 MB raw / ~1.0 MB compressed; the full tree was 11.2 MB /
  ~3.4 MB). A fresh install downloads only the manifest at first launch (its window is the starter pack); each win
  then fetches about one level file and its new symbols. With no starter pack, the window 1–5 is 5 level files +
  47 symbol files (~1.8 MB).
- Lobby menu: Play/Continue (always the first level not won; "Continue" only for a saved game of that level),
  "Completed Levels", Settings. No "N levels ready" footer (owner); the footer only
  shows a content notice (offline / update skipped / new content installed).
- "Completed Levels" screen (`level_select_screen.dart`, owner): a panel with the next level to play (first not won; title, tier,
  size, tray; Play/Continue) and below it ONLY the completed levels, in order, as a lazy list to replay from
  (one row each: number, title, tier badge, tiles, best time, date-time of that best win). Replays keep the
  fastest time and its date (`ProgressRepository.recordWin`).
- All levels won (owner): `AllLevelsCompleteNote` ("All N levels complete! New levels are coming soon.") in the
  lobby (Play becomes "Replay · Level N") and in place of the next-level panel on Completed Levels; the last
  level's win card says so instead of "Next level". No list of all levels and no locked cells; an empty message before the first win.
  Tray UI lays out 2 to 5 wells.
- Static art pipeline: `art/asset_sources.json` → `python3 tool/assets/prepare_symbols.py` → `content/brain-train/symbols/v1/`
  (image set renamed v4 → v1 on 2026-10-16: `art/source/symbols-v1/`, `art/masters/v1/`, `art/review/v1-contact-sheet.png`).
  Animated: `art/animated_sources.json` → `python3 tool/assets/prepare_animated.py` → `content/brain-train/animated-symbols/`.
  Originals live in `art/source/` (gitignored). IconScout downloads use the owner's subscription via the iconscout MCP.
- Art sources: each entry has a `status`; builds take only `integrated` ones. Static: 203 integrated (82 earlier +
  23 owner nano-banana cut-outs + 76 IconScout 3D Sport/Christmas/Tech/Robot/Cinema/Trip + 24 from the Sport, Sport
  Equipment, Equipment and Medicine packs, minus 2 rejected for 6+), 60 `rejected` (unreadable at 31 px, look-alikes, duplicates; each has a
  reason), 16 `awaiting download`. Duplicate subjects are never added (owner). Animated: 111 integrated (2 rejected for 6+; 83 earlier +
  9 owner LottieFiles `LF_*` + India map + 20 country flags `FLAG_*` restyled with a zoom), rejected ones have a
  reason. Check new art at 31 px and 64 px tile width.
- Not yet integrated: 4 IconScout AI images (spring rolls ×2, salad, nachos) — not reachable via the IconScout API.
- Tray mechanic is integrated (tray at the top, flights, strike-and-shatter matches, Tray full card with
  Revive / Restart), with 2 to 5 slots per level.
- App version 1.0.0+4 (`feat/rewarded-ads`, merged into `feat/campaign-v2`): rewarded ads on Revive, age screen,
  Privacy choices row, built with Google's AdMob test IDs (`google_mobile_ads` 9.1.0). This bundle (66.7 MB AAB,
  19.2 MB install) is the Closed testing - Alpha release in the Play Console.
- Play Store listing (owner-approved): texts in `art/store/listing-en-US.md`, `art/store/icon-512.png`,
  `art/store/feature-graphic.png` (1024x500), 6 phone screenshots in `art/store/phone/` (1080x1920, from
  `test/visual/` captures, taken before ads). AI asset declaration: "Don't label assets" (owner).
- Studio website sungamestudio.com (static, nginx on game-server-01): Brain Train page `/brain-train`, privacy policy
  `/brain-train/privacy/` (source `website/brain-train/privacy/index.html`, same text as the deployed page); the
  premium night redesign was deployed on 2026-10-16 (source repo `~/Project/sungamestudio-site` on the Linux machine).

## Working on another machine

- Code: `master` (repo private; PR #1 `feat/brain-train-game` and PR #2 `feat/play-games` are merged).
  `git clone https://github.com/surajk543/Brain-Train.git && cd Brain-Train && flutter pub get`. Branch from `master`
  for new work. Latest handoff notes: `docs/superpowers/handoff-2026-10-16.md`.
  Flutter 3.44.7 / Dart 3.12.2. Android SDK + AVD (`Pixel_6_API_34` on the old machine;
  `emulator -avd Pixel_6_API_34 -gpu host -no-snapshot-load`). This Mac: Flutter `~/flutter`, SDK
  `/opt/homebrew/share/android-commandlinetools`, AVD `Pixel_9` = Play Store image (use for Play Games), `TP_*` AVDs
  have no Play Store, `Pixel_6_API_34` does not exist. Python 3 + Pillow for `tool/assets/*.py`, ffmpeg for audio.
- `flutter analyze` and `flutter test` work on a fresh clone (tests use fixtures and `content/starter/`); on the Linux
  machine all 512 pass (2026-10-16); on the Mac 6 tests failed before (see Open work).
- Run on a Mac (iPhone simulator) or any machine with no secrets: `flutter pub get && flutter run`. Debug builds read
  content from the public host, use Google's test AdMob IDs, skip Play Games (Android only) and use debug signing;
  `.env` and the `android/*.properties` files are only for publishing and release builds.
- CI: `.github/workflows/ios-build.yml` builds the iOS simulator app (`flutter build ios --simulator --debug`) on a
  macOS runner when `ios/**`, `pubspec.*` or the workflow change, or by hand (Actions > Run workflow). macOS runners
  use the private repo's free Actions minutes faster, so it does not run on every PR.
- Content tree: `content/brain-train/` is not in git. Before `tool/content.dart build|validate` or `tool/publish.dart`
  on a new machine, mirror the live tree: `dart run tool/fetch_content.dart` (public prefix, no keys, sha256-checked).
- Secrets: copy `.env` by a secure channel (password manager), never git/chat/email, likewise `android/key.properties`,
  `android/play_games.properties`, `android/admob.properties` and the upload keystore. Keys: `R2_ACCOUNT_ID`,
  `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `R2_BUCKET_NAME`, `ASSET_TOKEN_SECRET`. Only publishing and
  `tool/r2_art.dart` need it.
- Symbol masters `art/masters/` are not in git (moved to R2 on 2026-10-16, 260 PNGs, ~39 MB; older git history still
  has them): `dart run tool/r2_art.dart pull` fetches them, `push` stores new ones after `prepare_symbols.py`.
  Needed only for `make_app_icon.py --symbol` and art review; builds and the app never read them.
- Licensed originals `art/source/` are not in git; needed only to re-process art. Re-download through the IconScout
  MCP (`claude mcp add --transport http iconscout https://mcp.iconscout.com/mcp`) from `art/asset_sources.json` /
  `art/animated_sources.json` (`sourceUrl`; slug `<name>_<assetId>`). IconScout 3D downloads once failed after ~24 in a
  day, but 150 went through on 2026-10-16 evening; stop at the first server error.
- Open work: 16 static entries `awaiting download` (MED_VIRUS + 15 SCI_, not downloaded on the owner's stop); a frame-time slowdown after hours of play on the emulator (Impeller GLES; watch
  `adb logcat | grep app_time_stats`, app restart resets it) is not explained yet.
- Play Console setup (2026-10-16, docs/PLAY_GAMES.md steps 1–6 done): app "Brain Train" in the sungamestudio.com
  developer account (personal account), Play App Signing on; Games Services project = Play Games app ID `923515226118`
  (in `android/play_games.properties`), linked Cloud project `brain-train-511814` (OAuth consent screen External,
  Testing; test user + PGS tester surajk543@gmail.com); 3 Android credentials (Play App Signing key, upload key,
  this Linux machine's debug key — another machine's debug key needs its own credential). Upload keystore:
  `~/keys/brain-train-upload-keystore.jks` on the Linux machine (password only in `android/key.properties`).
  Internal testing release draft exists (versionCode 1 was built before the app ID existed: replace with a newer build).
- Play Console release state (2026-10-16): every App content declaration is done (privacy policy, ads = yes,
  Advertising ID, content rating, target audience 6+ incl. under 13 (Families), Data safety, Health/Financial/
  Government); category Puzzle; store listing saved. Closed testing - Alpha: versionCode 4 (1.0.0), all countries,
  testers = Google Group sungamestudiotesters@googlegroups.com, feedback contact@sungamestudio.com. Its 16 changes sit
  in Publishing overview, not yet sent for review (owner decides; Google Play Games on PC is opted in by default).
  Production needs 12+ opted-in testers for 14 days, then real AdMob IDs.
- Open work (ads, docs/ADS.md "Owner setup"): AdMob account, app and "Revive" rewarded unit → real IDs in
  `android/admob.properties` and `ios/Runner/Info.plist`; app-ads.txt on sungamestudio.com; AdMob Families /
  mixed-audience settings and a published GDPR consent message; Play Console Ads, Advertising ID, Target audience and
  Data safety answers. The iOS `AppDelegate.swift` channel (`rewardedAdUnitId`) is untested until the first Xcode build.
- Open work: Play Games pieces 2–3 (piece 2 builds on `bestScore`/`bestCombo`; publishing the PGS configuration needs
  at least 5 achievements). Scoring + combo is implemented (4 s window).
- Open work: Play Games / scoring follow-ups after the PR #2 merge: run an iOS build on a Mac with full Xcode (iOS min
  14.0, never built yet); check the combo pill on a phone (its top overlaps the tray wells by ~5 px at 360×640).
- Open work: 5–6 tests fail on this Mac (predate PR #2): RenderFlex overflow of 4.4 px at
  `lib/features/levels/level_select_screen.dart:232` (Completed Levels row) — level_select_test (2), level_loader_test (1),
  lobby_capture_test (2, per-phone "home, levels, settings"), gameplay_capture_test ("tray-full overlay 360x640 at 1.3x
  text"). Owner to decide.

Keep this file current when commands, layout, or these rules change.
