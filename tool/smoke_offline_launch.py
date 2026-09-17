"""Quick offline launch smoke: drain-safe + custom API hosts."""
from __future__ import annotations

import subprocess
import time
from pathlib import Path

java = Path(r"C:\xingqiong\runtimes\java\jdk-17\bin\java.exe")
game = Path(r"C:\xingqiong\game")
src = game / ".xingqiong_launch.args"
lines = src.read_text(encoding="utf-8").splitlines()

# Insert offline fail-fast props after launcher.version if missing
insert_after = "-Dminecraft.launcher.version=0.1.0"
extra = [
    "-Dsun.net.client.defaultConnectTimeout=2000",
    "-Dsun.net.client.defaultReadTimeout=2000",
    "-Djava.net.preferIPv4Stack=true",
    "-Dminecraft.api.env=custom",
    "-Dminecraft.api.auth.host=http://127.0.0.1:9",
    "-Dminecraft.api.account.host=http://127.0.0.1:9",
    "-Dminecraft.api.session.host=http://127.0.0.1:9",
    "-Dminecraft.api.services.host=http://127.0.0.1:9",
]
out: list[str] = []
done = False
for line in lines:
    if line.startswith("-XX:+AlwaysPreTouch"):
        continue
    out.append(line)
    if (not done) and line.strip() == insert_after:
        out.extend(extra)
        done = True
if not done:
    # put after first -Xmx
    out2 = []
    for line in out:
        out2.append(line)
        if line.startswith("-Xmx") and extra[0] not in out2:
            out2.extend(extra)
    out = out2

arg = Path(r"C:\Users\梦\AppData\Local\Temp\xq_offline_smoke.args")
arg.write_text("\n".join(out) + "\n", encoding="utf-8")
print("wrote", arg)

# DETACHED-ish: DEVNULL so pipes don't block
p = subprocess.Popen(
    [str(java), f"@{arg}"],
    cwd=str(game),
    stdout=subprocess.DEVNULL,
    stderr=subprocess.DEVNULL,
)
print("pid", p.pid)
latest = game / "logs" / "latest.log"
t0 = time.time()
last_size = -1
while time.time() - t0 < 90:
    if p.poll() is not None:
        print("exited early", p.returncode, "after", round(time.time() - t0, 1), "s")
        break
    if latest.exists():
        sz = latest.stat().st_size
        if sz != last_size:
            last_size = sz
            text = latest.read_text(encoding="utf-8", errors="replace")
            tail = text[-500:].replace("\n", " | ")
            print(f"+{round(time.time()-t0,1)}s log={sz} {tail[-200:]}")
            if "LWJGL" in text or "Reloading ResourceManager" in text or "Setting user" in text:
                print("PROGRESS_OK window stage likely reached")
                time.sleep(8)
                break
    time.sleep(1)
else:
    print("TIMEOUT still running")
print("poll", p.poll())
# leave running a bit for user? kill to be clean
if p.poll() is None:
    p.terminate()
    try:
        p.wait(timeout=5)
    except Exception:
        p.kill()
    print("terminated smoke process")
