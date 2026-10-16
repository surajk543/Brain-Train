#!/usr/bin/env python3
"""Turn the owner's Lottie emoji animations into animated tile symbols.

Pipeline per entry of art/animated_sources.json:
  1. Read art/source/animated-symbols/<sourceFile> (the licensed original,
     gitignored, never modified). Only Lottie JSON is accepted, not .lottie
     (dotLottie zip) or GIF/MP4 exports.
  2. Check it the way the app does (checkLottieJson in
     lib/content/content_sources.dart): at most 1 MiB, a JSON object with
     version "v", frame rate "fr" in [1, 240], in/out points "ip"/"op" giving
     0-120 s, size "w"/"h" in [1, 8192], a non-empty "layers" array, and image
     assets only as embedded data: URIs.
  3. Optional per-entry "restyle" for thin line-art loaders (see restyle()):
     {"bounds": [l, t, r, b], "fill": 0.8, "strokeScale": 3, "colour": "#RRGGBB"}
     scales the content (bounds = union of the drawn pixels over the whole
     loop, fractions of w/h, measured from a render) to fill that share of the
     symbol box, multiplies every stroke width by strokeScale, and turns dark
     strokes/fills into colour. Entries without it are copied as is.
  4. Minify (no whitespace; --precision N also rounds floats to N decimals).
  5. Write content/brain-train/animated-symbols/<outputFile>. Published object
     keys are immutable: an existing output with different bytes is not
     replaced (give it a new outputFile) unless --force, which is only safe
     before that file was ever published.

Prints which sources are still missing. Exit code 1 if any present source is
invalid. Then run `dart run tool/content.dart build`.

Usage:
  python3 tool/assets/prepare_animated.py
  options: --force  --precision 3
"""

import argparse
import json
import math
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCES = ROOT / "art" / "animated_sources.json"
SOURCE_DIR = ROOT / "art" / "source" / "animated-symbols"
OUTPUT_DIR = ROOT / "content" / "brain-train" / "animated-symbols"
MAX_BYTES = 1024 * 1024  # kMaxAnimationBytes in lib/content/content_config.dart
WARN_BYTES = 300 * 1024
CODE = re.compile(r"^[A-Z0-9_]{1,40}$")
SEGMENT = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$")


class Invalid(Exception):
    pass


def _reject_constant(name):
    raise Invalid(f"invalid JSON number {name}")


def check_lottie(data: bytes) -> dict:
    """Mirror of checkLottieJson (Dart). Returns the parsed animation."""
    if len(data) > MAX_BYTES:
        raise Invalid(f"{len(data)} bytes exceeds {MAX_BYTES}")
    try:
        doc = json.loads(data.decode("utf-8"), parse_constant=_reject_constant)
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise Invalid(f"invalid JSON ({error})") from None
    if not isinstance(doc, dict):
        raise Invalid("expected a JSON object")

    def number(key, low, high):
        value = doc.get(key)
        if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or not low <= value <= high:
            raise Invalid(f'"{key}" must be a number in [{low}, {high}]')
        return float(value)

    if not isinstance(doc.get("v"), str):
        raise Invalid('"v" (version) must be a string')
    frame_rate = number("fr", 1, 240)
    seconds = (number("op", -100000, 100000) - number("ip", -100000, 100000)) / frame_rate
    number("w", 1, 8192)
    number("h", 1, 8192)
    if not 0 < seconds <= 120:
        raise Invalid('"op" - "ip" must give a duration in (0, 120] seconds')
    layers = doc.get("layers")
    if not isinstance(layers, list) or not layers or not all(isinstance(layer, dict) for layer in layers):
        raise Invalid('"layers" must be a non-empty array of objects')
    assets = doc.get("assets")
    if assets is not None:
        if not isinstance(assets, list):
            raise Invalid('"assets" must be an array')
        for asset in assets:
            if not isinstance(asset, dict):
                raise Invalid('"assets" entries must be objects')
            if asset.get("layers") is not None:
                continue  # a precomposition
            path = asset.get("p")
            if isinstance(path, str) and not path.startswith("data:"):
                raise Invalid(f'image asset "{asset.get("id")}" is an external file; export with images embedded')
    return doc


