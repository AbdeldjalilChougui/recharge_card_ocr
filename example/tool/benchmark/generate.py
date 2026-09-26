#!/usr/bin/env python3
"""Render a synthetic recharge-card dataset for the recharge_card_ocr benchmark.

Every image is a made-up card: a gradient background with generic shapes,
the word "RECHARGE", Arabic and French distracting text, a price, dates, a
scratch panel with the code and a serial-number block with a fake barcode.
The code and serial sit where ZoneLayout.rechargeCard expects them:

    code:   NormRect(0.08, 0.28, 0.92, 0.46)
    serial: NormRect(0.05, 0.50, 0.95, 0.86)

No real operator's design, logo or trademark is reproduced, and the codes
are random digits with no checksum.

Each image gets one primary condition (blur, glare, EXIF rotation, ...)
at a random strength, or a mix of several; labels.json records the true
code, serial, grouping, conditions, font and parameters. The output is
reproducible for a given --seed, Pillow/NumPy version and set of installed
fonts.

Usage:
    python3 generate.py --out build/benchmark/synthetic [--seed 20260926]
                        [--per-condition 20]

Needs Pillow (with libraqm for Arabic shaping) and NumPy.
"""

from __future__ import annotations

import argparse
import io
import json
import math
import os
import random
import sys
from dataclasses import dataclass, field

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

CARD_ASPECT = 1.7

# Card-relative zones of ZoneLayout.rechargeCard (left, top, right, bottom).
CODE_ZONE = (0.08, 0.28, 0.92, 0.46)
SERIAL_ZONE = (0.05, 0.50, 0.95, 0.86)

# Code formats: total length -> printed groupings.
CODE_FORMATS = {
    16: [[4, 4, 4, 4]],
    15: [[5, 5, 5], [3, 4, 4, 4]],
    14: [[4, 4, 4, 2], [7, 7]],
}
SERIAL_LENGTH = 12

FONT_DIRS = [
    "/usr/share/fonts",
    "/usr/local/share/fonts",
    os.path.expanduser("~/.local/share/fonts"),
    os.path.expanduser("~/.fonts"),
    "/Library/Fonts",
    "/System/Library/Fonts",
    "C:/Windows/Fonts",
]

# Candidate fonts for the printed code; those that are installed are used.
CODE_FONTS = [
    "DejaVuSans.ttf",
    "DejaVuSans-Bold.ttf",
    "DejaVuSansMono.ttf",
    "DejaVuSansMono-Bold.ttf",
    "DejaVuSansCondensed-Bold.ttf",
    "DejaVuSerif.ttf",
    "LiberationSans-Regular.ttf",
    "LiberationSans-Bold.ttf",
    "LiberationMono-Regular.ttf",
    "LiberationMono-Bold.ttf",
    "LiberationSerif-Regular.ttf",
    "NotoSans-Regular.ttf",
    "NotoSans-Bold.ttf",
    "NotoSansMono-Bold.ttf",
    "NotoSerif-Regular.ttf",
]
TEXT_FONTS = ["DejaVuSans-Bold.ttf", "LiberationSans-Bold.ttf", "NotoSans-Bold.ttf"]
PLAIN_FONTS = ["DejaVuSans.ttf", "LiberationSans-Regular.ttf", "NotoSans-Regular.ttf"]
ARABIC_FONTS = [
    "NotoKufiArabic-Bold.ttf",
    "NotoNaskhArabic-Bold.ttf",
    "NotoSansArabic-Bold.ttf",
    "DroidKufi-Bold.ttf",
    "DejaVuSans.ttf",
]

ARABIC_TEXTS = ["بطاقة تعبئة", "بطاقة شحن الرصيد", "اكشط بلطف"]

CONDITIONS = [
    "clean",
    "perspective",
    "exif_rotation",
    "small_angle",
    "gaussian_blur",
    "motion_blur",
    "jpeg_low",
    "noise",
    "lighting_glare",
    "scratch_residue",
    "low_res",
    "mixed",
]
# Conditions that can be combined in "mixed" (at milder strength).
MIXABLE = [
    "perspective",
    "exif_rotation",
    "small_angle",
    "gaussian_blur",
    "motion_blur",
    "jpeg_low",
    "noise",
    "lighting_glare",
    "scratch_residue",
]


