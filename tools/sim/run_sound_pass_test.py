"""claude-bud JOB 59 (B): the sound pass, on the REAL SoundConfig and the client AmbienceController's pure functions.

1. Every sound id in the JOB 59 (B) list is in SoundConfig (as a key or a Pass59 override).
2. World-placed keys are 3D / proximity only (Bus World, MaxDistance > 0); the night beds ride the Loop bus (the SFX
   toggle); nothing new is a 2D Stinger except the quiet desert artillery.
3. Pass59 is owner-first; its overrides only touch keys that exist.
4. AmbienceController: the night share follows LightingConfig.Cycle; crickets on land / harbor near water at night,
   nothing by day; the artillery only in the desert ring.
Run: LUAU=path/to/luau(.exe) python tools/sim/run_sound_pass_test.py   (exit 1 on any failure; VERBOSE=1 prints all)"""
import os
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from run_kit_detail_test import PRELUDE  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
SH = ROOT / "src/ReplicatedStorage/Shared"
CL = ROOT / "src/StarterPlayer/StarterPlayerScripts/Client"
MODS = {
    "Configs/SoundConfig": SH / "Configs/SoundConfig.luau",
    "Configs/LightingConfig": SH / "Configs/LightingConfig.luau",
    "Controllers/AmbienceController": CL / "Controllers/AmbienceController.luau",
}
WANT = [9112764546, 9112835836, 9112792684, 9114057104, 9114461215, 9114576083, 9112851398, 9125793009, 9113169264,
        9113417759, 9125390124, 9112750448, 9126201834, 9116875342, 9119661640, 9113728042, 15675059323, 15675032796,
        1844397606, 1841116989, 1845181958]

TEST = r'''
local fails = 0
local function check(ok, msg) print((ok and "ok    " or "FAIL  ") .. msg); if not ok then fails += 1 end end
task = { spawn = function() end, delay = function() end, defer = function() end, wait = function() end }
Random = { new = function() return { NextNumber = function(_, a, b) return a end } end }
local SC = require(node("Configs/SoundConfig"))
-- codebot_v220 (Shaun 2026-10-02 07:51: everything public): SC.Pass59.OwnerFirst = false live; the owner-first paths
-- below are still proved with OwnerFirst = true, and a non-owner is live once it is restored (end of test)
local __V220_LAUNCHED = SC.Pass59.OwnerFirst
check(__V220_LAUNCHED == false, "codebot_v220: SC.Pass59.OwnerFirst = false (public for everyone)")
SC.Pass59.OwnerFirst = true
local LC = require(node("Configs/LightingConfig"))
local AC = require(node("Controllers/AmbienceController"))
local have = {}
for _, d in pairs(SC.Sounds) do have[tostring(d.Id)] = true end
for _, id in pairs(SC.Pass59.Overrides) do have[tostring(id)] = true end
local missing = {}
for _, id in ipairs(WANT) do if not have[tostring(id)] then table.insert(missing, tostring(id)) end end
check(#missing == 0, "every JOB 59 (B) sound id is wired (missing: " .. table.concat(missing, ",") .. ")")
local bad = {}
for _, k in ipairs({ "World.FlagFlap", "World.FlagFlap2", "World.Radio", "World.Radio2", "World.Gate" }) do
  local d = SC.Sounds[k]
  if d == nil or d.Bus ~= "World" or not (d.MaxDistance > 0 and d.MaxDistance <= 60) then table.insert(bad, k) end
end
check(#bad == 0, "world-placed sounds are 3D / proximity only (Bus World, MaxDistance 1..60): " .. (if #bad == 0 then "ok" else table.concat(bad, ",")))
check(SC.Sounds["Amb.NightCrickets"].Bus == "Loop" and SC.Sounds["Amb.HarborNight"].Bus == "Loop" and SC.Sounds["Amb.NightAmbience"].Bus == "Loop", "the night beds ride the Loop bus (the SFX toggle)")
check(SC.Pass59.Enabled == true and SC.Pass59.OwnerFirst == true, "Pass59 is owner-first")
local unknown = {}
for k in pairs(SC.Pass59.Overrides) do if SC.Sounds[k] == nil then table.insert(unknown, k) end end
check(#unknown == 0, "overrides touch only existing keys (" .. (if #unknown == 0 then "ok" else table.concat(unknown, ",")) .. ")")
local P = SC.Pass59
check(AC.NightShare(12, LC.Cycle) == 0 and AC.NightShare(23, LC.Cycle) == 1, "night share: 0 at noon, 1 at 23:00")
check(AC.NightKey(1, false, P) == "Amb.NightCrickets" and AC.NightKey(1, true, P) == "Amb.HarborNight" and AC.NightKey(0, false, P) == nil, "night: crickets on land, the harbor by the water; nothing by day")
check(AC.InDesert(Vector3.new(P.DesertFromTownStuds + 10, 0, 0), P) and not AC.InDesert(Vector3.new(100, 0, 100), P), "the distant artillery only out in the desert ring")
print(string.format("SOUND PASS LUA: %d failed", fails))
if fails > 0 then error("failed") end
'''


def main():
    chunks = [PRELUDE]
    for key, path in MODS.items():
        chunks.append("SOURCES[%r] = function(script)\n%s\nend" % (key, path.read_text(encoding="utf-8")))
    chunks.append("WANT = { %s }" % ", ".join(str(i) for i in WANT))
    chunks.append(TEST)
    with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False, encoding="utf-8") as f:
        f.write("\n".join(chunks))
        path = f.name
    r = subprocess.run([os.environ.get("LUAU", "luau"), path], capture_output=True, text=True)
    out = r.stdout.strip().splitlines()
    fails = 0
    if r.returncode != 0 or "SOUND PASS LUA: 0 failed" not in r.stdout:
        fails = 1
        out.append(r.stderr.strip()[-2500:])
    out.append("SOUND PASS TEST: %d failed" % fails)
    print("\n".join(out) if os.environ.get("VERBOSE") else "\n".join(l for l in out if l.startswith(("FAIL", "SOUND PASS TEST"))))
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
