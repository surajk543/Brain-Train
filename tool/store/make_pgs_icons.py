"""Play Games Services icons: achievements and leaderboards (512x512 PNG).

Gold medallions on emerald, in the game's look. Where a licensed 3D original
exists in art/source/play-games/<id>.png (IconScout "Trophy And Award" pack by
Yuni Nur Ikhwanto, owner's subscription; gitignored like all art/source/), it is
placed on the medallion, with a small gold tag (TAGS) for the milestones;
otherwise Playfair Display numerals are drawn. Writes art/play-games/<id>.png.
Run: python3 -I tool/store/make_pgs_icons.py
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[2]
SOURCES = ROOT / "art/source/play-games"
# Tag drawn on the 3D art (milestones), by icon id.
TAGS = {
    "levels_10": "10",
    "levels_50": "50",
    "levels_100": "100",
    "levels_250": "250",
    "levels_500": "500",
    "combo_5": "\u00d75",
    "summit": "10/10",
}
OUT = ROOT / "art/play-games"
FONT = ROOT / "assets/fonts/playfair_display/PlayfairDisplay-VariableFont_wght.ttf"
S = 512

# id -> (big text, small text under it)
ICONS = {
    "first_win": ("1", "FIRST WIN"),
    "levels_10": ("10", "LEVELS"),
    "levels_50": ("50", "LEVELS"),
    "levels_100": ("100", "LEVELS"),
    "levels_250": ("250", "LEVELS"),
    "levels_500": ("500", "LEVELS"),
    "combo_5": ("\u00d75", "COMBO"),
    "summit": ("10/10", "SUMMIT"),
    "pure_skill": (None, "PURE SKILL"),  # a drawn star: Playfair has no star glyph
    "lb_total_score": ("TOP", "TOTAL SCORE"),
    "lb_levels": ("#", "LEVELS"),
    "lb_best_combo": ("\u00d7", "BEST COMBO"),
}
# Per difficulty: best single-level score and fastest win.
for _d in range(1, 11):
    ICONS[f"lb_score_d{_d}"] = (f"{_d}/10", "SCORE")
    ICONS[f"lb_time_d{_d}"] = (f"{_d}/10", "TIME")


def font(size, weight=800):
    f = ImageFont.truetype(str(FONT), size)
    try:
        f.set_variation_by_axes([weight])
    except Exception:
        pass
    return f


def medallion(big, small):
    img = Image.new("RGB", (S, S), (6, 44, 37))
    # Emerald radial glow.
    glow = Image.new("L", (S, S), 0)
    ImageDraw.Draw(glow).ellipse((40, 30, S - 40, S - 50), fill=255)
    glow = glow.filter(ImageFilter.GaussianBlur(70))
    img = Image.composite(Image.new("RGB", (S, S), (18, 96, 66)), img, glow)
    d = ImageDraw.Draw(img)
    # Gold rims.
    d.ellipse((34, 34, S - 34, S - 34), outline=(227, 169, 71), width=14)
    d.ellipse((58, 58, S - 58, S - 58), outline=(248, 214, 126), width=4)
    if big is None:
        # A five-pointed gold star (Playfair has no star glyph).
        import math
        cx, cy, ro, ri = S / 2, 200, 120, 50
        pts = []
        for i in range(10):
            r = ro if i % 2 == 0 else ri
            a = -math.pi / 2 + i * math.pi / 5
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
        d.polygon([(x + 4, y + 6) for x, y in pts], fill=(3, 26, 21))
        d.polygon(pts, fill=(248, 214, 126))
        big = ""
    # Big text in gold, fitted to the medallion.
    size = 230
    while size > 60:
        f = font(size)
        box = d.textbbox((0, 0), big, font=f)
        if box[2] - box[0] <= 300 and box[3] - box[1] <= 210:
            break
        size -= 6
    if not big:
        f = font(60)
    box = d.textbbox((0, 0), big or " ", font=f)
    w, h = box[2] - box[0], box[3] - box[1]
    x, y = (S - w) / 2 - box[0], 205 - h / 2 - box[1]
    d.text((x + 4, y + 6), big, font=f, fill=(3, 26, 21))
    d.text((x, y), big, font=f, fill=(248, 214, 126))
    # Label.
    lf = font(40, 700)
    lb = d.textbbox((0, 0), small, font=lf)
    lw = lb[2] - lb[0]
    d.text(((S - lw) / 2 - lb[0], 352), small, font=lf, fill=(255, 243, 216))
    return img


def art_medallion(key, art_path):
    img = medallion("", "")
    d = ImageDraw.Draw(img)
    # Clear the label band: the art alone, larger.
    art = Image.open(art_path).convert("RGBA")
    box = art.getbbox()
    if box:
        art = art.crop(box)
    target = 300
    scale = target / max(art.size)
    art = art.resize((max(1, int(art.width * scale)), max(1, int(art.height * scale))), Image.LANCZOS)
    tag = TAGS.get(key)
    cy = 240 if tag else 256
    x, y = (S - art.width) // 2, cy - art.height // 2
    # Soft drop shadow from the art's alpha.
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    a = art.split()[3].point(lambda v: int(v * 0.55))
    shadow.paste(Image.new("RGBA", art.size, (2, 20, 16, 255)), (x + 6, y + 10), a)
    shadow = shadow.filter(ImageFilter.GaussianBlur(10))
    img = img.convert("RGBA")
    img.alpha_composite(shadow)
    img.alpha_composite(art, (x, y))
    if tag:
        d = ImageDraw.Draw(img)
        tf = font(56, 800)
        tb = d.textbbox((0, 0), tag, font=tf)
        tw, th = tb[2] - tb[0], tb[3] - tb[1]
        pw, ph = tw + 48, th + 26
        px, py = (S - pw) / 2, 372
        d.rounded_rectangle((px, py, px + pw, py + ph), radius=ph / 2, fill=(9, 58, 44), outline=(248, 214, 126), width=5)
        d.text(((S - tw) / 2 - tb[0], py + (ph - th) / 2 - tb[1]), tag, font=tf, fill=(248, 214, 126))
    return img.convert("RGB")


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    for key, (big, small) in ICONS.items():
        art = SOURCES / f"{key}.png"
        icon = art_medallion(key, art) if art.exists() else medallion(big, small)
        icon.save(OUT / f"{key}.png", optimize=True)
        print(OUT / f"{key}.png")


if __name__ == "__main__":
    main()
