"""Generate the original wallpapers for the Make It So Omarchy theme.

usage: uv run --with numpy --with pillow python tools/make_bgs.py backgrounds/
"""
import sys
import numpy as np
from PIL import Image, ImageFilter

W, H = 3840, 2160
OUT = sys.argv[1]
rng = np.random.default_rng(1701)


def hexc(h):
    return np.array([int(h[i:i + 2], 16) for i in (1, 3, 5)], dtype=np.float32)


BG = hexc("#11141c")
DEEP = hexc("#08090e")
RED = hexc("#b3232c")  # command uniform crimson
GOLD = hexc("#e2b25a")
CREAM = hexc("#f7f0e2")
BLUE = hexc("#7f96d4")
LAV = hexc("#b591c8")
WOOD = hexc("#8c6849")

yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)


def stars(img, n, max_r=2.2, tint=True):
    xs = rng.uniform(0, W, n)
    ys = rng.uniform(0, H, n)
    b = rng.power(6, n)  # mostly faint
    layer = np.zeros((H, W), np.float32)
    xi, yi = xs.astype(int), ys.astype(int)
    np.add.at(layer, (yi, xi), b * 255)
    glow = Image.fromarray(np.clip(layer, 0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.1))
    g = np.asarray(glow, np.float32) / 255 * 3.0
    sharp = np.clip(layer / 255, 0, 1)
    s = np.clip(g + sharp, 0, 1)[..., None]
    col = CREAM if not tint else (CREAM * 0.8 + BLUE * 0.2)
    return img * (1 - s) + col * s


def noise(scale, octaves=4, seed=0):
    r = np.random.default_rng(seed)
    acc = np.zeros((H, W), np.float32)
    amp = 1.0
    for o in range(octaves):
        s = max(2, int(W / (scale / 2 ** o)))
        sh = max(2, int(s * H / W))
        small = r.random((sh, s)).astype(np.float32)
        im = Image.fromarray((small * 255).astype(np.uint8)).resize((W, H), Image.BICUBIC)
        acc += np.asarray(im, np.float32) / 255 * amp
        amp *= 0.5
    return acc / acc.max()


def save(img, name):
    # gentle film grain to avoid banding
    img = img + rng.normal(0, 1.6, img.shape).astype(np.float32)
    Image.fromarray(np.clip(img, 0, 255).astype(np.uint8)).save(f"{OUT}/{name}", quality=92, method=6)
    print("wrote", name)


def vertical(top, bottom):
    t = (yy / H)[..., None]
    return top * (1 - t) + bottom * t


# 1. The ready-room window: a planet limb at dawn under deep space.
img = vertical(DEEP, BG)
neb = noise(1400, 5, seed=3)
neb = np.clip((neb - 0.45) * 2.2, 0, 1) ** 2
mask = np.exp(-((xx - W * 0.72) ** 2 / (W * 0.35) ** 2 + (yy - H * 0.3) ** 2 / (H * 0.35) ** 2))
img += (LAV * 0.10 + BLUE * 0.06) * (neb * mask)[..., None]
img = stars(img, 5200)
cx, cy, R = W * 0.5, H * 2.35, H * 1.75
d = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2)
inside = d < R
# planet body: nearly black with a faint terminator
body = np.clip((yy - (cy - R)) / (H * 0.5), 0, 1)
planet = DEEP * 0.6 + WOOD * 0.05 * (1 - body)[..., None]
img = np.where(inside[..., None], planet, img)
# atmospheric rim: gold at the core of the sunrise, red to the flanks
rim = np.exp(-((d - R) / 10.0) ** 2) + 0.55 * np.exp(-np.clip(d - R, 0, None) / 55.0) * (d >= R)
spread = np.exp(-((xx - W * 0.5) / (W * 0.33)) ** 2)
rimcol = GOLD * spread[..., None] + RED * (1 - spread)[..., None]
img += rimcol * (rim * (0.25 + 0.75 * spread))[..., None] * 0.9
# sun flare at the limb
fd = np.sqrt((xx - W * 0.5) ** 2 + ((yy - (cy - R)) * 2.2) ** 2)
img += CREAM * (np.exp(-fd / 38.0) * 1.2 + np.exp(-fd / 260.0) * 0.18)[..., None] * 0.9
save(img, "1-seize-the-time.webp")

