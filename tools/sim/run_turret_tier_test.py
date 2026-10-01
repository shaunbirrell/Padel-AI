"""claude-bud JOB 67 (1): the turret tier by Turret Guns level, on the REAL VisualAssetConfig.TurretTierFor (stand-ins:
run_kit_detail_test.PRELUDE). 0 = T1, 1-3 = T2, 4-6 = T3, 7-9 = T4, 10 = T5; every tier key is promoted (Code Bot v200) to its pack level with a rising size."""
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
-- Code Bot v200: promoted after WE_CHECK2 (docs/we_check2_minigun_v200.txt): pack Lvl 1 / 3 / 5 / 8 / 10, Yaw 180 +
-- AimHitbox (the pack's barrels point +Z), LongAxisStuds growing per tier (each tier bigger than the last, all 4..7.5)
local keysOk, lastLong = true, 0
local child = { "minigun_l01", "minigun_l03", "minigun_l05", "minigun_l08", "minigun_l10" }
for i, k in ipairs(VA.Job67.TurretTierKeys) do
	local r = VA.GateDefense[k]
	if r == nil or r.ModelAssetId ~= 109072907337393 or r.PendingAssetId ~= nil or r.ChildName ~= child[i] or r.Yaw ~= 180
		or r.AimHitbox ~= true or typeof(r.LongAxisStuds) ~= "number" or r.LongAxisStuds <= lastLong or r.LongAxisStuds < 4 or r.LongAxisStuds > 7.5 then
		keysOk = false
	end
	lastLong = if r and typeof(r.LongAxisStuds) == "number" then r.LongAxisStuds else 99
end
check(keysOk and #VA.Job67.TurretTierKeys == 5, "5 tier keys promoted: Lvl 1/3/5/8/10, Yaw 180, AimHitbox, LongAxisStuds rising")
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
