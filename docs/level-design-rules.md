# Level design rules

These are the rules every Brain Train level follows. Read this before you create, change or add levels. The numbers live in
`content-src/catalog.json` (the `campaign` object); this file explains them. If you change one, change both.

Levels are not drawn by hand. `dart run tool/content.dart build` generates them from the catalog and the integrated symbols,
proves each one solvable, and writes `content/brain-train/` (published to R2) and `content/starter/` (bundled in the app).

## 1. Difficulty: 1 to 10

Every level has a difficulty from **1 (very easy)** to **10 (very, very hard)**, stored as the level's `difficulty`
(`"1"` … `"10"`). The app shows it as a coloured badge, `7/10`, from green (1) to red (10).

Each difficulty is a tier in the catalog. A tier sets the board size, the depth, the tray and how often symbols repeat:

| Difficulty | Tiles   | Layers | Tray slots | Pairs per static / animated symbol (average) | Decoy pairs | Target win rate (random player) |
|-----------:|---------|--------|------------|-----------------------------------------------|-------------|---------------------------------|
| 1          | 20–32   | 1–2    | 5          | 2.0 / 2.0                                     | 0           | 85–100%                         |
| 2          | 24–38   | 1–2    | 5          | 2.0 / 2.0                                     | 0           | 70–95%                          |
| 3          | 30–46   | 2–3    | 4–5        | 2.0 / 2.0                                     | 0           | 55–80%                          |
| 4          | 36–54   | 2–3    | 4          | 2.0 / 2.0                                     | 0           | 40–65%                          |
| 5          | 44–62   | 2–3    | 4          | 2.0 / 2.0                                     | 0           | 25–45%                          |
| 6          | 50–70   | 3      | 4          | 1.9 / 1.8                                     | 0           | 10–30%                          |
| 7          | 56–78   | 3–4    | 3–4        | 1.8 / 1.8                                     | 0           | 2–15%                           |
| 8          | 64–88   | 3–4    | 3          | 1.6 / 1.5                                     | 5%          | 0–6%                            |
| 9          | 72–100  | 3–4    | 2–3        | 1.4 / 1.5                                     | 10%         | 0–3%                            |
| 10         | 84–126  | 4      | 2          | 1.25 / 1.25                                   | 20%         | 0–2%                            |

The tile and layer bands are those of the fixed 7×9 grid with depth showing (section 5, 2026-10-17): upper layers are
sparser, so a board holds at most about 126 tiles on 4 layers (before, difficulty 10 had 144–176 tiles on 5–7 layers).
Tray slots, pairs per symbol, decoys and win-rate bands did not change. Easy tiers also keep at least one symbol with a
single pair (for the coloured pair, section 3), so their pairs-per-symbol average is a little under 2.0.

How each column makes a level harder:

- **Tiles and layers:** bigger, deeper boards have fewer free tiles at the start.
- **Tray slots:** fewer slots leave less room for mistakes (section 2).
- **Pairs per symbol:** a lower number means more different symbols, so fewer ways to make a match.
- **Decoy pairs:** a share of pairs is built so that one tile is free long before its partner, and it waits in the tray.
- **Win rate:** the generator plays every candidate board 200 times with a simulated player who taps free tiles at
  random. It keeps the board whose win rate is closest to the tier's band (a few levels end just outside it). A careful
  player does much better. The build also reports a "pair-seeking" player, who wins about 64–69% of difficulty 8–10
  levels.

## 2. Tray size: 2 to 5 slots

- Every tapped tile goes into the tray. If the tray fills up without a match, the level is lost (Revive or Restart).
- The tray holds **2 to 5** tiles (`rules.trayCapacity`). The tray is tied to difficulty: easy levels get 5, the
  hardest get 2. A tier with a range (for example `[3, 4]`) picks one size per level with a seeded random draw.
- With 2 slots, every second tap must complete a pair.
- 2 and 3 slots need content schema 3 (section 8).

## 3. Symbols: 85% static, 15% animated

