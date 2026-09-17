"""Fix ICO + richer Inno wizard BMPs from logo.png."""
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(r"i:\menghuan\frontend")
LOGO = ROOT / "assets" / "images" / "logo.png"
OUT = ROOT / "installer" / "branding"
OUT.mkdir(parents=True, exist_ok=True)
im = Image.open(LOGO).convert("RGBA")


def fit_square(src: Image.Image, size: int, bg=(12, 10, 28, 255)) -> Image.Image:
    canvas = Image.new("RGBA", (size, size), bg)
    scale = max(size / src.width, size / src.height)
    nw, nh = int(src.width * scale), int(src.height * scale)
    resized = src.resize((nw, nh), Image.Resampling.LANCZOS)
    canvas.paste(resized, ((size - nw) // 2, (size - nh) // 2), resized)
    return canvas


sizes = [16, 32, 48, 64, 128, 256]
imgs = [fit_square(im, s) for s in sizes]
for path in (OUT / "setup.ico", ROOT / "windows" / "runner" / "resources" / "app_icon.ico"):
    imgs[-1].save(
        path,
        format="ICO",
        sizes=[(s, s) for s in sizes],
        append_images=imgs[:-1],
    )
    print(path.name, path.stat().st_size)

w, h = 164, 314
canvas = Image.new("RGB", (w, h), (8, 10, 26))
pixels = canvas.load()
for y in range(h):
    t = y / h
    r = int(8 + 40 * (1 - t))
    g = int(10 + 20 * (1 - t))
    b = int(26 + 60 * t)
    for x in range(w):
        pixels[x, y] = (r, g, b)
icon = fit_square(im, 128).convert("RGBA")
canvas.paste(icon, ((w - 128) // 2, 70), icon)
d = ImageDraw.Draw(canvas)
d.rectangle([0, 0, w, 6], fill=(140, 90, 255))
d.rectangle([0, h - 56, w, h], fill=(6, 8, 20))
canvas.save(OUT / "wizard_image.bmp")
fit_square(im, 55).convert("RGB").save(OUT / "wizard_small.bmp")
print("wizard bmps", (OUT / "wizard_image.bmp").stat().st_size)
