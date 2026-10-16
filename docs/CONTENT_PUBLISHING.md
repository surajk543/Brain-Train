# Brain Train content publishing

Levels, the symbol registry and symbol artwork are data. Publishing new levels that use existing
mechanics and renderer types needs **no app release**.

## Where content lives

| What | Where |
|---|---|
| Authoring sources | `content-src/catalog.json` (`campaign`: tiers, counts, seed), `art/asset_sources.json`, `art/animated_sources.json` (optional hand layouts: `content-src/layouts/*.layout.json`) |
| Generated, publishable tree | `content/brain-train/` (also bundled into the app as the offline fallback) |
| R2 bucket | `braintrain` (private) |
| Public read URL | `https://braintrain-assets.surajk543.workers.dev/brain-train/<path>` |
| Worker source | `infra/cloudflare/braintrain-assets/worker.js` |

The Worker serves keys under `brain-train/` publicly (GET/HEAD only, CORS `*`). `manifest.json` is
served with `max-age=60`; every other object is `immutable`. All other bucket keys require a signed
token. The app never holds R2 credentials or the token secret.

### R2 object keys

```text
brain-train/
  manifest.json                                # the only mutable object; uploaded last
  registries/symbols-<sha12>.json              # content-addressed symbol registry
  levels/level-0001-<sha12>.json … level-0200-<sha12>.json   # content-addressed levels
  symbols/v4/*.webp                            # static symbol art
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
  "contentVersion": "2026.10.16.9",
  "publishedAt": "2026-10-16 07:00:00",
  "compatibility": { "minClientContentSchema": 2 },
  "symbolRegistry": { "url": "registries/symbols-b932cfbdc9d6.json", "sha256": "<hex>" },
  "levels": [
    { "levelId": "level-0001", "order": 1, "title": "Quiet Pines", "url": "levels/level-0001-176020c9449a.json",
      "sha256": "<hex>", "difficulty": "easy", "category": "nature", "tileCount": 28 }
  ]
}
```

- `difficulty`: the tier id (`easy`, `medium`, `hard`, `veryHard`); the app labels it ("Very Hard")
  and colours its badge. Unknown ids still get a label made from the id.
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

## The campaign (200 levels)

`tool/content.dart build` generates every level from `catalog.json` `campaign`
(`lib/game_engine/campaign/`):

- **Tiers** are data: `tiers` lists `id`, `count`, `tiles`, `layers`, `trayCapacity`,
  `pairsPerStaticSymbol`/`pairsPerAnimatedSymbol` (symbol repeats; higher is easier),
  `stalePairing` (decoy pairs), `freeRatio` (share of tiles free at the start) and `winRate`
  (accepted win rate of the simulated tray player). The order is a seeded shuffle with every tier at
  exactly its `count`, level 1 = `firstTier`, and no tier more than `maxTierRun` times in a row.
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
- **Symbols (70/30)**: each level gets `floor(30% of its pairs)` animated pairs (at least one, never
  above 30%) and static pairs for the rest, with at most `maxDistinctAnimated` (12) distinct animated
  symbols (big boards reuse one for two or more pairs). Which codes a level uses is chosen by
  rendezvous hashing over the integrated pools: each level ranks every code by a hash of the level and
  the code and takes the best ones.
- **Titles** are two nature words (a first word plus a noun that fits the shape: "Heron Bridge"),
  unique across the campaign; `backdrop.colors` come from 20 nature palettes.

The build is reproducible: the same catalog and symbol pools give byte-identical files (and an
unchanged manifest keeps its `publishedAt`). Boards, tiers, titles, tray sizes, removal orders and
simulated win rates do not depend on the symbol pools at all, so new symbols change only symbol codes,
and only in the levels that rank a new code high enough.

## Publish

1. Edit `catalog.json` (`campaign`, or optional hand layouts in `levels`) and bump `contentVersion`.
2. `dart run tool/content.dart build`. It prints every level and a per-tier summary (tiles, layers,
   tray, free tiles, simulated win rates, symbol counts, animated share, symbol coverage) and fails if
   a level is invalid or unsolvable, or if an integrated symbol is used by no level. Files the new
   manifest no longer references are removed from `content/brain-train/` (they stay on R2).
3. `dart run tool/content.dart validate` and `flutter test` (includes
   `test/content/published_content_test.dart`).
4. `dart run tool/publish.dart --dry-run`, then `dart run tool/publish.dart`. It validates again,
   compares every referenced object with the bucket in parallel (an existing key with other bytes
   aborts before anything is written), uploads only new objects in parallel batches of 8 and verifies
   each by ETag, uploads `manifest.json` last, and checks the public URL.
5. `dart run tool/smoke_remote.dart`: the app's own loading code against production (every level and
   all art, plus a detailed check of levels 1, 57, 128 and 200 and their symbols).

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

On launch the app compares the cached known-good manifest with the bundled one and loads only the
levels of the newer (one parse of 200 levels, about 70 ms on a desktop VM), so it starts without the
network; the lobby never waits for downloads. It then fetches the manifest in the background. When
it is newer, the registry, every level and all artwork are taken from the cache, else from the app
bundle when the SHA-256 matches (copied into the cache, no download), else from the network (8
parallel requests, retries for transient errors, 12 s timeout), and validated. Only a complete,
valid set becomes the new known-good content; partial or invalid updates are discarded. Objects are
never downloaded twice: keys are immutable and the cache is checked first. A game in progress keeps
the content snapshot it started with. Unreferenced cached objects are pruned after each update.

The app bundles the whole tree (all 200 level files, the registry, all static and animated art), so
a fresh install plays every level offline.

## Worker / CDN configuration

- Deploy `infra/cloudflare/braintrain-assets/worker.js` (dashboard editor or wrangler) with binding
  `ASSETS` → bucket `braintrain` and secret `ASSET_TOKEN_SECRET`.
- Optional: attach a custom domain such as `content.sungamestudio.com` to the Worker (not to the
  bucket) and update `ContentConfig.production` plus its `allowedHosts`.
- Keep the bucket's r2.dev URL disabled and do not attach a custom domain directly to the bucket:
  that would bypass the Worker.
