# Brain Train — notes for Claude

Flutter Mahjong Solitaire game. Android + iOS. App ID `com.sungamestudio.braintrain` (do not change).
Levels, symbols and artwork are data. Cloudflare R2 is the source of truth: the app downloads level files and
the art they use on demand (the next 5 levels are kept on the phone) and bundles only a starter pack (levels 1–5).

## Commands (run from repo root)

```bash
flutter pub get
flutter analyze                         # must be clean
flutter test                            # unit + widget tests, no network
flutter run -d emulator-5554            # AVDs: Pixel_6_API_34, Pixel7_Play_API36
dart run tool/content.dart build        # content-src/ -> content/brain-train/ (campaign: generate + solve + simulate + hash)
dart run tool/content.dart validate     # check content/brain-train/ like the app, plus solver
dart run tool/content.dart stats        # simulated tray-player win rates per tier of the built tree
dart run tool/publish.dart --dry-run    # then without --dry-run to upload to R2 (parallel, manifest last)
python3 tool/assets/prepare_symbols.py [--placeholders]   # art -> WebP symbols
python3 tool/assets/make_app_icon.py    # launcher icons from the logo emblem (Android + iOS)
python3 tool/assets/make_foliage.py     # gameplay edge foliage -> assets/decor/
python3 tool/assets/make_lobby_art.py   # lobby night art -> assets/lobby/
python3 tool/assets/make_sounds.py      # sound effects -> assets/sounds/
CAPTURE_DIR=/tmp/x flutter test test/visual/   # write screenshots of lobby/gameplay at phone sizes
dart run tool/smoke_remote.dart         # live check: app's content client vs production R2 (+ levels 1/57/128/200)
```

## Layout

- `lib/game_engine/` — pure Dart, no Flutter imports (tools import it). Models, geometry
  (`BoardGeometry`, `TileAvailabilityCalculator`, `BoardProjection`, `TileHitTester`), rules
  (`MatchRules`), `GameEngine`, `MahjongSolver`, `LevelValidator`, `LevelGenerator` (hand layouts),
  `TraySimulator` (simulated tray player). `campaign/`: `CampaignConfig` (tiers from the catalog),
  `scheduleTiers`, `board_shapes.dart` (22 symmetric shape families + stacking programs),
  `CampaignGenerator`, `LevelDecor` (titles, backdrops), `SeededRandom`/`stableHash` (pinned PRNG).
- `lib/content/` — pure Dart except `file_content_store.dart` (dart:io). Manifest, registry and
  level loading; permanent disk cache (`ContentCache`, with the ready-level index); `ContentCoordinator`
  (known-good / starter pack, gated version switch, 5-level window, on-demand `ensureLevel`, offline fallback to
  older cached level files); `content_files.dart` (level file encoding, content-addressed keys).
- `lib/rendering/` — tile body rasterizer, symbol art cache, board painter, effects.
- `lib/features/` — screens. `levels/` Completed Levels (`LevelSelectScreen`), `LevelLoaderScreen`
  (`level_loader.dart`: every game opens through it — the game at once when the level is on the device, else
  "Downloading level…", or offline "Connect to the internet to download this level"), `DifficultyStyle`; `home/` lobby (hero tiles, title, buttons, footer widgets);
  `gameplay/` (`game_controller.dart` glues engine + UI; `widgets/premium_chrome.dart` HUD, felt
  backdrop, dialogs; `widgets/tray_view.dart` tray + `TrayController`; `widgets/tile_flight_overlay.dart`
  board↔tray flights + `TrayFlightDirector`; `widgets/tile_shatter.dart` match strike + shards;
  `widgets/tile_art.dart` single-tile art; `widgets/board_intro.dart` level-start intro); `common/` shared lobby chrome, `PremiumMahjongTile`,
  lobby background + fireflies; `intro/` studio video + logo screen.
- `lib/app/` — `AppServices` (wiring), `AppScope` (above `MaterialApp`), `theme.dart`
  (`BrainTrainPalette.night`, `LobbyTheme.night`), `brand.dart` (serif display font, gold),
  `sound_effects.dart`.
- `content-src/` — authoring: `catalog.json` (`campaign`: seed, tiers, counts, bands). `layouts/*.layout.json`
  are the old hand layouts (not in the catalog; the tool still accepts catalog `levels` entries).
- `content/brain-train/` — generated, published tree (not in git; local output of `tool/content.dart build`,
  uploaded by `tool/publish.dart`). Mirrors R2 keys `brain-train/...`.
- `content/starter/` — the starter pack, committed and the only content in pubspec: the full manifest and the
  registry (metadata of all levels), levels 1–5 and only their art (~2 MB). Written by `tool/content.dart build`.
- `art/` — `asset_sources.json` (IconScout attribution + status), masters, review sheets.
  `art/source/` (licensed originals) is gitignored.
