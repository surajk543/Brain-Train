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
flutter build appbundle                 # Play upload; needs android/key.properties (+ play_games.properties for Play Games)
dart run tool/content.dart build        # content-src/ -> content/brain-train/ (campaign: generate + solve + simulate + hash)
dart run tool/content.dart validate     # check content/brain-train/ like the app, plus solver
dart run tool/content.dart stats        # simulated tray-player win rates per tier of the built tree
dart run tool/publish.dart --dry-run    # then without --dry-run to upload to R2 (parallel, manifest last)
dart run tool/r2_prune.dart             # list R2 objects the live manifest no longer uses (--delete: owner only)
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
  older cached level files); `content_files.dart` (level file encoding, content-addressed keys).
- `lib/rendering/` — tile body rasterizer, symbol art cache, board painter, effects.
- `lib/features/` — screens. `levels/` Completed Levels (`LevelSelectScreen`), `LevelLoaderScreen`
  (`level_loader.dart`: every game opens through it — the game at once when the level is on the device, else
  "Downloading level…", or offline "Connect to the internet to download this level"), `DifficultyStyle`; `home/` lobby (hero tiles, title, footer widgets; `widgets/lobby_buttons.dart` glass buttons via `_LobbyGlass`;
  `widgets/lobby_play_games.dart` round Play Games buttons);
  `gameplay/` (`game_controller.dart` glues engine + UI; `widgets/premium_chrome.dart` HUD, felt
  backdrop, dialogs; `widgets/tray_view.dart` tray + `TrayController`; `widgets/tile_flight_overlay.dart`
  board↔tray flights + `TrayFlightDirector`; `widgets/tile_shatter.dart` match strike + shards;
  `widgets/tile_art.dart` single-tile art; `widgets/board_intro.dart` level-start intro; `widgets/win_trophy.dart` trophy Lottie
  on the win card; `widgets/combo_badge.dart`, `widgets/score_popups.dart`); `common/` shared lobby chrome, `glass_painters.dart` (`GlassRimPainter`/`GlassShadowPainter`), `PremiumMahjongTile`,
  lobby background + fireflies; `intro/` studio video + logo screen.
- `lib/app/` — `AppServices` (wiring), `AppScope` (above `MaterialApp`), `theme.dart`
  (`BrainTrainPalette.night`, `LobbyTheme.night`), `brand.dart` (serif display font, gold),
  `sound_effects.dart`, `play_games_controller.dart` (lobby Play Games state).
- `lib/platform/` — `play_games.dart` (`PlayGames` interface, statuses, `UnavailablePlayGames`, pure Dart);
  `games_services_play_games.dart` (the only file importing `games_services`; `createPlayGames()`).
- `content-src/` — authoring: `catalog.json` (`campaign`: seed, tiers, counts, bands). `layouts/*.layout.json`
  are the old hand layouts (not in the catalog; the tool still accepts catalog `levels` entries).
- `content/brain-train/` — generated, published tree (not in git; local output of `tool/content.dart build`,
  uploaded by `tool/publish.dart`). Mirrors R2 keys `brain-train/...`.
- `content/starter/` — the starter pack, committed and the only content in pubspec: the full manifest and the
  registry (metadata of all levels), levels 1–5 and only their art (~2 MB). Written by `tool/content.dart build`.
- `art/` — `asset_sources.json` (IconScout attribution + status), masters, review sheets.
  `art/source/` (licensed originals) is gitignored.
- `infra/cloudflare/braintrain-assets/worker.js` — the deployed Worker's source of truth.
- `docs/` — `level-design-rules.md` (all level rules: difficulty 1–10, tray 2–5, 85/15, batches),
  `CONTENT_PUBLISHING.md`, `ASSET_PIPELINE.md`.

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
  (`GameEngine.revive`, unlimited, not a move) puts all the tray tiles back in their board places. Saves store the tap sequence plus `GameEngine.reviveMarker` entries
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
  by several levels once. Top-ups: at start, after every win, on app resume, and on a backoff timer while offline
  (`ContentController`). Nothing is ever evicted; a level that was ever ready replays offline, after a content
  update too (from its older cached file, `CachedLevel` index, until the new file is cached). Other levels download
  on demand when opened. A newer manifest becomes active only once its registry and its window are cached; never a
  downgrade. Startup never waits for the network (`loadInitial` + `warmUp` read only cache and bundle).
