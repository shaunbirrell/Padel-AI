"""claude-bud JOB 63: anti-spawn-camping, on the REAL RaidConfig.AntiCamp + AntiCampService (+ PlotFrame / BaseConfig)
(stand-ins: run_kit_detail_test.PRELUDE; players, BaseService and the clock are fakes; LoadCharacter is recorded).

1. Defender shield: his own respawn at his base gets 5 s (owner-first: another owner gets the normal shield).
2. Raider limit: inside the owner's base 89 s = nothing; 90 s = back to his base by the normal respawn (LoadCharacter)
   with a notice; then a 180 s same-base cooldown.
3. Cooldown: stepping back in = sent home again at once; he cannot hurt the owner (BlocksHurt) nor the base
   (BlocksBaseDamage); the TARGETS wait time counts down; near the base edge one toast with the time.
4. Repeat kills: 3 kills of the same defender inside 60 s while in his base -> home early.
5. A base whose owner is not live (OwnerFirst) has none of this.
Run: LUAU=path/to/luau(.exe) python tools/sim/run_anti_camp_test.py   (exit 1 on any failure; VERBOSE=1 prints all)"""
import os
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from run_kit_detail_test import PRELUDE  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
SH = ROOT / "src/ReplicatedStorage/Shared"
SV = ROOT / "src/ServerScriptService/Server"
MODS = {
    "Configs/RaidConfig": SH / "Configs/RaidConfig.luau",
    "Configs/RetentionConfig": SH / "Configs/RetentionConfig.luau",
    "Configs/AdminConfig": SH / "Configs/AdminConfig.luau",
    "Configs/EconomyConfig": SH / "Configs/EconomyConfig.luau",
    "Configs/BaseConfig": SH / "Configs/BaseConfig.luau",
    "Configs/BaseLayoutConfig": SH / "Configs/BaseLayoutConfig.luau",
    "Configs/BusinessConfig": SH / "Configs/BusinessConfig.luau",
    "Util/PlotFrame": SH / "Util/PlotFrame.luau",
    "Services/AntiCampService": SV / "Services/AntiCampService.luau",
}

