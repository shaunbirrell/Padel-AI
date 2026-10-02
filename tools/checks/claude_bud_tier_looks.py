"""claude-bud (Shaun item 3): turret + wall looks read ONE central config. BuyPathStatic-safe (every name _tl-prefixed).

On the REAL EndgameConfig / VisualAssetConfig / Job67DressConfig in Luau:
  * Turrets: EndgameConfig.Defence.TurretTiers is the one table: for every Turret Guns level 0..10 the gameplay tier
    (EndgameConfig.TurretTier), the look (VisualAssetConfig.TurretTierFor + TurretTierKey -> the GateDefense piece) and
    the extra Defence visual parts (DefenceVisualTier) agree; the pinned mirrors (Job67.TurretTierAt,
    DefenceVisuals.TierAt) equal it; 5 tiers, each a bigger Minigun pack level than the last (Lvl 1/3/5/8/10, long side
    strictly rising); the damage (GunsPct x level) rises with every level; the upgrade text names the Mk (TierText on)
    and is unchanged with it off.
  * Walls: the saved DefensiveWalls level 1..5 -> Job67DressConfig.Walls.Tiers: 5 distinct names, one style on every
    face, each tier more than the one below (the JOB 70 sim covers the faces); the walls buy row text names that tier.
  * TierText is owner-first (NEW-OWNER-FIRST); save keys / levels / prices untouched (no BaseConfig / Monetization edit).
"""
import os as _tl_os
import subprocess as _tl_sp
import sys as _tl_sys
import tempfile as _tl_tmp
from pathlib import Path as _TLP

if "ok" not in globals():
    def ok(m):
        print("PASS " + m)

    def bad(m):
        print("FAIL " + m)


def _tl_rd(p):
    q = _TLP(p)
    return q.read_text(encoding="utf-8").replace("\r\n", "\n") if q.is_file() else ""


_tl_C = "src/ReplicatedStorage/Shared/Configs/"
_tl_ec = _tl_rd(_tl_C + "EndgameConfig.luau")
_tl_bc = _tl_rd("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/BaseController.luau")
_tl_gd = _tl_rd("src/ServerScriptService/Server/Services/GateDefenseService.luau")
_tl_es = _tl_rd("src/ServerScriptService/Server/Services/EndgameService.luau")
(ok if "OwnerFirst = true, -- NEW-OWNER-FIRST (claude-bud item 3)" in _tl_ec else bad)("EndgameConfig.TierText is owner-first (NEW-OWNER-FIRST)")
(ok if ("EndgameConfigMod.Defence.TurretTiers.Keys[tier]" in _tl_gd and "EndgameConfigMod.TurretTier(level)" in _tl_gd) else bad)("GateDefenseService picks the gun model through the central tier table")
(ok if "EndgameConfig.DefenceText(track, L, EndgameConfig.TierTextLive(uid))" in _tl_es else bad)("the Engineering Bureau Guns row text reads the central tier name")
(ok if ('structureId == "DefensiveWalls"' in _tl_bc and "J.WallTier(" in _tl_bc and "EC.TierTextLive(player.UserId)" in _tl_bc) else bad)(
    "the walls buy row names the look its next level builds (Job67DressConfig.Walls.Tiers, owner-first)")

_tl_env = dict(_tl_os.environ)
if "LUAU" not in _tl_env and _tl_env.get("LUAU_COMPILE"):
    _tl_x = _tl_env["LUAU_COMPILE"].replace("luau-compile", "luau")
    if _tl_os.path.isfile(_tl_x):
        _tl_env["LUAU"] = _tl_x
if not _tl_env.get("LUAU"):
    bad("tier looks Luau proof needs LUAU / LUAU_COMPILE (fail closed)")
