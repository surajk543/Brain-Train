#!/usr/bin/env python3
"""Google Play feature graphic (1024 x 500) for Tile Park.

The Tile Park logo and name in gold on the night garden, two short lines in
Manrope, and a tilted phone showing a game in progress.

    python3 tool/store/make_feature_graphic.py

Reads   art/app_icon/tile-park-icon-1024.png   (tool/branding/make_tile_park_icons.py)
        art/store/phone/02-tray-gameplay.png   (test/visual/store_screenshots_test.dart)
        assets/lobby/night_*.webp, assets/fonts/ (Playfair Display, Manrope)
Writes  art/store/feature-graphic.png (RGB, no alpha, as Play requires)

Needs Pillow only; shares colours and the glow helper with make_store_shots.py.
"""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "art/store/feature-graphic.png"
W, H = 1024, 500

TITLE = "Tile Park"
LINE_1 = "Mahjong tile puzzle with a tray"
LINE_2 = "675 levels  ·  difficulty 1/10 to 10/10"

_spec = importlib.util.spec_from_file_location("store_shots", Path(__file__).with_name("make_store_shots.py"))
shots = importlib.util.module_from_spec(_spec)
sys.modules["store_shots"] = shots  # dataclasses look the module up by name
_spec.loader.exec_module(shots)


def font(name: str, size: int, weight: int) -> ImageFont.FreeTypeFont:
    f = ImageFont.truetype(str(ROOT / f"assets/fonts/{name}"), size)
    f.set_variation_by_axes([weight])
    return f


def rounded(img: Image.Image, radius: float) -> Image.Image:
    """[img] with anti-aliased rounded corners (RGBA)."""
    k = 4
    mask = Image.new("L", (img.width * k, img.height * k), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, mask.width - 1, mask.height - 1), radius * k, fill=255)
    out = img.convert("RGBA")
    out.putalpha(mask.resize(img.size, Image.Resampling.LANCZOS))
    return out


def shadow_of(layer: Image.Image, blur: float, alpha: float) -> Image.Image:
    """A soft black shadow in the shape of [layer]'s alpha, on a padded canvas."""
    pad = int(blur * 3)
    a = layer.getchannel("A").point(lambda v: int(v * alpha))
    canvas = Image.new("L", (layer.width + 2 * pad, layer.height + 2 * pad), 0)
    canvas.paste(a, (pad, pad))
    canvas = canvas.filter(ImageFilter.GaussianBlur(blur))
    out = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    out.putalpha(canvas)
    return out