def warnings_for(doc: dict) -> list:
    """Features lottie-flutter draws poorly or not at all."""
    found = set()
    layers = list(doc["layers"])
    for asset in doc.get("assets") or []:
        layers.extend(asset.get("layers") or [])
    for layer in layers:
        if layer.get("ty") == 5:
            found.add("text layer (drawn with a default font)")
        if layer.get("ddd") == 1:
            found.add("3D layer (not supported)")

    def has_expression(node):
        if isinstance(node, dict):
            return isinstance(node.get("x"), str) or any(has_expression(v) for v in node.values())
        if isinstance(node, list):
            return any(has_expression(item) for item in node)
        return False

    if has_expression(doc):
        found.add("expressions (ignored)")
    return sorted(found)


def round_floats(node, digits):
    if isinstance(node, float):
        value = round(node, digits)
        return int(value) if value == int(value) else value
    if isinstance(node, list):
        return [round_floats(item, digits) for item in node]
    if isinstance(node, dict):
        return {key: round_floats(value, digits) for key, value in node.items()}
    return node


def _shapes(node):
    """Every stroke/fill shape item ("ty": "st"/"fl") anywhere in the animation."""
    if isinstance(node, dict):
        if node.get("ty") in ("st", "fl") and isinstance(node.get("c"), dict):
            yield node
        for value in node.values():
            yield from _shapes(value)
    elif isinstance(node, list):
        for item in node:
            yield from _shapes(item)


def _keyframe_values(prop: dict) -> list:
    """The value lists of a Lottie property: [k] when static, else each keyframe's "s"/"e"."""
    if prop.get("a") == 1 and isinstance(prop.get("k"), list):
        return [frame[key] for frame in prop["k"] if isinstance(frame, dict) for key in ("s", "e") if key in frame]
    return [prop.get("k")]


def _scale_number_prop(prop: dict, factor: float):
    if prop.get("a") == 1 and isinstance(prop.get("k"), list):
        for frame in prop["k"]:
            for key in ("s", "e"):
                if isinstance(frame, dict) and isinstance(frame.get(key), list):
                    frame[key] = [v * factor if isinstance(v, (int, float)) else v for v in frame[key]]
    elif isinstance(prop.get("k"), (int, float)):
        prop["k"] = prop["k"] * factor


def restyle(doc: dict, spec: dict) -> dict:
    """Make a thin line-art animation readable on a small tile (per-entry "restyle")."""
    width, height = doc["w"], doc["h"]
    left, top, right, bottom = spec["bounds"]
    content = max((right - left) * width, (bottom - top) * height)
    scale = spec.get("fill", 0.8) * min(width, height) / content
    if "strokeScale" in spec:
        # Layer transforms scale strokes too, so the factor is tuned by eye per entry.
        for shape in _shapes(doc):
            if shape["ty"] == "st" and isinstance(shape.get("w"), dict):
                _scale_number_prop(shape["w"], spec["strokeScale"])
    if "colour" in spec:
        hex_colour = spec["colour"].lstrip("#")
        rgb = [int(hex_colour[i : i + 2], 16) / 255 for i in (0, 2, 4)]
        for s in _shapes(doc):
            for value in _keyframe_values(s["c"]):
                if not isinstance(value, list) or len(value) < 3:
                    continue
                unit = 255 if max(value[:3]) > 1 else 1
                if 0.2126 * value[0] + 0.7152 * value[1] + 0.0722 * value[2] < 0.35 * unit:
                    value[:3] = [c * unit for c in rgb]
    # A null parent for every top-level layer: zoom about the content centre.
    indices = [layer.get("ind", 0) for layer in doc["layers"] if isinstance(layer.get("ind"), int)]
    parent = max(indices, default=0) + 1
    for layer in doc["layers"]:
        if "parent" not in layer:
            layer["parent"] = parent
    centre = [(left + right) / 2 * width, (top + bottom) / 2 * height, 0]
    doc["layers"].append({
        "ddd": 0, "ind": parent, "ty": 3, "nm": "tile fit", "sr": 1, "ao": 0, "bm": 0,
        "ip": doc["ip"], "op": doc["op"], "st": 0,
        "ks": {
            "o": {"a": 0, "k": 100}, "r": {"a": 0, "k": 0},
            "p": {"a": 0, "k": [width / 2, height / 2, 0]},
            "a": {"a": 0, "k": centre},
            "s": {"a": 0, "k": [scale * 100, scale * 100, 100]},
        },
    })
    return doc


