# Brain Train content publishing

Levels, the symbol registry and symbol artwork are data. Publishing new levels that use existing
mechanics and renderer types needs **no app release**.

## Where content lives

| What | Where |
|---|---|
| Authoring sources | `content-src/catalog.json` (`campaign`: tiers, counts, seed), `art/asset_sources.json`, `art/animated_sources.json` (optional hand layouts: `content-src/layouts/*.layout.json`) |
| Generated, publishable tree | `content/brain-train/` (not in git: local output of the build, uploaded by `tool/publish.dart`; on another machine mirror it with `dart run tool/fetch_content.dart`) |
| Starter pack (bundled in the app, in git) | `content/starter/`: the manifest and registry (metadata of every level), levels 1–5 and only their art |
| R2 bucket (content) | `braintrain-public`: holds only `brain-train/`; everything in it is public |
| Public read URL (app, versionCode 5+) | `https://braintrain-cdn.sungamestudio.com/brain-train/<path>` (R2 custom domain, minimum TLS 1.2) |
| R2 bucket (private) | `braintrain`: symbol masters `art/masters/` (`tool/r2_art.dart`) and a frozen copy of content 2026.10.16.12 |
| Old read URL (builds before versionCode 5) | `https://braintrain-assets.surajk543.workers.dev/brain-train/<path>` (Worker `infra/cloudflare/braintrain-assets/worker.js`, reads the private bucket) |

`tool/publish.dart` uploads to `braintrain-public` with `Cache-Control: public, max-age=60,
must-revalidate` on `manifest.json` and `public, max-age=31536000, immutable` on every other object.
On the `sungamestudio.com` zone (Cloudflare free plan):

- Cache rule "Brain Train content cache": host `braintrain-cdn.sungamestudio.com` is eligible for
  cache, and the edge follows each object's Cache-Control (so JSON is cached too, not only images).
- Rate limiting rule "Brain Train content per-IP limit": more than 100 requests per 10 s from one IP
  on that host are blocked for 10 s.
- R2 budget alert: an email to the owner when R2 billable usage reaches $1.

The app never holds R2 credentials or the token secret. Reading content needs no key; only
publishing does (`.env`). Never put anything private in `braintrain-public`.

### R2 object keys

```text
brain-train/
  manifest.json                                # the only mutable object; uploaded last
  registries/symbols-<sha12>.json              # content-addressed symbol registry
  levels/level-0001-<sha12>.json … level-0200-<sha12>.json   # content-addressed levels
  symbols/v1/*.webp                            # static symbol art
  animated-symbols/*.json                      # Lottie symbols
```

Levels and the registry are **content-addressed**: the key ends in the first 12 hex digits of the
file's SHA-256. A level whose bytes change gets a new key by itself, an unchanged level keeps its
key (so it is neither uploaded nor downloaded again, and a saved game on it stays resumable), and a
published key can never be overwritten. Older keys (`level-0001-v6.json`, `symbols-v5.json`) stay
on R2 untouched.

Paths inside JSON are relative to `brain-train/`. The client rejects absolute URLs, other hosts,
`..`, `.`, empty segments, query strings, and unexpected extensions.

## Formats

### Manifest (`schemaVersion` 1)

```json
{
  "schemaVersion": 1,
  "contentVersion": "2026.10.16.10",
  "publishedAt": "2026-10-16 07:00:00",
  "compatibility": { "minClientContentSchema": 2 },
  "symbolRegistry": { "url": "registries/symbols-b932cfbdc9d6.json", "sha256": "<hex>" },
  "levels": [
    { "levelId": "level-0001", "order": 1, "title": "Quiet Pines", "url": "levels/level-0001-176020c9449a.json",
      "sha256": "<hex>", "difficulty": "easy", "category": "nature", "tileCount": 28, "trayCapacity": 4 }
  ]
}
```

- `difficulty`: the tier id, `"1"` (very easy) to `"10"` (hardest); the app shows it as `7/10` on a
  green-to-red badge. Named ids (`easy`, `veryHard`) and unknown ids still get a label made from the id.
