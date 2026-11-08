"""Compose preview.png: the Make It So wallpaper with a terminal in the theme's colours.

usage: uv run --with pillow python tools/make_preview.py
Reads colors.toml and backgrounds/4-make-it-so.webp; writes preview.png (2560x1440).
Built only from the theme's own artwork, so the preview carries nothing third-party.
"""
import re
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
W, H = 2560, 1440
c = dict(re.findall(r'^(\w+)\s*=\s*"(#[0-9a-fA-F]{6})"', (ROOT / "colors.toml").read_text(), re.M))

FONT = next((p for p in sys.argv[1:] if p.endswith(".ttf")), None) or \
    "/usr/share/fonts/TTF/MesloLGSDZNerdFontMono-Regular.ttf"
font = ImageFont.truetype(FONT, 30)
small = ImageFont.truetype(FONT, 24)

img = Image.open(ROOT / "backgrounds" / "4-make-it-so.webp").convert("RGB").resize((W, H), Image.LANCZOS)
d = ImageDraw.Draw(img)

# Bar along the top, with the delta engine-hum toggle on the right.
d.rectangle([0, 0, W, 44], fill=c["darker_background"])
d.text((28, 9), "1  2  3", font=small, fill=c["foreground"])
d.text((W // 2 - 90, 9), "Stardate 47457.1", font=small, fill=c["foreground"])
# delta, scaled from the bar icon's path outline (15.6 x 24 units)
s, ox, oy = 1.25, W - 70, 7
pts = [(7.8, 0), (12.7, 8.4), (15.6, 23.9), (13.0, 18.3), (10.3, 14.5), (7.4, 16.5), (2.9, 20.7), (0.05, 23.7), (3.9, 6)]
d.polygon([(ox + x * s, oy + y * s) for x, y in pts], fill=c["foreground"])

# Terminal window with the uniform-crimson-to-pip-gold border.
x0, y0, x1, y1 = 360, 230, 1700, 1010
border = Image.new("RGB", (x1 - x0, y1 - y0))
bd = ImageDraw.Draw(border)
for x in range(x1 - x0):
    t = x / (x1 - x0)
    a, b = (0xcc, 0x3a, 0x40), (0xf2, 0xc2, 0x72)
    bd.line([(x, 0), (x, y1 - y0)], fill=tuple(int(a[k] + (b[k] - a[k]) * t) for k in range(3)))
img.paste(border, (x0, y0))
d.rectangle([x0 + 4, y0 + 4, x1 - 4, y1 - 4], fill=c["background"])

lines = [
    [("~ ", c["blue"]), ("❯ ", c["accent"]), ("engine-hum on", c["foreground"])],
    [("Engine hum engaged. ", c["light_foreground"]), ("Make it so.", c["yellow"])],
    [],
    [("~ ", c["blue"]), ("❯ ", c["accent"]), ("cat ", c["foreground"]), ("first-duty.txt", c["cyan"])],
    [('"The first duty of every Starfleet officer is to the truth."', c["foreground"])],
    [],
    [("~ ", c["blue"]), ("❯ ", c["accent"]), ("git log --oneline", c["foreground"])],
    [("4f1a2c0 ", c["yellow"]), ("(HEAD -> ", c["cyan"]), ("main", c["green"]), (") ", c["cyan"]),
     ("Seize the time", c["foreground"])],
    [("9d03b7e ", c["yellow"]), ("We work to better ourselves", c["foreground"])],
    [("1701d00 ", c["yellow"]), ("Engage", c["foreground"])],
    [],
]
y = y0 + 50
for line in lines:
    x = x0 + 50
    for text, col in line:
        d.text((x, y), text, font=font, fill=col)
        x += d.textlength(text, font=font)
    y += 48

# The palette, as swatches along the bottom of the terminal.
names = ["red", "orange", "yellow", "green", "cyan", "blue", "magenta", "brown",
         "bright_red", "bright_yellow", "bright_green", "bright_cyan", "bright_blue", "bright_magenta"]
sw = (x1 - x0 - 100) / len(names)
for i, n in enumerate(names):
    sx = x0 + 50 + i * sw
    d.rounded_rectangle([sx, y1 - 110, sx + sw - 12, y1 - 50], radius=8, fill=c[n])

img.save(ROOT / "preview.png", optimize=True)
print("wrote preview.png")
