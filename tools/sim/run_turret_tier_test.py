"""claude-bud JOB 67 (1): the turret tier by Turret Guns level, on the REAL VisualAssetConfig.TurretTierFor (stand-ins:
run_kit_detail_test.PRELUDE). 0 = T1, 1-3 = T2, 4-6 = T3, 7-9 = T4, 10 = T5; every tier key exists and is PENDING (0)."""
import os
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from run_kit_detail_test import PRELUDE  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
SH = ROOT / "src/ReplicatedStorage/Shared"
TEST = r'''
local fails = 0
local function check(ok, msg) print((ok and "ok    " or "FAIL  ") .. msg); if not ok then fails += 1 end end
local VA = require(node("Configs/VisualAssetConfig"))
local want = { [0] = 1, 2, 2, 2, 3, 3, 3, 4, 4, 4, 5 }
local got, okAll = {}, true
for l = 0, 10 do got[l + 1] = VA.TurretTierFor(l); if VA.TurretTierFor(l) ~= want[l] then okAll = false end end
check(okAll, "Guns level 0..10 -> tier " .. table.concat(got, ","))
local keysOk = true
for _, k in ipairs(VA.Job67.TurretTierKeys) do local r = VA.GateDefense[k]; if r == nil or r.ModelAssetId ~= 0 or r.PendingAssetId ~= 109072907337393 then keysOk = false end end
check(keysOk and #VA.Job67.TurretTierKeys == 5, "5 tier keys, all PENDING until promoted (today's gun meanwhile)")
print(string.format("TURRET TIER LUA: %d failed", fails))
if fails > 0 then error("failed") end
'''


def main():
    src = (SH / "Configs/VisualAssetConfig.luau").read_text(encoding="utf-8")
    chunks = [PRELUDE, "SOURCES['Configs/VisualAssetConfig'] = function(script)\n%s\nend" % src, TEST]
    with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False, encoding="utf-8") as f:
        f.write("\n".join(chunks))
        path = f.name
    r = subprocess.run([os.environ.get("LUAU", "luau"), path], capture_output=True, text=True, timeout=100)
    fails = 0 if (r.returncode == 0 and "TURRET TIER LUA: 0 failed" in r.stdout) else 1
    print(r.stdout.strip() if os.environ.get("VERBOSE") or fails else "")
    if fails:
        print(r.stderr[-1500:])
    print("TURRET TIER TEST: %d failed" % fails)
    sys.exit(fails)


if __name__ == "__main__":
    main()
