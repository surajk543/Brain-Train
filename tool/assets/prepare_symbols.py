#!/usr/bin/env python3
"""Turn downloaded symbol artwork into game-ready transparent WebP files.

Pipeline per symbol (see docs/ASSET_PIPELINE.md):
  1. Find the original in art/source/iconscout/<expectedSourceFile>.<ext>
     (PNG/WebP/JPG, or a 3D file rendered with Blender: GLB/GLTF/FBX/OBJ/BLEND).
  2. Keep the original untouched; work on a copy.
  3. Remove a flat background if the image has no transparency.
  4. Trim empty margins, then scale (never stretch) so the longest side fills
     FILL of a square transparent canvas, centred.
  5. Write a PNG master (art/masters/<set>/) and a WebP for the game
     (content/brain-train/symbols/<set>/).
  6. Write a contact sheet (art/review/<set>-contact-sheet.png) to inspect all
     symbols together on tile-coloured faces.

Usage:
  python3 tool/assets/prepare_symbols.py                 # licensed art -> symbols/v1
  options: --lossless  --quality 90  --size 512  --fill 0.86
"""

import argparse
import hashlib
import json
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFont

sys.path.insert(0, str(Path(__file__).resolve().parent))
from cutout import erase_colours, remove_background  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
RASTER_EXTS = (".png", ".webp", ".jpg", ".jpeg")
MODEL_EXTS = (".glb", ".gltf", ".fbx", ".obj", ".blend")


def find_source(directory: Path, stem: str):
    for ext in RASTER_EXTS + MODEL_EXTS:
        candidate = directory / f"{stem}{ext}"
        if candidate.exists():
            return candidate
    return None


def render_model(path: Path, size: int) -> Image.Image:
    """Render a 3D source to a transparent PNG with Blender (headless)."""
    script = ROOT / "tool" / "assets" / "blender_render.py"
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "render.png"
        cmd = ["blender", "-b", "--factory-startup", "-P", str(script), "--", str(path), str(out), str(size * 2)]
        subprocess.run(cmd, check=True, capture_output=True)
        return Image.open(out).convert("RGBA")


def has_transparency(img: Image.Image) -> bool:
    alpha = img.getchannel("A")
    histogram = alpha.histogram()
    transparent = sum(histogram[:250])
    return transparent > 0.01 * img.width * img.height


def remove_flat_background(img: Image.Image, tolerance: int = 18) -> Image.Image:
    """Make a uniform border-connected background transparent.

    Only acts when the four corners agree on a colour; otherwise the image is
    returned unchanged and flagged for manual cleanup.
    """
    rgb = img.convert("RGB")
    w, h = rgb.size
    corners = [rgb.getpixel(p) for p in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1))]
    ref = corners[0]
    if any(max(abs(a - b) for a, b in zip(c, ref)) > tolerance for c in corners):
        print("  ! background is not uniform; left as-is, clean it manually", file=sys.stderr)
        return img
    marker = (255, 0, 255)
    flood = rgb.copy()
    for seed in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)):
        ImageDraw.floodfill(flood, seed, marker, thresh=tolerance)
    mask = Image.eval(
        Image.merge("RGB", [flood.getchannel(i).point(lambda v, t=t: 255 if v == t else 0) for i, t in enumerate(marker)])
        .convert("L"),
        lambda v: 0 if v == 255 else 255,
    )
    out = img.copy()
    out.putalpha(mask)
    return out


def apply_crop(img: Image.Image, crop) -> Image.Image:
    """Per-entry "crop": [left, top, right, bottom] as fractions of the source,
    or {"box": [...], "ellipse": true} to also keep only the inscribed ellipse
    (e.g. a round badge). Used to cut a scene illustration down to its subject."""
    box = crop["box"] if isinstance(crop, dict) else crop
    left, top, right, bottom = (round(v * s) for v, s in zip(box, (img.width, img.height) * 2))
    img = img.crop((left, top, right, bottom))
    if isinstance(crop, dict) and crop.get("ellipse"):
        mask = Image.new("L", (img.width * 4, img.height * 4), 0)
        ImageDraw.Draw(mask).ellipse((0, 0, img.width * 4 - 1, img.height * 4 - 1), fill=255)
        mask = mask.resize(img.size, Image.LANCZOS)
        img.putalpha(ImageChops.multiply(img.getchannel("A"), mask))
    return img


