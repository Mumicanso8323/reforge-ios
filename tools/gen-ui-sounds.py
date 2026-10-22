#!/usr/bin/env python3
"""仮の効果音を作る(PT-B3)。Python の標準のライブラリだけ。正弦波・雑音・包絡線で短い音を作り、
ReForge/Resources/Sounds/<名前>.wav に書く(モノラル・44.1kHz・16bit・各 1 秒以内)。
本物の音は後で同じ名前で差し替える。決定的(雑音の種を固定)なので、何度回しても同じ wav になる。"""
import math
import pathlib
import random
import struct
import sys
import wave

RATE = 44100
OUT = pathlib.Path(__file__).resolve().parent.parent / "ReForge" / "Resources" / "Sounds"


def tone(freq, seconds, gain=0.5, glide=0.0, attack=0.004, noise=0.0, seed=1):
    """freq から glide 倍まで滑る正弦波に雑音を混ぜ、立ち上がり attack と指数の減衰を掛ける。"""
    rng = random.Random(seed)
    n = int(RATE * seconds)
    out = []
    phase = 0.0
    for i in range(n):
        t = i / RATE
        f = freq * (1 + (glide - 1) * (i / n)) if glide else freq
        phase += 2 * math.pi * f / RATE
        env = min(1.0, t / attack) * math.exp(-5.0 * i / n)
        out.append(gain * env * ((1 - noise) * math.sin(phase) + noise * rng.uniform(-1, 1)))
    return out


def seq(*parts):
    return [s for p in parts for s in p]


SOUNDS = {
    "ui_press": tone(520, 0.05, 0.35),
    "ui_rub": tone(180, 0.35, 0.3, noise=0.7, seed=2),
    "ui_unit": tone(740, 0.09, 0.4),
    "ui_place": tone(300, 0.12, 0.45, glide=0.7),
    "ui_done": seq(tone(523, 0.1, 0.4), tone(784, 0.25, 0.45)),
    "ui_reject": tone(160, 0.14, 0.45, glide=0.8),
    "ui_feed_1": tone(330, 0.15, 0.35, noise=0.3, seed=3),
    "ui_feed_2": tone(370, 0.15, 0.35, noise=0.3, seed=4),
    "ui_feed_3": tone(415, 0.15, 0.35, noise=0.3, seed=5),
    "ui_ignite": tone(260, 0.5, 0.4, glide=2.0, noise=0.4, seed=6),
    "ui_fire_down": tone(300, 0.4, 0.35, glide=0.5, noise=0.2, seed=7),
    "ui_night": tone(110, 0.95, 0.5, glide=0.8),
}


def write(name, samples):
    OUT.mkdir(parents=True, exist_ok=True)
    assert len(samples) <= RATE, f"{name} は 1 秒以内"
    with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s)) * 32767)) for s in samples))


def main():
    for name, samples in SOUNDS.items():
        write(name, samples)
    print(f"{len(SOUNDS)} files -> {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
