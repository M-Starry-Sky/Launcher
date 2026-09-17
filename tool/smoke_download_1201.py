"""按启动器同款镜像规则冒烟下载：清单 → 版本 JSON → client jar → 抽样资产。

用法: python tool/smoke_download_1201.py [version]
默认 version=1.20.1，写入 %TEMP%/xq_smoke_game/
"""
from __future__ import annotations

import hashlib
import json
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

UA = {"User-Agent": "xingqiong-launcher/0.1.0"}
MIRRORS = [
    "https://bmclapi2.bangbang93.com",
    "https://bmclapi.bangbang93.com",
]
OFFICIAL_MANIFEST = (
    "https://piston-meta.mojang.com/mc/game/version_manifest_v2.json"
)


def get_bytes(url: str, timeout: float = 30) -> bytes:
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read()


def get_json(urls: list[str]) -> dict:
    last = None
    for u in urls:
        try:
            data = get_bytes(u)
            print(f"  OK {u}")
            return json.loads(data.decode("utf-8"))
        except Exception as e:
            last = e
            print(f"  FAIL {u}: {e}")
    raise RuntimeError(f"all sources failed: {last}")


def main() -> int:
    version = sys.argv[1] if len(sys.argv) > 1 else "1.20.1"
    root = Path(os.environ["TEMP"]) / "xq_smoke_game"
    ver_dir = root / "versions" / version
    ver_dir.mkdir(parents=True, exist_ok=True)
    print(f"smoke download {version} → {root}")

    print("1) version manifest")
    manifest_urls = [f"{m}/mc/game/version_manifest_v2.json" for m in MIRRORS]
    manifest_urls.append(OFFICIAL_MANIFEST)
    manifest = get_json(manifest_urls)
    entry = next((v for v in manifest["versions"] if v["id"] == version), None)
    if not entry:
        print("version not found")
        return 1

    print("2) version metadata")
    official_meta = entry["url"]
    meta_urls = []
    for m in MIRRORS:
        # HMCL-style: replace mojang host prefix with mirror root
        for prefix in (
            "https://piston-meta.mojang.com",
            "https://launchermeta.mojang.com",
        ):
            if official_meta.startswith(prefix):
                meta_urls.append(m + official_meta[len(prefix) :])
        meta_urls.append(f"{m}/version/{version}/json")
    meta_urls.append(official_meta)
    # dedupe
    seen = set()
    meta_urls = [u for u in meta_urls if not (u in seen or seen.add(u))]
    meta = get_json(meta_urls)
    (ver_dir / f"{version}.json").write_text(
        json.dumps(meta, ensure_ascii=False), encoding="utf-8"
    )

    print("3) client jar")
    client = meta["downloads"]["client"]
    jar = ver_dir / f"{version}.jar"
    if jar.exists() and jar.stat().st_size == client["size"]:
        print(f"  skip existing {jar.stat().st_size} bytes")
    else:
        client_urls = [f"{m}/version/{version}/client" for m in MIRRORS]
        client_urls.append(client["url"])
        last = None
        for u in client_urls:
            try:
                t0 = time.time()
                data = get_bytes(u, timeout=120)
                sha = hashlib.sha1(data).hexdigest()
                if sha != client["sha1"]:
                    raise RuntimeError(f"sha1 {sha} != {client['sha1']}")
                jar.write_bytes(data)
                print(f"  OK {u} ({len(data)} bytes, {time.time()-t0:.1f}s)")
                last = None
                break
            except Exception as e:
                last = e
                print(f"  FAIL {u}: {e}")
        if last is not None and not jar.exists():
            raise RuntimeError(last)

    print("4) sample 32 assets")
    idx_url = meta["assetIndex"]["url"]
    idx_urls = []
    for m in MIRRORS:
        for prefix in (
            "https://piston-meta.mojang.com",
            "https://launchermeta.mojang.com",
        ):
            if idx_url.startswith(prefix):
                idx_urls.append(m + idx_url[len(prefix) :])
    idx_urls.append(idx_url)
    seen = set()
    idx_urls = [u for u in idx_urls if not (u in seen or seen.add(u))]
    index = get_json(idx_urls)
    objects = list(index["objects"].items())[:32]
    ok = fail = 0
    t0 = time.time()
    for _name, info in objects:
        h = info["hash"]
        dest = root / "assets" / "objects" / h[:2] / h
        if dest.exists():
            ok += 1
            continue
        dest.parent.mkdir(parents=True, exist_ok=True)
        urls = [f"{m}/assets/{h[:2]}/{h}" for m in MIRRORS]
        urls.append(f"https://resources.download.minecraft.net/{h[:2]}/{h}")
        done = False
        for u in urls:
            try:
                data = get_bytes(u, timeout=20)
                if hashlib.sha1(data).hexdigest() != h:
                    raise RuntimeError("sha1 mismatch")
                dest.write_bytes(data)
                ok += 1
                done = True
                break
            except Exception:
                continue
        if not done:
            fail += 1
            print(f"  asset fail {h[:8]}")
    print(f"  assets ok={ok} fail={fail} in {time.time()-t0:.1f}s")
    print("SMOKE PASS" if fail == 0 and jar.exists() else "SMOKE FAIL")
    return 0 if fail == 0 and jar.exists() else 2


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as e:
        print("SMOKE ERROR", e)
        raise SystemExit(1)
