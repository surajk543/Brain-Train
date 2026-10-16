"""Background removal for symbol artwork on light/grey studio backgrounds.

No ML model:
1. A gradient-following flood fill grows the background in from the image
   border through low-saturation pixels whose colour changes smoothly (white
   or grey backdrops, vignettes, soft cast shadows, reflections). It stops at
   the subject's sharp, colourful edges.
2. Enclosed holes that match the backdrop colour (e.g. inside a loop) are
   cleared too; small bright spots inside the subject (highlights) are kept.
3. Only the main subject survives: the largest piece plus large pieces near
   it. Specks, floor strips and reflections that touch the border go.
4. The edge is eroded 1px (no light fringe) and feathered.
"""

from collections import deque

from PIL import Image, ImageChops, ImageFilter

NEIGHBOURS = ((1, 0), (-1, 0), (0, 1), (0, -1))


def _components(mask: bytearray, w: int, h: int, value: int):
    """Connected components of pixels equal to `value`: (pixels, touches_border)."""
    seen = bytearray(w * h)
    for start in range(w * h):
        if mask[start] != value or seen[start]:
            continue
        seen[start] = 1
        pixels = [start]
        border = False
        k = 0
        while k < len(pixels):
            i = pixels[k]
            k += 1
            x, y = i % w, i // w
            if x in (0, w - 1) or y in (0, h - 1):
                border = True
            for dx, dy in NEIGHBOURS:
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h:
                    j = ny * w + nx
                    if mask[j] == value and not seen[j]:
                        seen[j] = 1
                        pixels.append(j)
        yield pixels, border


def remove_background(
    img: Image.Image,
    size: int = 512,
    step: int = 14,
    max_saturation: int = 70,
    hole_distance: int = 30,
    min_hole: float = 0.002,
    keep_ratio: float = 0.12,
) -> Image.Image:
    """Returns a `size`x`size` RGBA image with the backdrop transparent.

    step: largest per-channel change between neighbouring background pixels.
    max_saturation: background pixels are at most this saturated (HSV 0-255).
    hole_distance / min_hole: enclosed regions within this colour distance of
    the backdrop and at least this share of the image become transparent.
    keep_ratio: detached pieces smaller than this share of the main subject
    are dropped.
    """
    rgb = img.convert("RGB").resize((size, size), Image.LANCZOS)
    px = rgb.load()
    sat = rgb.convert("HSV").getchannel("S").load()
    w = h = size
    background = bytearray(w * h)  # 1 = background
    queue = deque()

    def seed(x, y):
        i = y * w + x
        if not background[i] and sat[x, y] <= max_saturation:
            background[i] = 1
            queue.append((x, y))

    for x in range(w):
        seed(x, 0)
        seed(x, h - 1)
    for y in range(h):
        seed(0, y)
        seed(w - 1, y)
    while queue:
        x, y = queue.popleft()
        r, g, b = px[x, y]
        for dx, dy in NEIGHBOURS:
            nx, ny = x + dx, y + dy
            if 0 <= nx < w and 0 <= ny < h:
                i = ny * w + nx
                if background[i] or sat[nx, ny] > max_saturation:
                    continue
                nr, ng, nb = px[nx, ny]
                if abs(nr - r) <= step and abs(ng - g) <= step and abs(nb - b) <= step:
                    background[i] = 1
                    queue.append((nx, ny))

    # Backdrop colour = mean of the flooded border pixels.
    border = [px[x, y] for x in range(0, w, 4) for y in (0, h - 1) if background[y * w + x]]
    border += [px[x, y] for y in range(0, h, 4) for x in (0, w - 1) if background[y * w + x]]
    if border:
        bg = tuple(sum(c[k] for c in border) / len(border) for k in range(3))
        # Enclosed holes that look like the backdrop.
        candidate = bytearray(w * h)
        for i in range(w * h):
            if background[i]:
                continue
            x, y = i % w, i // w
            r, g, b = px[x, y]
            if sat[x, y] <= max_saturation and max(abs(r - bg[0]), abs(g - bg[1]), abs(b - bg[2])) <= hole_distance:
                candidate[i] = 1
        for pixels, _ in _components(candidate, w, h, 1):
            if len(pixels) >= min_hole * w * h:
                for i in pixels:
                    background[i] = 1

    # Keep the main subject: largest piece + large pieces not on the border.
    subject = bytearray(0 if v else 1 for v in background)
    pieces = list(_components(subject, w, h, 1))
    if pieces:
        largest = max(len(p) for p, _ in pieces)
        for pixels, touches in pieces:
            if len(pixels) == largest:
                continue
            if touches or len(pixels) < keep_ratio * largest:
                for i in pixels:
                    background[i] = 1

    mask = Image.frombytes("L", (w, h), bytes(0 if v else 255 for v in background))
    mask = mask.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(0.9))
    out = rgb.convert("RGBA")
    out.putalpha(mask)
    return out