- `tileCount`, `trayCapacity`: copied from the level (since 2026.10.16.10), so the app shows titles,
  tiers, sizes and tray slots for levels whose file is not on the device. Older builds ignore them.
- `contentVersion`: dotted integers. The app only installs a version **higher** than the one it has
  (bundled or cached). To roll back, republish the old files under a higher version.
- `compatibility.minClientContentSchema`: raise it when content needs code that older builds lack.
  Older builds then reject the manifest and keep their last known-good content.
- `sha256` values are optional but always written by the tool; the app verifies them.

### Symbol registry (`schemaVersion` 1)

```json
{
  "schemaVersion": 1,
  "registryVersion": "brain-train-symbols-<hash of the symbol table>",
  "symbols": {
    "LEAF_01": { "type": "image", "assetPath": "symbols/v1/leaf-01.webp", "matchGroup": "LEAF_01",
                 "label": "Leaf 3D Icon", "sha256": "<hex>",
                 "source": "https://iconscout.com/3d-icon/leaf-3d-icon_12870188" }
  }
}
```

Supported `type`s: `image` (WebP/PNG `assetPath`), `emoji` and `text` (`value`, optional
`textColor` `#RRGGBB`). Unknown types are rejected per symbol, not for the whole registry; levels
that use a rejected symbol are skipped. `placeholder: true` marks stand-in art.

### Level (`schemaVersion` 1)

```json
{
  "schemaVersion": 1,
  "levelId": "level-0005",
  "title": "Coral Basin",
  "difficulty": "hard",
  "tileSetId": "classic-ivory",
  "board": { "tileWidth": 2, "tileHeight": 2, "layerOffsetX": -0.07, "layerOffsetY": -0.07 },
  "rules": { "matchingMode": "same_symbol", "requireSolvable": true, "trayCapacity": 5 },
  "backdrop": { "colors": ["#3FA66B", "#B8E07A", "#F2E8B5"] },
  "tiles": [ { "tileId": "t001", "symbolCode": "LEAF_01", "x": 0, "y": 0, "layer": 0 } ]
}
```

- `x`, `y`: top-left of the tile footprint in logical units; the footprint is
  `tileWidth × tileHeight`. Brain Train uses 2×2, so a half-tile offset is `1`. Coordinates may be
  negative or irregular.
- `layer`: 0 is the table. A tile above layer 0 must rest on a tile one layer below it.
- `layerOffsetX/Y`: visual shift per layer, as a fraction of the face size. Rendering only.
- `backdrop.colors` (optional): 2–4 `#RRGGBB` colours for the level's glass background, in both
  day and night mode. Set it in the layout file; the build copies it into the level.
- `matchingMode`: `same_symbol` (default) or `match_group` (uses registry `matchGroup`).
- `rules.trayCapacity` (optional): tray slots, `4` (default, written only when different) or `5`.
  Hard and very hard levels use 5. Builds that predate the field ignore it (JSON readers skip unknown
  keys) and play with 4, which is safe because every level is pair-solvable; no
  `minClientContentSchema` change is needed.
  `rules.matchGroups` declares special groups, e.g. `{"FLOWERS": ["ZINNIA", "ANEMONE"]}`.
- Free tile: no remaining higher-layer tile overlaps it, and its left or right side has no
  remaining same-layer tile touching it.

The app checks structure, IDs, symbols, overlaps, floating tiles, even pairs and initial moves.
**Solvability is proven before publishing** by `tool/content.dart`; the app does not repeat it.
The solver proves a pair-removal order. The game plays through a 4-slot tray, and every pair order
is also a winning tray order (tap one tile of the pair, then the other), so a proven level is winnable.

## The campaign

The rules every level follows (difficulty 1–10, tray 2–5, 85/15 symbols, at most 2 pairs per symbol,
every symbol used, batches) are in **docs/level-design-rules.md**. `tool/content.dart build`
generates every level from `catalog.json` `campaign` (`lib/game_engine/campaign/`):

