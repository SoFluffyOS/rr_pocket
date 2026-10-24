"""Composes the Play listing's graphics from store/captures/ into store/play/:
five phone screenshots (1080x1920) and the feature graphic (1024x500).

Every shot that shows the demo app also shows where it comes from (the
project on a computer, the command that runs it) and says it is the
developer's app running in RR Pocket, so nobody takes RR Pocket for a trails
app.

Usage: python3 tool/make_store_assets.py   (needs Pillow; run the capture first)
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
CAPTURES = ROOT / "store/captures"
OUT = ROOT / "store/play"
FONTS = ROOT / "app/fonts"
MONO = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"

SLATE = (31, 41, 51)
NIGHT = (14, 19, 25)
AMBER = (255, 181, 71)
WHITE = (255, 255, 255)
MIST = (201, 210, 220)
DIM = (120, 134, 150)
BEZEL = (10, 13, 17)
EDGE = (64, 76, 90)
CODE_BG = (16, 21, 28)
KEYWORD = (255, 181, 71)
TYPE = (125, 207, 255)
NUMBER = (232, 152, 255)
REMOVED = (120, 40, 44)
ADDED = (36, 96, 60)


def font(weight, size):
    return ImageFont.truetype(str(FONTS / f"Nunito-{weight}.ttf"), size)


def mono(size):
    try:
        return ImageFont.truetype(MONO, size)
    except OSError:
        return ImageFont.load_default(size)


def capture(name):
    return Image.open(CAPTURES / f"{name}.png").convert("RGB")


def background(size):
    """Slate fading to night, with a soft amber glow up top."""
    w, h = size
    image = Image.new("RGB", size, SLATE)
    draw = ImageDraw.Draw(image)
    for y in range(h):
        t = y / h
        draw.line([(0, y), (w, y)], fill=tuple(round(SLATE[i] + (NIGHT[i] - SLATE[i]) * t) for i in range(3)))
    glow = Image.new("L", size, 0)
    ImageDraw.Draw(glow).ellipse((w * 0.45, -h * 0.18, w * 1.25, h * 0.32), fill=90)
    glow = glow.filter(ImageFilter.GaussianBlur(w * 0.12))
    image.paste(Image.new("RGB", size, AMBER), (0, 0), glow)
    return image.convert("RGBA")


def phone(screen, width):
    """The capture in a drawn phone: bezel, edge, rounded screen, punch hole."""
    bezel = round(width * 0.028)
    screen = screen.resize((width, round(screen.height * width / screen.width)), Image.LANCZOS)
    w, h = width + 2 * bezel, screen.height + 2 * bezel
    radius = round(width * 0.12)
    body = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(body)
    draw.rounded_rectangle((0, 0, w - 1, h - 1), radius=radius, fill=BEZEL, outline=EDGE, width=3)
    mask = Image.new("L", screen.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, *screen.size), radius=radius - bezel, fill=255)
    body.paste(screen, (bezel, bezel), mask)
    hole = round(width * 0.017)
    cx, cy = w // 2, bezel + round(width * 0.045)
    draw.ellipse((cx - hole, cy - hole, cx + hole, cy + hole), fill=BEZEL)
    return body


def window(title, width, height, radius=28):
    """A dark desktop window with traffic lights and a title."""
    card = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    draw = ImageDraw.Draw(card)
    draw.rounded_rectangle((0, 0, width - 1, height - 1), radius=radius, fill=CODE_BG + (250,), outline=EDGE, width=2)
    for i, color in enumerate([(255, 95, 86), (255, 189, 46), (39, 201, 63)]):
        draw.ellipse((24 + i * 28, 20, 40 + i * 28, 36), fill=color)
    if title:
        draw.text((width / 2, 28), title, font=font("SemiBold", 22), fill=DIM, anchor="mm")
    return card, draw


def code_lines(draw, lines, x, y, size, line_height, numbers=True, right=None):
    """Lines of (text, color) runs, with dim line numbers and diff bands."""
    typeface = mono(size)
    for index, line in enumerate(lines):
        if line and line[0][0] in ("- ", "+ "):
            band = REMOVED if line[0][0] == "- " else ADDED
            draw.rectangle((x - 10, y - 6, right, y + line_height - 12), fill=band)
        cursor = x
        if numbers:
            draw.text((cursor, y), f"{index + 1:>2}", font=typeface, fill=DIM)
            cursor += typeface.getlength("00  ")
        for text, color in line:
            draw.text((cursor, y), text, font=typeface, fill=color)
            cursor += typeface.getlength(text)
        y += line_height
    return y


def plain(text):
    return (text, MIST)


SOURCE = [
    [("const ", KEYWORD), plain("accent = "), ("Color", TYPE), plain("("), ("0xFF2E7D6B", NUMBER), plain(");")],
    [],
    [("void ", KEYWORD), plain("main() => runApp("), ("const ", KEYWORD), ("TrailsApp", TYPE), plain("());")],
    [],
    [("class ", KEYWORD), ("TrailsApp ", TYPE), ("extends ", KEYWORD), ("StatelessWidget ", TYPE), plain("{")],
    [plain("  "), ("Widget ", TYPE), plain("build(context) => "), ("MaterialApp", TYPE), plain("(")],
    [plain("    theme: "), ("ThemeData", TYPE), plain("(colorSchemeSeed: accent),")],
    [plain("    home: "), ("const ", KEYWORD), ("ExplorePage", TYPE), plain("(),")],
    [plain("  );")],
    [plain("}")],
]

RUN = [
    [("$ ", AMBER), ("flutter run -d pocket", WHITE)],
    [plain("Launching lib/main.dart on RR Pocket...")],
    [plain("Syncing files to device RR Pocket...")],
    [("r", WHITE), plain(" Hot reload.  "), ("q", WHITE), plain(" Quit.")],
]


def laptop(width):
    """A laptop showing the project: its code above, the run below."""
    screen_w = width - 40
    screen_h = round(screen_w * 0.66)
    editor, draw = window("trails — lib/main.dart", screen_w, screen_h, radius=18)
    y = code_lines(draw, SOURCE, 28, 66, 19, 30)
    draw.line((0, y + 6, screen_w, y + 6), fill=EDGE, width=2)
    draw.text((28, y + 18), "TERMINAL", font=font("Bold", 16), fill=DIM)
    code_lines(draw, RUN, 28, y + 48, 19, 30, numbers=False)
    if screen_w != 860:
        editor = editor.resize((screen_w, screen_h), Image.LANCZOS)

    body = Image.new("RGBA", (width + 120, screen_h + 64), (0, 0, 0, 0))
    d = ImageDraw.Draw(body)
    d.rounded_rectangle((60, 0, 60 + width - 1, screen_h + 40), radius=26, fill=BEZEL, outline=EDGE, width=3)
    body.alpha_composite(editor, (80, 20))
    d.polygon([(0, screen_h + 40), (width + 120, screen_h + 40), (width + 90, screen_h + 64), (30, screen_h + 64)],
              fill=(52, 62, 74))
    d.rounded_rectangle((width // 2, screen_h + 40, width // 2 + 120, screen_h + 50), radius=5, fill=(36, 44, 54))
    return body


def scaled(item, width):
    return item.resize((width, round(item.height * width / item.width)), Image.LANCZOS)


def pill(text, dark=False):
    typeface = font("ExtraBold", 34)
    w = round(typeface.getlength(text)) + 56
    card = Image.new("RGBA", (w, 70), (0, 0, 0, 0))
    draw = ImageDraw.Draw(card)
    fill, ink = ((14, 19, 25, 235), AMBER) if dark else (AMBER + (255,), NIGHT)
    draw.rounded_rectangle((0, 0, w - 1, 69), radius=35, fill=fill, outline=AMBER, width=3)
    draw.text((w / 2, 35), text, font=typeface, fill=ink, anchor="mm")
    return card


def place(canvas, item, xy, shadow=True):
    """Pastes an RGBA item with a soft shadow below it."""
    if shadow:
        blur = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
        alpha = item.split()[3].point(lambda a: a * 0.55)
        blur.paste((0, 0, 0, 255), (xy[0], xy[1] + 30), alpha)
        canvas.alpha_composite(blur.filter(ImageFilter.GaussianBlur(40)))
    canvas.alpha_composite(item, xy)


def centered(draw, y, text, typeface, fill, width):
    """Draws text, each line centred; returns the y below it."""
    box = draw.multiline_textbbox((0, 0), text, font=typeface, spacing=12, align="center")
    x = (width - (box[2] - box[0])) / 2 - box[0]
    draw.multiline_text((x, y), text, font=typeface, fill=fill, spacing=12, align="center")
    return y + box[3]


def captioned(title, subtitle, subtitle_font=None):
    """The background and the caption; returns it and the y below the caption."""
    canvas = background((1080, 1920))
    draw = ImageDraw.Draw(canvas)
    y = centered(draw, 110, title, font("Black", 84), WHITE, 1080)
    y = centered(draw, y + 30, subtitle, subtitle_font or font("SemiBold", 42), MIST, 1080)
    return canvas, y


def hero():
    canvas, y = captioned("Your Flutter app,\non your phone", "Code on your computer. It runs here.")
    computer = laptop(900)
    computer_y = y + 70
    place(canvas, computer, ((1080 - computer.width) // 2, computer_y))
    place(canvas, pill("Your project", dark=True), (60, computer_y - 35), shadow=False)
    device = phone(capture("demo"), 470)
    phone_xy = (540, computer_y + computer.height - 140)
    place(canvas, device, phone_xy)
    label = pill("Running in RR Pocket")
    label_xy = (phone_xy[0] - label.width + 90, phone_xy[1] + 560)
    link(canvas, 330, computer_y + computer.height - 6, label_xy[1] - 6)
    place(canvas, label, label_xy)
    save(canvas, "1-your-app")


def link(canvas, x, top, bottom):
    """A dashed line from the computer down to the phone's label, through a
    Wi-Fi badge."""
    draw = ImageDraw.Draw(canvas)
    for y in range(top, bottom, 28):
        draw.line((x, y, x, min(y + 14, bottom)), fill=AMBER, width=6)
    cy, r = (top + bottom) // 2, 52
    draw.ellipse((x - r, cy - r, x + r, cy + r), fill=NIGHT, outline=AMBER, width=5)
    for radius in (12, 24, 36):
        draw.arc((x - radius, cy + 12 - radius, x + radius, cy + 12 + radius), 225, 315, fill=AMBER, width=6)
    draw.ellipse((x - 5, cy + 7, x + 5, cy + 17), fill=AMBER)


def pairing():
    canvas, y = captioned("No Android SDK.\nNo adb.", "Pair once over Wi-Fi. That's the setup.")
    device = phone(capture("home_light"), 620)
    place(canvas, device, ((1080 - device.width) // 2, y + 70))
    card, draw = window("Terminal", 980, 200)
    code_lines(draw, [
        [("$ ", AMBER), ("pocket pair 10.0.2.16 FXSLEDDB", WHITE)],
        [plain("Paired with RR Pocket.")],
    ], 28, 74, 25, 52, numbers=False)
    place(canvas, card, ((1080 - card.width) // 2, 1500))
    place(canvas, pill("On your computer, once"), (50, 1462), shadow=False)
    save(canvas, "2-no-sdk")


def command():
    canvas, y = captioned("One command", "flutter run -d pocket", subtitle_font=mono(44))
    card, draw = window("Terminal — your project", 960, 300)
    code_lines(draw, RUN, 28, 74, 25, 52, numbers=False)
    place(canvas, card, ((1080 - card.width) // 2, y + 60))
    device = phone(capture("demo"), 600)
    top = y + 60 + card.height + 70
    place(canvas, device, ((1080 - device.width) // 2, top))
    label = pill("Your app, on RR Pocket")
    place(canvas, label, ((1080 - label.width) // 2, top - 40))
    save(canvas, "3-one-command")


def reload():
    canvas, y = captioned("Hot reload,\nunder a second", "Change your code, press r, see it.")
    card, draw = window("lib/main.dart", 960, 180)
    diff = [
        [("- ", (255, 140, 140)), ("const ", KEYWORD), plain("accent = "), ("Color", TYPE), plain("("),
         ("0xFF2E7D6B", NUMBER), plain(");")],
        [("+ ", (140, 255, 170)), ("const ", KEYWORD), plain("accent = "), ("Color", TYPE), plain("("),
         ("0xFFE8622C", NUMBER), plain(");")],
    ]
    code_lines(draw, diff, 34, 70, 27, 52, numbers=False, right=940)
    place(canvas, card, ((1080 - card.width) // 2, y + 50))
    top = y + 50 + card.height + 110
    left = phone(capture("demo"), 450)
    right = phone(capture("demo_reloaded"), 450)
    place(canvas, left, (50, top))
    place(canvas, right, (1080 - 50 - right.width, top))
    draw = ImageDraw.Draw(canvas)
    cx, cy, r = 540, top + 380, 70
    draw.ellipse((cx - r, cy - r, cx + r, cy + r), fill=AMBER, outline=NIGHT, width=8)
    draw.text((cx, cy), "r", font=font("Black", 72), fill=NIGHT, anchor="mm")
    for text, x in [("Before", 50 + left.width // 2), ("After", 1080 - 50 - right.width // 2)]:
        label = pill(text, dark=True)
        place(canvas, label, (x - label.width // 2, top - 40), shadow=False)
    save(canvas, "4-hot-reload")


def plugins():
    canvas, y = captioned("26 plugins built in", "Camera, location, notifications, storage.")
    device = phone(capture("plugins_dark"), 640)
    place(canvas, device, ((1080 - device.width) // 2, y + 70))
    save(canvas, "5-plugins")


def feature_graphic():
    canvas = background((1024, 500))
    icon = Image.open(ROOT / "branding/icon-512.png").convert("RGBA").resize((110, 110), Image.LANCZOS)
    mask = Image.new("L", icon.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, 109, 109), radius=28, fill=255)
    rounded = Image.new("RGBA", icon.size, (0, 0, 0, 0))
    rounded.paste(icon, (0, 0), mask)
    place(canvas, rounded, (56, 64), shadow=False)
    draw = ImageDraw.Draw(canvas)
    draw.text((54, 190), "RR Pocket", font=font("Black", 66), fill=WHITE)
    draw.text((58, 284), "Run your Flutter project", font=font("SemiBold", 28), fill=MIST)
    draw.text((58, 322), "on your phone, over Wi-Fi.", font=font("SemiBold", 28), fill=MIST)
    draw.text((58, 376), "No Android SDK. No adb.", font=font("ExtraBold", 28), fill=AMBER)
    computer = scaled(laptop(900), 470)
    place(canvas, computer, (470, 80))
    device = phone(capture("demo"), 150)
    place(canvas, device, (840, 170))
    save(canvas, "feature-graphic", size=(1024, 500))


def save(canvas, name, size=(1080, 1920)):
    OUT.mkdir(parents=True, exist_ok=True)
    image = canvas.convert("RGB")
    assert image.size == size, (name, image.size)
    image.save(OUT / f"{name}.png", optimize=True)
    print("wrote", f"store/play/{name}.png")


hero()
pairing()
command()
reload()
plugins()
feature_graphic()
# Play wants the icon as a 32-bit PNG.
Image.open(ROOT / "branding/icon-512.png").convert("RGBA").save(OUT / "icon-512.png")
print("wrote store/play/icon-512.png")