def flatten_square(img: Image.Image, matte) -> Image.Image:
    """Centre a transparent (or non-square) source on a square canvas of the
    backdrop colour, so tool/assets/cutout.py can flood it away without
    stretching the image."""
    side = max(img.size)
    canvas = Image.new("RGBA", (side, side), (*matte, 255))
    canvas.alpha_composite(img, ((side - img.width) // 2, (side - img.height) // 2))
    return canvas


def parse_colour(value) -> tuple:
    if isinstance(value, str):
        value = value.lstrip("#")
        return tuple(int(value[i : i + 2], 16) for i in (0, 2, 4))
    return tuple(value)


def normalise(img: Image.Image, size: int, fill: float) -> Image.Image:
    alpha = img.getchannel("A").point(lambda v: 255 if v > 8 else 0)
    bbox = alpha.getbbox()
    if bbox is None:
        raise ValueError("image is fully transparent")
    cropped = img.crop(bbox)
    scale = fill * size / max(cropped.width, cropped.height)
    target = (max(1, round(cropped.width * scale)), max(1, round(cropped.height * scale)))
    resized = cropped.resize(target, Image.LANCZOS)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.paste(resized, ((size - target[0]) // 2, (size - target[1]) // 2), resized)
    return canvas


def photo_tile(img: Image.Image, size: int, crop: float = 0.06, radius: float = 0.14) -> Image.Image:
    """Full-bleed artwork (no transparency): centre-square crop, trimmed
    border, resized, with rounded corners so it sits on the tile face like an
    inlaid picture."""
    img = img.convert("RGB")
    side = min(img.size)
    left, top = (img.width - side) // 2, (img.height - side) // 2
    inset = int(side * crop)
    img = img.crop((left + inset, top + inset, left + side - inset, top + side - inset)).resize((size, size), Image.LANCZOS)
    mask = Image.new("L", (size * 4, size * 4), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size * 4 - 1, size * 4 - 1), int(size * 4 * radius), fill=255)
    out = img.convert("RGBA")
    out.putalpha(mask.resize((size, size), Image.LANCZOS))
    return out


def contact_sheet(items, path: Path):
    cell_w, cell_h, pad, per_row = 180, 230, 24, 8
    columns = min(per_row, len(items))
    rows = (len(items) + per_row - 1) // per_row
    row_h = cell_h + pad + 30
    sheet = Image.new("RGB", (pad + columns * (cell_w + pad), pad + rows * row_h), (31, 74, 52))
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.load_default(size=14)
    for i, (code, img) in enumerate(items):
        x, y = pad + (i % per_row) * (cell_w + pad), pad + (i // per_row) * row_h
        draw.rounded_rectangle((x + 8, y + 10, x + cell_w + 8, y + cell_h + 10), 18, fill=(46, 92, 60))
        draw.rounded_rectangle((x, y, x + cell_w, y + cell_h), 18, fill=(248, 241, 222), outline=(214, 200, 168), width=3)
        face = img.copy()
        face.thumbnail((int(cell_w * 0.86), int(cell_w * 0.86)), Image.LANCZOS)
        sheet.paste(face, (x + (cell_w - face.width) // 2, y + (cell_h - face.height) // 2), face)
        draw.text((x + cell_w / 2, y + cell_h + 24), code, fill=(240, 230, 200), font=font, anchor="mm")
    path.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(path)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--set", help="output set name (default: imageSet from art/asset_sources.json)")
    parser.add_argument("--size", type=int, default=512)
    parser.add_argument("--fill", type=float, default=0.86)
    parser.add_argument("--quality", type=int, default=90)
    parser.add_argument("--lossless", action="store_true")
    args = parser.parse_args()

    sources = json.loads((ROOT / "art" / "asset_sources.json").read_text())
    set_name = args.set or sources.get("imageSet", "v1")
    source_dir = ROOT / "art" / f"source/symbols-{set_name}"
    master_dir = ROOT / "art" / "masters" / set_name
    webp_dir = ROOT / "content" / "brain-train" / "symbols" / set_name
    master_dir.mkdir(parents=True, exist_ok=True)
    webp_dir.mkdir(parents=True, exist_ok=True)

    entries = sources["symbols"]
    processed, missing = [], []
    for entry in entries:
        source = find_source(source_dir, entry["expectedSourceFile"])
        if source is None:
            missing.append(entry)
            continue
        print(f"{entry['code']}: {source.relative_to(ROOT)}")
        if source.suffix.lower() in MODEL_EXTS:
            img = render_model(source, args.size)
        else:
            img = Image.open(source).convert("RGBA")
        print(f"  source {img.width}x{img.height}, transparency={'yes' if has_transparency(img) else 'no'}")
        if "crop" in entry:
            img = apply_crop(img, entry["crop"])
            print(f"  cropped to {img.width}x{img.height}")
        if "erase" in entry:
            # Decorative backdrop colours of a transparent illustration (see cutout.erase_colours).
            img = erase_colours(img, **entry["erase"])
        if entry.get("style") == "photo":
            final = photo_tile(img, args.size)
        elif entry.get("style") == "cutout":
            # Light studio background removed, then trimmed and centred like transparent art.
            # Transparent or non-square sources (cropped illustrations) are first put on a
            # square canvas of their backdrop colour ("matte", default white).
            if has_transparency(img) or img.width != img.height:
                img = flatten_square(img, parse_colour(entry.get("matte", "#FFFFFF")))
            final = normalise(remove_background(img, **entry.get("cutout", {})), args.size, args.fill)
        else:
            if not has_transparency(img):
                img = remove_flat_background(img)
            final = normalise(img, args.size, args.fill)
        master = master_dir / f"{Path(entry['outputFile']).stem}.png"
        webp = webp_dir / entry["outputFile"]
        final.save(master, optimize=True)
        final.save(webp, "WEBP", lossless=args.lossless, quality=args.quality, method=6, exact=True)
        digest = hashlib.sha256(webp.read_bytes()).hexdigest()
        print(f"  -> {webp.relative_to(ROOT)} ({webp.stat().st_size} bytes, sha256 {digest[:12]}…)")
        processed.append((entry["code"], final))

    if processed:
        sheet = ROOT / "art" / "review" / f"{set_name}-contact-sheet.png"
        contact_sheet(processed, sheet)
        print(f"contact sheet: {sheet.relative_to(ROOT)}")
    if missing:
        print(f"\nmissing source files (place them in {source_dir.relative_to(ROOT)}/):")
        for entry in missing:
            print(f"  {entry['code']:<16} {entry['expectedSourceFile']}.<png|jpg|webp|glb|…>")
    return 0 if processed else 1


if __name__ == "__main__":
    sys.exit(main())