- **Tiers** are data: `tiers` lists `id` (`1`..`10`), `tiles`, `layers`, `trayCapacity` (one size or
  `[min, max]`, picked per level), `pairsPerStaticSymbol`/`pairsPerAnimatedSymbol` (symbol repeats;
  higher is easier), `stalePairing` (decoy pairs), `freeRatio` (share of tiles free at the start) and
  `winRate` (accepted win rate of the simulated tray player). `batches` lists levels per tier; each
  batch is a seeded shuffle with every tier at exactly its count, level 1 = `firstTier`, and no tier
  more than `maxTierRun` times in a row. A batch depends only on earlier batches, so new levels go in
  a new batch.
- **Boards** come from 22 mirror-symmetric shape families (pyramid, terrace, diamond, cross, ring,
  fortress, arch, bridge, hourglass, heart, flower, grove, furrows, chevron, isles, oval, star,
  butterfly, turtle, lattice, crown, pillars) and stacking programs (aligned pyramid, half-offset
  stagger, brick, ridge, rim walls, towers). Footprints are 2x2, offsets are whole half tiles. A board
  must keep tile faces at least `minFaceWidth` px wide on a 360x640 phone. Neighbouring levels never
  reuse the shape family of the previous three.
- **Solvable by construction**: the generator clears the empty board pair by pair (two tiles free at
  the same moment) and gives each pair a symbol; the solver must also prove it within
  `solverBudget` nodes or the board is replaced, and the build re-proves every level with 2M nodes.
