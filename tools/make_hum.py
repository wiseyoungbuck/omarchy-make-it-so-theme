"""Original warp-core-style ambient hum. Frequency-domain synthesis => perfect loop."""
import sys, wave
import numpy as np
SR, SEC = 48000, 120
N = SR * SEC
rng = np.random.default_rng(1701)
f = np.fft.rfftfreq(N, 1 / SR)
f[0] = 1
# deep brown-ish rumble: 1/f^2 power, rolled off above ~180 Hz, cut below 20 Hz
mag = 1 / f ** 0.95
mag *= 1 / (1 + (f / 180) ** 4)
mag *= 1 / (1 + (25 / f) ** 6)
# soft resonant bodies of the "engine room": narrow humps, gently wavering
for c, w, g in [(42, 3, 6), (84, 4, 3), (126, 6, 1.4), (300, 40, 0.5)]:
    mag *= 1 + g * np.exp(-((f - c) / w) ** 2)
spec = mag * np.exp(1j * rng.uniform(0, 2 * np.pi, f.size))
spec[0] = 0
x = np.fft.irfft(spec, N)
x /= np.abs(x).max()
t = np.arange(N) / SR
# slow breathing (whole cycles per loop so it stays seamless)
x *= 0.85 + 0.15 * np.sin(2 * np.pi * (3 / SEC) * t)
# a very faint airy hiss on top, the "space" part of the noise
air = np.fft.irfft(np.exp(1j * rng.uniform(0, 2 * np.pi, f.size)) / (1 + (f / 2500) ** 2) * (f > 400), N)
x += 0.012 * air / np.abs(air).max()
x = x / np.abs(x).max() * 0.6
stereo = np.stack([x, np.roll(x, SR // 50)], 1)  # slight width
with wave.open(sys.argv[1], "wb") as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes((stereo * 32767).astype("<i2").tobytes())