def background() -> Image.Image:
    base = Image.open(ROOT / "assets/lobby/night_base.webp").convert("RGB")
    scale = max(W / base.width, H / base.height)
    base = base.resize((round(base.width * scale), round(base.height * scale)), Image.Resampling.LANCZOS)
    base = base.crop(((base.width - W) // 2, (base.height - H) // 2, (base.width - W) // 2 + W, (base.height - H) // 2 + H))
    # Deep emerald over the art, darker on the left behind the text.
    shade = shots.vertical_gradient((W, H), [(0, shots.EMERALD_TOP), (1, shots.TEAL_NAVY)])
    img = Image.blend(base, shade, 0.55).convert("RGBA")
    left = Image.new("L", (W, 1))
    left.putdata([round(150 * max(0.0, 1 - x / (W * 0.7))) for x in range(W)])
    dark = Image.new("RGBA", (W, H), (2, 18, 14, 0))
    dark.putalpha(left.resize((W, H)))
    img.alpha_composite(dark)
    img.alpha_composite(shots.soft_glow((W, H), (250, 250), (360, 260), shots.GOLD_WARM, 70))
    # Foliage in the top-left and bottom-right corners.
    for name, width, pos, opacity in (
        ("night_foliage_tl.webp", 300, (-40, -40), 0.85),
        ("night_foliage_br.webp", 330, (W - 290, H - 230), 0.9),
    ):
        leaf = Image.open(ROOT / f"assets/lobby/{name}").convert("RGBA")
        leaf = leaf.resize((width, round(leaf.height * width / leaf.width)), Image.Resampling.LANCZOS)
        leaf.putalpha(leaf.getchannel("A").point(lambda v: int(v * opacity)))
        img.alpha_composite(leaf, pos)
    return img


def gold_text(img: Image.Image, xy: tuple[int, int], text: str, f: ImageFont.FreeTypeFont) -> None:
    """[text] filled with the title's gold gradient over a soft dark shadow."""
    l, t, r, b = f.getbbox(text)
    mask = Image.new("L", (r - l + 8, b - t + 8), 0)
    ImageDraw.Draw(mask).text((4 - l, 4 - t), text, font=f, fill=255)
    x, y = xy[0] + l - 4, xy[1] + t - 4
    shade = Image.new("RGBA", mask.size, (0, 0, 0, 0))
    shade.putalpha(mask.point(lambda v: int(v * 0.75)))
    shade = shadow_of(shade, 6, 1.0)
    pad = (shade.width - mask.width) // 2
    img.alpha_composite(shade, (x - pad + 2, y - pad + 4))
    fill = shots.vertical_gradient(mask.size, [(0, shots.GOLD_LIGHT), (0.55, shots.GOLD_WARM), (1, shots.GOLD)]).convert("RGBA")
    fill.putalpha(mask)
    img.alpha_composite(fill, (x, y))


def phone(screen: Image.Image, height: int) -> Image.Image:
    """The screenshot in a dark bezel with a fine gold rim, tilted a little."""
    width = round(screen.width * height / screen.height)
    shot = rounded(screen.resize((width, height), Image.Resampling.LANCZOS), 24)
    bezel, rim = 9, 3
    body = Image.new("RGBA", (width + 2 * (bezel + rim), height + 2 * (bezel + rim)), (0, 0, 0, 0))
    ImageDraw.Draw(body).rounded_rectangle((0, 0, body.width - 1, body.height - 1), 24 + bezel + rim, fill=shots.GOLD + (255,))
    ImageDraw.Draw(body).rounded_rectangle(
        (rim, rim, body.width - 1 - rim, body.height - 1 - rim), 24 + bezel, fill=(6, 20, 16, 255)
    )
    body.alpha_composite(shot, (bezel + rim, bezel + rim))
    return body.rotate(-5, resample=Image.Resampling.BICUBIC, expand=True)


def main() -> None:
    img = background()

    # The phone on the right, bleeding off the top and bottom edges.
    device = phone(Image.open(ROOT / "art/store/phone/02-tray-gameplay.png").convert("RGB"), 560)
    px, py = W - device.width + 6, (H - device.height) // 2 + 6
    img.alpha_composite(shots.halo((W, H), (px + 30, py + 30, px + device.width - 30, py + device.height - 30), 40, 60, shots.GOLD_WARM, 60))
    shade = shadow_of(device, 16, 0.6)
    pad = (shade.width - device.width) // 2
    img.alpha_composite(shade, (px - pad - 10, py - pad + 12))
    img.alpha_composite(device, (px, py))

    # Logo with a soft shadow.
    logo = rounded(Image.open(ROOT / "art/app_icon/tile-park-icon-1024.png").convert("RGB").resize((150, 150), Image.Resampling.LANCZOS), 34)
    shade = shadow_of(logo, 10, 0.55)
    pad = (shade.width - logo.width) // 2
    img.alpha_composite(shade, (72 - pad, 58 - pad + 6))
    img.alpha_composite(logo, (72, 58))

    # Name and lines.
    gold_text(img, (66, 222), TITLE, font("playfair_display/PlayfairDisplay-VariableFont_wght.ttf", 104, 700))
    draw = ImageDraw.Draw(img)
    draw.text((72, 372), LINE_1, font=font("manrope/Manrope-VariableFont_wght.ttf", 30, 600), fill=shots.IVORY)
    draw.text((72, 418), LINE_2, font=font("manrope/Manrope-VariableFont_wght.ttf", 22, 600), fill=shots.GOLD_WARM)

    img.convert("RGB").save(OUT, optimize=True)
    print(f"feature graphic written: {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
