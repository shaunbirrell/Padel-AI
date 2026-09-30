"""claude-bud JOB 40 part E: real-code tests for the base owner markers (stand-ins: run_kit_detail_test.PRELUDE).

1. CONFIG (the real BaseMarkerConfig): the fade curve (hidden <= 60, full >= 90), the size curve (MaxPx near, MinPx far),
   the rank chip (the real RebirthConfig titles; hidden at R0), the far-compact rule (past CompactFarStuds; the farther of
   two overlapping on screen).
2. DATA (the real BaseMarkerService.PlotData on stubs): an owned plot (name, @user, prestige, the nation the owner shows,
   the clan tag), an open plot (nothing), a neutral / hidden nation (no flag), a left owner (open again).
Run: LUAU=path/to/luau(.exe) python tools/sim/run_base_marker_test.py   (exit 1 on any failure)"""
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
    "Configs/BaseMarkerConfig": SH / "Configs/BaseMarkerConfig.luau",
    "Configs/RetentionConfig": SH / "Configs/RetentionConfig.luau",
    "Configs/AdminConfig": SH / "Configs/AdminConfig.luau",
    "Configs/EconomyConfig": SH / "Configs/EconomyConfig.luau",
    "Configs/RebirthConfig": SH / "Configs/RebirthConfig.luau",
    "Configs/NationConfig": SH / "Configs/NationConfig.luau",
    "Services/BaseMarkerService": SV / "Services/BaseMarkerService.luau",
}

EXTRA = r'''
task = { spawn = function() end, wait = function() end, delay = function() end }
local function signal() local s = {}; s.Connect = function() return { Disconnect = function() end } end; return s end
BY_UID = {}
local Players = { PlayerAdded = signal(), PlayerRemoving = signal(), GetPlayers = function() return {} end, GetPlayerByUserId = function(_, uid) return BY_UID[uid] end }
local RunService = { IsStudio = function() return false end }
local prevGame = game
game = { GetService = function(_, n)
  if n == "Players" then return Players elseif n == "RunService" then return RunService end
  return prevGame:GetService(n) end }
'''

TEST = r'''
local fails = 0
local function check(ok, msg) print((ok and "ok    " or "FAIL  ") .. msg); if not ok then fails += 1 end end
local BM = require(node("Configs/BaseMarkerConfig"))
local RC = require(node("Configs/RebirthConfig"))

-- ── 1. config ──
check(BM.Fade(0) == 0 and BM.Fade(60) == 0 and BM.Fade(75) == 0.5 and BM.Fade(90) == 1 and BM.Fade(5000) == 1, "fade: hidden inside 60 (the v123 sign takes over), half at 75, full past 90")
local near, far, mid = BM.SizeAt(50), BM.SizeAt(4000), BM.SizeAt((BM.NearStuds + BM.FarStuds) / 2)
check(near.X == BM.MaxPx.X and far.X == BM.MinPx.X and mid.X < near.X and mid.X > far.X, "size: MaxPx near, MinPx far, between in the middle")
check(BM.MinPx.Y >= 40, "the far marker stays >= 40 px tall (legible on an 800x360 phone)")
check(BM.RankText(0, RC.TitleFor) == nil, "R0: no rank chip")
local r3 = BM.RankText(3, RC.TitleFor)
check(r3 ~= nil and string.find(r3, "R3$") ~= nil and (RC.TitleFor(3) == nil or string.find(r3, string.upper(RC.TitleFor(3)), 1, true) == 1), "R3: the rebirth title + R3 (" .. tostring(r3) .. ")")
local cs = BM.CompactSet({ { Key = "far", Dist = BM.CompactFarStuds + 1, X = 0, Y = 0 }, { Key = "a", Dist = 300, X = 500, Y = 200 }, { Key = "b", Dist = 700, X = 520, Y = 210 }, { Key = "c", Dist = 400, X = 900, Y = 200 } })
check(cs.far and cs.b and not cs.a and not cs.c, "compact: past CompactFarStuds, and the farther of two overlapping (b behind a); c stays full")
check(BM.MaxDistance >= 5000 and BM.AlwaysOnTop == true and BM.HeightStuds >= 60, "visible from anywhere (MaxDistance 5000, AlwaysOnTop), high above the v123 sign (70 > 26)")

-- ── 2. data ──
local S = require(node("Services/BaseMarkerService"))
local NC = require(node("Configs/NationConfig"))
local owner = { UserId = 470626172, DisplayName = "Shaun", Name = "shaunie6" }
BY_UID[470626172] = owner
local ownerOf = { [1] = 470626172 }
local view = { [1] = { OwnerUserId = 470626172, NationId = "IE", Show = true } }
local deps = {
  BaseService = { GetOwnerUserId = function(pid) return ownerOf[pid] end },
  DataService = { GetProfile = function(p) return { Prestige = 5 } end },
  ClanService = { GetClanId = function(p) return "c1" end, GetClan = function(id) return { Tag = "WAR" } end },
}
-- Init wires deps + NationFlag; the NationFlag stand-in is set through a require stub
SOURCES["Modules/NationFlag"] = function() return { ViewOf = function(pid) return view[pid] end } end
S.Init(deps)
local d = S.PlotData(1)
check(d.Owner == 470626172 and d.Name == "Shaun" and d.User == "shaunie6" and d.Prestige == 5 and d.Clan == "WAR" and d.ClanId == "c1", "owned plot: owner, name, @user, prestige, clan tag")
check(d.Nation == "IE", "the nation the owner shows (IE)")
view[1].Show = false
check(S.PlotData(1).Nation == nil, "a hidden nation view: no flag")
view[1].Show = true
view[1].NationId = NC.NeutralId
check(S.PlotData(1).Nation == nil, "neutral: no flag")
check(next(S.PlotData(2)) == nil, "an open plot: no data (the client shows OPEN BASE)")
BY_UID[470626172] = nil
check(next(S.PlotData(1)) == nil, "the owner left: open again")

print(string.format("BASE MARKER TEST: %d failed", fails))
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
    print(out if os.environ.get("VERBOSE") else ("\n".join(l for l in out.splitlines() if l.startswith("FAIL") or l.startswith("BASE MARKER TEST")) or out))
    if r.returncode != 0:
        print(r.stderr.strip()[-2000:])
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
