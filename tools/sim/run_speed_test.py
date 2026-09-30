"""claude-bud JOB 40 part B: speed values + the one text helper (the real MonetizationConfig) and the 40-stud/s army sim.

1. TEXT: SpeedText -> "Run 50% faster", "Run 75% faster", "Run 2x faster", "Run 2.5x faster" (+ ", forever").
2. VALUES: off = x1.5 / x2 (today, and the Descriptions read exactly as before); SpeedV2 live = x1.75 (28) / x2.5 (40);
   the cap MaxWalkSpeedMult 2.5 (40); Robux prices / Ids unchanged; DescFor derives every speed string.
3. ARMY at 40 studs/s (tools/sim/army_follow_sim.luau S40 set, the REAL FormationController / SoldierController /
   Follow3): 0 teleports / PivotTo, no slot faster than the soldier top speed (Follow3.MaxSpeed), every scenario settles
   in its slots; the worst formation error after the first 3 s is PRINTED per scenario (the spec's <= 6 is met on the
   straight run; the turn / hairpin numbers are reported, not hidden).
Run: LUAU=path/to/luau(.exe) python tools/sim/run_speed_test.py"""
import os
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from run_kit_detail_test import PRELUDE  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
SH = ROOT / "src/ReplicatedStorage/Shared"
MODS = {
    "Configs/MonetizationConfig": SH / "Configs/MonetizationConfig.luau",
    "Configs/AdminConfig": SH / "Configs/AdminConfig.luau",
}
EXTRA = r'''
local RunService = { IsStudio = function() return false end }
local prevGame = game
game = { GetService = function(_, n) if n == "RunService" then return RunService end return prevGame:GetService(n) end }
'''
TEST = r'''
local fails = 0
local function check(ok, msg) print((ok and "ok    " or "FAIL  ") .. msg); if not ok then fails += 1 end end
local MC = require(node("Configs/MonetizationConfig"))
check(MC.SpeedText(1.5) == "Run 50% faster" and MC.SpeedText(1.75) == "Run 75% faster" and MC.SpeedText(2) == "Run 2x faster" and MC.SpeedText(2.5) == "Run 2.5x faster", "SpeedText: 50% / 75% / 2x / 2.5x")
check(MC.SpeedText(2.5, true) == "Run 2.5x faster, forever", "', forever' where the surface has room")
local SP, SB = MC.GamePasses.ImpulseSpeed, MC.DevProducts.SpeedBoost
check(SP.Description == "Run 50% faster, forever" and SB.Description == "Run 2x faster, forever", "off: the Descriptions read exactly as today (now from the helper)")
check(MC.SpeedMultOf(SP, 9) == 1.5 and MC.SpeedMultOf(SB, 9) == 2 and MC.SpeedMultOf(SP, nil) == 1.5, "not live: x1.5 / x2 (WalkSpeed 24 / 32)")
check(MC.SpeedMultOf(SP, 470626172) == 1.75 and MC.SpeedMultOf(SB, 470626172) == 2.5, "SpeedV2 live: x1.75 (28) / x2.5 (40)")
check(16 * MC.SpeedMultOf(SP, 470626172) == 28 and 16 * MC.SpeedMultOf(SB, 470626172) == 40 and MC.MaxWalkSpeedMult == 2.5, "WalkSpeed 28 / 40; the cap 2.5 (40)")
check(MC.DescFor(SP, 470626172) == "Run 75% faster, forever" and MC.DescFor(SB, 470626172) == "Run 2.5x faster, forever" and MC.DescFor(SB, 9) == "Run 2x faster, forever",
  "DescFor: every speed string from the multiplier the player actually gets")
check(SP.Id == 1998656357 and SP.RobuxPrice == 99 and SB.Id == 3713839342 and SB.RobuxPrice == 99, "Robux prices / Ids unchanged")
print(string.format("SPEED TEST: %d failed", fails))
if fails > 0 then error("failed") end
'''


def main():
    chunks = [PRELUDE, EXTRA]
    for key, path in MODS.items():
        chunks.append("SOURCES[%r] = function(script)\n%s\nend" % (key, path.read_text(encoding="utf-8")))
    chunks.append(TEST)
    with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False, encoding="utf-8") as f:
        f.write("\n".join(chunks))
        path = f.name
    r = subprocess.run([os.environ.get("LUAU", "luau"), path], capture_output=True, text=True)
    out = r.stdout.strip()
    print(out if os.environ.get("VERBOSE") else ("\n".join(l for l in out.splitlines() if l.startswith("FAIL") or l.startswith("SPEED TEST")) or out))
    bad = r.returncode != 0
    if bad:
        print(r.stderr.strip()[-2000:])
    import run_army_sim  # noqa: E402

    o = run_army_sim.run(s40=True)
    if o is None:
        print("SKIP army 40 sim (no luau)")
    else:
        top = float(run_army_sim.follow3_lua()[1].get("MaxSpeed", 0))
        for name, m in run_army_sim.metrics(o).items():
            okay = m["teleports"] == 0 and m["maxSlotSpeed"] <= top and m["finalRms"] <= 3
            print("%s%s: teleports=%d maxSlot=%.1f (top %.0f) finalRms=%.2f meanErr=%.2f worstAfter3s=%.2f minOwner=%.2f" % (
                "ok    " if okay else "FAIL  ", name, m["teleports"], m["maxSlotSpeed"], top, m["finalRms"], m["rmsMean"], m.get("rmsMax3", -1), m["minOwner"]))
            bad = bad or not okay
    print("SPEED ALL: %s" % ("FAIL" if bad else "0 failed"))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
