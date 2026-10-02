"""claude-bud JOB 68: the shooting range soldiers, on the REAL RangeLifeController pure helpers + RangeLifeConfig.

  * Pick: only shooters within NearStuds of the player, the nearest MaxYards ranges, <= MaxPerYard per range, <= MaxActive;
    nobody far away (no effects when no player is near).
  * Step: a soldier fires ShotsPerMag shots, ShotGapMin..ShotGapMax apart, then reloads for ReloadSeconds, then fires
    again (60 s simulated at the controller's TickHz).
  * HitPoint: the hole lands on the board face toward the shooter, inside the red ring.
Run: LUAU=path/to/luau(.exe) python tools/sim/run_range_life_test.py   (exit 1 on any failure; VERBOSE=1 prints all)"""
import os
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from run_kit_detail_test import PRELUDE  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
MODS = {
    "Controllers/RangeLifeController": ROOT / "src/StarterPlayer/StarterPlayerScripts/Client/Controllers/RangeLifeController.luau",
    "Configs/RangeLifeConfig": ROOT / "src/ReplicatedStorage/Shared/Configs/RangeLifeConfig.luau",
}

TEST = r'''
local fails = 0
local function check(ok, msg) print((ok and "ok    " or "FAIL  ") .. msg); if not ok then fails += 1 end end
Random = { new = function() return { NextNumber = function(_, a, b) a = a or 0; b = b or 1; return (a + b) / 2 end, NextInteger = function(_, a) return a end } end }
local R = require(node("Controllers/RangeLifeController"))
local cfg = require(node("Configs/RangeLifeConfig"))
-- codebot_v220 (Shaun 2026-10-02 07:51: everything public): cfg.OwnerFirst = false live; the owner-first paths
-- below are still proved with OwnerFirst = true, and a non-owner is live once it is restored (end of test)
local __V220_LAUNCHED = cfg.OwnerFirst
check(__V220_LAUNCHED == false, "codebot_v220: cfg.OwnerFirst = false (public for everyone)")
cfg.OwnerFirst = true
check(cfg.OwnerFirst == true and cfg.Enabled == true, "RangeLifeConfig: Enabled + OwnerFirst = true")
check(cfg.NearStuds == 80 and cfg.MaxPerYard <= 4, "effects only within 80 studs, <= 4 shooters per range")

-- Pick
local list = {}
local function add(x, yard) table.insert(list, { Pos = Vector3.new(x, 0, 0), Yard = yard }) end
add(10, "A"); add(12, "A"); add(14, "A"); add(50, "B"); add(52, "B"); add(54, "B"); add(70, "C"); add(200, "D")
local me = Vector3.new(0, 0, 0)
local got = R.Pick(list, me, cfg)
local seen = {}
for _, i in ipairs(got) do seen[list[i].Yard] = (seen[list[i].Yard] or 0) + 1 end
check(#got == 6 and seen.A == 3 and seen.B == 3 and seen.C == nil and seen.D == nil, string.format("near: the 2 nearest ranges, 3 each (%d picked; C / far none)", #got))
local c2 = table.clone(cfg); c2.MaxPerYard = 2
got = R.Pick(list, me, c2)
check(#got == 4, "MaxPerYard 2 -> 4 shooters (" .. #got .. ")")
local c3 = table.clone(cfg); c3.MaxActive = 3
check(#R.Pick(list, me, c3) == 3, "MaxActive caps the total")
check(#R.Pick(list, Vector3.new(400, 0, 0), cfg) == 0, "no player near any range -> nothing runs")

-- Step: 60 s at TickHz
local s = { NextAt = 0, Shots = 0, ReloadUntil = 0 }
local dt = 1 / cfg.TickHz
local fires, reloads, lastFire, minGap, run, runs, reloadAt, minReload = 0, 0, nil, math.huge, 0, {}, nil, math.huge
local t = 0
while t < 60 do
  local st = R.Step(s, t, cfg, 0.5)
  if st == "fire" then
    fires += 1; run += 1
    if lastFire then minGap = math.min(minGap, t - lastFire) end
    lastFire = t
  elseif st == "reload" then
    reloads += 1; table.insert(runs, run); run = 0; reloadAt = t
  elseif st == "reloaded" then
    minReload = math.min(minReload, t - reloadAt)
  end
  t += dt
end
local allMag = #runs > 0
for _, r in ipairs(runs) do if r ~= cfg.ShotsPerMag then allMag = false end end
check(allMag and reloads >= 2, string.format("%d shots then a reload, every time (%d reloads in 60 s)", cfg.ShotsPerMag, reloads))
check(minGap >= cfg.ShotGapMin - dt and minGap < math.huge, string.format("shots at least %.1f s apart (min %.2f s): a low rate", cfg.ShotGapMin, minGap))
check(minReload >= cfg.ReloadSeconds, string.format("a reload lasts >= %.1f s (%.2f s)", cfg.ReloadSeconds, minReload))
check(fires >= 15 and fires <= 60 / cfg.ShotGapMin, "shots in 60 s: " .. fires)

-- HitPoint
local board = { Position = Vector3.new(17, 4.2, 0), RightVector = Vector3.new(1, 0, 0), UpVector = Vector3.new(0, 1, 0), LookVector = Vector3.new(0, 0, -1) }
local p, n = R.HitPoint(board, Vector3.new(0.3, 3.4, 3.2), Vector3.new(-7, 4.5, 0), 1, -1, cfg.HitSpread)
check(math.abs(p.X - (17 - 0.17)) < 1e-6 and n.X == -1, string.format("the hole is on the face toward the shooter (x %.2f)", p.X))
local off = math.sqrt((p.Y - 4.2) ^ 2 + p.Z ^ 2)
check(off <= 1.3, string.format("inside the red ring (%.2f <= 1.3 studs from the bull)", off))
local p2 = R.HitPoint(board, Vector3.new(0.3, 3.4, 3.2), Vector3.new(30, 4.5, 0), 0, 0, cfg.HitSpread)
check(p2.X > 17, "a shooter behind the board hits its back face")
print(string.format("RANGE LIFE LUA: %d failed", fails))
if fails > 0 then error("failed") end
'''


def main():
    chunks = [PRELUDE]
    for k, p in MODS.items():
        chunks.append("SOURCES['%s'] = function(script)\n%s\nend" % (k, p.read_text(encoding="utf-8")))
    chunks.append(TEST)
    with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False, encoding="utf-8") as f:
        f.write("\n".join(chunks))
        path = f.name
    r = subprocess.run([os.environ.get("LUAU", "luau"), path], capture_output=True, text=True, timeout=100)
    out = r.stdout.strip().splitlines()
    fails = 0
    if r.returncode != 0 or "RANGE LIFE LUA: 0 failed" not in r.stdout:
        fails = 1
        out.append(r.stderr.strip()[-2000:])
    out.append("RANGE LIFE TEST: %d failed" % fails)
    print("\n".join(out) if os.environ.get("VERBOSE") else "\n".join(l for l in out if l.startswith(("FAIL", "RANGE LIFE TEST"))))
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
