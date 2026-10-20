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
                                        #   (Linux: Pixel7_Play_API36 is the owner's; agents use TP_* on their own -port, adb -s)
flutter build appbundle                 # Play upload; needs android/key.properties (+ play_games.properties for Play Games,
                                        #   admob.properties for real ads: warns while it uses AdMob test IDs)
dart run tool/content.dart build        # content-src/ -> content/brain-train/ (campaign: generate + solve + simulate + hash)
dart run tool/content.dart validate     # check content/brain-train/ like the app, plus solver
dart run tool/content.dart stats        # simulated tray-player win rates per tier of the built tree
dart run tool/publish.dart --dry-run    # then without --dry-run to upload to R2 (parallel, manifest last)
dart run tool/r2_prune.dart             # list R2 objects the live manifest no longer uses, never app-update.json (--delete: owner only)
dart run tool/r2_art.dart push|pull     # symbol masters art/masters/ <-> R2 (private keys art/masters/..., not in git)
python3 tool/assets/prepare_symbols.py [--placeholders]   # art -> WebP symbols
python3 tool/branding/make_tile_park_icons.py   # Tile Park icons (Android + iOS), Play icon-512, logo screen image
python3 tool/assets/make_foliage.py     # gameplay edge foliage -> assets/decor/
python3 tool/assets/make_lobby_art.py   # lobby night art -> assets/lobby/
python3 -I tool/lobby_art/make_day_lobby_art.py  # hero ledge assets/lobby/night_ledge.webp (+ unused Day art: delete assets/lobby/day/)
python3 tool/assets/make_sounds.py      # sound effects -> assets/sounds/
CAPTURE_DIR=/tmp/x flutter test test/visual/   # write screenshots of lobby/gameplay at phone sizes
CAPTURE_DIR=/tmp/x flutter test test/visual/tile_closeup_capture_test.dart   # tile close-ups: 3 layers on the felt, 64/31-px faces
CAPTURE_DIR=/tmp/x flutter test test/visual/gameplay_redesign_capture_test.dart   # gameplay 1.1.0: combo+hint, hint hand, cards, Level Complete, spent action
STORE_DIR=art/store flutter test test/visual/store_screenshots_test.dart   # 6 store scenes -> phone/, ios/iphone-6.9/, ios/ipad-13/
python3 tool/store/make_store_shots.py  # framed marketing shots (headline, gold rim) -> art/store/styled/<target>/
python3 tool/store/make_feature_graphic.py  # Play feature graphic 1024x500 (Tile Park logo + name) -> art/store/feature-graphic.png
python3 -I tool/store/make_pgs_icons.py # achievement + leaderboard icons (512 px) -> art/play-games/ (Play Games + Game Center)
dart run tool/smoke_remote.dart         # live check: app's content client vs production R2 (+ first/middle/last level)
```

## Layout

- `lib/game_engine/` — pure Dart, no Flutter imports (tools import it). Models, geometry
  (`BoardGeometry`, `TileAvailabilityCalculator`, `BoardProjection`, `TileHitTester`), rules
  (`MatchRules`), `GameEngine`, `MahjongSolver`, `LevelValidator`, `LevelGenerator` (hand layouts),
  `TraySimulator` (simulated tray player), `TraySolver` (tray-aware tap solver: hints, shuffle proofs); `state/`:
  `game_actions.dart` (Undo/Hint/Shuffle types, `kStartingCharges`), `HintFinder`, `ShufflePlanner`. `scoring/`: `ScoringRules`, `ScoreKeeper`, `formatScore` (pure Dart). `campaign/`: `CampaignConfig` (tiers from the catalog),
  `scheduleTiers`, `board_shapes.dart` (22 symmetric shape families + stacking programs),
  `CampaignGenerator`, `LevelDecor` (titles, backdrops), `SeededRandom`/`stableHash` (pinned PRNG).
- `lib/content/` — pure Dart except `file_content_store.dart` (dart:io). Manifest, registry and
  level loading; permanent disk cache (`ContentCache`, with the ready-level index); `ContentCoordinator`
  (known-good / starter pack, gated version switch, 5-level window, on-demand `ensureLevel`, offline fallback to
  older cached level files); `content_files.dart` (level file encoding, content-addressed keys);
  `app_update_config.dart` (app update notice: parse, `decideAppUpdate` → none / optional / required, fetch).
- `lib/rendering/` — tile body rasterizer, symbol art cache, board painter, effects.
- `lib/features/` — screens. `levels/` Levels (`LevelSelectScreen`), `LevelLoaderScreen`
  (`level_loader.dart`: every game opens through it — the game at once when the level is on the device, else
  "Downloading level…", or offline "Connect to the internet to download this level"), `DifficultyStyle`; `home/` lobby (`widgets/lobby_hero.dart` hero tiles on the mossy ledge + gold "Brain Train" title, `widgets/lobby_footer.dart` status line; `widgets/lobby_buttons.dart` glass buttons via `_LobbyGlass`;
  `widgets/lobby_play_games.dart` round Play Games buttons; `widgets/lobby_update_card.dart` update card);
  `gameplay/` (`game_controller.dart` glues engine + UI; `game_layout.dart` (`GameLayout`: the screen's heights,
  compact on short screens); `widgets/game_hud.dart` top HUD + `ComboTimerBar`; `widgets/action_bar.dart` Undo / Hint /
  Shuffle / Restart; `widgets/hint_glow.dart` hint overlay (blinking glow + hand); `widgets/hint_hand.dart` the hint's
  pointing hand (`HintHand` geometry, `HintHandMotion`); `widgets/result_cards.dart` Level Complete, Tray full,
  Restart and ad-offer cards; `widgets/premium_chrome.dart` felt backdrop, panels, buttons;
  `widgets/tray_view.dart` tray + `TrayController`; `widgets/tile_flight_overlay.dart`
  board↔tray flights + `TrayFlightDirector`; `widgets/tile_shatter.dart` match strike + shards;
  `widgets/tile_art.dart` single-tile art; `widgets/board_intro.dart` level-start intro; `widgets/win_trophy.dart` trophy Lottie
  on the win card; `widgets/combo_badge.dart`, `widgets/score_popups.dart`;
  `widgets/first_play_tutorial.dart` first-play coach marks); `common/` shared lobby chrome, `glass_painters.dart` (`GlassRimPainter`/`GlassShadowPainter`), `PremiumMahjongTile`,
  lobby background + fireflies; `intro/` studio video + logo screen + `age_screen.dart` (neutral age screen).
- `lib/app/` — `AppServices` (wiring), `AppScope` (above `MaterialApp`), `theme.dart`
  (`BrainTrainPalette.night`, `LobbyTheme.night`, `FeltFoliage`, `buildBrainTrainTheme()`), `typography.dart` (`BrainTrainFonts`, `BrainTrainType` builders,
  `BrainTrainTypography` theme extension, `registerFontLicenses`), `brand.dart` (`kDisplayFont` = Playfair, gold),
  `sound_effects.dart`, `play_games_controller.dart` (lobby Play Games / Game Center state, win reports, catch-up),
  `play_games_reports.dart` (`WonGame`, `reportForWin`, `reportForProgress`, `leaderboardTime`), `rewarded_ads_controller.dart`
  (`AppServices.ads`: Revive's ad state, show with music/SFX held, privacy options, `offer()`),
  `rewarded_ad_offer.dart` (`RewardedAdOffer`: one card's ad with the no-ad fallback, `kAdFallbackDelay`),
  `app_update_controller.dart`
  (`AppServices.updates`: the lobby's update card, its check, kept notice, Update / Later).
- `lib/data/` — `ProgressRepository`, `SettingsRepository` (also the stored `AgeGroup`), `age_group.dart`,
  `app_update_cache.dart` (last good update notice).
- `lib/platform/` — `play_games.dart` (`PlayGames` interface, `GamesService`, statuses, `UnavailablePlayGames`, pure
  Dart); `game_services_ids.dart` (every achievement and leaderboard ID: `GameAchievement`, `GameLeaderboard`, Play
  Games + Game Center, pure Dart); `games_services_play_games.dart` (the only file importing `games_services`;
  `createPlayGames()`: Play Games on Android, Game Center on iOS);
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
- Board grid and depth (owner, 2026-10-17): every campaign board fits a fixed grid of 7 × 9 tiles and 4 layers
  (`kBoardGridColumns/Rows/Layers`, `lib/game_engine/geometry/board_grid.dart`), and `boardProjectionFor` fits that
  grid, not the level, into the board area: one tile size on every level (34.8 px at 360x640, 44.3 px at 393x852;
  tablets through `TabletScale` ~78 dp on iPad 13, 69 on iPad 11, 75 on a 10-inch, 55 on a 7-inch; smaller boards
  centred, larger old boards scaled down; `game_actions_ui_test` checks phone and tablet sizes). Depth shows: upper tiles sit half a tile off the tiles below,
  never exactly on one (`stackedTiles`), and every tile keeps >= 1 uncovered quarter (`visibleQuarters`,
  `depth_rules.dart`); `board_shapes.dart` builds layers that way (`_Stack`). `LevelValidator(checkCampaignRules:
  true)` (build, validate) enforces grid, depth and coloured pairs; the app never does (older cached boards play).
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
  (`GameEngine.revive`, not a move) puts all the tray tiles back in their board places, only after a
  rewarded ad's reward (or free when no ad can be had while online; see Ads below). At most `kMaxRevivesPerLevel` = 2
  revives per level attempt (owner, 2026-10-17; was unlimited), free ones included: counted from the game's `!revive`
  markers (`GameEngine.revivesUsed/revivesLeft/canRevive`, `GameController.revivesLeft/canRevive`), so a resumed save
  keeps its count; Restart resets it to 0; Undo never gives one back; `GameEngine.revive` refuses a third (replay
  still accepts more from a 1.0 save, which then has none left). With none left the Tray full card shows Restart only
  (primary) and "No revives left. Restart to try again."; no ad is loaded or offered. Saves (`progress.current.v3` since 1.1.0; `ProgressRepository.open` moves a
  1.0 `progress.current.v2` save over, and reads one while no v3 exists) store the tap sequence plus markers:
  `!revive`, `!undo`, `!hint`, `!shuffle:1:<seed>` (planner version 1, pinned), `!grant:<action>`; replaying them
  (`GameEngine.replay`) restores board, tray, shuffled symbols and action uses, and `SavedGame.scoring` keeps the
  score with its undo checkpoints; a tray-full game is saved so it can be revived later. Only the first level not won is saved:
  `saveGame` skips already-won levels (replays), `clearSavedGame(levelId:)` clears only that level's save, so a replay
  never wipes the highest level's game (an unfinished replay is dropped). Solver/generator still prove
  pair-removal orders, which are valid tray orders (tap a, then b). Screen (1.1.0, `GameLayout`): HUD at the top,
  the combo timer row, the tray, the board (all the rest) and the action bar at the bottom; nothing between tray and
  board. The tray is low (32-px tray tiles, 30 compact) and the action bar one row of 44-px discs with labels beside
  (owner, 2026-10-17), so the fixed board grid gets the height. On a 360x640 phone the layout is compact and the board
  gets 360x439.8 (>= `kSmallBoardWidth` x `kSmallBoardHeight`; the grid's faces there are 34.8 px). The board drops a tile at the tap; `TileFlightOverlay` draws it until it lands (ticks only during
  flights); revived tiles fly back one by one, slowly (owner: 700 ms each, 300 ms apart, lower tiles first) and
  stay hidden on the board until they land; an undone tile flies back the same way (`kTileUndoDuration`, 450 ms) from
  its slot or from mid-air, an undone pair's strike is cancelled and its twin stays in the tray
  (`TrayController.takeBack`), and `GameController.pairImpact(a, b)` ignores strikes of pairs that no longer exist
  (undone, or from before a restart). A matched pair
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
  add levels by appending a batch, never by editing one. A dead end restarts the batch, at most `maxScheduleAttempts`
  (2,000,000, `tier_schedule.dart`) times; batch 2 needs 1,263,282 restarts (~2 s). The draw is pinned
  (`campaign_test.dart` pins the batches' orders): never change how it draws, only the restart limit. Published
  titles are pinned in `campaign.titles` (level 1 first; `LevelDecor`), so a change to board building never renames a
  level: append a batch's titles once it is published.
- Coloured pairs (owner, 2026-10-17): every level colours 1–2 single pairs (static symbols with exactly two tiles),
  level file `faceColors: {"CODE": "gold"}` (`gold`, `sky`, `blush`, `lavender`, `peach`; optional, older builds ignore
  it). Rendering: `TileStyle.namedFaceColors`, one body per colour from `MahjongTileRenderer(style.withFace(c))`,
  baked once and picked per symbol (`BoardArt`/`TileArt` `faceBodies`): board cache, intro atlas, tray, flights,
  shatters. Never green; never a per-frame tint.
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
- Play Games (Google Play Games on Android, Game Center on iOS; docs/PLAY_GAMES.md): optional and never on the
  startup path (a local channel check in `AppServices.create`; sign-in starts after the lobby's first frame). Only
  `games_services_play_games.dart` imports the plugin; every call is caught and timed out. The Android app ID comes
  from gitignored `android/play_games.properties`; without it Dart sees `UnavailablePlayGames`. 13+ only (Play
  Families policy, owner 2026-10-17): `PlayGamesController.start(ageGroup)` never starts Play Games / Game Center for
  under 13 (or no answer) and hides the lobby buttons; the library's `PlayGamesInitProvider` is always disabled, and
  `MainActivity` starts the SDK (`initPlayGames` on `brain_train/platform`) only when Dart asks, so nobody is signed in
  at launch. iOS: the Runner has the Game Center entitlement (`ios/Runner/Runner.entitlements`); the lobby's start
  asks GameKit to authenticate (`GameAuth.signIn`: Apple's banner, or its sign-in sheet at most once per launch).
  Achievements and leaderboards (piece 2, 2026-10-17): every ID in `lib/platform/game_services_ids.dart` (Game Center
  `bt.ach.<key>` / `bt.lb.<key>`). Every win (replays too), signed in at 13+, after its record is saved
  (`GameController.onWin` → `PlayGamesController.reportWin`, fire and forget, never blocks the win card): Best Score
  and Fastest Time of its difficulty (none for named tiers; time in ms on Play Games (Duration), hundredths on Game
  Center), Total Score (sum of `bestScore`), Levels Completed, Best Combo, and the achievements earned (1/10/50/100/
  250/500 wins, combo ×5, Summit = a difficulty-10 win, Pure Skill = difficulty 7+ with no Hint/Undo/Shuffle). Once
  per app run at the first sign-in a catch-up sends what the records earned (per-difficulty bests from the manifest's
  tiers, totals, counts, combo, Summit; never Pure Skill), unlocking without Game Center banners; each achievement
  goes at most once per run. Release signing reads gitignored `android/key.properties`. iOS min is 15.0 (App Store: ITMS-90068, iOS 15+ required for uploads from April 2027).
- Ads (owner, docs/ADS.md): Revive shows an AdMob rewarded ad (`GameScreen._revive`); the revive runs only once the
  ad has closed with its reward earned (and the app is in the foreground). Closed early → no revive, the card
  stays. No ad loaded (loading, no fill, errors) → Revive off with "Loading an ad…"; offline → off with "Connect to the
  internet to watch an ad and revive"; Restart always works; a resumed tray-full save needs an ad too. No-ad fallback
  (owner 2026-10-17: no ad available while online → the reward is free after `kAdFallbackDelay`; offline stays blocked;
  reason: AdMob limited ad serving before store linking): each card gets a `RewardedAdOffer` (`RewardedAdsController.offer()`,
  created when the Tray full card or the refill card opens, which also preloads). With no ad to show (loading, no
  fill, load errors, SDK not started) it waits `kAdFallbackDelay` (8 s), or not at all after a failed load
  (`RewardedAdsState.loadFailed`), then runs a fresh online check (`RewardedAds.checkOnline`: DNS + a TCP connect to
  the ad server's public addresses, false on failure or after 6 s); online → free ("No ad available right now. This
  revive is free.", Revive without the video icon), else offline (checked again every 8 s). A loaded ad that fails to
  show → free if online. Once free, the open card stays free even if an ad loads; the next card needs an ad again.
  An ad closed early starts the wait over. The offer pays once (rapid taps → one reward) through the same path as an
  ad (`GameController.revive` / `grant`, same save markers). Ads status `offline` is never free. Action refills
  (1.1.0) work the same way: an Undo / Hint / Shuffle with 0 uses opens "Watch an ad for +1 Hint?" (`ActionRefillCard`,
  clock paused while it is open; Watch ad / Not now; Back closes it); `GameController.grant` only after the reward and
  the app back in the foreground (`GameScreen._watchRefillAd`); closed early → "Watch the ad to the end to get +1
  Hint.", no grant; loading → "Loading an ad…", offline → "Connect to the internet to watch an ad" (Watch ad off);
  free → "One more Hint?" / "Get +1 Hint" / "No ad available right now. This hint is free."; builds without ads grant
  at once (no card, "+" badge). At most one refill per action per level attempt (`kMaxGrantsPerAction` = 1, owner
  2026-10-17; a free one counts too): once its granted use is spent the action is spent (`GameController.isSpent`), its
  button is gone and no ad is loaded or offered for it (`GameScreen._onAction` returns) until Restart. Never on the
  startup path: the lobby starts ads after its first frame (configuration by age group → UMP consent → `initialize` →
  load); a game opening, the Tray full card and app resume preload; failures retry 5/10/20/30 s then every minute.
  Only `google_mobile_ads_rewarded.dart` imports the plugin; every call is caught and timed out. While an ad shows the
  clock stays stopped (a full tray stops it), music is held (`BackgroundMusic.interrupted`) and SFX stop. Builds
  without the SDK (tests) have ads `off`: Revive needs no ad. Under 13: TFCD + TFUA + `ageRestrictedTreatment.child`,
  rated G, non-personalized, UMP `tagForUnderAgeOfConsent`, never the iOS tracking prompt; 13+: rated PG, normal UMP
  flow, then on iOS Apple's App Tracking Transparency prompt once (`AdsBackend.requestTracking`, `AppDelegate.swift`
  `requestTrackingAuthorization`, `NSUserTrackingUsageDescription`) before the SDK starts. IDs: Android
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
  floats on the tray's bottom edge, a little low (`kComboBadgeAnchor`; 20 px high on compact screens) so it never covers
  the wells: never add layout space between tray and board (the fixed grid's tile size).
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

- Night look only (owner, 2026-10-20; replaces the 1.1.0 Day / Night / System looks): the game's `MaterialApp`
  (`lib/app/app.dart`) has one theme, `buildBrainTrainTheme()` (Night), whatever the phone's brightness; no theme
  setting and no Game Theme cards. A `settings.appearance` value stored by 1.1.0 is ignored. The Day palette, lobby,
  foliage, sun patches, dark status bar icons and Day art (`assets/lobby/day/`, `assets/decor/day/`, ~545 KB) were
  removed; do not bring back a light look without the owner.
- Design tokens (redesign 1.1.0): screens take every colour from `BrainTrainPalette.of(context)` (felt, background,
  panels `panelFill/panelRim/panelSheen/panelHighlight/panelShadows`, HUD `hudFill/hudSeparator/hudLabel/hudValue`,
  buttons `primaryButton*`/`secondaryButton*`/`quietButtonText`, text `text/textMuted/textOnGold`, golds
  `accent/accentLight/accentDeep`, `textShadow/shadow/overlayScrim`, `feltFoliage` assets) and the lobby scene from
  `LobbyTheme.of(context)` (art assets, lights, particles, hero ledge, title golds, glass, buttons, panels); text from
  `BrainTrainTypography.of(context)` (`title`, `levelName`, `heading`, `button`, `scoreValue`, `combo`, `hudLabel`,
  `body`, `bodyMuted`) or `BrainTrainType.*(size:, color:)`. Dark translucent green panels with fine gold rims and
  ivory text (reference board); dark green text (`textOnGold`) only on gold or ivory, never gold on ivory. Night is the
  1.0 look (#062C25 / #0A4433, panel #08392F, gold #F4CB72, ivory #FFF3D8). Status bar icons are light everywhere
  (`kStatusBarLightIcons`). Missing lobby art falls back to the scene gradient. `test/app/appearance_test.dart` checks
  the app stays Night, the bundled art and WCAG contrast of the tokens.
- Settings (redesign 1.1.0, reference panel; `settings_screen.dart`): one dark translucent gold-rimmed panel with a
  header (gear, "Settings", close X; a route, back/close pop it), Sound Effects, Music and Vibration switches and the
  app version (owner, 2026-10-20: the Game Theme cards were removed with Day). Do not add other options.
  One exception (owner): a "Privacy choices" row (Google's UMP privacy options form) shown only when UMP says the
  entry point is required (EEA/UK); hidden everywhere else.
- Rewarded ads on Revive (owner, 2026-10-16): every Revive plays an AdMob rewarded ad; no ad, no revive. At most 2
  revives per level attempt (owner, 2026-10-17; was unlimited), then Restart only and no ad. Owner 2026-10-17: no ad
  available while online → the reward (Revive or a refill) is free after `kAdFallbackDelay`; offline stays blocked;
  reason: AdMob limited ad serving before store linking (as soon as AdMob serves ads they are required again). The audience includes children under 13 (Play Families policy, mixed audience): neutral age screen,
  child-directed ads for under 13. Rewarded ads only (owner, 2026-10-17, 1.1.0; replaces "No other ads anywhere"):
  on Revive and on action refills (+1 Undo / Hint / Shuffle at 0 uses, at most one per action per level attempt, see
  Ads above); never interstitials or banners.
- Background music `assets/music/water_flowing.mp3` loops at volume 0.4 (owner, 2026-10-17; was 0.6) (`lib/app/background_music.dart`),
  starts after the studio intro, pauses in background and while a rewarded ad shows, and follows the Music switch
  (redesign 1.1.0: `SettingsRepository.music`, `settings.music`; until set it reads the stored Sound value, and the
  first Sound change pins it, so players who muted Sound before 1.1.0 stay silent). Sound Effects (`settings.sound`)
  gates only the effects (`SoundEffects`). `BackgroundMusic` takes a `MusicPlayer` (audioplayers; a fake in
  `test/app/background_music_test.dart`).
- Sounds: `assets/sounds/tap.wav` (one tap cut from the owner's Tap.mp3) on every playable tap; `assets/sounds/strike.wav` (the owner's impact.mp3, trimmed to 0.81 s, -6 dB; owner 2026-10-17; was a hit cut from strike.mp3) is `Sfx.match`, played when a matched pair strikes in the tray; the last pair's strike is followed by `Sfx.win` 450 ms later.
- Game actions (owner, 2026-10-17, 1.1.0; replaces "no Undo and no Hint"): Undo, Hint and Shuffle, 1 / 1 / 1 uses
  per level attempt (`kStartingCharges`), back to 1/1/1 on Restart, unchanged by Revive; with none left the player can
  watch a rewarded ad for +1 of that action (`GameController.grant`, saved as `!grant:<action>`), at most once per
  action per attempt (owner, 2026-10-17, 1.1.0+11: `kMaxGrantsPerAction` = 1, so each action is used at most 2 times;
  a free no-ad refill counts as the grant; `GameEngine.grant` refuses a second; Restart gives it back, Revive changes
  nothing; counted from the `!grant:` markers, so a resumed save keeps it; replay still accepts more from a save made
  before the cap (1.1.0+8 to +10), whose action then has no grant left). Once the granted use is spent the action is
  spent (`isSpent`: no use and no grant left): its button disappears for the rest of the attempt and no ad is loaded
  or offered for it. API: `GameController.isAvailable` / `canUse` / `usesLeft` / `grantsLeft` / `isSpent`, `undo`,
  `useHint`, `shuffle`, `grant`; events `MoveUndone`, `TileHinted`, `BoardShuffled`; `winSummary` counts the uses. UI
  (`widgets/action_bar.dart`, under the board): gold-outlined round buttons with labels (under them; beside them on
  compact screens) and a gold badge with the uses left, a play mark at 0 while the grant is left (an ad offer; "+"
  without ads); a button is on only while `isAvailable` and no card is open (off = dimmed colours, no ad offer). A
  spent action's button fades out (`kSpentFadeDuration` 240 ms, colour alphas, no Opacity layer; at once with reduce
  motion or in a resumed save) and leaves an invisible placeholder of the same size (laid out, not painted, no taps,
  ink or semantics; key `action-<name>-spent`), so the other buttons and Restart never move; back after Restart and on
  a new level. Hint (owner, 2026-10-17): `HintGlowOverlay` (own `RepaintBoundary`, over the
  board, `IgnorePointer`) shows a pointing hand (`HintHand`, `assets/lottie/hint_hand.json`, drawn with one
  `LottieDrawable`) that taps the tile twice, glides to its twin on the board, taps it once and glides back
  (`HintHandMotion`, 2.8 s rounds); one hand, not two, so the order reads (this tile first) and only one hand covers
  the small faces. A twin in the tray gets no hand (tray tiles cannot be tapped), only the blink. Fingertip (the
  finger pad at the pressed frame, (366, 364) in the 512 frame) slightly up-left of the face centre, hand 1.3 face
  widths wide, mirrored near the left/top edges to stay on screen. Meanwhile the tile and its twin (board or tray)
  blink 2.5 times a second: the pre-rendered gold glow (`renderGlow`, no per-frame blur) plus a gold wash and line,
  stamped with an animated alpha. Until the next tap, undo, shuffle, revive or restart (and the tray-full or
  win taps), or 4.5 s; reduce motion: a still hand pressed on the tile and a still glow (no ticker); if the hand
  fails to load, the glow alone breathes as before. It never taps. Shuffle: the board, tray,
  intro atlas and animated-tile list draw `GameController.boardLevel` (rebuilt on `symbolsSerial`, so resumed
  shuffled saves draw right); the changed tiles turn over in a left-to-right wave (`BoardEffects.flip`, 360 ms each,
  220 ms stagger; instant with reduce motion; taps wait); "No new arrangement found…" snackbar when no seed passes.
  Undo (`GameEngine.undo`) takes back the last tap: the tile goes back to its board place; a tap that cleared a pair
  also puts the twin back in its tray slot and takes that match's score, combo and best combo back from the
  `ScoreKeeper` checkpoint (blocked-tap penalties since stay); not before a tap, after a win, with a full tray, during
  the intro or the tutorial, or across a Revive or a Shuffle; the clock runs on; scoring values are unchanged.
  Hint (`HintFinder`, pure, never scores) returns a tap: the last board tile of a tray tile's symbol, else a safe pair
  (all of a symbol's board tiles free) when the tray has room, else the first tap of `TraySolver` (20k nodes; after a
  shuffle, the order the shuffle was built along), else any tray match, else any free tile the tray has room for;
  none when every tap would fill the tray. A tray twin whose symbol has more board tiles goes to the solver: taking
  the first one found loses often with 2-slot trays. Shuffle (`GameEngine.shuffle`, `ShufflePlanner`) re-deals the
  board's symbols over the same tiles (places, ids, counts and the tray stay) along a seeded random winning tap order
  (twins for the tray first, then pairs), proved with `TraySolver.check`; uniform shuffles of the 2-slot boards are
  mostly unwinnable, so it is built, not drawn. It ends the combo, seals undo, keeps the score; nothing to shuffle
  (one symbol left) or no passing seed spends no use.
- Restart stays: a quiet icon-only round button at the right end of the action bar (tooltip "Restart", semantics
  "Restart level"; smaller, ivory rim, no badge; the HUD has no room for it at 360 px next to the four statistics;
  only while playing, not during the intro, result cards or another card) with a confirm card "Restart this level?" /
  "Your score and time start over." (Restart / Keep playing; clock paused, Android back closes it), from the Tray full
  card and from Level Complete (Replay).
- HUD (1.1.0, `widgets/game_hud.dart`, top of the screen): back arrow, "Level N" (gold) over the level's name
  (Playfair, shrinks to 72% then ellipsizes; the statistics shrink first, down to 46% of the width; 1 of the 100 names,
  "Moonlit Standing Stones", still ends in "…" on phones), then SCORE (counts
  up), COMBO ×N (gold on a gold cell from ×2, a quiet ×1 otherwise), PAIRS a/b and TIME, Manrope tabular figures
  between fine gold separators; text scales up to 1.3x in a fixed-height panel. Under it `ComboTimerBar`: a gold bar
  draining with "2.1s", read from `GameController.comboTimeLeft` (the `ScoreKeeper` window on the game clock, no timer
  of its own), shown from a match until its window closes, ticking only while the clock runs. The "COMBO ×N · Best
  ×M" badge still floats on the tray's bottom edge (no ring any more); score popups unchanged.
- Level Complete (1.1.0, `LevelCompleteView`, over the whole screen on a deep scrim with warm light): `WinTrophy`,
  "Level Complete!" (gold Playfair), a results panel (Final Score in gold with "New best!" or the level best it missed,
  Completion Time, Best Combo with a crown, Pairs Matched, Hints / Shuffles / Undos Used, from `winSummary`), then
  Next Level (gold; the last level shows the all-complete text instead), Level Select (the Levels screen over the
  lobby: `pushAndRemoveUntil` to the first route), then quiet Replay and Lobby side by side (Lobby: `popUntil` the first
  route; owner, 2026-10-17); Next Level, Level Select and Lobby navigate once.
  Tray full, Restart and the ad offer are `PremiumPanel` cards under the HUD (Back stays usable).
- First-play tutorial (owner, 2026-10-17): once per install, the first time play begins on a game screen (after the
  intro, at once with reduce motion) with the flag `tutorial.firstPlay.v1` unset (`SettingsRepository`), coach marks
  over the real board (`widgets/first_play_tutorial.dart`): 1 "Tap a free tile" (a free matching pair from
  `tutorialPairFor`: a symbol whose remaining tiles are all free, else a short solver search), 2 "It drops into your
  tray" (Next), 3 "Find its twin" (twin + tray lit), 4 "Keep your tray clear" (Next), 5 "Clear every pair to win"
  (Let's play). Dim scrim with gold-rimmed holes (a path and strokes, no blur), one pulsing ring on a tile to tap (none
  with reduce motion), card placed clear of the holes; only the lit tile can be tapped; the clock and combo window wait
  (`GameController.beginTutorial`/`endTutorial`, `resumeClock` holds); Skip (steps 1-4) or Android back ends it. The
  two taps are real moves. Finish or Skip sets the flag; a player with any won level is marked done and never sees
  it; killed mid-tutorial, it shows again; not started over a result card or with tiles in the tray (a resumed save).
  Test services (`testServices`, gameplay captures) mark it done unless `tutorialDone: false`.
- Win trophy (Level Complete): `assets/lottie/trophy_cup_rays.json` (LottieFiles, owner's premium licence) via `WinTrophy`, looping while the card is open
  (owner), last frame with reduce motion, `PremiumEmblem` fallback if it fails to load.
- Hint hand pointer: owner-supplied Lottie (`assets/lottie/hint_hand.json`, recoloured): the owner's `Hint.json`
  (v5.12.1, 512x512, 30 fps, 21 frames), only its colours changed (light-green fill → gold #F2C96B, green outline →
  dark green #183D2D, readable on both felts and on ivory tiles), still minified.
- Lobby update card and force update (owner, 2026-10-16): installed build below the notice's latest → "Update
  available" / "A new version of Brain Train is ready." (or the notice's `message`) with Update (gold) and Later, at
  most once per launch (Later or back hides it until the next launch; needs a `storeUrl`). Below its min → "Update
  required" / "This version of Brain Train is no longer supported. Please update to keep playing.", Update only, not
  dismissible (back does nothing), Play / Continue / Levels unreachable; still there after a trip to the
  store. Lobby only, never over a game. The live notice (2026-10-17): Android latest 10, min 10 (forced, after build 10 went live: 1.1.0+9 crashed at launch on Android); iOS unset.
- Google Play Games (owner, 2026-10-16) and Game Center (owner, 2026-10-17): Play Games on Android, Game Center on
  iOS; silent sign-in; two round lobby buttons top-right (Achievements, Leaderboards) open Google's / Apple's
  screens, signing in first when needed; no Settings entry. Pieces: 1 sign-in (done), 2 achievements + leaderboards
  (done 2026-10-17: 9 achievements, 23 leaderboards; see the Play Games rule above), 3 cloud save. Two phones on one
  account must never clash: piece 3 merges (union of wins, fastest time) before play; no hard one-device lock.
- Every launch: navy native screen (no icon) → `assets/video/sun_game_studio_intro.mp4`
  (Sun Game Studio) → Tile Park logo on white (`assets/branding/tile_park_logo.jpg`, at least
  2.2 s and until content is loaded) → lobby. Sequence lives in `lib/app/app.dart`. Once, at first launch (and
  once after updating from a version without it), the neutral age screen (`AgeScreen`: "What year were you born?",
  decade then year, nothing preselected, no hint of why) comes between the logo and the lobby; only the derived group
  (`privacy.ageGroup` = `under13` / `13plus`; the year someone may still be 12 counts as under 13) is stored, on the
  phone, never sent.
- App icon (owner, 2026-10-20; was the Brain Train emblem) = the Tile Park logo (`art/branding/tile-park-logo.png`,
  purple-framed board of tiles): cropped to its frame, corners filled with the frame purple #7432F4 (iOS, Play
  `art/store/icon-512.png`, legacy Android); Android 8+ adaptive = the board on a purple background, sized for the
  circle mask. Regenerate with `python3 tool/branding/make_tile_park_icons.py` (needs Pillow); never with
  `tool/assets/make_app_icon.py`, which still draws the old Brain Train emblem.
- No "Mahjong Solitaire" subtitle on the lobby.
- Look: emerald felt + botanical foliage, dark-green panels with fine gold borders, thick 3D tiles (owner, 2026-10-17):
  warm ivory face with a soft top-left-lit rim and fine inner edge, a light wall over an olive/emerald-green base on
  the right and bottom, a fine dark outline, a soft cast shadow down-right and a longer one under upper layers onto the
  tiles below. All baked once per face size (`MahjongTileRenderer.renderBody` / `renderRaisedShadow`), never blurred
  per frame. The face colour is one input, `TileStyle.faceColor` (`withFace(Color)`; highlight, rim and wall shades
  derive from it). Walls and shadows stay inside `TileStyle.edgeFraction` (fixed 0.2999 = `kFitEdgeFraction`, a test
  checks), so retuning the look never moves tiles. Fonts (bundled, redesign 1.1.0): Playfair Display (title, level names, headings; `kDisplayFont`,
  `displayText`) and Manrope (buttons, HUD, numbers, body; the theme's default text), the official variable TTFs from
  google/fonts in `assets/fonts/` (unmodified, OFL 1.1 with `OFL.txt` next to each; Playfair has a Reserved Font Name,
  so never make modified instances). Flutter sets the `wght` axis from `fontWeight`; no runtime download. Lobby buttons
  are frosted glass with fine gold rims (`FrostedGlass` + `StaticLayer`): Play/Continue gold with a dark green Manrope
  label, chevron, leaves at both ends and soft gold glow (`LobbyTheme.primaryGlass*`), Levels / Settings / round Play
  Games buttons dark-green glass (`secondaryGlass*`; icon + Manrope label centred, chevron); `primaryFill/Edge/Text`
  stay for the Levels panel medallion. Level `backdrop.colors` only tints the gameplay ambient light. Tune tiles in
  `TileStyle`, never the art. Playfair is bundled roman only (the italic was used only by the old tagline).
- Every tile everywhere (board, lobby hero) uses `MahjongTileRenderer`; no second tile renderer.
- Tablets (owner, 2026-10-17): `TabletScale` (`lib/app/tablet_scale.dart`, the `MaterialApp` builder) lays the whole UI out
  on a canvas whose shortest side is 600 and scales it to the screen (at most 1.75x) when the shortest side is 600+;
  phones are untouched. Code that maps between widgets via "global" coordinates (flights, shatter, intro, score popups,
  `StaticLayer` pixel snapping, board/tray face rects) must use `TabletScale.canvasAbove(box)` as the ancestor.
- Portrait only (owner, 2026-10-17): iOS `UISupportedInterfaceOrientations` portrait (iPad portrait + upside down,
  `UIRequiresFullScreen`), Android `MainActivity` `screenOrientation="portrait"`. iPhone and iPad are both supported
  (`TARGETED_DEVICE_FAMILY = "1,2"`).
- Store names (owner, 2026-10-20; was "Brain Train - Tile Match"): "Tile Park: Puzzles" on Google Play and the App
  Store; the home-screen name is "Tile Park" (`android:label`, iOS `CFBundleDisplayName`/`CFBundleName`; the long name
  would be cut off under the icon). The package / bundle ID stays `com.sungamestudio.braintrain` (Play never allows a
  change; a new ID would be a new app). The player sees Tile Park everywhere (lobby title, logo screen, update card,
  Settings version line); code identifiers, docs and tools still say Brain Train. Shipped as 1.1.0+13 (2026-10-20).

## Current state (2026-10-16)

- Redesign 1.1.0 in progress on `feat/redesign-1.1` (ships later as version 1.1.0): phase 1 design system (tokens,
  fonts, Day/Night/System setting) on `redesign/design-system`; phase 4 game actions (engine) on
  `redesign/game-actions`; phase 2 lobby (Day art, hero tiles, title, footer) and the Settings panel (theme cards,
  separate Music) on `redesign/lobby-settings`; phase 3 gameplay screen + Level Complete (top HUD, combo timer,
  action bar with ad refills, hint glow, shuffled-board drawing, restyled cards) on `redesign/gameplay`; phase 6 verify
  and polish on `redesign/verify` (bundled hero art, Day gameplay foliage and felt, status bar icons, round action
  ripples, combo pill clear of the wells, HUD names). Emulator pass (2026-10-17, profile build on TP_API36 1080x2400 and
  TP_Small 1080x1920, Linux): intro, age screen, lobby Day/Night (live switch), Settings, Levels, tutorial, Hint, Undo,
  Shuffle, a rewarded test ad for +1 Shuffle (granted), combo x5, Level Complete; no Flutter errors in logcat; ~60 fps
  idle in lobby and game (SurfaceFlinger latency: median 16.7 ms, p99 19-26 ms), a few 30-87 ms frames when a game
  opens (art decoding).

- Previous content 2026.10.17.2 (superseded by .17.3 below; its old R2 objects were deleted): 175 levels
  (`catalog.json` `campaign`, seed 20261641, chosen so levels 1–10 open 1 2 1 4 4 5 2 6 1 1): batch 1 = levels
  1–100, 10 per difficulty 1–10; batch 2 = levels 101–175, `{"9": 25, "10": 50}` (only fits as `10 10 9` repeats),
  added on 2026-10-17 with 16 new static symbols; levels 1–100 kept their boards, tiers, trays, titles and win rates
  (95 got new symbol codes). Trays 2–5, 85/15 symbols, at most 2 pairs per symbol; rules in
  docs/level-design-rules.md. The registry (`registries/symbols-c56cfec96e94.json`) holds 322 symbols: 211 static
  (set v1) and 111 animated, every one on some level (static 27–28 levels each, animated 9–10). Removed for the
  audience: 4 tiles in .12 for a 6+ Play rating (CINEMA_NO_SMOKING, TRIP_COCKTAIL, MONSTER_POOP, EMOJI_KNIFE: tobacco,
  alcohol, crude humour, weapon; IARC) and 8 in .17.1 for a 4+ App Store rating (WEAPON_* swords, ray guns, blaster,
  war hammer, EQUIP_CUTTER, EQUIP_STAPLE_GUN: "guns or other weapons"). Never add weapons, alcohol, tobacco, drugs or
  crude humour. The private bucket's frozen .12 copy (old Worker) is unchanged.
- Published content 2026.10.17.3 on `braintrain-public` (live since 2026-10-17, manifest `minClientContentSchema: 3`,
  grid 7x9; all 675 titles pinned in `campaign.titles`; `r2_prune --delete` removed the 372 objects of older versions
  the same day, so the bucket holds only .17.3 plus `app-update.json`): 675 levels, batch 3 = levels 176–675 `{"5": 84, "6": 84, "7": 83, "8": 83, "9": 83,
  "10": 83}`; every level regenerated for the fixed 7x9 grid, depth and coloured pairs (levels 1–175 keep difficulty,
  tray and title); tier bands in docs/level-design-rules.md (difficulty 10: 84–126 tiles, 4 layers); registry
  `registries/symbols-08ab2ec20da3.json`, 331 symbols (220 static, 61–62 levels each; 111 animated, 21–22 each). Random
  player: 1 99%, 2 92%, 3 70%, 4 46%, 5 35%, 6 15%, 7 4%, 8 0.1%, 9–10 0% (5 levels of difficulty 7 at 1.0–1.5%, just
  under the 2% floor); pair-seeking 64–69% at 8–10. The build takes ~32 s. Families per tier: 9 at difficulty 10, 12
  at 9, 13 at 8, 15–19 at 5–7; no family on two of three neighbouring levels; 675 unique titles. Previews:
  `PREVIEW_TREE=content/brain-train PREVIEW_LEVELS=level-0001,... [PREVIEW_PHONES=393x852,360x640,ipad-13]
  CAPTURE_DIR=<dir> flutter test test/visual/gameplay_capture_test.dart --plain-name "board previews"`.
- Simulated random-player win rate per difficulty (published .17.2, 200 games per level): 1 98%, 2 90%, 3 68%, 4 52%, 5 29%, 6 12%,
  7 2%, 8–10 0% (all 35 levels of 9 and all 60 of 10, batch 2 included; a pair-seeking player still wins ~40–50% of
  8–10, some star/towers boards under 3%). Every level is solver-proven and keeps tile faces
  >= 31 px wide on a 360x640 phone.
- Rebuild after new symbols: bump `contentVersion`, `dart run tool/content.dart build` (the registry key and the
  levels that rank a new code change by themselves), `validate`, `flutter test`, `publish --dry-run`, `publish`,
  `smoke_remote`.
- The app bundles only `content/starter/` (54 files, ~2.0 MB raw / ~1.0 MB compressed; the full tree was 11.2 MB /
  ~3.4 MB). A fresh install downloads only the manifest at first launch (its window is the starter pack); each win
  then fetches about one level file and its new symbols. With no starter pack, the window 1–5 is 5 level files +
  47 symbol files (~1.8 MB). Besides it, the lobby hero's 3 symbols (below) are bundled (55 KB).
- Lobby (redesign 1.1.0, reference panels 1-2): three hero tiles on a mossy ledge
  (`LobbyHero`: left leaf, middle sunflower forward and larger, right purple flower; real registry symbols drawn by
  `PremiumMahjongTile`, each slot the first code of `LobbyHero.slots` whose art is on the device, never the network:
  PLANT_POT_B / FLOWER_SUNFLOWER / FLOWER_PANSY, whose published files are bundled at their registry paths under
  `assets/lobby/hero/symbols/v1/` (`kHeroArtPrefix`, 55,494 bytes; the app's bundled source `bundledContent` reads the
  starter pack, then them, sha256-checked against the registry), so a fresh install shows them; the starter pack's
  XMAS_TREE / BIRD_PEACOCK / GALAXY_POMEGRANATE only if a later registry changes their art before it is cached), the
  gold Playfair title "Brain Train" (replaces the "Train your
  brain" tagline), then Play/Continue/Replay · Level N (always the first level not won; "Continue" only for a saved
  game of that level), "Levels", "Settings". Footer status line (owner, replaces "no N levels ready footer"): "N levels
  ready · v<contentVersion>" with N = window levels on the device now (`ContentController.windowReadiness`); a content
  notice (offline / update skipped / new content installed) takes the count's place; a Play Games notice replaces the
  line.
- Levels screen (`level_select_screen.dart`, title "Levels", owner): a panel with the next level to play (first not won; title, tier,
  size, tray; Play/Continue) and below it ("COMPLETED") ONLY the completed levels, in order, as a lazy list to replay from
  (one row each: number, title, tier badge, tiles, best time, date-time of that best win). Replays keep the
  fastest time and its date (`ProgressRepository.recordWin`).
- All levels won (owner): `AllLevelsCompleteNote` ("All N levels complete! New levels are coming soon.") in the
  lobby (Play becomes "Replay · Level N") and in place of the next-level panel on Levels; the last
  level's win card says so instead of "Next level". No list of all levels and no locked cells; an empty message before the first win.
  Tray UI lays out 2 to 5 wells.
- Static art pipeline: `art/asset_sources.json` → `python3 tool/assets/prepare_symbols.py` → `content/brain-train/symbols/v1/`
  (image set renamed v4 → v1 on 2026-10-16: `art/source/symbols-v1/`, `art/masters/v1/`, `art/review/v1-contact-sheet.png`).
  Animated: `art/animated_sources.json` → `python3 tool/assets/prepare_animated.py` → `content/brain-train/animated-symbols/`.
  Originals live in `art/source/` (gitignored). IconScout downloads use the owner's subscription via the iconscout MCP.
- Art sources: each entry has a `status`; builds take only `integrated` ones. Static: 220 integrated (82 earlier +
  23 owner nano-banana cut-outs + 76 IconScout 3D Sport/Christmas/Tech/Robot/Cinema/Trip + 24 from the Sport, Sport
  Equipment, Equipment and Medicine packs, minus 2 rejected for 6+ and 8 for 4+; + 16 on 2026-10-17 from the User
  Interface, Shopping And Sale, Internet Marketing, Travel & Holiday and Valentine's Day 3D packs: `SHOP_*`, `UI_*`,
  `MKT_EMAIL`, `TRIP2_*`, `LOVE2_*`; the rest of those packs was screened out from previews; + 9 seasonal on
  2026-10-17 from 8 Christmas/Halloween 3D packs: `HALLOWEEN_*` candy bucket, witch hat, broom, bat, moon, candies,
  cauldron, lollipop and `XMAS2_LIGHTS`, friendly items only, nothing scary), 75 `rejected` (unreadable at 31 px,
  look-alikes, duplicates, `SHOP_CREDIT_CARD` as a payment card for under-13 players, `HALLOWEEN_BROOM_YELLOW` reading
  as a bell; each has a reason), 16 `awaiting download`. Duplicate subjects are never added (owner). Animated: 111 integrated (2 rejected for 6+; 83 earlier +
  9 owner LottieFiles `LF_*` + India map + 20 country flags `FLAG_*` restyled with a zoom), rejected ones have a
  reason. Check new art at 31 px and 64 px tile width.
- Not yet integrated: 4 IconScout AI images (spring rolls ×2, salad, nachos) — not reachable via the IconScout API.
- Tray mechanic is integrated (tray at the top, flights, strike-and-shatter matches, Tray full card with
  Revive / Restart), with 2 to 5 slots per level.
- App version 1.1.0+11 (2026-10-17, `feat/action-cap`): each of Undo, Hint and Shuffle at most 2 uses per level
  attempt (1 free + 1 after an ad), then its button disappears (see Game actions).
  1.1.0+10 (2026-10-17): fixes a launch crash of every Android release build ("Failed to create an instance
  of androidx.work.impl.WorkDatabase": R8 full mode removed `WorkDatabase_Impl`'s no-arg constructor, which the
  room-runtime 2.2.5 keep rule pulled in by the ads SDK's WorkManager does not keep); `android/app/proguard-rules.pro`
  keeps `<init>()` of every `RoomDatabase`. Debug builds skip R8, so only release builds showed it: test a release APK
  (`flutter build apk --release`) on an emulator before every store upload.
  1.1.0+9 (2026-10-17, for App Review and Play; crashes at launch on Android, replaced by +10): no-ad fallback for rewarded ads (free after
  `kAdFallbackDelay` while online), at most 2 revives per level attempt, new strike sound. 1.1.0+8 (redesign, `feat/redesign-1.1`): Day/Night/System looks, new lobby, Settings, gameplay HUD, Undo / Hint / Shuffle, Level Complete, iOS min 15.0. 1.0.0+7 (2026-10-17): first-play tutorial, Play Games for 13+ only. 1.0.0+6: real AdMob IDs. 1.0.0+5: new content host, update popup, iOS release settings. 1.0.0+4 (`feat/rewarded-ads`, merged into `feat/campaign-v2`): rewarded ads on Revive, age screen,
  Privacy choices row, built with Google's AdMob test IDs (`google_mobile_ads` 9.1.0). This bundle (66.7 MB AAB,
  19.2 MB install) is the Closed testing - Alpha release in the Play Console.
- Play Store listing (owner-approved): texts in `art/store/listing-en-US.md`, `art/store/icon-512.png`,
  `art/store/feature-graphic.png` (1024x500), 6 phone screenshots in `art/store/phone/` (1080x1920, from
  `test/visual/` captures, taken before ads). AI asset declaration: "Don't label assets" (owner).
  Store screenshots (2026-10-17, `test/visual/store_screenshots_test.dart`, content .17.1): raw `art/store/phone/`,
  `art/store/ios/iphone-6.9/` (1320x2868), `art/store/ios/ipad-13/` (2064x2752); framed versions with captions in
  `art/store/styled/{play-phone,iphone-6.9,ipad-13}/` (`tool/store/make_store_shots.py`).
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
  machine 817 pass and 17 skip with the full content tree (2026-10-17, content 2026.10.17.3 draft); on the Mac 6 failed before
  (see Open work).
- Run on a Mac (iPhone simulator) or any machine with no secrets: `flutter pub get && flutter run`. Debug builds read
  content from the public host, use Google's test AdMob IDs, skip Play Games (no app ID; iOS uses Game Center) and
  use debug signing;
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
- App Store Connect (2026-10-17): individual account, Team ID `A47UYXZH7P` (`DEVELOPMENT_TEAM` in the Runner target);
  bundle ID registered; app "Brain Train - Tile Match", Apple ID `6823729570` (store URL after release:
  `https://apps.apple.com/app/id6823729570`), SKU `braintrain-ios`, Games › Puzzle + Board, age rating 4+ (not "Made
  for Kids"), free in all 175 countries, App Privacy published (Google Mobile Ads SDK data: coarse location, device
  ID, product interaction, advertising data for third-party ads + analytics, not linked, tracking; diagnostics for
  analytics), version 1.0 texts and URLs saved. `Info.plist`: `ITSAppUsesNonExemptEncryption` false; app privacy
  manifest `ios/Runner/PrivacyInfo.xcprivacy` (no tracking by the app's own code; UserDefaults CA92.1). Still to do:
  screenshots, App Review contact, real AdMob iOS IDs, build upload. Game Center (2026-10-17): the 9 achievements
  `bt.ach.*` (300 points) and 23 Classic leaderboards `bt.lb.*` of `lib/platform/game_services_ids.dart` are created
  with en-US texts and the `art/play-games/` icons (Fastest Time: Elapsed Time to the hundredth, low to high; the rest
  Integer, high to low); still to do: turn on Game Center for the version and add them there for review.
- Play Console release state (2026-10-16): every App content declaration is done (privacy policy, ads = yes,
  Advertising ID, content rating, target audience 6+ incl. under 13 (Families), Data safety, Health/Financial/
  Government); category Puzzle; store listing saved. Closed testing - Alpha: versionCode 4 (1.0.0), all countries,
  testers = Google Group sungamestudiotesters@googlegroups.com, feedback contact@sungamestudio.com. Its 16 changes sit
  in Publishing overview, not yet sent for review (owner decides; Google Play Games on PC is opted in by default).
  Production needs 12+ opted-in testers for 14 days, then real AdMob IDs.
- AdMob (2026-10-17): account ca-app-pub-6766349950907943 (under review; apps "Brain Train - Tile Match" show limited
  ad serving until linked to a published store listing: after each release, AdMob → the app → "Add store" to link it;
  until then the no-ad fallback makes Revive and refills free while online). iOS app `~6846744759`, rewarded "Revive" unit `/7563920896`
  (in `ios/Runner/Info.plist`); Android app `~8517909911`, rewarded "Revive" unit `/5905943038` (in gitignored
  `android/admob.properties` on the Linux machine; copy it to another machine like `key.properties`).
- Open work (ads, docs/ADS.md "Owner setup"): AdMob account, app and "Revive" rewarded unit → real IDs in
  `android/admob.properties` and `ios/Runner/Info.plist`; app-ads.txt on sungamestudio.com; AdMob Families /
  mixed-audience settings and a published GDPR consent message; Play Console Ads, Advertising ID, Target audience and
  Data safety answers. The iOS `AppDelegate.swift` channel (`rewardedAdUnitId`) is untested until the first Xcode build.
- Open work (owner, 2026-10-20): App Store screenshots still show Brain Train (Apple locks them while 1.1.0 build 13 is
  in review); upload `art/store/styled/iphone-6.9/` and `art/store/styled/ipad-13/` (Tile Park, Night) with the next
  iOS version. Google Play's screenshots and feature graphic are already Tile Park.
- Open work: Play Games piece 3 (cloud save). Piece 2 (achievements + leaderboards, Play Games and Game Center) is
  implemented (2026-10-17); the owner still publishes the Play Games configuration (Play Console → Play Games
  Services → Publishing; only testers see it until then) and finishes Game Center in App Store Connect. The iOS
  Game Center path is untested until the first Xcode build. Scoring + combo is implemented (4 s window).
- Open work: Play Games / scoring follow-ups after the PR #2 merge: run an iOS build on a Mac with full Xcode (iOS min
  15.0, never built yet).
- Open work: 5–6 tests fail on this Mac (predate PR #2): RenderFlex overflow of 4.4 px at
  `lib/features/levels/level_select_screen.dart:232` (Completed Levels row) — level_select_test (2), level_loader_test (1),
  lobby_capture_test (2, per-phone "home, levels, settings"), gameplay_capture_test ("tray-full overlay 360x640 at 1.3x
  text"). Owner to decide.

Keep this file current when commands, layout, or these rules change.
