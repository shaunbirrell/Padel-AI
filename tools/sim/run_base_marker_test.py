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

-- ── 1. config (JOB 40E FIX: slim, high, capped, never empty) ──
check(BM.Fade(0) == 0 and BM.Fade(60) == 0 and BM.Fade(75) == 0.5 and BM.Fade(90) == 1 and BM.Fade(1500) == 1, "fade: hidden inside 60 (the v123 sign takes over), half at 75, full past 90")
check(BM.Fade(BM.FarFadeStart) == 1 and BM.Fade((BM.FarFadeStart + BM.FarFadeEnd) / 2) == 0.5 and BM.Fade(BM.FarFadeEnd) == 0 and BM.Fade(5000) == 0, "fades out past FarFadeStart .. FarFadeEnd (" .. BM.FarFadeStart .. " .. " .. BM.FarFadeEnd .. ")")
check(BM.HeightAt(0) >= 150 and BM.HeightAt(1000) >= 200 and BM.HeightAt(99999) == BM.MaxHeightStuds and BM.HeightAt(500) <= BM.HeightAt(1000),
  "HIGH: >= 150 studs over the base, rising with distance (1000 away: " .. BM.HeightAt(1000) .. " studs), capped at " .. BM.MaxHeightStuds)
local ang = math.deg(math.atan((BM.HeightAt(1000) - 5) / 1000))
check(ang >= 10, string.format("a base 1000 studs away: the tag is %.1f deg above eye level (was ~3.7 deg at 70 studs)", ang))
check(BM.ScaleAt(50) == BM.MaxScale and BM.ScaleAt(4000) == BM.MinScale and BM.ScaleAt(800) < BM.ScaleAt(200) and BM.MinScale <= BM.MaxScale, "scale: 1.2 near, 1.0 far, a far tag is never bigger than a near one")
check(BM.PillHeight <= 26 and BM.NameTextSize >= 14 and BM.NameTextSize * BM.MinScale >= 14, "SLIM: a 24 px pill at scale 1 with 14 px real name text")
local wMax = BM.PadPx + math.floor((BM.PillHeight - 10) * 4 / 3) + 5 + BM.MaxNameWidth + BM.PadPx + 2
check(wMax * BM.MaxScale <= 1024 * 0.16, string.format("the widest (near, longest name) pill is %d px (<= 16%% of a 1024 px phone; was 150-230 px min/max)", math.ceil(wMax * BM.MaxScale)))
check(BM.RankText(0) == nil and BM.RankText(3) == "R3", "rank: a short R3 only (no VETERAN / title text on the tag)")
check(BM.ShowOpenBases == false and not BM.HasTag(nil, "Shaun") and not BM.HasTag(470626172, nil) and not BM.HasTag(470626172, "  ") and BM.HasTag(470626172, "Shaun"),
  "NO EMPTY TAGS: no live owner or no name yet -> no tag at all")
-- the visible set: own first, the nearest MaxShown rivals, never two overlapping on screen
local tags = {}
for i = 1, 8 do table.insert(tags, { Key = "r" .. i, Dist = 200 * i, X = 100 * i, Y = 50, W = 80, H = 24 }) end
table.insert(tags, { Key = "me", Dist = 900, X = 950, Y = 300, W = 60, H = 24, Mine = true })
local vs = BM.VisibleSet(tags)
local n = 0
for k in pairs(vs) do if k ~= "me" then n += 1 end end
check(vs.me and n == BM.MaxShown and vs.r1 and vs.r5 and not vs.r6, "cap: the own tag + the nearest " .. BM.MaxShown .. " rivals")
local ov = BM.VisibleSet({ { Key = "near", Dist = 300, X = 500, Y = 100, W = 90, H = 24 }, { Key = "far", Dist = 900, X = 540, Y = 110, W = 90, H = 24 },
  { Key = "clear", Dist = 1200, X = 800, Y = 100, W = 90, H = 24 } })
check(ov.near and not ov.far and ov.clear, "never overlapping: of two tags on top of each other the farther hides")
check(BM.MaxDistance >= 5000 and BM.AlwaysOnTop == true, "AlwaysOnTop (the one documented exception) kept")

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
check(next(S.PlotData(2)) == nil, "an open plot: no data (no tag at all)")
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