def erase_colours(
    img: Image.Image,
    colours,
    tolerance: int = 8,
    keep_ratio: float = 0.12,
    min_hole: float = 0.0005,
    max_side: int = 1024,
) -> Image.Image:
    """For flat vector illustrations that already have transparency but carry a
    decorative backdrop (window patterns, clouds, flowers) behind the subject.

    Grows the transparent area into opaque pixels within `tolerance` of any of
    `colours` (hex strings or RGB) that are connected to it, clears enclosed
    patches of those colours of at least `min_hole` of the image, then keeps only the
    main subject: the largest opaque piece plus pieces at least `keep_ratio` of
    its size. Works at `max_side` resolution (symbols are 512 px).
    """
    palette = [
        tuple(int(c.lstrip("#")[i : i + 2], 16) for i in (0, 2, 4)) if isinstance(c, str) else tuple(c)
        for c in colours
    ]
    img = img.convert("RGBA")
    if max(img.size) > max_side:
        scale = max_side / max(img.size)
        img = img.resize((max(1, round(img.width * scale)), max(1, round(img.height * scale))), Image.LANCZOS)
    w, h = img.size
    px = img.load()

    def matches(p):
        return any(max(abs(p[0] - c[0]), abs(p[1] - c[1]), abs(p[2] - c[2])) <= tolerance for c in palette)

    clear = bytearray(w * h)  # 1 = transparent in the result
    queue = deque()
    for y in range(h):
        for x in range(w):
            if px[x, y][3] < 128:
                clear[y * w + x] = 1
                queue.append((x, y))
    while queue:
        x, y = queue.popleft()
        for dx, dy in NEIGHBOURS:
            nx, ny = x + dx, y + dy
            if 0 <= nx < w and 0 <= ny < h:
                i = ny * w + nx
                if not clear[i] and matches(px[nx, ny]):
                    clear[i] = 1
                    queue.append((nx, ny))

    # Backdrop patches enclosed by the subject (e.g. inside a curled tail).
    enclosed = bytearray(w * h)
    for i in range(w * h):
        if not clear[i] and matches(px[i % w, i // w]):
            enclosed[i] = 1
    for pixels, _ in _components(enclosed, w, h, 1):
        if len(pixels) >= min_hole * w * h:
            for i in pixels:
                clear[i] = 1

    subject = bytearray(0 if v else 1 for v in clear)
    pieces = list(_components(subject, w, h, 1))
    if pieces:
        largest = max(len(p) for p, _ in pieces)
        for pixels, _ in pieces:
            if len(pixels) < keep_ratio * largest:
                for i in pixels:
                    clear[i] = 1

    mask = Image.frombytes("L", (w, h), bytes(0 if v else 255 for v in clear))
    mask = mask.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(0.7))
    out = img.copy()
    out.putalpha(ImageChops.multiply(img.getchannel("A"), mask))
    return out
