# Symbol artwork pipeline

Brain Train levels 1–5 use exactly seven symbols, all IconScout 3D nature icons. Only these are
used; no generic emoji or unrelated icons.

## Acquisition status

| Code | Asset | Source page | Status |
|---|---|---|---|
| `NATURE_01` | Nature 3D Icon | https://iconscout.com/3d-icon/nature-3d-icon_11904203 | awaiting download |
| `LEAF_01` | Leaf 3D Icon | https://iconscout.com/3d-icon/leaf-3d-icon_12870188 | awaiting download |
| `NATURE_02` | Nature 3D Icon | https://iconscout.com/3d-icon/nature-3d-icon_9889887 | awaiting download |
| `ACORN_SEED` | Acorn Seed 3D Icon | https://iconscout.com/3d-icon/acorn-seed-3d-icon_14103709 | awaiting download |
| `SUNFLOWER` | Sunflower 3D Icon | https://iconscout.com/3d-icon/sunflower-3d-icon_14103705 | awaiting download |
| `ZINNIA` | Zinnia 3D Icon | https://iconscout.com/3d-icon/zinnia-3d-icon_14289284 | awaiting download |
| `ANEMONE` | Anemone 3D Icon | https://iconscout.com/3d-icon/anemone-3d-icon_14289282 | awaiting download |

The machine-readable copy, with output filenames, is `art/asset_sources.json`; keep `status` there
current. The pages are references only. The files must be downloaded with your IconScout
account and license; they are not scraped. Confirm the license allows redistribution inside a game.

**Until then the game uses placeholders**: original drawings by `tool/assets/make_placeholders.py`,
stored under `symbols/placeholder-v1/` and flagged `"placeholder": true` in the registry (Settings
shows the count). They are not IconScout art.

## Replace the placeholders with the licensed files

1. Download each asset (PNG preferred; GLB/GLTF/FBX/OBJ/BLEND also work) and save it as
   `art/source/iconscout/<expectedSourceFile>.<ext>`, e.g. `art/source/iconscout/leaf-01.png`.
   This folder is gitignored, so the originals stay untouched and out of git.
2. `python3 tool/assets/prepare_symbols.py` (optionally `--lossless`). Per symbol it:
   - renders 3D sources to a transparent PNG with Blender (`tool/assets/blender_render.py`),
   - removes a flat background only when the image has no transparency and the corners agree,
   - trims empty margins, then scales (never stretches) so the longest side fills 86% of a
     512×512 transparent canvas, centred, aspect ratio preserved,
   - writes `art/masters/v1/<name>.png` and `content/brain-train/symbols/v1/<name>.webp`,
   - writes `art/review/v1-contact-sheet.png`. **Inspect this sheet**: nothing cropped, colours and
     silhouettes unchanged, similar visual weight on the tile faces.
3. In `content-src/catalog.json` set `registry` to
   `{"registryVersion": "brain-train-nature-v1", "path": "registries/symbols-v1.json", "imageSet": "v1", "placeholder": false}`
   and bump `contentVersion`. Levels do not change: they reference symbol codes.
4. Set each `status` in `art/asset_sources.json` to `integrated`.
5. `dart run tool/content.dart build`, `flutter test`, `dart run tool/publish.dart`.
6. (Historical: the app now bundles only `content/starter/`, written by `tool/content.dart build`;
   no pubspec change is needed for new art.)
7. `python3 tool/assets/make_app_icon.py --symbol art/masters/v1/sunflower.png` to rebuild the
   launcher icon from the licensed sunflower.

### Current static set (v1) and per-entry options

`imageSet` in `art/asset_sources.json` names the set; originals live in `art/source/symbols-<set>/`
(gitignored), outputs in `art/masters/<set>/`, `content/brain-train/symbols/<set>/` and
`art/review/<set>-contact-sheet.png`. Set v1 (named v4 until 2026-10-16) mixes owner-supplied images and IconScout premium 3D
icons / illustrations (owner's subscription, no attribution required; `sourceUrl` per entry).
Optional keys per entry, applied in this order:

- `"crop": [l, t, r, b]` (fractions of the source) or `{"box": [...], "ellipse": true}` — cut a
  scene illustration down to its subject (ellipse keeps a round badge).
- `"erase": {"colours": ["#F9E2C9", …], "tolerance": 8}` — transparent vector art with a decorative
  backdrop: those colours are cleared where connected to transparency (or enclosed patches), then
  only the main subject is kept (`tool/assets/cutout.py` `erase_colours`).
- `"style": "cutout"` (+ `"cutout": {…}` for `remove_background` options, `"matte": "#RRGGBB"` for a
  transparent/non-square source's backdrop colour) — remove a light background.
- `"style": "photo"` — full-bleed picture with rounded corners.
- no style — transparent art is trimmed, centred and normalised as is.

Colours on the board are boosted at paint time (`TileStyle.symbolSaturation`/`symbolContrast`);
the WebP files keep the original colours.

## Where symbol files go

Processed static WebP and animated Lottie files are written to `content/brain-train/symbols/<set>/`
and `content/brain-train/animated-symbols/`. That tree is not in git and not in the app: it is
uploaded to R2 by `tool/publish.dart`, and the app downloads a symbol's file only when a level it
needs (the next 5 levels, or a level being opened) uses it, then keeps it on disk. Only the art of
the starter pack (levels 1–5) is copied into `content/starter/` by `tool/content.dart build` and
bundled. Builds use only entries with `"status": "integrated"` whose processed file exists.

## Requirements the pipeline enforces

- Transparent WebP (or PNG) only; the app also checks file signatures and SHA-256.
- Square 512 px canvas with transparent padding; the tile renderer fits art inside the face inset
  without distortion.
- Missing or undecodable art never crashes the game: the tile shows a neutral fallback face.

## Other generated art

All of these are drawn by scripts (Pillow, no licensed art) and bundled, so the app works offline:

| Art | Script | Output |
|---|---|---|
| Lobby night scene (forest, lanterns, path, ledge, foliage, button leaves) | `python3 tool/assets/make_lobby_art.py` | `assets/lobby/` |
| Gameplay edge foliage | `python3 tool/assets/make_foliage.py` | `assets/decor/` |
| Sound effects | `python3 tool/assets/make_sounds.py` | `assets/sounds/` |
| Launcher icons (from the logo emblem) | `python3 tool/assets/make_app_icon.py` | Android mipmaps, iOS AppIcon |
