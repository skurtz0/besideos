#!/usr/bin/env python3
"""Draws the placeholder BesideOS mark (two bars on a dark rounded square) with no dependencies.

Run from the project folder:  python3 tool/make_icons.py
Writes web/favicon.png and web/icons/Icon-192.png, Icon-512.png. Replace with real artwork later.
"""
import math, pathlib, struct, zlib

LAYERS = [
    (128, 128, 128, 128, 56, (24, 28, 38)),
    (90, 128, 40, 66, 16, (96, 165, 255)),
    (166, 128, 40, 66, 16, (245, 247, 250)),
]

def sdf(px, py, cx, cy, hw, hh, r):
    qx, qy = abs(px - cx) - (hw - r), abs(py - cy) - (hh - r)
    return math.hypot(max(qx, 0.0), max(qy, 0.0)) + min(max(qx, qy), 0.0) - r

def render(size):
    k = size / 256.0
    rows = bytearray()
    for y in range(size):
        rows.append(0)
        for x in range(size):
            px, py = (x + 0.5) / k, (y + 0.5) / k
            r = g = b = a = 0.0
            for cx, cy, hw, hh, rad, (lr, lg, lb) in LAYERS:
                c = min(max(0.5 - sdf(px, py, cx, cy, hw, hh, rad) * k, 0.0), 1.0)
                if c <= 0.0:
                    continue
                oa = c + a * (1.0 - c)
                r = (lr * c + r * a * (1.0 - c)) / oa
                g = (lg * c + g * a * (1.0 - c)) / oa
                b = (lb * c + b * a * (1.0 - c)) / oa
                a = oa
            rows += bytes((round(r), round(g), round(b), round(a * 255)))
    return bytes(rows)

def chunk(kind, data):
    body = kind + data
    return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

def png(size):
    header = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(render(size), 9)) + chunk(b"IEND", b"")

root = pathlib.Path(__file__).resolve().parent.parent
(root / "web" / "icons").mkdir(parents=True, exist_ok=True)
(root / "web" / "favicon.png").write_bytes(png(64))
(root / "web" / "icons" / "Icon-192.png").write_bytes(png(192))
(root / "web" / "icons" / "Icon-512.png").write_bytes(png(512))
print("wrote favicon.png, Icon-192.png, Icon-512.png")
