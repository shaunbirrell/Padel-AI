"""claude-bud JOB 69 C: the ONE "how to play" lookup (Shared/Util/HowTo) over the REAL configs.

Loads MissionConfig, DailyOpsConfig, SiteActivityConfig, OpsConfig and RebirthZonesConfig and checks that HowTo.Find
returns the row's HowTo for a mission, a daily op, a site activity, a job site and a zone run; HowTo.Line falls back
for an unknown id; HowTo.Card has the how-to card shape (Title / Goal / 3 Steps / Reward / Seconds); and HowTo.Live is
owner-first (RebirthZonesConfig.Rebuild "HowTo").
Run: LUAU=path/to/luau(.exe) python tools/sim/run_howto_test.py   (exit 1 on any failure; VERBOSE=1 prints all)"""
import os
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from run_kit_detail_test import PRELUDE  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
SH = ROOT / "src/ReplicatedStorage/Shared"
MODS = {"Util/HowTo": SH / "Util/HowTo.luau"}
for n in ("MissionConfig", "DailyOpsConfig", "SiteActivityConfig", "OpsConfig", "RebirthZonesConfig", "AdminConfig", "RetentionConfig"):
    MODS["Configs/" + n] = SH / ("Configs/%s.luau" % n)

TEST = r'''
local fails = 0
local function check(ok, msg) print((ok and "ok    " or "FAIL  ") .. msg); if not ok then fails += 1 end end
-- a live server, not Studio (RetentionConfig.Live treats Studio as owner-live)
local baseGS = game.GetService
game.GetService = function(g, n)
  if n == "RunService" then return { IsStudio = function() return false end, IsServer = function() return true end, IsClient = function() return false end } end
  return baseGS(g, n)
end
local H = require(node("Util/HowTo"))
local __V220ZC = require(node("Configs/RebirthZonesConfig"))
-- codebot_v220 (Shaun 2026-10-02 07:51: everything public): __V220ZC.Rebuild.OwnerFirst = false live; the owner-first paths
-- below are still proved with OwnerFirst = true, and a non-owner is live once it is restored (end of test)
local __V220_LAUNCHED = __V220ZC.Rebuild.OwnerFirst
check(__V220_LAUNCHED == false, "codebot_v220: __V220ZC.Rebuild.OwnerFirst = false (public for everyone)")
__V220ZC.Rebuild.OwnerFirst = true
for _, id in ipairs({ "DailyKillNPC", "SupplyRun", "DailyOpBank", "ClearViper", "Town.Bank", "EastYard", "StrategicYard" }) do
  local h = H.Find(id)
  check(h ~= nil and type(h.What) == "string" and type(h.Steps) == "table" and #h.Steps == 3 and h.Reward ~= nil and h.TimeLimit ~= nil,
    id .. ": " .. (if h then h.What else "no HowTo"))
end
check(H.Line("NoSuchThing", "old text") == "old text", "an unknown id keeps the old row text")
check(H.Line("EastYard", "x") == "DRILL COURSE: run the obstacle course", "the zone row line: " .. H.Line("EastYard", "x"))
local c = H.Card("ClearViper", "Clear Camp Viper")
check(c and c.Title == "Clear Camp Viper" and c.Goal ~= nil and #c.Steps == 3 and c.Seconds == 240 and c.Compact == false, "the card shape (Seconds " .. tostring(c and c.Seconds) .. ")")
check(H.Card("NoSuchThing", "x") == nil, "no card for an unknown id (the caller starts at once, the old path)")
check(H.Live(470626172) == true, "owner: HowTo live (owner-first)")
check(H.Live(1) == false, "another player: HowTo off (OFF = the old rows / instant START)")
print(string.format("HOWTO LUA: %d failed", fails))
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
    if r.returncode != 0 or "HOWTO LUA: 0 failed" not in r.stdout:
        fails = 1
        out.append(r.stderr.strip()[-2000:])
    out.append("HOWTO TEST: %d failed" % fails)
    print("\n".join(out) if os.environ.get("VERBOSE") else "\n".join(l for l in out if l.startswith(("FAIL", "HOWTO TEST"))))
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
