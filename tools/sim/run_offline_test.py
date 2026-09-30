"""claude-bud JOB 29: runs the REAL RetentionService.ComputeOffline (extracted from the service source) in the Luau CLI
against the brief's cases, with the numbers from EconomyConfig.OfflineEarnings:
  first join (no LastSeen) = 0, negative time = 0, under MinSeconds = 0, +2 h, +20 h (capped at 8 h), Premium +10 %.
Run: LUAU=path/to/luau(.exe) python tools/sim/run_offline_test.py   (exit 1 on any failure)"""
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SRC = (ROOT / "src/ServerScriptService/Server/Services/RetentionService.luau").read_text(encoding="utf-8")
ECO = (ROOT / "src/ReplicatedStorage/Shared/Configs/EconomyConfig.luau").read_text(encoding="utf-8")

m = re.search(r"^function RetentionService\.ComputeOffline\(.*?^end$", SRC, re.S | re.M)
if not m:
    print("FAIL: ComputeOffline not found")
    sys.exit(1)
fn = m.group(0).replace("function RetentionService.ComputeOffline", "local function ComputeOffline")
block = re.search(r"OfflineEarnings = \{(.*?)\n\t\},", ECO, re.S).group(1)


def num(key):
    v = re.search(r"\b" + key + r" = ([\d.* ]+)", block).group(1)
    return eval(v)  # config literals like 8 * 3600


cfg = {k: num(k) for k in ("Share", "CapSeconds", "MinSeconds", "PremiumBonus")}
now = 1_800_000_000
per = 12.0  # $/s of passive income (e.g. $60 per 5 s tick)
cases = [
    ("first join (no LastSeen)", 0, now, per, 1, 0),
    ("negative time (clock skew)", now + 500, now, per, 1, 0),
    ("under MinSeconds", now - int(cfg["MinSeconds"]) + 1, now, per, 1, 0),
    ("+2 h", now - 7200, now, per, 1, int(per * 7200 * cfg["Share"])),
    ("+20 h (capped at 8 h)", now - 72000, now, per, 1, int(per * cfg["CapSeconds"] * cfg["Share"])),
    ("+2 h Premium", now - 7200, now, per, 1 + cfg["PremiumBonus"], int(per * 7200 * cfg["Share"] * (1 + cfg["PremiumBonus"]))),
    ("no income", now - 7200, now, 0, 1, 0),
]
lua = [fn, "local o = { Share = %s, CapSeconds = %s, MinSeconds = %s }" % (cfg["Share"], cfg["CapSeconds"], cfg["MinSeconds"]), "local fails = 0"]
for name, prev, t, p, mult, want in cases:
    lua.append(
        'do local got, secs = ComputeOffline(%d, %d, %s, %s, o); local ok = got == %d; if not ok then fails += 1 end; '
        'print(string.format("%%s  %%-28s got=%%d want=%%d secs=%%d", ok and "ok  " or "FAIL", %r, got, %d, secs)) end'
        % (prev, t, p, mult, want, name, want)
    )
lua.append('print(string.format("OFFLINE TEST: %d case(s) failed", fails)); if fails > 0 then error("failed") end')
with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False, encoding="utf-8") as f:
    f.write("\n".join(lua).replace("local function ComputeOffline(prevSeen: number, now: number, perSec: number, mult: number, o: any): (number, number)", "local function ComputeOffline(prevSeen, now, perSec, mult, o)"))
    path = f.name
luau = os.environ.get("LUAU", "luau")
r = subprocess.run([luau, path], capture_output=True, text=True)
print(r.stdout.strip())
if r.returncode != 0:
    print(r.stderr.strip())
    sys.exit(1)