- Play Games (Android only, docs/PLAY_GAMES.md): optional and never on the startup path (a local channel check in
  `AppServices.create`; sign-in starts after the lobby's first frame). Only `games_services_play_games.dart`
  imports the plugin; every call is caught and timed out. The app ID comes from gitignored
  `android/play_games.properties`; without it `PlayGamesInitProvider` is disabled and Dart sees
  `UnavailablePlayGames`. Release signing reads gitignored `android/key.properties`. iOS min is 14.0 (plugin).
- Scoring (owner): a match scores `100 x min(combo, 5)` + speed bonus (+50 gap < 1 s, +25 < 2 s, +10 for 2-4 s);
  combo window 4 s on the game clock (pauses with it), every match restarts it from that match, a gap > 4 s starts over
  at x1; only `TapOutcome.matched` scores; a blocked-tile tap costs 1 (never below 0) and ends the combo; Revive ends
  the combo; Restart resets. State is `SavedGame.scoring`; `LevelRecord.bestScore/bestCombo` only go up. The combo badge
  floats on the tray's bottom edge: never add layout space between tray and board (31-px faces).
- The app never holds R2 keys or `ASSET_TOKEN_SECRET`. `.env` is gitignored and used only by tools.
- R2 bucket `braintrain` is private. Worker `braintrain-assets` serves `brain-train/*` publicly (GET/HEAD);
  all other keys need an HMAC token (`aud: "bt-assets"`, max 10 min).
- Content host is `ContentConfig.production` (`braintrain-assets.surajk543.workers.dev`), not
  `assets.sungamestudio.com` (that is the king-teenpatti bucket's public domain).

## Product decisions (from the owner)

- Night look only: no day mode, no theme setting. `MaterialApp` is always dark.
- Settings contains only Sound, Vibration and the app version. Do not add other options.
- Background music `assets/music/water_flowing.mp3` loops at volume 0.6 (`lib/app/background_music.dart`),
  starts after the studio intro, pauses in background, and follows the Sound switch (no separate music toggle).
- Sounds: `assets/sounds/tap.wav` (one tap cut from the owner's Tap.mp3) on every playable tap; `assets/sounds/strike.wav` (one hit cut from the owner's strike.mp3, 0.95 s) is `Sfx.match`, played when a matched pair strikes in the tray; the last pair's strike is followed by `Sfx.win` 450 ms later.
- No Undo and no Hint in the game; Restart is the only action (the engine has no undo). Reachable from the round HUD
  icon (`PremiumRoundIconButton`, right end; only while playing, not during the intro or result cards) with a confirm
  card "Restart this level?" / "Your score and time start over." (Restart / Keep playing; clock paused, Android back
  closes it), from the Tray full card and from the win card (Replay).
- HUD shows SCORE where Moves was (owner); the win card and Completed Levels show score, best score and best combo.
- Win card ("Level complete!"): `assets/lottie/trophy_cup_rays.json` (LottieFiles, owner's premium licence) via `WinTrophy`, looping while the card is open
  (owner), last frame with reduce motion, `PremiumEmblem` fallback if it fails to load.
- Google Play Games (owner, 2026-10-16): Android only; silent sign-in; two round lobby buttons top-right
  (Achievements, Leaderboards) open Google's screens, signing in first when needed; no Settings entry.
  Pieces: 1 sign-in (done), 2 achievements + leaderboards, 3 cloud save. Two phones on one account must never
  clash: piece 3 merges (union of wins, fastest time) before play; no hard one-device lock.
- Every launch: navy native screen (no icon) → `assets/video/sun_game_studio_intro.mp4`
  (Sun Game Studio) → Brain Train logo on white (`assets/branding/brain_train_logo.jpg`, at least
  2.2 s and until content is loaded) → lobby. Sequence lives in `lib/app/app.dart`.
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

- Published content 2026.10.16.11 (manifest `minClientContentSchema: 3`, from branch `feat/campaign-v2`): a fresh
  campaign of 100 levels, one batch of 10 per difficulty 1–10 (`catalog.json` `campaign`, seed 20261641, chosen so
  levels 1–10 open 1 2 1 4 4 5 2 6 1 1), trays 2–5, 85/15 symbols, at most 2 pairs per symbol; rules in
  docs/level-design-rules.md. The registry (`registries/symbols-125d9a47d9b6.json`) holds 318 symbols: 205 static
  (set v1) and 113 animated, every one on some level (static 10–11 levels each, animated 3–4). Apps built before
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
- Art sources: each entry has a `status`; builds take only `integrated` ones. Static: 205 integrated (82 earlier +
  23 owner nano-banana cut-outs + 76 IconScout 3D Sport/Christmas/Tech/Robot/Cinema/Trip + 24 from the Sport, Sport
  Equipment, Equipment and Medicine packs), 58 `rejected` (unreadable at 31 px, look-alikes, duplicates; each has a
  reason), 16 `awaiting download`. Duplicate subjects are never added (owner). Animated: 113 integrated (83 earlier +
  9 owner LottieFiles `LF_*` + India map + 20 country flags `FLAG_*` restyled with a zoom), rejected ones have a
  reason. Check new art at 31 px and 64 px tile width.
- Not yet integrated: 4 IconScout AI images (spring rolls ×2, salad, nachos) — not reachable via the IconScout API.
- Tray mechanic is integrated (tray at the top, flights, strike-and-shatter matches, Tray full card with
  Revive / Restart), with 2 to 5 slots per level.

## Working on another machine

- Code: `master` (repo private; PR #1 `feat/brain-train-game` and PR #2 `feat/play-games` are merged).
  `git clone https://github.com/surajk543/Brain-Train.git && cd Brain-Train && flutter pub get`. Branch from `master`
  for new work. Latest handoff notes: `docs/superpowers/handoff-2026-10-16.md`.
  Flutter 3.44.7 / Dart 3.12.2. Android SDK + AVD (`Pixel_6_API_34` on the old machine;
  `emulator -avd Pixel_6_API_34 -gpu host -no-snapshot-load`). This Mac: Flutter `~/flutter`, SDK
  `/opt/homebrew/share/android-commandlinetools`, AVD `Pixel_9` = Play Store image (use for Play Games), `TP_*` AVDs
  have no Play Store, `Pixel_6_API_34` does not exist. Python 3 + Pillow for `tool/assets/*.py`, ffmpeg for audio.
- `flutter analyze` and `flutter test` work on a fresh clone (tests use fixtures and `content/starter/`); on this Mac 6
  tests currently fail (see Open work).
- Content tree: `content/brain-train/` is not in git. Before `tool/content.dart build|validate` or `tool/publish.dart`
  on a new machine, mirror the live tree: `dart run tool/fetch_content.dart` (public prefix, no keys, sha256-checked).
- Secrets: copy `.env` by a secure channel (password manager), never git/chat/email, likewise `android/key.properties`,
  `android/play_games.properties` and the upload keystore. Keys: `R2_ACCOUNT_ID`,
  `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `R2_BUCKET_NAME`, `ASSET_TOKEN_SECRET`. Only publishing needs it.
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
- Open work: Play Games pieces 2–3 (piece 2 builds on `bestScore`/`bestCombo`; publishing the PGS configuration needs
  at least 5 achievements). Scoring + combo is implemented (4 s window).
- Open work: Play Games / scoring follow-ups after the PR #2 merge: run an iOS build on a Mac with full Xcode (iOS min
  14.0, never built yet); check the combo pill on a phone (its top overlaps the tray wells by ~5 px at 360×640).
- Open work: 5–6 tests fail on this Mac (predate PR #2): RenderFlex overflow of 4.4 px at
  `lib/features/levels/level_select_screen.dart:232` (Completed Levels row) — level_select_test (2), level_loader_test (1),
  lobby_capture_test (2, per-phone "home, levels, settings"), gameplay_capture_test ("tray-full overlay 360x640 at 1.3x
  text"). Owner to decide.

Keep this file current when commands, layout, or these rules change.