- **85 / 15:** on each level, `floor(15% of pairs)` pairs use animated (Lottie) symbols, at least 1. The rest are
  static. This is `animatedShare: 0.15`; the code allows at most 0.3.
- **At most 12 different animated symbols on one level** (`maxDistinctAnimated`). The app draws each one once per frame.
- **At most 2 pairs of the same symbol on one level** (`maxPairsPerSymbol: 2`), so no symbol covers more than 4 tiles.
- **Each level gets a random-looking subset** of all integrated symbols, static and animated.
- **Every integrated symbol is used:** symbols are picked least-used first, with ties broken by a seeded hash of the level
  and the symbol. Every symbol is therefore on some level before any symbol is on many. The build **fails** if any
  integrated symbol is on no level. Add levels or lower `pairsPer...Symbol` if that happens.
- **Coloured pairs (owner, 2026-10-17):** every level has **1 or 2 pairs** (seeded random) whose tile face is a
  different colour from the usual ivory. The colour is drawn from a fixed palette (for example warm gold, sky blue,
  blush pink, lavender, peach), never green, so it stands out on the felt. It is applied per symbol: pick only symbols
  that appear as exactly one pair on that level, so both tiles of the pair share the colour. Matching still uses symbol
  codes only; the colour is decoration, and the symbol must stay readable on it. In the level file it is the optional
  `faceColors` map (`{"CODE": "gold"}`; names `gold`, `sky`, `blush`, `lavender`, `peach`), which older app builds
  ignore. The generator colours static symbols only, picked among the level's abstract symbols (so new symbols change
  which codes are coloured, never which pairs), and `validate` checks 1–2 coloured single pairs with palette names.
- **Neighbouring levels look different:** they share only a small part of their symbol set (the build reports the
  maximum).
- **Which symbols are integrated:** only symbols with `"status": "integrated"` in `art/asset_sources.json` (static, image
  set `v1`) or `art/animated_sources.json` (Lottie). A new symbol joins the next build by itself.

## 4. Level order

- Levels come in **batches** (`campaign.batches`), and each batch lists how many levels each difficulty gets. Batch 1 has
  10 of each difficulty (levels 1–100), batch 2 has 25 of difficulty 9 and 50 of 10 (101–175), batch 3 has 84 each of
  5 and 6 and 83 each of 7–10 (176–675).
- Inside a batch the difficulties are **shuffled** with the campaign seed.
- **Level 1 is always difficulty 1.**
- **No difficulty appears 3 times in a row** (`maxTierRun: 2`).
- The seed (`20261641`) was chosen so the game opens gently. Levels 1–10 have difficulty 1, 2, 1, 4, 4, 5, 2, 6, 1, 1.
- **A batch depends only on the batches before it.** Appending a batch never changes an existing level's difficulty or
  tray. Never edit an existing batch's counts, the seed or a tier, because that regenerates every level after it.
- **Titles of published levels are pinned** (`campaign.titles`, level 1 first): a change to how boards are built never
  renames a level. New levels get generated titles that repeat none of them; every title is unique. Append a batch's
  titles to the list once it is published.

## 5. Boards

- Boards come from 22 symmetric shape families (`lib/game_engine/campaign/board_shapes.dart`). The same family never
  appears on two of three neighbouring levels.
- **Depth must show (owner, 2026-10-17).** Upper layers sit **half a tile off** the layer below (right and/or down),
  never exactly on top, so the player can always see that there are more tiles underneath:
  - No two tiles on different layers share the same `(x, y)`: no tile sits exactly on top of another.
  - Every tile shows part of its face from above: of the four quarters of its 2×2 footprint, at least one (two where
    possible) is not covered by any higher tile.
  - Boards stay mirror-symmetric. The generator rejects boards that break these rules, and `validate` checks them.
  - How the generator stacks: each layer takes half offsets (right/left and down/up, mirrored) from the tiles below, a
    tile rests on at least half a tile of the layer directly below and lies wholly over lower tiles. Most stacking
    programs keep two quarters of every tile showing; the dense ones (`heap`, `dense`, `solid`, `towers`) keep one.
