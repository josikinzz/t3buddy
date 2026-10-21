#!/usr/bin/env python3
"""Draws the shoggoth's eye textures: the eyes on its body and tentacles (`eye`) and the eight-eyed
flower under its mask (`eyeface`). Standard library only.

    python3 -I scripts/draw_shoggoth_eyes.py [OUTDIR]

writes OUTDIR/eye.png and OUTDIR/eyeface.png (default .scratch/shoggoth-eyes), each with a
nearest-neighbour preview beside it (8x for eye, 4x for the larger eyeface). scripts/strip_shoggoth_glb.py draws them again and puts them
in Resources/Pet/shoggoth.glb in place of the owner's.

Each texture is two square panels side by side, for the shader (Resources/Pet/bodies/shoggoth-eyes.js)
to put together each frame:

    left    the open eye without its iris: ink outline, white of the eye, the fold above it
    right   the iris with its slit pupil and glint, where it sits looking straight ahead

The shader moves the iris toward what the shoggoth looks at and closes lids over the white, both
in whole texels. The eyes are almonds: at s along the eye (-1 .. 1, tip to tip) the opening reaches
`almond(s)` either side of the middle line, in units of the eye's half-height. The numbers here
are mirrored in shoggoth-eyes.js; Tests/Pet/bodies.test.mjs decodes these textures and fails if
the two disagree.

Greys sit in three bands, so the flower's Blender graph (shoggoth-eyes.js) reads them as it
reads the owner's art: ink and shading below linear 0.15 stay grey, the iris inside 0.15 .. 0.37
takes the tint, and white and glints above 0.37 stay white.
"""

import math
import os
import struct
import sys
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

ALMOND_POWER = 0.75
# The body's eye: one almond across the middle of its panel. Lengths are shares of the panel.
EYE = {"size": 64, "half_length": 0.44, "half_height": 0.26, "iris": 0.225, "slit": (0.05, 0.19)}
# The flower: FLOWER_EYES almonds on spokes 45 degrees apart, the first along +u, each centred
# `radius` out from the middle, its slit across its spoke.
FLOWER = {"size": 128, "eyes": 8, "radius": 0.3, "half_length": 0.165, "half_height": 0.085, "iris": 0.078, "slit": (0.014, 0.064)}

# sRGB greys. The iris tones are inside the tint band (sRGB 109 .. 164), everything else outside it.
INK = 0
SHADE = 72          # the fold above the eye, the iris rim
SCLERA = (252, 236, 214)   # white, its shaded edge, the shadow under the upper outline
IRIS = (120, 138, 156)     # the iris's outer, middle and inner rings
GLINT = 255


def almond(s):
    return (1 - s * s) ** ALMOND_POWER if abs(s) < 1 else 0.0


def eye_frame(du_, dv_, du, dv):
    """(along, across) of an offset from an eye's centre, its length along (du, dv); across is
    toward the top of the image for the body's eye, and turns with the spoke on the flower."""
    return du_ * du + dv_ * dv, du_ * dv - dv_ * du


def blank(n):
    return [[None] * n for _ in range(n)]


def grey(value, alpha=255):
    return (value, value, value, alpha)


def dilate(mask, radius):
    n, reach = len(mask), int(math.ceil(radius))
    offsets = [(dx, dy) for dy in range(-reach, reach + 1) for dx in range(-reach, reach + 1) if dx * dx + dy * dy <= radius * radius]
    return [[any(0 <= x + dx < n and 0 <= y + dy < n and mask[y + dy][x + dx] for dx, dy in offsets) for x in range(n)] for y in range(n)]


def frames(eyes, size):
    """Each eye as (centre u, v, along unit vector) in uv; yields texel (x, y) -> (eye, s, t)."""
    def local(x, y):
        u, v = (x + 0.5) / size, (y + 0.5) / size
        best = None
        for index, (cu, cv, du, dv, half_length, half_height) in enumerate(eyes):
            along, across = eye_frame(u - cu, v - cv, du, dv)
            s, t = along / half_length, across / half_height
            score = max(abs(s), abs(t) / max(almond(s), 1e-6))
            if best is None or score < best[3]:
                best = (index, s, t, score)
        return best[:3]
    return local


