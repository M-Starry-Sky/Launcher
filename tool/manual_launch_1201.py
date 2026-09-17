"""手动按启动器逻辑拉起 1.20.1，捕获 stdout/stderr。"""
from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

# 与启动器默认一致：C:\xingqiong\game（勿用 Temp，会被系统清理）
game = Path(r"C:\xingqiong\game")
if not (game / "versions" / "1.20.1").exists():
    legacy = Path(os.environ["TEMP"]) / "game"
    if (legacy / "versions" / "1.20.1").exists():
        game = legacy
        print("WARN using legacy TEMP game:", game)
ver = game / "versions" / "1.20.1"
meta = json.loads((ver / "1.20.1.json").read_text(encoding="utf-8"))
natives = ver / "natives-windows"
lib_root = game / "libraries"

# find java
java = None
for cand in [
    os.environ.get("JAVA_HOME", "") + r"\bin\java.exe",
    r"C:\Program Files\Eclipse Adoptium",
    r"C:\Program Files\Java",
    r"C:\Program Files\Microsoft",
]:
    p = Path(cand)
    if p.is_file():
        java = str(p)
        break
if java is None:
    # where java
    try:
        out = subprocess.check_output(["where", "java"], text=True, stderr=subprocess.STDOUT)
        for line in out.splitlines():
            if line.strip() and Path(line.strip()).exists():
                java = line.strip()
                break
    except Exception:
        pass
# portable from app support
if java is None:
    local = Path(os.environ["LOCALAPPDATA"])
    for p in local.rglob("java.exe"):
        if "runtimes" in str(p) and "jdk" in str(p):
            java = str(p)
            break

print("java=", java)
if not java:
    sys.exit("no java")

subprocess.run([java, "-version"], check=False)

# classpath: all allowed libs + client jar
os_name = "windows"


def rules_allow(rules):
    if not rules:
        return True
    allowed = False
    for rule in rules:
        action = rule.get("action")
        osmap = rule.get("os") or {}
        name = osmap.get("name")
        if name is None:
            if action == "allow":
                allowed = True
        elif name == os_name:
            allowed = action == "allow"
    return allowed


cps = []
for lib in meta["libraries"]:
    if not rules_allow(lib.get("rules")):
        continue
    art = (lib.get("downloads") or {}).get("artifact") or {}
    path = art.get("path")
    if not path:
        # maven name fallback
        name = lib.get("name", "")
        parts = name.split(":")
        if len(parts) < 3:
            continue
        group, artifact, version = parts[0], parts[1], parts[2]
        classifier = f"-{parts[3]}" if len(parts) > 3 else ""
        path = f"{group.replace('.', '/')}/{artifact}/{version}/{artifact}-{version}{classifier}.jar"
    full = lib_root / path
    if full.exists():
        cps.append(str(full))
    else:
        print("MISSING LIB", path)

client = ver / "1.20.1.jar"
cps.insert(0, str(client))
cp = ";".join(cps)
print("classpath entries", len(cps))
print("natives dlls", len(list(natives.glob("*.dll"))))

# game args strings only
game_args = []
for a in meta["arguments"]["game"]:
    if isinstance(a, str):
        game_args.append(a)

values = {
    "auth_player_name": "Player",
    "version_name": "1.20.1",
    "game_directory": str(game),
    "assets_root": str(game / "assets"),
    "assets_index_name": meta["assetIndex"]["id"],
    "auth_uuid": "00000000-0000-0000-0000-000000000000",
    "auth_access_token": "0",
    "user_type": "msa",
    "version_type": "xingqiong",
    "clientid": "",
    "auth_xuid": "",
    "user_properties": "{}",
}


def subst(s: str) -> str:
    import re

    return re.sub(r"\$\{([^}]+)\}", lambda m: values.get(m.group(1), m.group(0)), s)


game_args = [subst(a) for a in game_args]

main = meta["mainClass"]
args = [
    java,
    "-Xms512M",
    "-Xmx2048M",
    f"-Djava.library.path={natives}",
    f"-Djna.tmpdir={natives}",
    f"-Dorg.lwjgl.system.SharedLibraryExtractPath={natives}",
    f"-Dio.netty.native.workdir={natives}",
    "-cp",
    cp,
    main,
    *game_args,
]

print("launching...")
# write cp to file to avoid command line length? Windows limit ~8191
# Use classpath via env or argfile
argfile = game / "_launch.args"
# Use java @argfile for long classpath
with argfile.open("w", encoding="utf-8") as f:
    f.write(f"-Xms512M\n-Xmx2048M\n")
    f.write(f"-Djava.library.path={natives}\n")
    f.write(f"-Djna.tmpdir={natives}\n")
    f.write(f"-Dorg.lwjgl.system.SharedLibraryExtractPath={natives}\n")
    f.write(f"-Dio.netty.native.workdir={natives}\n")
    f.write(f"-cp\n{cp}\n")
    f.write(f"{main}\n")
    for a in game_args:
        f.write(a + "\n")

proc = subprocess.Popen(
    [java, f"@{argfile}"],
    cwd=str(game),
    stdout=subprocess.PIPE,
    stderr=subprocess.STDOUT,
    text=True,
    encoding="utf-8",
    errors="replace",
)
out_lines = []
try:
    for line in proc.stdout:
        out_lines.append(line.rstrip())
        print(line.rstrip())
        if len(out_lines) > 200:
            break
    proc.wait(timeout=25)
except subprocess.TimeoutExpired:
    proc.kill()
    print("TIMEOUT killed")
print("exit", proc.poll())
log = game / "_manual_launch.log"
log.write_text("\n".join(out_lines), encoding="utf-8")
print("wrote", log)

