"""Rasterize Phosphor (MIT) SVGs to 32x32 white PNGs for Minecraft textures."""
from __future__ import annotations

import re
import sys
from pathlib import Path

from reportlab.graphics import renderPM
from svglib.svglib import svg2rlg

TMP = Path(sys.argv[1]) if len(sys.argv) > 1 else Path.home() / "AppData/Local/Temp/phosphor_xq"
DEST = Path(sys.argv[2]) if len(sys.argv) > 2 else Path(
    r"i:\menghuan\frontend\tool\xingqiong_hud_bridge\src\main\resources"
    r"\assets\xingqiong-perf\textures\gui\icons"
)

MAPPING = {
    "home": "home.svg",
    "mine": "mine.svg",
    "boss": "boss.svg",
    "danger": "danger.svg",
    "quest": "quest.svg",
    "bed": "bed.svg",
    "skull": "skull.svg",
    "flag": "flag.svg",
}


def main() -> None:
    DEST.mkdir(parents=True, exist_ok=True)
    for key, fn in MAPPING.items():
        src = TMP / fn
        if not src.exists():
            print("missing", src)
            continue
        text = src.read_text(encoding="utf-8")
        if "fill=" not in text:
            text = text.replace("<svg", '<svg fill="#FFFFFF"', 1)
        text = re.sub(r'fill="(?!none)[^"]*"', 'fill="#FFFFFF"', text)
        work = TMP / f"{key}_w.svg"
        work.write_text(text, encoding="utf-8")
        drawing = svg2rlg(str(work))
        if drawing is None:
            print("fail parse", key)
            continue
        sx = 32.0 / drawing.width if drawing.width else 1.0
        sy = 32.0 / drawing.height if drawing.height else 1.0
        drawing.width = 32
        drawing.height = 32
        drawing.scale(sx, sy)
        out = DEST / f"{key}.png"
        renderPM.drawToFile(drawing, str(out), fmt="PNG", dpi=72)
        print(key, out.stat().st_size)


if __name__ == "__main__":
    main()
