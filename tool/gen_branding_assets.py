"""Generate branded icons for Inno Setup wizard + multi-platform app icons from logo.png."""
from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(r"i:\menghuan\frontend")
LOGO = ROOT / "assets" / "images" / "logo.png"
OUT = ROOT / "installer" / "branding"
OUT.mkdir(parents=True, exist_ok=True)


def load_logo() -> Image.Image:
    im = Image.open(LOGO).convert("RGBA")
    return im


def fit_square(im: Image.Image, size: int, bg=(12, 10, 28, 255)) -> Image.Image:
    canvas = Image.new("RGBA", (size, size), bg)
    # cover fit
    scale = max(size / im.width, size / im.height)
    nw, nh = int(im.width * scale), int(im.height * scale)
    resized = im.resize((nw, nh), Image.Resampling.LANCZOS)
    x = (size - nw) // 2
    y = (size - nh) // 2
    canvas.paste(resized, (x, y), resized)
    return canvas


def wizard_side(im: Image.Image) -> None:
    # Classic Inno: 164x314 BMP
    w, h = 164, 314
    canvas = Image.new("RGB", (w, h), (10, 12, 28))
    # top brand area
    icon = fit_square(im, 120, (10, 12, 28, 255)).convert("RGBA")
    canvas.paste(icon, (22, 40), icon)
    # accent bar
    draw = ImageDraw.Draw(canvas)
    draw.rectangle([0, 0, w, 8], fill=(120, 80, 220))
    draw.rectangle([0, h - 48, w, h], fill=(20, 24, 48))
    # soft glow strip
    glow = Image.new("RGBA", (w, 60), (80, 60, 180, 40))
    canvas.paste(Image.alpha_composite(canvas.convert("RGBA"), Image.new("RGBA", (w, h), (0, 0, 0, 0))), (0, 0))
    canvas.save(OUT / "wizard_image.bmp", format="BMP")
    print("wizard_image.bmp")


def wizard_small(im: Image.Image) -> None:
    # 55x55 BMP
    icon = fit_square(im, 55).convert("RGB")
    icon.save(OUT / "wizard_small.bmp", format="BMP")
    print("wizard_small.bmp")


def setup_ico(im: Image.Image) -> None:
    sizes = [16, 32, 48, 64, 128, 256]
    icons = [fit_square(im, s).convert("RGBA") for s in sizes]
    icons[0].save(
        OUT / "setup.ico",
        format="ICO",
        sizes=[(s, s) for s in sizes],
        append_images=icons[1:],
    )
    # also refresh windows runner icon
    dest = ROOT / "windows" / "runner" / "resources" / "app_icon.ico"
    icons[0].save(
        dest,
        format="ICO",
        sizes=[(s, s) for s in sizes],
        append_images=icons[1:],
    )
    print("setup.ico + app_icon.ico")


def png_set(im: Image.Image) -> None:
    for s in (48, 96, 192, 512, 1024):
        fit_square(im, s).save(OUT / f"app_icon_{s}.png")
    print("png set")


def android_mipmaps(im: Image.Image) -> None:
    # Will be used after flutter create android
    mapping = {
        "mipmap-mdpi": 48,
        "mipmap-hdpi": 72,
        "mipmap-xhdpi": 96,
        "mipmap-xxhdpi": 144,
        "mipmap-xxxhdpi": 192,
    }
    base = OUT / "android_mipmaps"
    for folder, size in mapping.items():
        d = base / folder
        d.mkdir(parents=True, exist_ok=True)
        fit_square(im, size).save(d / "ic_launcher.png")
    print("android_mipmaps")


def main() -> None:
    im = load_logo()
    wizard_side(im)
    wizard_small(im)
    setup_ico(im)
    png_set(im)
    android_mipmaps(im)


if __name__ == "__main__":
    main()
