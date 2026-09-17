"""Generate 32x32 white-on-transparent waypoint PNGs.

Shapes follow Phosphor Icons (MIT) silhouettes used as reference;
original SVGs are stored beside PNGs under icons/svg/ with LICENSE.
"""
from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw

DEST = Path(
    r"i:\menghuan\frontend\tool\xingqiong_hud_bridge\src\main\resources"
    r"\assets\xingqiong-perf\textures\gui\icons"
)
SIZE = 32


def blank() -> tuple[Image.Image, ImageDraw.ImageDraw]:
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    return img, ImageDraw.Draw(img)


def save(name: str, img: Image.Image) -> None:
    DEST.mkdir(parents=True, exist_ok=True)
    path = DEST / f"{name}.png"
    img.save(path)
    print(name, path.stat().st_size)


def home() -> None:
    img, d = blank()
    # roof triangle + body
    d.polygon([(16, 4), (28, 14), (4, 14)], fill=(255, 255, 255, 255))
    d.rectangle([7, 14, 25, 28], fill=(255, 255, 255, 255))
    d.rectangle([13, 18, 19, 28], fill=(0, 0, 0, 0))
    save("home", img)


def mine() -> None:
    img, d = blank()
    # hammer: handle + head
    d.rectangle([14, 10, 18, 28], fill=(255, 255, 255, 255))
    d.polygon([(6, 8), (26, 8), (24, 14), (8, 14)], fill=(255, 255, 255, 255))
    d.rectangle([8, 6, 24, 10], fill=(255, 255, 255, 255))
    save("mine", img)


def boss() -> None:
    img, d = blank()
    # crown
    d.polygon([(4, 22), (4, 10), (10, 16), (16, 6), (22, 16), (28, 10), (28, 22)], fill=(255, 255, 255, 255))
    d.rectangle([4, 20, 28, 26], fill=(255, 255, 255, 255))
    save("boss", img)


def danger() -> None:
    img, d = blank()
    d.polygon([(16, 3), (30, 28), (2, 28)], fill=(255, 255, 255, 255))
    d.rectangle([14, 12, 18, 20], fill=(0, 0, 0, 0))
    d.ellipse([14, 22, 18, 26], fill=(0, 0, 0, 0))
    save("danger", img)


def quest() -> None:
    img, d = blank()
    d.rounded_rectangle([6, 4, 26, 28], radius=3, fill=(255, 255, 255, 255))
    d.rectangle([10, 10, 22, 12], fill=(0, 0, 0, 0))
    d.rectangle([10, 15, 20, 17], fill=(0, 0, 0, 0))
    d.rectangle([10, 20, 18, 22], fill=(0, 0, 0, 0))
    save("quest", img)


def bed() -> None:
    img, d = blank()
    d.rectangle([4, 14, 28, 24], fill=(255, 255, 255, 255))
    d.rectangle([4, 10, 12, 16], fill=(255, 255, 255, 255))
    d.rectangle([5, 24, 8, 28], fill=(255, 255, 255, 255))
    d.rectangle([24, 24, 27, 28], fill=(255, 255, 255, 255))
    save("bed", img)


def skull() -> None:
    img, d = blank()
    d.ellipse([5, 4, 27, 24], fill=(255, 255, 255, 255))
    d.rectangle([10, 20, 22, 28], fill=(255, 255, 255, 255))
    d.ellipse([9, 11, 14, 16], fill=(0, 0, 0, 0))
    d.ellipse([18, 11, 23, 16], fill=(0, 0, 0, 0))
    d.rectangle([14, 24, 16, 28], fill=(0, 0, 0, 0))
    d.rectangle([17, 24, 19, 28], fill=(0, 0, 0, 0))
    save("skull", img)


def flag() -> None:
    img, d = blank()
    d.rectangle([7, 4, 10, 28], fill=(255, 255, 255, 255))
    d.polygon([(10, 5), (26, 10), (10, 16)], fill=(255, 255, 255, 255))
    save("flag", img)


if __name__ == "__main__":
    home()
    mine()
    boss()
    danger()
    quest()
    bed()
    skull()
    flag()
