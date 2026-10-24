"""Draws the R² mark as SVG for the Lumide plugin, from Nunito ExtraBold's
own outlines, laid out as tool/make_icons.py lays out the app icon:

- desktop/assets/icon_rr_pocket_solid.svg: one colour, for the status bar,
  which tints it like Lumide's own icons;
- desktop/assets/icon_rr_pocket.svg: the app icon's colours, for the menu.

Usage: python3 tool/make_plugin_icons.py   (needs fontTools)
"""
from pathlib import Path

from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parent.parent
FONT = ROOT / "app/fonts/Nunito-ExtraBold.ttf"
OUT = ROOT / "desktop/assets"
BACKGROUND = "#1F2933"  # the app icon's, also in values/colors.xml
LETTER = "#FFFFFF"
SQUARE = "#FFB547"

font = TTFont(FONT)
glyphs = font.getGlyphSet()
cmap = font.getBestCmap()


def bounds(char):
    pen = BoundsPen(glyphs)
    glyphs[cmap[ord(char)]].draw(pen)
    return pen.bounds  # xMin, yMin, xMax, yMax, font units, y up


def path(char, scale, left, top):
    """The glyph as SVG path data, scaled, its box's top-left at (left, top)."""
    x_min, _, _, y_max = bounds(char)
    pen = SVGPathPen(glyphs)
    # Font units have y up; SVG has y down.
    glyphs[cmap[ord(char)]].draw(TransformPen(
        pen, (scale, 0, 0, -scale, left - x_min * scale, top + y_max * scale)))
    return pen.getCommands()


def logo(x, y, w, h):
    """R and a superscript 2 centred in the box, as make_icons.py's
    draw_logo: R at 0.92 of the box's height, 2 at 0.42, a slight overlap."""
    upm = font["head"].unitsPerEm
    r_scale, two_scale = h * 0.92 / upm, h * 0.42 / upm
    rx0, ry0, rx1, ry1 = bounds("R")
    tx0, ty0, tx1, ty1 = bounds("2")
    r_w, r_h = (rx1 - rx0) * r_scale, (ry1 - ry0) * r_scale
    two_w = (tx1 - tx0) * two_scale
    gap = -h * 0.03
    left = x + (w - (r_w + gap + two_w)) / 2
    top = y + (h - r_h) / 2
    return (path("R", r_scale, left, top),
            path("2", two_scale, left + r_w + gap, top - h * 0.02))


def svg(size, body):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" '
            f'height="{size}" viewBox="0 0 {size} {size}">{body}</svg>\n')


OUT.mkdir(parents=True, exist_ok=True)

# The status bar draws it at 14 px: the mark fills the square.
r, two = logo(0, 2, 24, 20)
(OUT / "icon_rr_pocket_solid.svg").write_text(
    svg(24, f'<path fill="#000" d="{r} {two}"/>'))

# The app icon: the mark on its slate square.
r, two = logo(64 * 0.18, 64 * 0.22, 64 * 0.64, 64 * 0.56)
(OUT / "icon_rr_pocket.svg").write_text(svg(64, (
    f'<rect width="64" height="64" rx="14" fill="{BACKGROUND}"/>'
    f'<path fill="{LETTER}" d="{r}"/><path fill="{SQUARE}" d="{two}"/>')))
print("plugin icons written")
