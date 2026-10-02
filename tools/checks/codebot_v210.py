# Code Bot Roblox v210 (2026-10-02): Golden Pumpjacks (DevProducts.GoldenPumpjack, 49 R$, one time) did +50 % on the two
# plot oil pumps only ($18 / 5 s each, multiplier-exempt): at most +$3.60/s on any base (Shaun's girlfriend: $2,105/s ->
# $2,107/s). Now (owner-first, MonetizationConfig.GoldenBoost) it is +IncomePct % on ALL steady base income (passive /
# training / plot_oil = what WE_IncomePerSec sums), and the Shop row shows the live "+N% ... +$N/s" from the SAME config.
# This file asserts that the effect (EconomyService), the display (ShopController / DescFor / stand) and the config agree,
# plus a Luau sim of the real MonetizationConfig + TycoonMath.ShortCash. Same save key (Entitlements.GoldenPumpjack), no
# price change, no WE_Building*, PreferMesh OFF, StreamingEnabled OFF.
import os
import re
import subprocess
import tempfile
from pathlib import Path

BUILD = 210
ROOT = Path.cwd()
PREV = os.environ.get("CODEBOT_V210_PREV", "7ee7fce")  # v209 handoff tip (place 207)
C = "src/ReplicatedStorage/Shared/Configs/"
SH = "src/ReplicatedStorage/Shared/"
S = "src/ServerScriptService/Server/"
CL = "src/StarterPlayer/StarterPlayerScripts/Client/"
LUAU = os.environ.get("LUAU", os.path.expanduser("~/.local/bin/luau"))


def _r(rel):
    p = ROOT / rel
    return p.read_text(encoding="utf-8").replace("\r\n", "\n") if p.is_file() else ""


def _shipped(rel, rev):
    r = subprocess.run(["git", "show", rev + ":" + rel], capture_output=True, text=True, cwd=ROOT)
    return (r.stdout or "").replace("\r\n", "\n") if r.returncode == 0 else None


def _c(cond, label):
    label = "CODEBOT v%d: %s" % (BUILD, label)
    if "ok" in globals() and "bad" in globals():
        (ok if cond else bad)(label)
    else:
        print(("PASS " if cond else "FAIL ") + label)
        if not cond:
            raise SystemExit(1)


_bud = (ROOT / S / "Services/ExperienceNotifyService.luau").is_file()  # claude/desktop-bud: ship-only pins skip
_own = ('SetAttribute("WE_Build", %d)' % BUILD) in _r(S + "Services/DataService.luau")
if not _bud:
    for _rel, _needle in (
        (S + "Services/BaseService.luau", 'SetAttribute("WE_Build", %d)' % BUILD),
        (S + "Services/DataService.luau", 'SetAttribute("WE_Build", %d)' % BUILD),
        (S + "Services/DataService.luau", "WE_Build=%d" % BUILD),
        (S + "EarlyRemotes.server.luau", 'SetAttribute("WE_Build", %d)' % BUILD),
    ):
        _c(_needle in _r(_rel) or not _own, "WE_Build=%d %s" % (BUILD, _rel.rsplit("/", 1)[-1]))

MON = _r(C + "MonetizationConfig.luau")
ECO = _r(S + "Services/EconomyService.luau")
PUMP = _r(S + "Services/PlotOilPumpService.luau")
SHOP = _r(CL + "Controllers/ShopController.luau")
TGC = _r(C + "TycoonGuideConfig.luau")

# ---- the ONE config
_gb = re.search(r"\n\(MonetizationConfig :: any\)\.GoldenBoost = \{\n(.*?)\n\}\n", MON, re.S)
GB = _gb.group(1) if _gb else ""
_c(bool(GB), "MonetizationConfig.GoldenBoost block present")
_c("\tEnabled = true,\n" in GB and "\tOwnerFirst = true, -- NEW-OWNER-FIRST (Code Bot v210)" in GB, "GoldenBoost Enabled + OwnerFirst = true (Shaun's phone test)")
_c('\tProductKey = "GoldenPumpjack",' in GB, "GoldenBoost.ProductKey = the existing GoldenPumpjack product (same save key)")
_pct = re.search(r"\tIncomePct = (\d+),", GB)
PCT = int(_pct.group(1)) if _pct else 0
_c(10 <= PCT <= 50, "IncomePct is a meaningful whole percent (%d)" % PCT)
_c('GoldenBoost.Description =\n\tstring.format("+%d%% on all your base income, forever", (MonetizationConfig :: any).GoldenBoost.IncomePct)' in MON,
   "Description is built from IncomePct (text can never drift from the effect)")
