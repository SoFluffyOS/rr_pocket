"""Draws the R² launcher icons into the Android app and branding/.

Usage: python3 tool/make_icons.py   (from the repo root; needs Pillow)
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
RES = ROOT / "app/android/app/src/main/res"
FONT = ROOT / "app/fonts/Nunito-ExtraBold.ttf"
BACKGROUND = (31, 41, 51)  # #1F2933, also in values/colors.xml
LETTER = (255, 255, 255)
SQUARE = (255, 181, 71)  # #FFB547

DENSITIES = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}


def font(px):
    return ImageFont.truetype(str(FONT), px)


def draw_logo(img, box):
    """Draws R² centred in box (x, y, w, h), sized to its height."""
    x, y, w, h = box
    d = ImageDraw.Draw(img)
    r, two = font(int(h * 0.92)), font(int(h * 0.42))
    rl, rt, rr, rb = d.textbbox((0, 0), "R", font=r)
    tl, tt, tr, tb = d.textbbox((0, 0), "2", font=two)
    gap = -h * 0.03
    width = (rr - rl) + gap + (tr - tl)
    left = x + (w - width) / 2
    top = y + (h - (rb - rt)) / 2
    d.text((left - rl, top - rt), "R", font=r, fill=LETTER)
    d.text((left + (rr - rl) + gap - tl, top - tt - h * 0.02), "2", font=two, fill=SQUARE)


def legacy(size):
    scale = 4
    big = Image.new("RGBA", (size * scale, size * scale), (0, 0, 0, 0))
    ImageDraw.Draw(big).rounded_rectangle(
        (0, 0, size * scale - 1, size * scale - 1), radius=size * scale * 0.22, fill=BACKGROUND)
    s = size * scale
    draw_logo(big, (s * 0.18, s * 0.22, s * 0.64, s * 0.56))
    return big.resize((size, size), Image.LANCZOS)


def foreground(size):
    """Adaptive icon layer: 108dp, the logo inside the 66dp safe zone."""
    scale = 4
    s = size * scale
    big = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    draw_logo(big, (s * 0.25, s * 0.31, s * 0.5, s * 0.38))
    return big.resize((size, size), Image.LANCZOS)


for name, k in DENSITIES.items():
    (RES / f"mipmap-{name}").mkdir(exist_ok=True)
    legacy(int(48 * k)).save(RES / f"mipmap-{name}/ic_launcher.png")
    foreground(int(108 * k)).save(RES / f"mipmap-{name}/ic_launcher_foreground.png")

(ROOT / "branding").mkdir(exist_ok=True)
play = Image.new("RGBA", (512, 512), BACKGROUND)
draw_logo(play, (512 * 0.18, 512 * 0.22, 512 * 0.64, 512 * 0.56))
play.save(ROOT / "branding/icon-512.png")
print("icons written")
