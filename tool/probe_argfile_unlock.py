"""Patch existing argfile: unlock experimental + unquote -cp, then smoke-run."""
from __future__ import annotations

import subprocess
import tempfile
from pathlib import Path

java = Path(r"C:\xingqiong\runtimes\java\jdk-17\bin\java.exe")
game = Path(r"C:\xingqiong\game")
src = game / ".xingqiong_launch.args"
lines = src.read_text(encoding="utf-8").splitlines()

out: list[str] = []
i = 0
inserted = False
while i < len(lines):
    line = lines[i]
    if (
        not inserted
        and line.startswith("-XX:G1NewSizePercent")
    ):
        out.append("-XX:+UnlockExperimentalVMOptions")
        inserted = True
    if line == "-cp" and i + 1 < len(lines):
        out.append("-cp")
        cp = lines[i + 1]
        if cp.startswith('"') and cp.endswith('"'):
            cp = cp[1:-1].replace(r"\"", '"').replace(r"\\", "\\")
        out.append(cp)
        i += 2
        continue
    # Also unquote -Djava.library.path etc if only backslashes caused quotes
    if line.startswith('"') and line.endswith('"') and " " not in line[1:-1]:
        inner = line[1:-1].replace(r"\"", '"').replace(r"\\", "\\")
        out.append(inner)
        i += 1
        continue
    out.append(line)
    i += 1

fixed = Path(tempfile.gettempdir()) / "xq_arg_unlock.args"
fixed.write_text("\n".join(out) + "\n", encoding="utf-8")
print("wrote", fixed)
print("has unlock", any("UnlockExperimental" in x for x in out))

r = subprocess.run(
    [str(java), f"@{fixed}"],
    cwd=str(game),
    capture_output=True,
    text=True,
    encoding="utf-8",
    errors="replace",
    timeout=45,
)
text = (r.stdout or "") + (r.stderr or "")
print("exit", r.returncode)
print(text[:2000])