- **Calibration**: each candidate board is played 200 times by a simulated tray player (takes a free
  tile that matches the tray, else a random free tile; the level's own tray capacity). The first
  candidate inside the tier's `winRate` band is taken (else the closest of 36). `dart run
  tool/content.dart stats` prints the rates of the published tree.
- **Symbols (85/15)**: each level gets `floor(15% of its pairs)` animated pairs (at least one) and
  static pairs for the rest, with at most `maxDistinctAnimated` (12) distinct animated symbols and at
  most `maxPairsPerSymbol` (2) pairs of any one symbol. Which codes a level uses: level by level, the
  codes used least so far first (ties by a hash of the level and the code), so every integrated
  symbol is on some level; the build fails if one is not.
- **Titles** are two nature words (a first word plus a noun that fits the shape: "Heron Bridge"),
  unique across the campaign; `backdrop.colors` come from 20 nature palettes.

The build is reproducible: the same catalog and symbol pools give byte-identical files (and an
unchanged manifest keeps its `publishedAt`). Boards, tiers, titles, tray sizes, removal orders and
simulated win rates do not depend on the symbol pools at all, so new symbols change only symbol codes
(from the first level that picks a new code on).

## Publish

1. Edit `catalog.json` (`campaign`, or optional hand layouts in `levels`) and bump `contentVersion`.
2. `dart run tool/content.dart build`. It prints every level and a per-tier summary (tiles, layers,
   tray, free tiles, simulated win rates, symbol counts, animated share, symbol coverage) and fails if
   a level is invalid or unsolvable, or if an integrated symbol is used by no level. Files the new
   manifest no longer references are removed from `content/brain-train/` (they stay on R2). It also
   rewrites the starter pack `content/starter/` (catalog `starterLevels`, 5): commit it with the
   catalog, since the app bundles it.
3. `dart run tool/content.dart validate` (also checks the starter pack against the tree) and
   `flutter test`. Tests never read `content/brain-train/`: `published_content_test.dart` regenerates
   the campaign from the catalog and the starter pack's registry and checks every level's checksum
   against the manifest; a few big-board captures skip without the tree.
4. `dart run tool/publish.dart --dry-run`, then `dart run tool/publish.dart`. It validates again,
   compares every referenced object with the bucket in parallel (an existing key with other bytes
   aborts before anything is written), uploads only new objects in parallel batches of 8 and verifies
   each by ETag, uploads `manifest.json` last, and checks the public URL.
5. `dart run tool/smoke_remote.dart`: the app's own loading code against production. A fresh install
   with the starter pack (what the first launch downloads), then the lazy path from R2 alone:
   manifest and registry, the 5-level window with only its art, the window after ten wins (nothing
   downloaded twice), and level 1, the middle level and the last level on demand, validated and
   solver-proven.
6. Optional cleanup: `dart run tool/r2_prune.dart` lists every `brain-train/` object the live
   manifest no longer references (old levels, registries, retired symbol sets), grouped by folder. It
   refuses to run unless the live manifest is the local one. Deleting is the owner's step:
   `dart run tool/r2_prune.dart --delete` (permanent).

Layouts that only change positions, layers, symbols or tile counts never need a code change.

### Rebuild after new symbols

When art is added (`status: "integrated"` in `art/asset_sources.json` or
`art/animated_sources.json`, processed file present): bump `contentVersion`, run `build` (no other
edit: the registry key and the affected level keys change by themselves), then validate, test,
publish and smoke as above. Entries that are not `integrated` yet, or whose processed file is
missing, are left out and listed by the build.

## Add or replace a symbol

1. Process the art: see `docs/ASSET_PIPELINE.md` (output `content/brain-train/symbols/<set>/` or
   `content/brain-train/animated-symbols/`) and set its `status` to `integrated`.
2. Rebuild and publish as above. The registry path is content-addressed, so it changes on its own.

A new symbol of type `image`, `emoji`, `text` or `lottie` works without an app update. A new renderer
type, new matching mechanics, or a level schema the app does not know need an app release (and a
raised `minClientContentSchema`).

## Client behaviour

R2 is the source of truth. The app bundles only the starter pack, and keeps everything it downloads
on disk for good (`ContentCache` over `FileContentStore`, keyed by content-addressed paths, never
evicted).

- **Start** (no network): the newer of the cached known-good manifest and the starter pack's, with
  every level file already on the device; the window's levels that are fully on the device are marked
  ready (`warmUp`), so they open at once. The lobby never waits for downloads.
- **Metadata**: in the background the app fetches the manifest (all 200 entries with title, tier,
  tile count and tray size, so lists and panels never need level files) and, for a new version, the
  registry (small).
- **Rolling window**: the next 5 levels (first level not won and the 4 after it) are kept ready: level
  file plus only the symbol art it uses; a symbol shared by several levels is fetched once. Objects
  come from the cache, else from the app bundle when the SHA-256 matches (copied into the cache), else
  from the network (8 parallel requests, retries for transient errors, 12 s timeout, checksum and
  file checks). Top-ups run at start, after every win, when the app returns to the foreground, and on
  a backoff timer (10 s up to 5 min) while the network is unreachable.
- **Other levels** download on demand when opened: `LevelLoaderScreen` shows "Downloading level…",
  or offline "Connect to the internet to download this level" with Try again.
- **Version switch**: a newer manifest becomes active only once its registry and its window, with
  their art, are cached (all or nothing for the window; a level file that fails validation is left
  out). Otherwise the current version stays. Older versions are never installed. A game in progress
  keeps the content snapshot it started with; a saved game whose level key changed starts over.
- **Offline replay**: every level that was ever ready is recorded (`state/levels.json`: its file and
  registry). If a content update changed a level's key and the new file is not cached yet, the level
  opens offline from its older cached file, so played and completed levels never become unplayable
  offline.

A fresh install downloads only the manifest at first launch (its window is the starter pack); each
win then fetches about one level file and that level's new symbols. Without a starter pack the first
window is 5 level files and 47 symbol files (~1.8 MB, 2026.10.16.10).

## Worker / CDN configuration

- Deploy `infra/cloudflare/braintrain-assets/worker.js` (dashboard editor or wrangler) with binding
  `ASSETS` → bucket `braintrain` and secret `ASSET_TOKEN_SECRET`.
- Optional: attach a custom domain such as `content.sungamestudio.com` to the Worker (not to the
  bucket) and update `ContentConfig.production` plus its `allowedHosts`.
- Keep the bucket's r2.dev URL disabled and do not attach a custom domain directly to the bucket:
  that would bypass the Worker.