def draw(eyes, size, *, outline, fold, centre_spokes=False, iris_radius, slit):
    local = frames(eyes, size)
    texels = [[local(x, y) for x in range(size)] for y in range(size)]
    opening = [[abs(t) < almond(s) for (_, s, t) in row] for row in texels]
    rim = dilate(opening, outline)
    base, iris = blank(size), blank(size)

    if fold:
        # A fold line above and below the eye, parallel to its outline and clear of it, like the owner's.
        inner, outer = dilate(opening, outline + 1.6), dilate(opening, outline + 1.6 + fold)
        for y, row in enumerate(texels):
            for x, (_, s, t) in enumerate(row):
                if outer[y][x] and not inner[y][x] and abs(s) < 0.8:
                    base[y][x] = grey(INK)

    if centre_spokes:
        # The flower's middle: thin ink lines from its centre to each eye's inner tip.
        for y in range(size):
            for x in range(size):
                u, v = (x + 0.5) / size - 0.5, (y + 0.5) / size - 0.5
                r = math.hypot(u, v)
                for cu, cv, du, dv, half_length, _ in eyes:
                    tip = (cu - 0.5) - du * half_length, (cv - 0.5) - dv * half_length
                    reach = math.hypot(*tip)
                    along, across = eye_frame(u, v, du, dv)
                    if r < reach and abs(across) < 0.75 / size and along > 0:
                        base[y][x] = grey(INK)

    for y, row in enumerate(texels):
        for x, (index, s, t) in enumerate(row):
            if opening[y][x]:
                h = almond(s)
                # Shadow under the upper outline, a shaded rim round the rest, white in the middle.
                if t > h - 0.26:
                    base[y][x] = grey(SCLERA[2])
                elif abs(t) > h - 0.2 or abs(s) > 0.78:
                    base[y][x] = grey(SCLERA[1])
                else:
                    base[y][x] = grey(SCLERA[0])
            elif rim[y][x]:
                base[y][x] = grey(INK)

    # The iris, centred in its eye, ringed; its slit across the eye's length; a glint up and to the
    # right in the image, whichever way the eye lies, as one light would put it, and a speck opposite.
    for y in range(size):
        for x in range(size):
            u, v = (x + 0.5) / size, (y + 0.5) / size
            for cu, cv, du, dv, half_length, half_height in eyes:
                along, across = eye_frame(u - cu, v - cv, du, dv)
                r = math.hypot(along, across) / iris_radius
                if r > 1:
                    continue
                px = r * iris_radius * size
                angle = math.atan2(across, along)
                if iris_radius * size - px < 1.25:
                    tone = grey(SHADE)
                elif r > 0.72:
                    tone = grey(IRIS[0] if (math.floor(angle / (math.pi / 7)) % 2) else IRIS[1])
                elif r > 0.45:
                    tone = grey(IRIS[1] if (math.floor(angle / (math.pi / 9) + 0.5) % 2) else IRIS[0])
                else:
                    tone = grey(IRIS[2])
                width, height = slit
                if abs(across) < height and abs(along) < width * math.sqrt(max(0.0, 1 - (across / height) ** 2)) + 0.5 / size:
                    tone = grey(INK)
                glint = (u - cu - 0.36 * iris_radius) ** 2 + (v - cv + 0.4 * iris_radius) ** 2
                speck = (u - cu + 0.42 * iris_radius) ** 2 + (v - cv - 0.42 * iris_radius) ** 2
                if glint < (0.2 * iris_radius) ** 2 or speck < (0.085 * iris_radius) ** 2 + 0.3 / size ** 2:
                    tone = grey(GLINT)
                iris[y][x] = tone
    clear = (0, 0, 0, 0)
    return [[p or clear for p in row] for row in base], [[p or clear for p in row] for row in iris]


def body_eye():
    e = EYE
    return draw([(0.5, 0.5, 1.0, 0.0, e["half_length"], e["half_height"])], e["size"],
                outline=3.4, fold=2.1, iris_radius=e["iris"], slit=e["slit"])


def flower():
    f = FLOWER
    eyes = []
    for k in range(f["eyes"]):
        angle = 2 * math.pi * k / f["eyes"]
        du, dv = math.cos(angle), math.sin(angle)
        eyes.append((0.5 + f["radius"] * du, 0.5 + f["radius"] * dv, du, dv, f["half_length"], f["half_height"]))
    return draw(eyes, f["size"], outline=2.2, fold=0, centre_spokes=True, iris_radius=f["iris"], slit=f["slit"])


def side_by_side(left, right):
    return [a + b for a, b in zip(left, right)]


def encode_png(rows):
    width, height = len(rows[0]), len(rows)
    raw = b"".join(b"\0" + bytes(c for texel in row for c in texel) for row in rows)

    def chunk(kind, body):
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def atlases():
    """The two textures as PNG bytes, by the glTF image names they replace."""
    return {"eye": encode_png(side_by_side(*body_eye())), "eyeface": encode_png(side_by_side(*flower()))}


def preview(rows, scale, backdrop=(118, 112, 128, 255)):
    out = []
    for row in rows:
        line = [texel if texel[3] >= 128 else backdrop for texel in row for _ in range(scale)]
        out += [line] * scale
    return out


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, ".scratch/shoggoth-eyes")
    os.makedirs(out, exist_ok=True)
    for name, panels in (("eye", body_eye()), ("eyeface", flower())):
        rows = side_by_side(*panels)
        open(os.path.join(out, f"{name}.png"), "wb").write(encode_png(rows))
        open(os.path.join(out, f"{name}-preview.png"), "wb").write(encode_png(preview(rows, 8 if name == "eye" else 4)))
        print(os.path.join(out, f"{name}.png"))


if __name__ == "__main__":
    main()
