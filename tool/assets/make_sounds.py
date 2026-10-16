#!/usr/bin/env python3
"""Synthesize Brain Train's sound effects (pure Python, no samples needed).

Usage: python3 tool/assets/make_sounds.py
Writes assets/sounds/{select,invalid,win,lose}.wav (22.05 kHz, mono, 16-bit).
The match sound is assets/sounds/strike.wav, cut from the owner's strike.mp3.
"""

import math
import random
import struct
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RATE = 22050


def tone(freq, start, length, decay, volume=1.0, harmonics=((1, 1.0), (2, 0.25), (3, 0.08)), glide=0.0):
    """A plucked/struck partial set: instant attack, exponential decay."""
    samples = []
    for i in range(int(length * RATE)):
        t = i / RATE
        f = freq * (1 + glide * t / max(length, 1e-6))
        env = math.exp(-t / decay) * min(1.0, t / 0.002)
        value = sum(a * math.sin(2 * math.pi * f * h * t) for h, a in harmonics)
        samples.append(volume * env * value)
    return start, samples


def mix(parts, length):
    out = [0.0] * int(length * RATE)
    for start, samples in parts:
        offset = int(start * RATE)
        for i, value in enumerate(samples):
            if offset + i < len(out):
                out[offset + i] += value
    return out


def write(name, samples, peak=0.6):
    top = max(abs(s) for s in samples) or 1.0
    fade = int(0.01 * RATE)
    data = bytearray()
    for i, s in enumerate(samples):
        gain = min(1.0, (len(samples) - i) / fade)
        data += struct.pack("<h", int(32767 * peak * gain * s / top))
    path = ROOT / "assets/sounds" / f"{name}.wav"
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(bytes(data))
    print(f"{path.relative_to(ROOT)}  {len(samples) / RATE:.2f}s")


def main():
    random.seed(3)
    # Select: short wooden tick of two tiles touching.
    click = (0.0, [random.uniform(-1, 1) * math.exp(-i / (0.0015 * RATE)) * 0.6 for i in range(int(0.01 * RATE))])
    write("select", mix([click, tone(880, 0, 0.09, 0.018, 0.9), tone(1320, 0, 0.09, 0.012, 0.4)], 0.09), peak=0.5)
    # Invalid: soft low bonk with a small downward glide.
    write("invalid", mix([tone(220, 0, 0.18, 0.06, glide=-0.18, harmonics=((1, 1.0), (2, 0.15)))], 0.18), peak=0.5)
    # Win: rising arpeggio resolving on a held chord.
    notes = [1046.5, 1318.5, 1568.0, 2093.0]
    parts = [tone(f, k * 0.11, 1.2 - k * 0.11, 0.32) for k, f in enumerate(notes)]
    parts += [tone(f, 0.5, 0.8, 0.45, 0.5) for f in (1046.5, 1318.5, 1568.0)]
    write("win", mix(parts, 1.3), peak=0.6)
    # Lose (tray full): two soft falling notes settling on a low, dull tone.
    soft = ((1, 1.0), (2, 0.12))
    parts = [
        tone(659.3, 0, 0.32, 0.12, 0.8, harmonics=soft),
        tone(523.3, 0.16, 0.36, 0.13, 0.8, harmonics=soft),
        tone(392.0, 0.34, 0.6, 0.22, 0.9, harmonics=soft, glide=-0.04),
    ]
    write("lose", mix(parts, 0.95), peak=0.5)


if __name__ == "__main__":
    main()