for _k in ("RowFormat", "OwnedFormat"):
    _m = re.search(r"\t" + _k + r' = "([^"]*)"', GB)
    _c(_m is not None and _m.group(1).startswith("+%d%%") and "+%s/s" in _m.group(1), _k + ' says "+N% ... +$N/s"')
_c(re.search(r'\tToastFormat = "[^"]*%s/s \(\+%s/s\)"', GB) is not None, "ToastFormat shows the new income per second and the gain")
# the boosted reasons are exactly what WE_IncomePerSec sums (so "+N% of income/s" is literally true)
_rs = re.search(r"\tReasons = \{([^}]*)\}", GB)
_ts = re.search(r"SteadyIncomeReasons = \{([^}]*)\}", TGC)
_set = lambda m: set(re.findall(r"(\w+) = true", m.group(1))) if m else set()
_c(_set(_rs) and _set(_rs) == _set(_ts), "GoldenBoost.Reasons == TycoonGuideConfig.SteadyIncomeReasons %s" % sorted(_set(_rs)))
_c("function MonetizationConfig.GoldenBoostLiveFor(userId: any): boolean\n\treturn (require(script.Parent.RetentionConfig) :: any).Live((MonetizationConfig :: any).GoldenBoost, userId)" in MON,
   "GoldenBoostLiveFor = RetentionConfig.Live (OwnerFirst = UserId 470626172 + Studio)")
_gp = re.search(r"\n\t\tGoldenPumpjack = \{(.*?)\n\t\t\},", MON, re.S)
_c(_gp is not None and "Id = 3714663783," in _gp.group(1) and "RobuxPrice = 49," in _gp.group(1) and 'GrantEntitlement = "GoldenPumpjack",' in _gp.group(1)
   and "OneTime = true," in _gp.group(1) and "LiveBlock" not in _gp.group(1), "GoldenPumpjack row: same Id / 49 R$ / entitlement / one time; still on sale for everyone (no LiveBlock)")

# ---- the effect (server)
_cm = re.search(r"local function cashMultFor\(player: Player, profile: any, reason: string\?\): number\n(.*?)\n\treturn mult\nend\n", ECO, re.S)
CM = _cm.group(1) if _cm else ""
_c("local GB = (MonetizationConfig :: any).GoldenBoost" in CM and "GB.Reasons[reasonKey] == true" in CM
   and "ents[GB.ProductKey] == true" in CM and "MonetizationConfig.GoldenBoostLiveFor(player.UserId)" in CM
   and "mult *= MonetizationConfig.GoldenBoostMult()" in CM and "if NEVER_MULTIPLIED[reasonKey] ~= true then" in CM,
   "EconomyService.cashMultFor: owners get x GoldenBoostMult on every GoldenBoost reason (exempt plot_oil included)")
_c(CM.rfind("mult *= MonetizationConfig.GoldenBoostMult()") > CM.rfind("elseif NEVER_MULTIPLIED[reasonKey] ~= true then"),
   "the Golden factor sits outside the exempt branch (applies to plot_oil too)")
_c("if MonetizationConfig.GoldenBoostLiveFor(ownerId) then\n\t\t\t\t\t\t\t\tgoldMult = 1" in PUMP,
   "PlotOilPumpService: no legacy per-pump x1.5 while GoldenBoost is live (no double count)")
_c("applyGoldenDress(pump)" in PUMP, "gold pumps still turn gold (visual unchanged)")