def find_fonts(names: list[str]) -> dict[str, str]:
    """Maps each installed font file name to its path."""
    index: dict[str, str] = {}
    for root in FONT_DIRS:
        if not os.path.isdir(root):
            continue
        for dirpath, _, files in os.walk(root):
            for f in files:
                index.setdefault(f, os.path.join(dirpath, f))
    return {n: index[n] for n in names if n in index}


@dataclass
class Sample:
    """One rendered card and its ground truth."""

    code: str
    groups: list[int]
    serial: str
    conditions: list[str]
    font: str
    params: dict = field(default_factory=dict)


# --------------------------------------------------------------------------
# Card rendering


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def gradient(w: int, h: int, c1, c2, angle: float) -> Image.Image:
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    d = xx / w * math.cos(angle) + yy / h * math.sin(angle)
    d = (d - d.min()) / max(1e-6, d.max() - d.min())
    arr = np.empty((h, w, 3), np.float32)
    for i in range(3):
        arr[..., i] = c1[i] + (c2[i] - c1[i]) * d
    return Image.fromarray(arr.clip(0, 255).astype(np.uint8), "RGB")


def random_color(rng: random.Random, dark: bool):
    base = [rng.randint(0, 255) for _ in range(3)]
    base[rng.randrange(3)] = rng.randint(150, 255)
    if dark:
        return tuple(int(v * 0.55) for v in base)
    return tuple(base)


