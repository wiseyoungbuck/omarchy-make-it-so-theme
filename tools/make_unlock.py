"""Draw unlock.png: the boot / disk-unlock logo for Make It So.

usage: uv run --with pillow python tools/make_unlock.py [font.ttf]
Four captain's pips over a line of uniform crimson, and MAKE IT SO lettered
beneath in Earl Grey parchment. Original artwork; no Star Trek logos.
Then render the preview with Omarchy itself:
  omarchy plymouth preview "#11141c" "#e3d8c3" unlock.png preview-unlock.png
"""
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
FONT = sys.argv[1] if len(sys.argv) > 1 else "/usr/share/fonts/noto/NotoSans-Light.ttf"
SS = 4                                   # supersample, then downscale for clean edges
W, H = 800, 188
GOLD, GOLD_HI = (226, 178, 90), (242, 194, 114)
CRIMSON = (179, 35, 44)
PARCHMENT = (227, 216, 195)

big = Image.new("RGBA", (W * SS, H * SS), (0, 0, 0, 0))
d = ImageDraw.Draw(big)

# The line of command: a crimson rule, tapering at both ends.
ly = 62 * SS
for x in range(80 * SS, (W - 80) * SS):
    t = (x - 80 * SS) / ((W - 160) * SS)
    a = int(255 * min(1, t * 6, (1 - t) * 6))
    d.line([(x, ly - 3 * SS), (x, ly + 3 * SS)], fill=CRIMSON + (a,))

# Four pips, centred above the line, each with a faint brass rim.
r, gap = 15 * SS, 50 * SS
cx0 = W * SS / 2 - 1.5 * gap
for k in range(4):
    cx, cy = cx0 + k * gap, 26 * SS
    d.ellipse([cx - r - 2 * SS, cy - r - 2 * SS, cx + r + 2 * SS, cy + r + 2 * SS], fill=GOLD_HI + (110,))
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=GOLD + (255,))

# MAKE IT SO, widely tracked.
font = ImageFont.truetype(FONT, 64 * SS)
text, track = "MAKE IT SO", 26 * SS
widths = [d.textlength(ch, font=font) for ch in text]
total = sum(widths) + track * (len(text) - 1)
x, y = (W * SS - total) / 2, 92 * SS
for ch, w in zip(text, widths):
    d.text((x, y), ch, font=font, fill=PARCHMENT + (255,))
    x += w + track

img = big.resize((W, H), Image.LANCZOS)
img.save(ROOT / "unlock.png", optimize=True)
print("wrote unlock.png")
