"""从 assets/images/logo.png 生成 Windows 多尺寸 app_icon.ico。"""
from __future__ import annotations

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "assets" / "images" / "logo.png"
DST = ROOT / "windows" / "runner" / "resources" / "app_icon.ico"
PREVIEW = ROOT / "windows" / "runner" / "resources" / "app_icon_preview_256.png"
SIZES = [(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]


def main() -> None:
    src = Image.open(SRC).convert("RGBA")
    # 居中裁成正方形，避免非方 logo 被拉伸变形
    w, h = src.size
    side = min(w, h)
    left = (w - side) // 2
    top = (h - side) // 2
    square = src.crop((left, top, left + side, top + side))

    images = [
        square.resize(size, Image.Resampling.LANCZOS) for size in SIZES
    ]
    # Pillow：以最大帧为主图，append_images 附带其余尺寸
    images[-1].save(
        DST,
        format="ICO",
        sizes=SIZES,
        append_images=images[:-1],
    )
    images[-1].save(PREVIEW, format="PNG")
    print(f"wrote {DST} ({DST.stat().st_size} bytes)")
    print(f"preview {PREVIEW}")

    # 校验可读帧
    check = Image.open(DST)
    n = getattr(check, "n_frames", 1)
    print(f"ico frames={n}")
    for i in range(n):
        check.seek(i)
        print(f"  {check.size} {check.mode}")


if __name__ == "__main__":
    main()