# 2. Engage: warp streaks converging on a vanishing point.
img = np.full((H, W, 3), DEEP, np.float32)
cx, cy = W * 0.5, H * 0.46
ang = np.arctan2(yy - cy, xx - cx)
rad = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2) / (W * 0.6)
nlines = 900
a_bins = ((ang + np.pi) / (2 * np.pi) * nlines).astype(int) % nlines
line_on = rng.random(nlines) < 0.32
line_b = rng.power(3, nlines)
line_start = rng.uniform(0.05, 0.6, nlines)
line_col = rng.random(nlines)
frac = ((ang + np.pi) / (2 * np.pi) * nlines) % 1.0
thin = np.exp(-((frac - 0.5) / 0.09) ** 2)
on = line_on[a_bins] & (rad > line_start[a_bins])
fade = np.clip((rad - line_start[a_bins]) * 2.5, 0, 1) * np.clip(1.4 - rad, 0, 1)
streak = (on * thin * fade * line_b[a_bins])[..., None]
col = np.where((line_col[a_bins] < 0.75)[..., None], CREAM * 0.7 + BLUE * 0.3, GOLD)
img += col * streak * 0.85
core = np.exp(-rad / 0.05)[..., None]
img += (BLUE * 0.5 + CREAM * 0.5) * core * 0.9 + RED * np.exp(-rad / 0.35)[..., None] * 0.10
img = stars(img, 1800)
save(img, "2-things-are-only-impossible-until-they-are-not.webp")

# 3. La Barre: vineyard hills at dusk.
sky_t = (yy / H)[..., None]
img = BG * (1 - sky_t) + (RED * 0.55 + GOLD * 0.25) * sky_t
glow = np.exp(-((xx - W * 0.62) ** 2 / (W * 0.25) ** 2 + (yy - H * 0.62) ** 2 / (H * 0.12) ** 2))
img += GOLD * glow[..., None] * 0.55
img = stars(img * 1.0, 700) * (1 - sky_t * 0.0)
# fade stars toward horizon
img = img * (yy < H * 0.55)[..., None] + img * (yy >= H * 0.55)[..., None]
layers = [
    (0.60, 60, 0.0016, hexc("#3a2a2c")),
    (0.68, 90, 0.0011, hexc("#2a1e22")),
    (0.78, 120, 0.0008, hexc("#1a1418")),
    (0.90, 150, 0.0006, hexc("#0c0b0f")),
]
for i, (base, amp, freq, c) in enumerate(layers):
    ph = rng.uniform(0, 6.28)
    ridge = H * base + amp * np.sin(xx[0] * freq + ph) + amp * 0.4 * np.sin(xx[0] * freq * 2.7 + ph * 1.3)
    m = yy > ridge[None, :]
    shade = c.copy()
    img = np.where(m[..., None], shade, img)
    if i >= 2:  # vine rows converging on the sunset, anti-aliased
        vx, vy = W * 0.62, H * 0.58
        theta = np.arctan2(xx - vx, yy - vy)
        r = np.sqrt((xx - vx) ** 2 + (yy - vy) ** 2)
        N = 140
        stripe = 0.5 + 0.5 * np.cos(theta * N)
        # rows only resolvable where angular period spans enough pixels
        aa = np.clip((r * 2 * np.pi / N - 3.0) / 6.0, 0, 1)
        depth = np.clip((yy - ridge[None, :]) / 80.0, 0, 1)
        amt = (stripe ** 3 * aa * depth * m)[..., None]
        img = img + (GOLD * 0.10 + WOOD * 0.12) * amt * (0.5 + 0.5 * (i == 3))
save(img, "3-we-work-to-better-ourselves.webp")

# 4. Make it so: quiet ground, one line of command red, four gold pips.
img = vertical(BG, DEEP)
img = stars(img, 900)
lineY = H * 0.62
band = np.clip(1 - (np.abs(yy - lineY) - 7) / 1.5, 0, 1) * (np.clip((xx - W * 0.12) / 40, 0, 1) * np.clip((W * 0.88 - xx) / 40, 0, 1))
img = img * (1 - band[..., None]) + RED * band[..., None]
img += RED * np.exp(-np.abs(yy - lineY) / 90)[..., None] * 0.10
for k in range(4):
    px, py = W * 0.88 - k * 46 - 8, lineY + 78
    dd = np.sqrt((xx - px) ** 2 + (yy - py) ** 2)
    pip = np.clip(13 - dd, 0, 1)
    ring = np.clip(1 - np.abs(dd - 13), 0, 1) * 0.6
    img = img * (1 - pip[..., None]) + GOLD * pip[..., None] * 0.95 + GOLD * ring[..., None] * 0.4
save(img, "4-make-it-so.webp")