# ---- the display (client + stand)
_c("if def == cfg.DevProducts[cfg.GoldenBoost.ProductKey] and userId ~= nil and cfg.GoldenBoostLiveFor(userId) then\n\t\treturn cfg.GoldenBoost.Description" in MON,
   "DescFor (Shop / purchase stand) says GoldenBoost.Description while live")
_c("local TycoonMath = require(Shared.Util.TycoonMath)" in SHOP and "TycoonMath.ShortCash(math.floor(math.max(0, gain) + 0.5))" in SHOP,
   "Shop formats with the shared TycoonMath.ShortCash (K/M/B/T)")
_c('MonetizationConfig.GoldenBoostGainPerSec(incomePerSecNow(), owned)' in SHOP and 'player:GetAttribute("WE_IncomePerSec")' in SHOP
   and "string.format(if owned then GB.OwnedFormat else GB.RowFormat, GB.IncomePct, goldenGainText(gain))" in SHOP,
   "Shop row = GoldenBoostGainPerSec(WE_IncomePerSec) with the config's formats")
_c('player:GetAttributeChangedSignal("WE_IncomePerSec"):Connect(function()\n\t\tif menuOpen then\n\t\t\trefreshGoldenRow()' in SHOP,
   "the row's +$N/s follows the live income (only while the Shop is open)")
_c("string.format(GB.ToastFormat, TycoonMath.ShortCash(math.floor(inc)), goldenGainText(gain))" in SHOP
   and "task.delay(tonumber(GB.ToastWaitSeconds) or 11" in SHOP and "gdef.Id == productId and goldenBoostShown()" in SHOP,
   "after the purchase: toast with the real new WE_IncomePerSec (after ToastWaitSeconds)")
_c('"Util/TycoonMath": SH / "Util/TycoonMath.luau"' in _r("tools/sim/run_shop_render_test.py"), "run_shop_render_test loads the real TycoonMath")

# ---- money / saves / guards
def _prices(src):
    return sorted(re.findall(r"\n\t\t(\w+) = \{[^{}]*?RobuxPrice = (\d+)", src))
_pm = _shipped(C + "MonetizationConfig.luau", PREV)
if _pm is not None and not _bud:
    _c(_prices(_pm) == _prices(MON) and len(_prices(MON)) > 30, "every RobuxPrice identical to %s (%d rows, no price change)" % (PREV, len(_prices(MON))))
    _ds_prev = re.sub(r"WE_Build\D{0,4}\d+", "", _shipped(S + "Services/DataService.luau", PREV) or "")
    _c(_ds_prev == re.sub(r"WE_Build\D{0,4}\d+", "", _r(S + "Services/DataService.luau")), "DataService save keys unchanged (only WE_Build)")
_c("WE_Building" not in GB and "WE_Building" not in CM, "never touches WE_Building*")
_c("PreferMeshWhenAssetIdSet = false" in _r(C + "StructureVisualConfig.luau"), "PreferMesh OFF")
_c('"StreamingEnabled": true' not in _r("default.project.json"), "StreamingEnabled stays OFF")