def minify(doc: dict, precision) -> bytes:
    if precision is not None:
        doc = round_floats(doc, precision)
    return json.dumps(doc, separators=(",", ":"), ensure_ascii=False, allow_nan=False).encode("utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--force", action="store_true", help="replace changed outputs (only before first publish)")
    parser.add_argument("--precision", type=int, default=None, help="round floats to N decimals (e.g. 3)")
    args = parser.parse_args()

    spec = json.loads(SOURCES.read_text(encoding="utf-8"))
    entries = spec["symbols"]
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    processed, missing, failed = [], [], []
    codes, outputs = set(), set()
    for entry in entries:
        code, source_name, output_name = entry["code"], entry["sourceFile"], entry["outputFile"]
        label = f"{code:<10} {source_name}"
        problems = []
        if not CODE.match(code):
            problems.append("code must be A-Z, 0-9 and _")
        if code in codes:
            problems.append("duplicate code")
        if not SEGMENT.match(output_name) or not output_name.lower().endswith(".json"):
            problems.append("outputFile must be a plain name ending in .json")
        if output_name in outputs:
            problems.append("duplicate outputFile")
        codes.add(code)
        outputs.add(output_name)
        if problems:
            failed.append(code)
            print(f"FAIL  {label}: {'; '.join(problems)}", file=sys.stderr)
            continue

        source = SOURCE_DIR / source_name
        if not source.exists():
            if source.with_suffix(".lottie").exists():
                failed.append(code)
                print(f"FAIL  {label}: found a .lottie (dotLottie) file; download the Lottie JSON format", file=sys.stderr)
            else:
                missing.append(entry)
            continue
        original = source.read_bytes()
        try:
            doc = check_lottie(original)
            if "restyle" in entry:
                doc = restyle(doc, entry["restyle"])
            data = minify(doc, args.precision)
            check_lottie(data)
        except Invalid as error:
            failed.append(code)
            print(f"FAIL  {label}: {error}", file=sys.stderr)
            continue

        output = OUTPUT_DIR / output_name
        if output.exists() and output.read_bytes() != data and not args.force:
            failed.append(code)
            print(
                f"FAIL  {label}: {output.relative_to(ROOT)} exists with different bytes; published keys are "
                "immutable, so give it a new outputFile (or --force before the first publish)",
                file=sys.stderr,
            )
            continue
        output.write_bytes(data)
        processed.append(code)
        seconds = (doc["op"] - doc["ip"]) / doc["fr"]
        size = f"{len(original) // 1024} -> {len(data) // 1024} KB"
        print(f"ok    {label} -> {output.relative_to(ROOT)}  {doc['w']}x{doc['h']} {seconds:.1f}s @ {doc['fr']}fps, "
              f"{len(doc['layers'])} layers, {size}")
        for warning in warnings_for(doc):
            print(f"      ! {warning}")
        if len(data) > WARN_BYTES:
            print(f"      ! large ({len(data) // 1024} KB): parsing and drawing cost more on every board")

    print(f"\n{len(processed)} processed, {len(missing)} missing, {len(failed)} failed (of {len(entries)})")
    if missing:
        print(f"missing (put the Lottie JSON files in {SOURCE_DIR.relative_to(ROOT)}/):")
        for entry in missing:
            print(f"  {entry['code']:<10} {entry['sourceFile']}  ({entry.get('title', '')})")
    if processed:
        print("next: dart run tool/content.dart build")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
