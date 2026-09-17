"""Verify whether .xingqiong_launch.args classpath quoting breaks Java."""
from __future__ import annotations

import subprocess
import tempfile
from pathlib import Path

java = Path(r"C:\xingqiong\runtimes\java\jdk-17\bin\java.exe")
game = Path(r"C:\xingqiong\game")
arg_existing = game / ".xingqiong_launch.args"


def run_argfile(path: Path, timeout: float = 25) -> str:
    r = subprocess.run(
        [str(java), f"@{path}"],
        cwd=str(game),
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=timeout,
    )
    return f"exit={r.returncode}\n{(r.stdout or '') + (r.stderr or '')}"


print("=== existing launcher argfile ===")
print(run_argfile(arg_existing)[:1500])

# Rebuild: same args but -cp value NOT quoted (fix backslash quote rule)
lines = arg_existing.read_text(encoding="utf-8").splitlines()
out = []
i = 0
while i < len(lines):
    line = lines[i]
    if line == "-cp" and i + 1 < len(lines):
        out.append("-cp")
        cp = lines[i + 1]
        if cp.startswith('"') and cp.endswith('"'):
            # unescape \" and \\
            inner = cp[1:-1].replace(r"\"", '"').replace(r"\\", "\\")
            out.append(inner)  # unquoted classpath
            i += 2
            continue
    out.append(line)
    i += 1

fixed = Path(tempfile.gettempdir()) / "xq_arg_fixed.args"
fixed.write_text("\n".join(out) + "\n", encoding="utf-8")
print("\n=== fixed unquoted -cp ===")
print(run_argfile(fixed)[:1500])

# Also test: classpath with only / separators, unquoted
cp_line = None
for idx, line in enumerate(lines):
    if line == "-cp":
        cp_line = lines[idx + 1]
        break
assert cp_line
inner = cp_line[1:-1].replace(r"\"", '"').replace(r"\\", "\\")
inner_fwd = inner.replace("\\", "/")
out2 = []
i = 0
while i < len(lines):
    if lines[i] == "-cp":
        out2.append("-cp")
        out2.append(inner_fwd)
        i += 2
        continue
    out2.append(lines[i])
    i += 1
fixed2 = Path(tempfile.gettempdir()) / "xq_arg_fwd.args"
fixed2.write_text("\n".join(out2) + "\n", encoding="utf-8")
print("\n=== forward-slash unquoted -cp ===")
print(run_argfile(fixed2)[:1500])