else:
    _tl_sys.path.insert(0, "tools/sim")
    from run_kit_detail_test import PRELUDE as _TL_PRELUDE  # noqa: E402
    _tl_test = r'''
local fails = 0
local function check(c, m) print((c and "ok    " or "FAIL  ") .. m); if not c then fails += 1 end end
local baseGS = game.GetService
game.GetService = function(g, n)
  if n == "RunService" then return { IsStudio = function() return false end, IsServer = function() return true end, IsClient = function() return false end } end
  return baseGS(g, n)
end
local EC = require(node("Configs/EndgameConfig"))
local VA = require(node("Configs/VisualAssetConfig"))
local J = require(node("Configs/Job67DressConfig"))
local T = EC.Defence.TurretTiers
local want = { 1, 2, 2, 2, 3, 3, 3, 4, 4, 4, 5 }
local agree = true
for L = 0, 10 do
  local t = EC.TurretTier(L)
  if t ~= want[L + 1] or VA.TurretTierFor(L) ~= t or VA.Job67.TurretTierKeys[t] ~= T.Keys[t] or EC.DefenceVisualTier(L) ~= t - 1 then agree = false end
end
check(agree, "Guns L0..10: gameplay tier = look tier = gun model key = visual-parts tier (0 | 1-3 | 4-6 | 7-9 | 10)")
local function same(a, b) if #a ~= #b then return false end for i = 1, #a do if a[i] ~= b[i] then return false end end return true end
check(same(VA.Job67.TurretTierAt, T.At) and same(EC.DefenceVisuals.TierAt, T.At) and same(VA.Job67.TurretTierKeys, T.Keys), "the pinned mirrors equal the central table")
check(#T.Names == 5 and #T.Keys == 5, "5 turret tiers: " .. table.concat(T.Names, ", "))
local prev, lvPrev, better = 0, 0, true
for i, k in ipairs(T.Keys) do
  local ref = VA.GateDefense[k]
  local lv = ref and tonumber(string.match(tostring(ref.ChildName), "(%d+)$")) or 0
  if not ref or (ref.LongAxisStuds or 0) <= prev or lv <= lvPrev then better = false end
  prev, lvPrev = ref and ref.LongAxisStuds or prev, lv
end
check(better, "each tier is a bigger, higher Minigun pack level than the last (Lvl 1 / 3 / 5 / 8 / 10, long side rising)")
local dmgUp = true
for L = 1, 10 do if EC.Defence.GunsPct * L <= EC.Defence.GunsPct * (L - 1) then dmgUp = false end end
check(dmgUp, "turret damage rises with every Guns level (+" .. EC.Defence.GunsPct .. "% each)")
check(EC.DefenceText("Guns", 7, true) == string.format("+%d%% turret + guard dmg · Mk IV gun", EC.Defence.GunsPct * 7), "the text names the look: " .. EC.DefenceText("Guns", 7, true))
check(EC.DefenceText("Guns", 7) == string.format("+%d%% turret + guard dmg", EC.Defence.GunsPct * 7), "TierText off: today's text exactly")
local names, seen, distinct = {}, {}, true
for lv = 1, 5 do
  local t = J.WallTier(lv)
  if not t or seen[t.Name] then distinct = false end
  if t then seen[t.Name] = true; table.insert(names, t.Name) end
  local st = J.WallStyleFor(lv)
  if not st or #st.Faces ~= 3 then distinct = false end
end
check(distinct and J.WallTier(0) == nil, "walls L1..L5: a new look at every level, on every face (" .. table.concat(names, " -> ") .. ")")
print(string.format("TL LUA: %d failed", fails))
if fails > 0 then error("failed") end
'''
    _tl_mods = {n: _tl_rd(_tl_C + n + ".luau") for n in ("EndgameConfig", "RetentionConfig", "BaseConfig", "AdminConfig", "VisualAssetConfig", "Job67DressConfig")}
    _tl_chunks = [_TL_PRELUDE] + ["SOURCES['Configs/%s'] = function(script)\n%s\nend" % (k, v) for k, v in _tl_mods.items()] + [_tl_test]
    with _tl_tmp.NamedTemporaryFile("w", suffix=".luau", delete=False, encoding="utf-8") as _tl_fh:
        _tl_fh.write("\n".join(_tl_chunks))
        _tl_path = _tl_fh.name
    _tl_r = _tl_sp.run([_tl_env["LUAU"], _tl_path], capture_output=True, text=True, timeout=100)
    for _tl_line in _tl_r.stdout.splitlines():
        if _tl_line.startswith("FAIL"):
            bad("tier looks: " + _tl_line[6:])
    (ok if (_tl_r.returncode == 0 and "TL LUA: 0 failed" in _tl_r.stdout) else bad)(
        "turret + wall looks read one central config (real configs in Luau)" + ("" if _tl_r.returncode == 0 else " :: " + _tl_r.stderr.strip()[-400:]))
