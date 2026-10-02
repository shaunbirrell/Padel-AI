"""claude-bud JOB 29: runs the REAL RetentionService.ComputeOffline (extracted from the service source) in the Luau CLI
against the brief's cases, with MinSeconds from EconomyConfig.OfflineEarnings and the cap + rate from the REAL
OfflineConfig module (Code Bot, Shaun 2026-10-01: min(away, 7200) x income/s x 0.10; was Share 0.25 / 8 h / Premium +10 %):
  first join (no LastSeen) = 0, negative time = 0, under MinSeconds = 0, +2 h, +20 h (capped at 2 h), Shaun's example.
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
OFC = (ROOT / "src/ReplicatedStorage/Shared/Configs/OfflineConfig.luau").read_text(encoding="utf-8")

m = re.search(r"^function RetentionService\.ComputeOffline\(.*?^end$", SRC, re.S | re.M)
if not m:
    print("FAIL: ComputeOffline not found")
    sys.exit(1)
fn = m.group(0).replace("function RetentionService.ComputeOffline", "local function ComputeOffline")
block = re.search(r"OfflineEarnings = \{(.*?)\n\t\},", ECO, re.S).group(1)


def num(key, text=None):
    v = re.search(r"\b" + key + r" = ([\d.* ]+)", text if text is not None else block).group(1)
    return eval(v)  # config literals like 8 * 3600


cfg = {"MinSeconds": num("MinSeconds"), "Share": num("Rate", OFC), "CapSeconds": num("MaxSeconds", OFC),
       "PremiumBonus": num("PremiumBonus", OFC)}
assert cfg["CapSeconds"] == 7200 and cfg["Share"] == 0.10, cfg
now = 1_800_000_000
per = 12.0  # $/s of passive income (e.g. $60 per 5 s tick)
cases = [
    ("first join (no LastSeen)", 0, now, per, 1, 0),
    ("negative time (clock skew)", now + 500, now, per, 1, 0),
    ("under MinSeconds", now - int(cfg["MinSeconds"]) + 1, now, per, 1, 0),
    ("+2 h", now - 7200, now, per, 1, int(per * 7200 * cfg["Share"])),
    ("+20 h (capped at 2 h)", now - 72000, now, per, 1, int(per * cfg["CapSeconds"] * cfg["Share"])),
    ("+2 h Premium", now - 7200, now, per, 1 + cfg["PremiumBonus"], int(per * 7200 * cfg["Share"] * (1 + cfg["PremiumBonus"]))),
    ("no income", now - 7200, now, 0, 1, 0),
    # claude-bud JOB 49 B: the brief's edges
    ("4 min (under MinSeconds)", now - 240, now, per, 1, 0),
    ("exactly the cap", now - int(cfg["CapSeconds"]), now, per, 1, int(per * cfg["CapSeconds"] * cfg["Share"])),
    ("30 h (capped)", now - 30 * 3600, now, per, 1, int(per * cfg["CapSeconds"] * cfg["Share"])),
    # Code Bot (Shaun): $1M earned in 2 h of play -> $100k while away; 16 h at $349,376/s -> 7200 x 349,376 x 0.10
    ("Shaun: $1M per 2 h, away 2 h", now - 7200, now, 1_000_000 / 7200, 1, 100_000),
    ("Shaun: $1M per 2 h, away 16 h", now - 16 * 3600, now, 1_000_000 / 7200, 1, 100_000),
    ("$349,376/s away 16 h", now - 16 * 3600, now, 349_376, 1, 251_550_720),
]
ofc_mod = "local OfflineConfig = (function()\n" + OFC.replace("--!strict", "") + "\nend)()"
lua = [ofc_mod, fn, "local o = { CapSeconds = %s, MinSeconds = %s }" % (cfg["CapSeconds"], cfg["MinSeconds"]), "local fails = 0"]
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