- Every level is **solver-proven**: it is built so that it can be cleared pair by pair, then the solver proves it.
- **Same tile size on every level (owner, 2026-10-17).** Boards never shrink or grow to fit the screen. Every board,
  with all its layers and half offsets, fits a fixed grid of **7 tiles wide × 9 tiles tall** (logical span ≤ 14 × 18
  units) and **4 layers** (`kBoardGridColumns`, `kBoardGridRows`, `kBoardGridLayers` in
  `lib/game_engine/geometry/board_grid.dart`). The app fits that grid, not the level, into the board area, so a phone
  shows every level at the same scale, and smaller boards are centred, not enlarged. The generator rejects boards
  outside the grid, and `validate` checks it.
- Tiles stay at least **31 px wide on a 360×640 phone** (`minFaceWidth`). With the fixed grid this holds for every level
  at once: 34.8 px there, and 44.3 px on a 393×852 phone (the gameplay screen's low tray and compact action bar give
  the board its height). Tablets lay the screen out on a 600-wide canvas (`TabletScale`) and scale it up, so their
  tiles are bigger: about 78 dp on an iPad 13, 69 on an iPad 11, 75 on a 10-inch and 55 on a 7-inch tablet.
- Board size grows a little through a difficulty's levels within each batch.

## 6. Delivery to the phone

- The app bundles the **first 5 levels** (the starter pack, `content/starter/`) and only their art, so a fresh install
  plays offline.
- It keeps a **window of 5 levels** on the phone: the first level not yet won and the 4 after it.
- When the player clears level 1, level 6 downloads; clearing level 2 downloads level 7, and so on. Each download is the
  level file plus any of its art the phone does not have yet.
- Every other level downloads when the player opens it.
- Nothing downloaded is ever deleted, so any level the phone has ever had replays offline.

## 7. How to …

### Add new symbols

1. Put the art in place and set its entry to `integrated` after checking it at 31 px and 64 px tile width:
   - **Static:** `art/source/symbols-v1/`, then `python3 tool/assets/prepare_symbols.py`, then the entry in
     `art/asset_sources.json`.
   - **Animated:** `art/source/animated-symbols/`, then `python3 tool/assets/prepare_animated.py`, then the entry in
     `art/animated_sources.json`.
   - Reject look-alikes and anything unreadable at 31 px.
2. Bump `contentVersion` in `content-src/catalog.json`.
3. Run `dart run tool/content.dart build`, then `dart run tool/content.dart validate`, then `flutter test`.
4. Publish with `dart run tool/publish.dart --dry-run`, then `dart run tool/publish.dart`.
5. Check the live content with `dart run tool/smoke_remote.dart`.

New symbols change which symbols existing levels show (picks are least-used first), never their boards, difficulty or
tray. Their level files get new content-addressed keys.

### Add new levels

1. Append a batch to `campaign.batches`, for example `{"1": 2, "2": 3, ..., "10": 10}`. Do not edit earlier batches.
2. Bump `contentVersion`, then run the build, validate, test and publish steps as above.
3. If the build fails with "symbols used by no level", the new levels did not need every symbol. That cannot happen
   when adding levels, only when adding symbols.

### Clean up R2

Published keys are immutable and the app never needs old ones once a new manifest is live. After a publish:

1. Run `dart run tool/r2_prune.dart`. It only lists what the live manifest no longer references, grouped by folder.
2. The owner runs `dart run tool/r2_prune.dart --delete` to delete those objects permanently.

The tool refuses to run unless the live manifest is the local one.

## 8. Compatibility

- Levels with 2- or 3-slot trays or numeric difficulty need **client content schema 3** (`kClientContentSchema` in
  `lib/content/content_config.dart`). The build sets `minClientContentSchema: 3` in the manifest by itself.
- Older app builds keep their last known-good content instead of loading content they cannot play.