- `infra/cloudflare/braintrain-assets/worker.js` — the deployed Worker's source of truth.
- `docs/` — `CONTENT_PUBLISHING.md`, `ASSET_PIPELINE.md`.

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
- Play goes through a tray whose size is per level: `rules.trayCapacity` = 4 by default (and when absent), 5 for
  hard and very hard levels; the validator allows 4 or 5, and `GameEngine`/`GameController`/`TrayController`
  take it from the level (old builds ignore the field and play with 4, which is safe: every level is
  pair-solvable). A tapped free tile leaves the board for the tray; if it matches a tray tile both clear;
  `capacity` tiles without a match lose (`GameStatus.trayFull`) and show a Revive / Restart card. Revive
  (`GameEngine.revive`, unlimited, not a move) puts all the tray tiles back in their board places. Saves store the tap sequence plus `GameEngine.reviveMarker` entries
  (`progress.current.v2`); a tray-full game is saved so it can be revived later. Solver/generator still prove
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
  board. Length by tier (`IntroTiming`: easy 2.0 s, medium 2.3, hard 2.6, very hard 3.0; by tile count without a
  tier); fly-in always 0.8 s, the extra time goes to the mix and a calmer settle; mix style per level
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
- 70/30 rule: each level has `floor(30% of pairs)` animated pairs (at least 1, never above 30%), the rest
  static; at most 12 distinct animated symbols per level (`SymbolFrameAtlas` renders each once per frame
  step, so big boards reuse one for 2+ pairs). Codes per level come from rendezvous hashing (level × code):
  new symbols change only codes, never boards, tiers, titles or win rates.
- Tiers are data (`campaign.tiers`): `easy`, `medium`, `hard`, `veryHard`, 50 levels each, seeded shuffle,
  level 1 easy, never 3 of a tier in a row; stored as `difficulty` in levels and manifest. The app labels any
  id (`difficultyLabel`: "Very Hard") and colours the badge (`DifficultyStyle`).
- Content delivery (owner): R2 is the source of truth; static and animated symbol files live only there (plus the
  starter pack's). The app downloads the manifest (every level's title, tier, tile count and `trayCapacity`, so
  lists and panels never need level files) and the registry in the background, and keeps a rolling window of the
  next 5 levels (first level not won + the 4 after it) on disk: level file + only the art it uses, a symbol shared
  by several levels once. Top-ups: at start, after every win, on app resume, and on a backoff timer while offline
  (`ContentController`). Nothing is ever evicted; a level that was ever ready replays offline, after a content
  update too (from its older cached file, `CachedLevel` index, until the new file is cached). Other levels download
  on demand when opened. A newer manifest becomes active only once its registry and its window are cached; never a
  downgrade. Startup never waits for the network (`loadInitial` + `warmUp` read only cache and bundle).
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
- No Undo and no Hint in the game; Restart is the only action (the engine has no undo).
- Every launch: navy native screen (no icon) → `assets/video/sun_game_studio_intro.mp4`
  (Sun Game Studio) → Brain Train logo on white (`assets/branding/brain_train_logo.jpg`, at least
  2.2 s and until content is loaded) → lobby. Sequence lives in `lib/app/app.dart`.
- App icon = the round emblem of the official logo (`art/branding/brain-train-logo.jpg`), adaptive on
  Android 8+. Regenerate with `python3 tool/assets/make_app_icon.py`.
- No "Mahjong Solitaire" subtitle on the lobby.
- Look: emerald felt + botanical foliage, dark-green panels with fine gold borders, serif display
  type (`brand.dart`), warm ivory tiles with olive-green underside. Level `backdrop.colors` only tints
  the gameplay ambient light. Tune tiles in `TileStyle`, never the art.
- Every tile everywhere (board, lobby hero) uses `MahjongTileRenderer`; no second tile renderer.

## Current state (2026-10-16)

- Published content 2026.10.16.10 (manifest `minClientContentSchema: 2`; .10 = .9 plus `trayCapacity` per manifest
  entry, no other object changed): a generated campaign of 200 levels
  (`catalog.json` `campaign`, seed 20261039, chosen so levels 2–4 are easy/medium), content-addressed keys.
  The registry (`registries/symbols-b932cfbdc9d6.json`) holds every integrated symbol: 82 static (set v4: owner
  cut-outs + IconScout 3D/illustration packs) and 83 animated (IconScout Lottie: Emoji, Valentine, Dog, Cute
  Monster, Shapes Loader restyled bold/coloured). 100 static IconScout entries are `awaiting download`
  (IconScout 3D downloads hit a daily limit); finish them, then rebuild and publish.
- Tiers (50 each; tiles / layers / tray / simulated random-player win rate over 200 games per level):
  easy 24–48 / 1–2 / 4 / ~92%; medium 48–78 / 2–3 / 4 / ~42%; hard 84–120 / 3–4 / 5 / ~13%;
  very hard 144–172 / 5–7 / 5 / ~0% (a pair-seeking player wins ~58%). Every level is solver-proven and keeps
  tile faces >= 31 px wide on a 360x640 phone.