# ---- Luau sim: the REAL MonetizationConfig (+ AdminConfig, RetentionConfig) and TycoonMath.ShortCash
if os.path.exists(LUAU):
    def _body(rel):
        s = _r(rel).replace("--!strict", "")
        return re.sub(r"^export type", "type", s, flags=re.M)
    _pre = r'''
local Color3 = { fromRGB = function(...) return { ... } end, new = function(...) return { ... } end }
local Vector3 = { new = function(x, y, z) return { X = x, Y = y, Z = z } end }
local game = { GetService = function() return { IsStudio = function() return false end } end }
local CACHE, LOADERS = {}, {}
local STUB = setmetatable({}, { __index = function(t) return t end })
local CONFIGS = setmetatable({}, { __index = function(_, k) return k end })
local function req(name)
	if CACHE[name] == nil then CACHE[name] = if LOADERS[name] then LOADERS[name]() else STUB end
	return CACHE[name]
end
'''
    for _n, _rel in (("AdminConfig", C + "AdminConfig.luau"), ("RetentionConfig", C + "RetentionConfig.luau"),
                     ("MonetizationConfig", C + "MonetizationConfig.luau"), ("TycoonMath", SH + "Util/TycoonMath.luau")):
        _pre += ('LOADERS["%s"] = function()\nlocal require = req\nlocal script = { Parent = { Parent = { Configs = CONFIGS }, '
                 'AdminConfig = "AdminConfig", RetentionConfig = "RetentionConfig", EconomyConfig = "EconomyConfig" } }\n%s\nend\n') % (_n, _body(_rel))
    _pre += r'''
local M, T = req("MonetizationConfig"), req("TycoonMath")
local GB = M.GoldenBoost
local fails = 0
local function ck(c, m) if not c then fails += 1 print("SIMFAIL " .. m) end end
local OWNER, OTHER = 470626172, 9
ck(M.GoldenBoostLiveFor(OWNER) == true and M.GoldenBoostLiveFor(OTHER) == false, "owner-first")
ck(math.abs(M.GoldenBoostMult() - (1 + GB.IncomePct / 100)) < 1e-9, "mult = 1 + pct")
ck(M.DescFor(M.DevProducts.GoldenPumpjack, OWNER) == string.format("+%d%% on all your base income, forever", GB.IncomePct), "owner desc")
ck(M.DescFor(M.DevProducts.GoldenPumpjack, OTHER) == M.DevProducts.GoldenPumpjack.Description, "others keep the legacy desc")
ck(M.SkuLiveFor(OTHER, "GoldenPumpjack") == true, "still sold to everyone")
-- the server's steady income for a $2,105/s base: passive / training / plot_oil grants per 5 s tick, each floored x mult
local function perSec(grants, mult) local s = 0 for _, a in ipairs(grants) do s += math.floor(a * mult) end return math.floor(s / 5 * 10 + 0.5) / 10 end
for _, g in ipairs({ { 10489, 0, 36 }, { 300, 0, 36 }, { 2400000, 60000, 36 }, { 0, 0, 36 } }) do
	local before, after = perSec(g, 1), perSec(g, M.GoldenBoostMult())
	local shown = M.GoldenBoostGainPerSec(before, false) -- the Shop row before buying
	local share = M.GoldenBoostGainPerSec(after, true) -- the toast / owned row after
	ck(math.abs((after - before) - shown) <= 0.2 + #g * 0.2, "row gain == real gain (" .. before .. " -> " .. after .. ", shown " .. shown .. ")")
	ck(math.abs(share - shown) <= 0.5, "owned share == pre-buy gain")
end
ck(perSec({ 10489, 0, 36 }, 1) == 2105, "example base = $2,105/s")
local gainText = T.ShortCash(math.floor(M.GoldenBoostGainPerSec(2105, false) + 0.5))
ck(string.format(GB.RowFormat, GB.IncomePct, gainText) == string.format("+%d%% income forever · +$316/s", GB.IncomePct) or GB.IncomePct ~= 15, "row text at $2,105/s: " .. string.format(GB.RowFormat, GB.IncomePct, gainText))
ck(T.ShortCash(12500) == "$12.5K" and T.ShortCash(2400000) == "$2.4M", "K/M formatter")
for _, f in ipairs({ GB.RowFormat, GB.OwnedFormat }) do
	ck(utf8.len(string.format(f, GB.IncomePct, "$999.9T")) <= 40, "row text fits a phone row with the longest amount (<= 40 of the 56-char phone budget)")
end
ck(utf8.len(GB.Description) <= 56, "Description fits a phone row / stand line")
print("ROW@2105 " .. string.format(GB.RowFormat, GB.IncomePct, gainText))
print("GOLDEN SIM: " .. fails .. " failed")
'''
    with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False) as _f:
        _f.write(_pre)
    _o = subprocess.run([LUAU, _f.name], capture_output=True, text=True, timeout=60)
    _c("GOLDEN SIM: 0 failed" in _o.stdout, "Luau sim (real MonetizationConfig + TycoonMath): effect == display == config " + (_o.stdout + _o.stderr).strip()[-300:])