TEST = r'''
local fails = 0
local function check(ok, msg) print((ok and "ok    " or "FAIL  ") .. msg); if not ok then fails += 1 end end
task = { spawn = function() end, delay = function(_, fn) DELAYED = fn end, defer = function() end, wait = function() end }
local ALL = {}
local prevG = game
game = { GetService = function(_, n)
  if n == "Players" then return { GetPlayers = function() return ALL end, PlayerRemoving = { Connect = function() end } } end
  if n == "RunService" then return { IsStudio = function() return false end } end
  return prevG:GetService(n) end }
local PF = require(node("Util/PlotFrame"))
local RC = require(node("Configs/RaidConfig"))
local A = RC.AntiCamp
local S = require(node("Services/AntiCampService"))
local OWNER, RAIDER, OTHER = 470626172, 9, 11
local PLOT_OF = { [OWNER] = 1, [RAIDER] = 2, [OTHER] = 3 }
local OWNER_OF = { [1] = OWNER, [2] = RAIDER, [3] = OTHER }
local LOADS, NOTES = {}, {}
local function mkP(uid)
  local root = { Position = Vector3.new(0, 0, 0), IsA = function(_, c) return c == "BasePart" end }
  local p = { UserId = uid, Parent = true, Character = { FindFirstChild = function() return root end } }
  p.LoadCharacter = function(self) table.insert(LOADS, self.UserId) end
  p.Root = root
  table.insert(ALL, p)
  return p
end
local O, R = mkP(OWNER), mkP(RAIDER)
S.Init({ BaseService = { GetOwnerUserId = function(pid) return OWNER_OF[pid] end, GetOwnedPlotId = function(p) return PLOT_OF[p.UserId] end },
  NotificationService = { Notify = function(p, t) table.insert(NOTES, { uid = p.UserId, t = t }) end } })
local T = 1000
S._clock = function() return T end
local function at(plotId, lx, lz) local w = PF.LocalToWorld(plotId, lx, lz); return Vector3.new(w.X, 3, w.Z) end

-- 1. defender shield
check(S.DefenderShieldSeconds(O) == A.DefenderShieldSeconds and A.DefenderShieldSeconds == 5, "the owner's respawn at his base: a 5 s defender shield")
check(S.DefenderShieldSeconds(R) == 0, "another player (OwnerFirst): the normal spawn shield only")

-- 2. raider limit in the owner's base
R.Root.Position = at(1, 20, 40)
check(S.PlotAt(R.Root.Position) == 1, "the raider stands inside plot 1 (the owner's base)")
S.Step()
T += 89; S.Step()
check(#LOADS == 0, "89 s inside: nothing yet")
T += 1; S.Step()
check(#LOADS == 1 and LOADS[1] == RAIDER and NOTES[#NOTES].t == A.Text.time, "90 s inside: back to his base by the normal respawn, with a notice")
check(S.CooldownLeft(RAIDER, 1) == A.SameBaseCooldownSeconds, "a 180 s same-base cooldown starts")

-- 3. cooldown rules
T += 5; S.Step()
check(#LOADS == 2 and NOTES[#NOTES].t == A.Text.cooldown, "stepping back in on cooldown: sent home again at once")
check(S.BlocksHurt(R, O) == true and S.BlocksBaseDamage(R, 1) == true and S.BlocksHurt(O, R) == false, "on cooldown he cannot hurt the owner or the base (and the owner can still hit him)")
R.Root.Position = at(1, 0, 160 + 10) -- just outside the base edge
local n0 = #NOTES
S.Step()
check(#NOTES == n0 + 1 and string.find(NOTES[#NOTES].t, "Base cooldown", 1, true), "near the base edge: one toast with the time left (" .. tostring(NOTES[#NOTES].t) .. ")")
S.Step()
check(#NOTES == n0 + 1, "the edge toast is throttled")
T += A.SameBaseCooldownSeconds; S.Step()
check(S.CooldownLeft(RAIDER, 1) == 0 and S.BlocksHurt(R, O) == false, "after the cooldown: allowed again")

-- 4. repeat kills
R.Root.Position = at(1, 20, 40); S.Step()
local loads0 = #LOADS
S.NoteKill(R, O); T += 10; S.NoteKill(R, O); T += 10
check(#LOADS == loads0, "2 kills of the same defender: still there")
S.NoteKill(R, O)
check(#LOADS == loads0 + 1 and NOTES[#NOTES].t == A.Text.kills, "the 3rd kill inside 60 s: sent home (stop spawn camping)")

-- 5. a base whose owner is not live
T += 1000
local loads1 = #LOADS
R.Root.Position = at(3, 20, 40)
S.Step(); T += 200; S.Step()
check(#LOADS == loads1, "a base whose owner is not live (OwnerFirst): no limit")

print(string.format("ANTI CAMP LUA: %d failed", fails))
if fails > 0 then error("failed") end
'''


def main():
    chunks = [PRELUDE]
    for key, path in MODS.items():
        chunks.append("SOURCES[%r] = function(script)\n%s\nend" % (key, path.read_text(encoding="utf-8")))
    chunks.append(TEST)
    with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False, encoding="utf-8") as f:
        f.write("\n".join(chunks))
        path = f.name
    r = subprocess.run([os.environ.get("LUAU", "luau"), path], capture_output=True, text=True, timeout=120)
    out = r.stdout.strip().splitlines()
    fails = 0
    if r.returncode != 0 or "ANTI CAMP LUA: 0 failed" not in r.stdout:
        fails = 1
        out.append(r.stderr.strip()[-2500:])
    out.append("ANTI CAMP TEST: %d failed" % fails)
    print("\n".join(out) if os.environ.get("VERBOSE") else "\n".join(l for l in out if l.startswith(("FAIL", "ANTI CAMP TEST"))))
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