def draw_texture(img: Image.Image, rng: random.Random) -> None:
    w, h = img.size
    over = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(over)
    kind = rng.choice(["circles", "waves", "stripes"])
    if kind == "circles":
        for _ in range(rng.randint(6, 14)):
            r = rng.randint(h // 10, h // 2)
            cx, cy = rng.randint(0, w), rng.randint(0, h)
            a = rng.randint(12, 40)
            d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=(255, 255, 255, a))
    elif kind == "waves":
        for k in range(rng.randint(5, 10)):
            y0 = rng.uniform(0, h)
            amp = rng.uniform(h * 0.03, h * 0.1)
            per = rng.uniform(w * 0.3, w * 0.8)
            pts = [(x, y0 + amp * math.sin(x / per * 2 * math.pi + k)) for x in range(0, w + 8, 8)]
            d.line(pts, fill=(255, 255, 255, rng.randint(25, 60)), width=max(2, h // 80))
    else:
        step = rng.randint(h // 14, h // 7)
        for x in range(-h, w + h, step):
            d.polygon(
                [(x, 0), (x + step // 2, 0), (x + step // 2 + h, h), (x + h, h)],
                fill=(255, 255, 255, rng.randint(10, 28)),
            )
    img.paste(Image.alpha_composite(img.convert("RGBA"), over).convert("RGB"))


def draw_logo(d: ImageDraw.ImageDraw, x: float, y: float, s: float, rng: random.Random) -> None:
    """A generic abstract mark: circles and a triangle, no letters."""
    c1 = (255, 255, 255)
    c2 = random_color(rng, dark=False)
    d.ellipse((x, y, x + s, y + s), fill=c1)
    kind = rng.choice(["ring", "tri", "dots"])
    if kind == "ring":
        m = s * 0.2
        d.ellipse((x + m, y + m, x + s - m, y + s - m), fill=c2)
        m2 = s * 0.38
        d.ellipse((x + m2, y + m2, x + s - m2, y + s - m2), fill=c1)
    elif kind == "tri":
        d.polygon([(x + s * 0.5, y + s * 0.15), (x + s * 0.85, y + s * 0.8), (x + s * 0.15, y + s * 0.8)], fill=c2)
    else:
        r = s * 0.12
        for i in range(3):
            cx = x + s * (0.28 + 0.22 * i)
            d.ellipse((cx - r, y + s * 0.5 - r, cx + r, y + s * 0.5 + r), fill=c2)


def fit_font(path: str, text: str, max_w: float, max_h: float) -> ImageFont.FreeTypeFont:
    size = int(max_h)
    while size > 6:
        f = ImageFont.truetype(path, size)
        b = f.getbbox(text)
        if b[2] - b[0] <= max_w and b[3] - b[1] <= max_h:
            return f
        size -= 1
    return ImageFont.truetype(path, 6)


def text_center(d, box, text, font, fill, **kw):
    b = d.textbbox((0, 0), text, font=font, **kw)
    tw, th = b[2] - b[0], b[3] - b[1]
    x = (box[0] + box[2]) / 2 - tw / 2 - b[0]
    y = (box[1] + box[3]) / 2 - th / 2 - b[1]
    d.text((x, y), text, font=font, fill=fill, **kw)


def render_card(s: Sample, rng: random.Random, fonts: dict, w: int, residue: float) -> Image.Image:
    h = round(w / CARD_ASPECT)
    c1 = random_color(rng, dark=True)
    c2 = random_color(rng, dark=rng.random() < 0.5)
    card = gradient(w, h, c1, c2, rng.uniform(0, math.pi))
    draw_texture(card, rng)
    d = ImageDraw.Draw(card)

    bold = fonts[rng.choice([f for f in TEXT_FONTS if f in fonts])]
    plain = fonts[rng.choice([f for f in PLAIN_FONTS if f in fonts])]
    arabic = [f for f in ARABIC_FONTS if f in fonts]

    # Top band: RECHARGE, logo, Arabic line.
    f = fit_font(bold, "RECHARGE", w * 0.42, h * 0.12)
    d.text((w * 0.05, h * 0.05), "RECHARGE", font=f, fill=(255, 255, 255))
    draw_logo(d, w * 0.84, h * 0.04, h * 0.17, rng)
    if arabic:
        at = rng.choice(ARABIC_TEXTS)
        fa = fit_font(fonts[arabic[0]], at, w * 0.28, h * 0.08)
        d.text((w * 0.52, h * 0.07), at, font=fa, fill=(255, 255, 255), direction="rtl", language="ar")
    price = rng.choice(["100 DA", "200 DA", "500 DA", "1000 DA", "2000 DA"])
    s.params["price"] = price
    small = fit_font(plain, "Grattez délicatement la zone argentée", w * 0.6, h * 0.045)
    d.text((w * 0.1, h * 0.215), "Grattez délicatement la zone argentée", font=small, fill=(240, 240, 240))

    # Scratch panel with the code (the panel as it looks after scratching).
    jx, jy = rng.uniform(-0.01, 0.01), rng.uniform(-0.008, 0.008)
    panel = (w * (0.11 + jx), h * (0.295 + jy), w * (0.89 + jx), h * (0.445 + jy))
    g = rng.randint(175, 215)
    d.rounded_rectangle(panel, radius=h * 0.03, fill=(g, g, g + rng.randint(-5, 10)))
    code_text = " ".join(_split(s.code, s.groups))
    code_font_path = fonts[s.font]
    size_frac = rng.uniform(0.55, 0.85)
    s.params["code_height_frac"] = round(size_frac, 3)
    fc = fit_font(code_font_path, code_text, (panel[2] - panel[0]) * 0.94, (panel[3] - panel[1]) * size_frac)
    ink = rng.randint(10, 60)
    text_center(d, panel, code_text, fc, (ink, ink, ink))
    if residue > 0:
        _scratch_residue(card, panel, residue, rng)

    # Serial block: serial line, barcode, validity and lot.
    d = ImageDraw.Draw(card)
    sy = h * rng.uniform(0.515, 0.545)
    grouped = rng.random() < 0.5
    serial_txt = " ".join(_split(s.serial, [4, 4, 4])) if grouped else s.serial
    label = rng.choice(["N° série :", "S/N", "Serial"])
    fs = fit_font(plain, f"{label} {serial_txt}", w * 0.62, h * 0.06)
    d.text((w * 0.07, sy), f"{label} {serial_txt}", font=fs, fill=(255, 255, 255))
    bx0, by0, bx1, by1 = w * 0.07, h * 0.63, w * rng.uniform(0.5, 0.6), h * 0.73
    d.rectangle((bx0 - 6, by0 - 6, bx1 + 6, by1 + 6), fill=(255, 255, 255))
    x = bx0
    while x < bx1:
        bw = rng.choice([1, 1, 2, 3]) * max(1, w // 400)
        if rng.random() < 0.55:
            d.rectangle((x, by0, x + bw - 1, by1), fill=(0, 0, 0))
        x += bw
    date = f"{rng.randint(1, 28):02d}/{rng.randint(1, 12):02d}/{rng.randint(2026, 2029)}"
    s.params["date"] = date
    fv = fit_font(plain, f"Valable jusqu'au {date}", w * 0.5, h * 0.05)
    d.text((w * 0.07, h * 0.77), f"Valable jusqu'au {date}", font=fv, fill=(255, 255, 255))
    lot = f"Lot {rng.randint(2024, 2026)}-{rng.randint(1, 9999):04d}"
    fl = fit_font(plain, lot, w * 0.25, h * 0.045)
    d.text((w * 0.66, h * 0.66), lot, font=fl, fill=(255, 255, 255))

    # Bottom band: price and a help line.
    fp = fit_font(bold, price, w * 0.3, h * 0.1)
    d.text((w * 0.64, h * 0.87), price, font=fp, fill=(255, 255, 255))
    fh = fit_font(plain, "Service client : 24h/24", w * 0.4, h * 0.04)
    d.text((w * 0.06, h * 0.92), "Service client : 24h/24", font=fh, fill=(235, 235, 235))
    return card


def _split(code: str, groups: list[int]) -> list[str]:
    out, i = [], 0
    for g in groups:
        out.append(code[i : i + g])
        i += g
    return out


def _scratch_residue(card: Image.Image, panel, amount: float, rng: random.Random) -> None:
    """Silver flakes and streaks left over the digits after scratching."""
    over = Image.new("RGBA", card.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(over)
    x0, y0, x1, y1 = panel
    ph = y1 - y0
    n = int(amount * 220)
    for _ in range(n):
        cx, cy = rng.uniform(x0, x1), rng.uniform(y0, y1)
        r = rng.uniform(ph * 0.02, ph * 0.11)
        g = rng.randint(170, 225)
        pts = [
            (cx + r * math.cos(a) * rng.uniform(0.5, 1.3), cy + r * math.sin(a) * rng.uniform(0.5, 1.3))
            for a in np.linspace(0, 2 * math.pi, 7)[:-1]
        ]
        d.polygon(pts, fill=(g, g, g, rng.randint(150, 250)))
    for _ in range(int(amount * 12)):
        yy = rng.uniform(y0, y1)
        d.line(
            (rng.uniform(x0, x1), yy, rng.uniform(x0, x1), yy + rng.uniform(-ph * 0.2, ph * 0.2)),
            fill=(200, 200, 205, rng.randint(120, 220)),
            width=max(1, int(ph * rng.uniform(0.03, 0.08))),
        )
    card.paste(Image.alpha_composite(card.convert("RGBA"), over).convert("RGB"))


# --------------------------------------------------------------------------
# Photographic conditions


def perspective_coeffs(src, dst):
    """Coefficients for Image.transform(PERSPECTIVE) mapping dst -> src."""
    a = []
    b = []
    for (xs, ys), (xd, yd) in zip(src, dst):
        a.append([xd, yd, 1, 0, 0, 0, -xs * xd, -xs * yd])
        a.append([0, 0, 0, xd, yd, 1, -ys * xd, -ys * yd])
        b += [xs, ys]
    return np.linalg.solve(np.array(a, float), np.array(b, float)).tolist()


def place_card(card: Image.Image, rng: random.Random, s: Sample, persp: float, angle: float) -> Image.Image:
    """Puts the card in a photo frame of the card's aspect, with small framing
    jitter, an optional perspective tilt and an optional in-plane angle."""
    w, h = card.size
    bg = tuple(rng.randint(40, 120) for _ in range(3))
    scale = rng.uniform(0.95, 1.0)
    ox = rng.uniform(-0.015, 0.015) * w + (1 - scale) * w / 2
    oy = rng.uniform(-0.015, 0.015) * h + (1 - scale) * h / 2
    corners = [(0, 0), (w, 0), (w, h), (0, h)]
    dst = []
    for cx, cy in corners:
        x = ox + cx * scale + rng.uniform(-persp, persp) * w
        y = oy + cy * scale + rng.uniform(-persp, persp) * h
        dst.append((x, y))
    if angle:
        mx, my = w / 2, h / 2
        ca, sa = math.cos(math.radians(angle)), math.sin(math.radians(angle))
        dst = [(mx + (x - mx) * ca - (y - my) * sa, my + (x - mx) * sa + (y - my) * ca) for x, y in dst]
    s.params["corners"] = [[round(x / w, 4), round(y / h, 4)] for x, y in dst]
    coeffs = perspective_coeffs(corners, dst)
    mask = Image.new("L", card.size, 255).transform(card.size, Image.PERSPECTIVE, coeffs, Image.BILINEAR)
    warped = card.transform(card.size, Image.PERSPECTIVE, coeffs, Image.BICUBIC)
    out = Image.new("RGB", card.size, bg)
    out.paste(warped, (0, 0), mask)
    return out


def lighting(img: Image.Image, rng: random.Random, strength: float, s: Sample) -> Image.Image:
    arr = np.asarray(img).astype(np.float32)
    h, w = arr.shape[:2]
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    a = rng.uniform(0, 2 * math.pi)
    ramp = (xx / w - 0.5) * math.cos(a) + (yy / h - 0.5) * math.sin(a)
    shade = 1 - strength * 0.6 * (ramp + 0.5)
    arr *= shade[..., None]
    spots = []
    for _ in range(rng.randint(1, 2)):
        cx = rng.uniform(0.15, 0.85) * w
        cy = rng.uniform(0.25, 0.5) * h  # glare tends to land on the glossy panel
        r = rng.uniform(0.05, 0.14) * w
        k = strength * rng.uniform(120, 230)
        arr += (k * np.exp(-(((xx - cx) ** 2 + (yy - cy) ** 2) / (2 * r * r))))[..., None]
        spots.append([round(cx / w, 3), round(cy / h, 3), round(r / w, 3)])
    s.params["glare_spots"] = spots
    return Image.fromarray(arr.clip(0, 255).astype(np.uint8))


def motion_blur(img: Image.Image, length: int, angle: float) -> Image.Image:
    arr = np.asarray(img).astype(np.float32)
    acc = np.zeros_like(arr)
    dx, dy = math.cos(math.radians(angle)), math.sin(math.radians(angle))
    for i in range(length):
        t = i - (length - 1) / 2
        acc += np.roll(np.roll(arr, int(round(t * dy)), axis=0), int(round(t * dx)), axis=1)
    return Image.fromarray((acc / length).clip(0, 255).astype(np.uint8))


def add_noise(img: Image.Image, sigma: float, rng: np.random.Generator) -> Image.Image:
    arr = np.asarray(img).astype(np.float32)
    arr += rng.normal(0, sigma, arr.shape[:2])[..., None] * 0.7
    arr += rng.normal(0, sigma * 0.5, arr.shape)
    return Image.fromarray(arr.clip(0, 255).astype(np.uint8))


# EXIF orientation tag -> how the stored pixels are rotated from upright.
EXIF_ROTATIONS = {
    1: None,
    6: Image.ROTATE_90,  # display needs 90 deg clockwise
    3: Image.ROTATE_180,
    8: Image.ROTATE_270,  # display needs 90 deg counter-clockwise
}


def encode(img: Image.Image, quality: int, orientation: int) -> bytes:
    stored = img
    op = EXIF_ROTATIONS[orientation]
    if op is not None:
        stored = img.transpose(op)
    exif = Image.Exif()
    exif[0x0112] = orientation
    buf = io.BytesIO()
    stored.save(buf, "JPEG", quality=quality, exif=exif.tobytes())
    return buf.getvalue()


# --------------------------------------------------------------------------


def make_sample(idx: int, primary: str, seed: int, fonts: dict, code_fonts: list[str]) -> tuple[Sample, bytes]:
    rng = random.Random(seed * 100003 + idx)
    nrng = np.random.default_rng(seed * 100003 + idx)
    length = rng.choice(sorted(CODE_FORMATS))
    groups = rng.choice(CODE_FORMATS[length])
    code = "".join(rng.choice("0123456789") for _ in range(length))
    serial = "".join(rng.choice("0123456789") for _ in range(SERIAL_LENGTH))
    font = code_fonts[idx % len(code_fonts)]

    if primary == "mixed":
        active = rng.sample(MIXABLE, rng.randint(2, 3))
        mild = 0.6
    elif primary == "clean":
        active, mild = [], 1.0
    else:
        active, mild = [primary], 1.0
    s = Sample(code=code, groups=groups, serial=serial, conditions=[primary] + ([c for c in active] if primary == "mixed" else []), font=font)

    width = rng.randint(1000, 1600)
    residue = rng.uniform(0.35, 1.0) * mild if "scratch_residue" in active else 0.0
    card = render_card(s, rng, fonts, width, residue)
    if residue:
        s.params["residue"] = round(residue, 3)

    persp = rng.uniform(0.02, 0.06) * mild if "perspective" in active else 0.0
    angle = 0.0
    if "small_angle" in active:
        angle = rng.choice([-1, 1]) * rng.uniform(2, 8) * mild
    img = place_card(card, rng, s, persp, angle)
    s.params["perspective"] = round(persp, 4)
    s.params["angle_deg"] = round(angle, 2)

    if "lighting_glare" in active:
        st = rng.uniform(0.5, 1.0) * mild
        s.params["lighting"] = round(st, 3)
        img = lighting(img, rng, st, s)
    scale = width / 1200
    if "gaussian_blur" in active:
        r = rng.uniform(1.2, 3.2) * mild * scale
        s.params["gaussian_radius_px"] = round(r, 2)
        img = img.filter(ImageFilter.GaussianBlur(r))
    if "motion_blur" in active:
        ln = max(3, int(rng.uniform(6, 18) * mild * scale))
        ang = rng.uniform(0, 180)
        s.params["motion_px"] = ln
        s.params["motion_angle"] = round(ang, 1)
        img = motion_blur(img, ln, ang)
    if "noise" in active:
        sg = rng.uniform(10, 30) * mild
        s.params["noise_sigma"] = round(sg, 1)
        img = add_noise(img, sg, nrng)
    if "low_res" in active:
        lw = rng.randint(320, 480)
        s.params["low_res_width"] = lw
        img = img.resize((lw, round(lw * img.height / img.width)), Image.BILINEAR)

    quality = rng.randint(80, 95)
    if "jpeg_low" in active:
        quality = rng.randint(8, 25) if mild == 1.0 else rng.randint(20, 40)
    s.params["jpeg_quality"] = quality
    orientation = 1
    if "exif_rotation" in active:
        orientation = rng.choice([6, 3, 8])
    s.params["exif_orientation"] = orientation
    s.params["width"] = img.width
    s.params["height"] = img.height
    return s, encode(img, quality, orientation)


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", required=True, help="output directory (created)")
    ap.add_argument("--seed", type=int, default=20260926)
    ap.add_argument("--per-condition", type=int, default=20, help="images per condition")
    args = ap.parse_args(argv)

    fonts = find_fonts(sorted(set(CODE_FONTS + TEXT_FONTS + PLAIN_FONTS + ARABIC_FONTS)))
    code_fonts = [f for f in CODE_FONTS if f in fonts]
    if not code_fonts or not any(f in fonts for f in TEXT_FONTS) or not any(f in fonts for f in PLAIN_FONTS):
        print("error: needs DejaVu, Liberation or Noto fonts installed", file=sys.stderr)
        return 1
    if not any(f in fonts for f in ARABIC_FONTS):
        print("warning: no Arabic-capable font found; Arabic text is skipped", file=sys.stderr)

    img_dir = os.path.join(args.out, "images")
    os.makedirs(img_dir, exist_ok=True)
    entries = []
    idx = 0
    for cond in CONDITIONS:
        for _ in range(args.per_condition):
            s, data = make_sample(idx, cond, args.seed, fonts, code_fonts)
            name = f"{idx:04d}_{cond}.jpg"
            with open(os.path.join(img_dir, name), "wb") as fh:
                fh.write(data)
            entries.append(
                {
                    "file": f"images/{name}",
                    "code": s.code,
                    "groups": s.groups,
                    "serial": s.serial,
                    "conditions": s.conditions,
                    "font": s.font,
                    "params": s.params,
                }
            )
            idx += 1
        print(f"{cond}: {args.per_condition} images", file=sys.stderr)

    labels = {
        "version": 1,
        "source": "synthetic",
        "generator": "example/tool/benchmark/generate.py",
        "seed": args.seed,
        "fonts": code_fonts,
        # What the on-device runner reads: one DigitCodeSpec per zone. The
        # code spec accepts all three generated lengths, as an app that
        # supports several card formats would; no grouping or checksum is
        # imposed.
        "spec": {"code": {"lengths": sorted(CODE_FORMATS)}, "serial": {"lengths": [SERIAL_LENGTH]}},
        "images": entries,
    }
    with open(os.path.join(args.out, "labels.json"), "w", encoding="utf-8") as fh:
        json.dump(labels, fh, ensure_ascii=False, indent=1)
    print(f"wrote {len(entries)} images to {img_dir}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