- Rebuild after new symbols: bump `contentVersion`, `dart run tool/content.dart build` (the registry key and the
  levels that rank a new code change by themselves), `validate`, `flutter test`, `publish --dry-run`, `publish`,
  `smoke_remote`.
- The app bundles only `content/starter/` (54 files, ~2.0 MB raw / ~1.0 MB compressed; the full tree was 11.2 MB /
  ~3.4 MB). A fresh install downloads only the manifest at first launch (its window is the starter pack); each win
  then fetches about one level file and its new symbols. With no starter pack, the window 1–5 is 5 level files +
  47 symbol files (~1.8 MB).
- Lobby menu: Play/Continue, "Completed Levels", Settings. No "N levels ready" footer (owner); the footer only
  shows a content notice (offline / update skipped / new content installed).
- "Completed Levels" screen (`level_select_screen.dart`, owner): a panel with the next level to play (title, tier,
  size, tray; Play/Continue) and below it ONLY the completed levels, in order, as a lazy list to replay from
  (one row each: number, title, tier badge, tiles, best time, date-time of that best win). Replays keep the
  fastest time and its date (`ProgressRepository.recordWin`).
- All levels won (owner): `AllLevelsCompleteNote` ("All N levels complete! New levels are coming soon.") in the
  lobby (Play becomes "Replay · Level N") and in place of the next-level panel on Completed Levels; the last
  level's win card says so instead of "Next level". No list of all levels and no locked cells; an empty message before the first win.
  Tray UI lays out 4 or 5 wells.
- Static art pipeline: `art/asset_sources.json` → `python3 tool/assets/prepare_symbols.py` → `content/brain-train/symbols/v4/`.
  Animated: `art/animated_sources.json` → `python3 tool/assets/prepare_animated.py` → `content/brain-train/animated-symbols/`.
  Originals live in `art/source/` (gitignored). IconScout downloads use the owner's subscription via the iconscout MCP.
- Art sources: each entry has a `status`; builds take only `integrated` ones. Static: 82 integrated (62 original
  + 6 fitness `FIT_*` + 5 `JULY4_*` + 9 `SPORT_*`), 3 `rejected` (unreadable at 31 px), 100 `awaiting download`
  (rest of Sport + Christmas `XMAS_*`, Technology `TECH_*`, Robot & AI `ROBOT_*`, Cinema `CINEMA_*`, Holiday Trip
  `TRIP_*`: IconScout 3D downloads failed with server errors after ~24 that day; rerun the download, copy to
  `art/source/symbols-v4/<expectedSourceFile>.png`, `prepare_symbols.py`, check at 31 px, set `integrated`).
  Animated: 83 integrated (50 + Cute Monster `MONSTER_*` 20 + Shapes Loader `SHAPE_*` 13, restyled bold/coloured
  via `restyle` into `*-bold.json`), 5 `SHAPE_*` rejected. Check new art at 31 px and 64 px tile width.
- Not yet integrated: 4 IconScout AI images (spring rolls ×2, salad, nachos) — not reachable via the IconScout API.
- Tray mechanic is integrated (tray at the top, flights, strike-and-shatter matches, Tray full card with
  Revive / Restart), with 4 or 5 slots per level.

## Working on another machine

- Code: branch `feat/brain-train-game` (PR #1, repo private).
  `git clone https://github.com/surajk543/Brain-Train.git && cd Brain-Train && git switch feat/brain-train-game && flutter pub get`.
  Flutter 3.44.7 / Dart 3.12.2. Android SDK + AVD `Pixel_6_API_34`
  (`emulator -avd Pixel_6_API_34 -gpu host -no-snapshot-load`). Python 3 + Pillow for `tool/assets/*.py`, ffmpeg for audio.
- `flutter analyze` and `flutter test` work on a fresh clone (tests use fixtures and `content/starter/`).
- Content tree: `content/brain-train/` is not in git. Before `tool/content.dart build|validate` or `tool/publish.dart`
  on a new machine, mirror the live tree: `dart run tool/fetch_content.dart` (public prefix, no keys, sha256-checked).
- Secrets: copy `.env` by a secure channel (password manager), never git/chat/email. Keys: `R2_ACCOUNT_ID`,
  `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `R2_BUCKET_NAME`, `ASSET_TOKEN_SECRET`. Only publishing needs it.
- Licensed originals `art/source/` are not in git; needed only to re-process art. Re-download through the IconScout
  MCP (`claude mcp add --transport http iconscout https://mcp.iconscout.com/mcp`) from `art/asset_sources.json` /
  `art/animated_sources.json` (`sourceUrl`; slug `<name>_<assetId>`). IconScout caps 3D downloads at ~24/day.
- Open work: 100 static entries `awaiting download` in `art/asset_sources.json` (then prepare_symbols, build, bump
  contentVersion, publish); a frame-time slowdown after hours of play on the emulator (Impeller GLES; watch
  `adb logcat | grep app_time_stats`, app restart resets it) is not explained yet.

Keep this file current when commands, layout, or these rules change.
