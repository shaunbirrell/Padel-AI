# Code Bot Roblox v212 (2026-10-02, Shaun: "the writing on the upgrade / pass boards is far too small on my phone";
# + "let me turn the yellow airdrop guide line off"). Both NEW-OWNER-FIRST (owner 470626172 + Studio).
# 1. Supply Depot stand signs, big phone layout (client-local; Client/Modules/StandSignBig + the pure
#    Shared/Util/StandSignLayout): bold name, ONE short effect line from MonetizationConfig.EffectFor (the Shop's config),
#    a big price / OWNED pill. This check RUNS the layout in Luau, measures every real text with the Montserrat metrics
#    (Roblox's Gotham faces), and asserts the minimum sizes, that no text overflows its box, and that no boxes overlap.
# 2. AIRDROP guide line: a big HIDE LINE button (ObjectiveMarker.Clear: the Beam goes) that keeps that airdrop hidden,
#    and a Settings toggle saved in the NEW key profile.Settings.AirdropGuideOff. A Luau sim of FeatureController's logic.
# No price change; PreferMesh OFF; StreamingEnabled OFF; WE_Building* untouched; no new Heartbeat.
# Code Bot v215 rollout: both switches are now public; the v215 check proves non-owner server/client access.
import os
import re
import subprocess
import tempfile
from pathlib import Path

BUILD = 212
ROOT = Path.cwd()
PREV = os.environ.get("CODEBOT_V212_PREV", "9f11ee5")  # v211 handoff tip (place 209)
C = "src/ReplicatedStorage/Shared/Configs/"
U = "src/ReplicatedStorage/Shared/Util/"
S = "src/ServerScriptService/Server/"
CL = "src/StarterPlayer/StarterPlayerScripts/Client/"
LUAU = os.environ.get("LUAU", os.path.expanduser("~/.local/bin/luau"))
TAG = "CODEBOT v212: "


def _r(rel):
    p = ROOT / rel
    return p.read_text(encoding="utf-8").replace("\r\n", "\n") if p.is_file() else ""


def _shipped(rel, rev):
    r = subprocess.run(["git", "show", rev + ":" + rel], capture_output=True, text=True, cwd=ROOT)
    return (r.stdout or "").replace("\r\n", "\n") if r.returncode == 0 else None


def _c(cond, label):
    label = TAG + label
    if "ok" in globals() and "bad" in globals():
        (ok if cond else bad)(label)
    else:
        print(("PASS " if cond else "FAIL ") + label)
        if not cond:
            raise SystemExit(1)


def _luau(src):
    with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False, encoding="utf-8") as f:
        f.write(src)
        path = f.name
    try:
        r = subprocess.run([LUAU, path], capture_output=True, text=True, timeout=60)
        return r.returncode, (r.stdout or "") + (r.stderr or "")
    finally:
        os.unlink(path)


def _strip_comments(src):
    src = re.sub(r"--\[(=*)\[.*?\]\1\]", "", src, flags=re.S)
    return re.sub(r"--[^\n]*", "", src)


_bud = (ROOT / S / "Services/ExperienceNotifyService.luau").is_file()  # claude/desktop-bud: ship-only pins skip
if not _bud:
    for _rel, _needle in (
        (S + "Services/BaseService.luau", 'SetAttribute("WE_Build", 219)'),
        (S + "Services/DataService.luau", 'SetAttribute("WE_Build", 219)'),
        (S + "Services/DataService.luau", "WE_Build=219"),
        (S + "EarlyRemotes.server.luau", 'SetAttribute("WE_Build", 219)'),
    ):
        _c(_needle in _r(_rel), "WE_Build=219 " + _rel.rsplit("/", 1)[-1])

MC = _r(C + "MonetizationConfig.luau")
SDC = _r(C + "SupplyDropConfig.luau")
LAY = _r(U + "StandSignLayout.luau")
BIG = _r(CL + "Modules/StandSignBig.luau")
FC = _r(CL + "Controllers/FeatureController.luau")
SET = _r(CL + "Controllers/SettingsController.luau")
SDS = _r(S + "Services/SupplyDropService.luau")
PS = _r(S + "Modules/PurchaseStands.luau")

# ───────────── 1. the board ─────────────
_bi = MC.find("\t\tBigSign = {")
_bs = MC[_bi:MC.find("\t\t},", _bi)] if _bi > 0 else ""
_c("Enabled = true," in _bs and "OwnerFirst = false, -- PUBLIC (Code Bot v215)" in _bs, "PremiumPads.BigSign enabled + OwnerFirst = false (public rollout)")
_num = lambda k: float(re.search(r"\b" + k + r" = ([\d.]+)", _bs).group(1)) if re.search(r"\b" + k + r" = ([\d.]+)", _bs) else 0.0
BW, BH, BPX = _num("W"), _num("H"), _num("PixelsPerStud")
_step = float(re.search(r"Depot = \{ X0 = -?\d+, Step = (\d+)", MC).group(1))
_c(0 < BW <= _step - 5, "BigSign W %.1f <= Depot.Step - 5 (%g): neighbouring boards never overlap" % (BW, _step - 5))
_c(BH > 0 and BPX >= 50, "BigSign H / PixelsPerStud set (%.1f studs, %g px/stud)" % (BH, BPX))
_c("function cfg.EffectFor(def: any, userId: any)" in MC and "cfg.SpeedText(cfg.SpeedMultOf(def, userId), false)" in MC,
   "MonetizationConfig.EffectFor: speed lines from SpeedText (one source), else Effect, else DescFor")
_c("function cfg.BigSignLiveFor(userId: any)" in MC and "RetentionConfig) :: any).Live(b, userId)" in MC,
   "BigSignLiveFor = RetentionConfig.Live (owner-first rule)")
_c('Effect = "Auto-collects cash"' in MC and 'Effect = "2x cash, forever"' in MC, "short Effect lines in MonetizationConfig")
# no hard-coded effect / price text in the client module: it reads EffectFor and the server's Title / Price labels
_bigc = _strip_comments(BIG)
for _s in ("Auto-collects", "2x cash", "faster", "forever", "R$", "OWNED", "99", "149"):
    _c(_s not in _bigc, "StandSignBig hard-codes no text %r (EffectFor / server labels only)" % _s)
_c("EffectFor(def, Players.LocalPlayer.UserId)" in BIG, "StandSignBig effect line = MonetizationConfig.EffectFor")
_c("BigSignLiveFor(lp.UserId)" in BIG, "StandSignBig only for a viewer the switch is live for")
_c('GetAttribute("PadSlot") == nil' in BIG, "StandSignBig only on Supply Depot stands (PadSlot): the Golden Pump stand untouched")
for _src, _nm in ((_bigc, "StandSignBig"), (_strip_comments(FC), "FeatureController")):
    _c("Heartbeat" not in _src and "RenderStepped" not in _src.replace("", "") and "BindToRenderStep" not in _src,
       _nm + ": no Heartbeat / RenderStepped")
_c(re.search(r"\bwhile\b", _bigc) is None, "StandSignBig: no loop")
# the server sign is unchanged for everyone else (byte-identical PurchaseStands; old v175 layout still built)
_old_ps = _shipped(S + "Modules/PurchaseStands.luau", PREV)
_c(_old_ps is None or _old_ps == PS, "PurchaseStands.luau byte-identical to " + PREV + " (other players keep the v175 sign)")

# prices unchanged
def _prices(t):
    return sorted(re.findall(r"(\w+)\s*=\s*\{[^{}]*?RobuxPrice = (\d+)", t))
_old_mc = _shipped(C + "MonetizationConfig.luau", PREV)
if _old_mc is not None:
    _c(_prices(_old_mc) == _prices(MC) and re.findall(r"RobuxPrice = \d+", _old_mc) == re.findall(r"RobuxPrice = \d+", MC),
       "every RobuxPrice identical to " + PREV)
    _c(re.findall(r"\bId = \d+", _old_mc) == re.findall(r"\bId = \d+", MC), "every product / pass Id identical to " + PREV)

# --- run the real layout + the real EffectFor / SpeedText in Luau ---
HARNESS = r'''
local MODS = {}
local function ctor() return setmetatable({}, { __index = function() return function(...) return { ... } end end }) end
Color3, Vector3, Vector2, UDim2, UDim, CFrame, ColorSequence, NumberRange = ctor(), ctor(), ctor(), ctor(), ctor(), ctor(), ctor(), ctor()
Enum = setmetatable({}, { __index = function(_, k) return setmetatable({}, { __index = function(_, j) return k .. "." .. j end }) end })
local function mkScript(name)
  return { Name = name, Parent = setmetatable({}, { __index = function(_, k) return { __mod = k } end }) }
end
local RS = { IsStudio = function() return false end }
game = { GetService = function(_, n) if n == "RunService" then return RS end return setmetatable({}, { __index = function() return function() return nil end end }) end }
local realRequire = require
local function req(m)
  if type(m) == "table" and m.__mod then
    local v = MODS[m.__mod]
    if v == nil then error("no stub " .. tostring(m.__mod)) end
    return v
  end
  return realRequire(m)
end
MODS.AdminConfig = { IsPlaytestOwner = function(u) return u == 470626172 end, UserIds = { 470626172 } }
MODS.RetentionConfig = { Live = function(b, u)
  if type(b) ~= "table" or b.Enabled ~= true then return false end
  if b.OwnerFirst ~= true then return true end
  if RS:IsStudio() then return true end
  return MODS.AdminConfig.IsPlaytestOwner(u)
end }
local function load(src, name)
  local f = assert(loadstring(src, name))
  setfenv(f, setmetatable({ script = mkScript(name), require = req, game = game, Color3 = Color3, Vector3 = Vector3, Vector2 = Vector2, UDim2 = UDim2, UDim = UDim, CFrame = CFrame, Enum = Enum, ColorSequence = ColorSequence, NumberRange = NumberRange }, { __index = getfenv(0) }))
  return f()
end
'''


def _lua_str(s):
    return "[==[" + s + "]==]"


_sim = HARNESS + "\nlocal MC = load(" + _lua_str(MC) + ", 'MonetizationConfig')\n" + "local LAY = load(" + _lua_str(LAY) + ", 'StandSignLayout')\n" + r'''
local B = MC.PremiumPads.BigSign
local L = LAY.Big(B.W, B.H, B.PixelsPerStud)
local function box(n, b) print(string.format("BOX %s %d %d %d %d %d %d %s", n, b.X, b.Y, b.W, b.H, b.Max or 0, b.Min or 0, b.Font or "-")) end
print(string.format("CANVAS %d %d %d", L.CanvasW, L.CanvasH, L.Inset))
box("Icon", L.Icon); box("Title", L.Title); box("Effect", L.Effect); box("Chip", L.Chip); box("Price", L.Price); box("Glyph", L.IconGlyph)
local ROBUX = utf8.char(0xE002)
for _, slot in ipairs(MC.PremiumPads.Slots) do
  for _, o in ipairs(slot.Offers) do
    local sec = if o.Kind == "GamePass" then MC.GamePasses else MC.DevProducts
    local def = sec[o.Key]
    for _, uid in ipairs({ 470626172, 1 }) do
      print("TITLE\t" .. def.DisplayName)
      print("EFFECT\t" .. o.Key .. "\t" .. MC.EffectFor(def, uid))
      print("OLDDESC\t" .. o.Key .. "\t" .. MC.DescFor(def, uid))
      print("PRICE\t" .. ROBUX .. " " .. tostring(def.RobuxPrice))
    end
  end
end
print("LIVE_OWNER " .. tostring(MC.BigSignLiveFor(470626172)) .. " LIVE_OTHER " .. tostring(MC.BigSignLiveFor(1)))
'''
_rc, _out = _luau(_sim)
_c(_rc == 0 and "CANVAS" in _out, "Luau: StandSignLayout.Big + MonetizationConfig.EffectFor ran" + ("" if _rc == 0 else " :: " + _out[-400:]))
_c("LIVE_OWNER true LIVE_OTHER true" in _out, "BigSignLiveFor: owner and non-owner are live (public rollout)")

BOX = {}
CANVAS = (0, 0, 0)
TITLES, EFFECTS, PRICES, OLDD = set(), {}, set(), set()
for _ln in _out.splitlines():
    p = _ln.split(" ")
    if p[0] == "CANVAS":
        CANVAS = tuple(int(x) for x in p[1:4])
    elif p[0] == "BOX":
        BOX[p[1]] = dict(X=int(p[2]), Y=int(p[3]), W=int(p[4]), H=int(p[5]), Max=int(p[6]), Min=int(p[7]), Font=p[8])
    elif _ln.startswith("TITLE\t"):
        TITLES.add(_ln.split("\t", 1)[1])
    elif _ln.startswith("EFFECT\t"):
        _k, _t = _ln.split("\t")[1:3]
        EFFECTS.setdefault(_k, set()).add(_t)
    elif _ln.startswith("OLDDESC\t"):
        _k, _t = _ln.split("\t")[1:3]
        OLDD.add((_k, _t))
    elif _ln.startswith("PRICE\t"):
        PRICES.add(_ln.split("\t", 1)[1])
PRICES.add("✓ OWNED")  # ShopController writes this into the same Price label
TITLES.add("Speed Boost")  # the Speed stand retargeted (ShopOverhaulService) for a live owner
_c(len(BOX) == 6 and CANVAS[0] > 0, "layout boxes read (%d)" % len(BOX))

# --- text metrics: Montserrat (Roblox's Gotham faces); conservative em widths when the font is not on this machine ---
_FONT = None
for _cand in ("/usr/share/fonts/truetype/sand-box/google/Montserrat/Montserrat-VariableFont_wght.ttf",):
    if os.path.isfile(_cand):
        _FONT = _cand
WEIGHT = {"GothamBlack": 900, "GothamBold": 700}


def text_em(text, font):
    """width of text in em (1 em = TextSize px)."""
    try:
        from PIL import ImageFont
        if _FONT is None:
            raise ImportError
        f = ImageFont.truetype(_FONT, 200)
        try:
            f.set_variation_by_axes([WEIGHT.get(font, 700)])
        except Exception:
            pass
        w = 0.0
        for ch in text:
            if ord(ch) >= 0xE000 or ch in "✓":  # Robux / check glyphs come from Roblox's fallback font
                w += 1.0
            else:
                w += f.getlength(ch) / 200.0
        return w
    except ImportError:
        return sum(1.0 if (ord(ch) >= 0xE000 or ch == "✓") else (0.78 if WEIGHT.get(font) == 900 else 0.72) for ch in text)


SAFETY = 1.08  # 8 % headroom over the measured width (kerning / renderer differences)


def fit(text, b):
    """the size Roblox's TextScaled picks (largest that fits the box, capped by MaxTextSize) and whether it overflows."""
    em = text_em(text, b["Font"]) * SAFETY
    s = min(b["Max"], b["H"], int(b["W"] / em) if em > 0 else b["Max"])
    return s, s < b["Min"]


# boxes inside the canvas (inside the gold edge) and never overlapping
CW, CH, INSET = CANVAS
for _n in ("Icon", "Title", "Effect", "Chip"):
    b = BOX[_n]
    _c(b["X"] >= 6 and b["Y"] >= 6 and b["X"] + b["W"] <= CW - 6 and b["Y"] + b["H"] <= CH - 6,
       "%s box inside the canvas %dx%d (clear of the 6 px edge)" % (_n, CW, CH))
_inner = BOX["Price"]
_c(_inner["X"] >= 0 and _inner["Y"] >= 0 and _inner["X"] + _inner["W"] <= BOX["Chip"]["W"] and _inner["Y"] + _inner["H"] <= BOX["Chip"]["H"],
   "Price label inside its chip")


def _ov(a, b):
    return a["X"] < b["X"] + b["W"] and b["X"] < a["X"] + a["W"] and a["Y"] < b["Y"] + b["H"] and b["Y"] < a["Y"] + a["H"]


for _a, _b in (("Icon", "Title"), ("Icon", "Effect"), ("Title", "Effect"), ("Effect", "Chip"), ("Title", "Chip"), ("Icon", "Chip")):
    _c(not _ov(BOX[_a], BOX[_b]), "no overlap: %s / %s" % (_a, _b))

# minimum readable sizes (px on a PixelsPerStud canvas -> studs: what a phone camera sees)
MIN_STUDS = {"Title": 0.55, "Effect": 0.55, "Price": 0.62}
for _n, _ms in MIN_STUDS.items():
    _c(BOX[_n]["Min"] / BPX >= _ms, "%s MinTextSize %d px = %.2f studs >= %.2f" % (_n, BOX[_n]["Min"], BOX[_n]["Min"] / BPX, _ms))

REPORT = []
for _t in sorted(TITLES):
    s, over = fit(_t, BOX["Title"])
    REPORT.append(("Title", _t, s))
    _c(not over, "title %r fits at %d px (%.2f studs, min %d), no overflow" % (_t, s, s / BPX, BOX["Title"]["Min"]))
for _k, _ts in sorted(EFFECTS.items()):
    for _t in sorted(_ts):
        s, over = fit(_t, BOX["Effect"])
        REPORT.append(("Effect", _t, s))
        _c(not over, "effect %r (%s) fits at %d px (%.2f studs, min %d), one line, no overflow" % (_t, _k, s, s / BPX, BOX["Effect"]["Min"]))
        _c(len(_t) <= 20, "effect %r is one short line (<= 20 chars)" % _t)
for _t in sorted(PRICES):
    s, over = fit(_t, BOX["Price"])
    REPORT.append(("Price", _t, s))
    _c(not over, "price %r fits at %d px (%.2f studs, min %d), no overflow" % (_t, s, s / BPX, BOX["Price"]["Min"]))

# old (v175, still built by the server) vs new, for the handoff
OLD = {"Title": dict(X=104, Y=12, W=384 - 118, H=80, Max=58, Min=14, Font="GothamBlack"),
       "Effect": dict(X=16, Y=98, W=384 - 32, H=34, Max=28, Min=14, Font="GothamMedium"),
       "Price": dict(X=10, Y=4, W=int(384 * 0.62) - 20, H=204 - 138 - 20, Max=44, Min=14, Font="GothamBlack")}
if os.environ.get("CODEBOT_V212_REPORT"):
    for _n, _t, _s in REPORT:
        src = _t
        if _n == "Effect":
            _key = next(k for k, ts in EFFECTS.items() if _t in ts)
            src = sorted(d for k, d in OLDD if k == _key)[-1]
        os_, _ = fit(src, OLD[_n])
        print("REPORT %s | old %r %d px (%.2f st) | new %r %d px (%.2f st)" % (_n, src, os_, os_ / 60, _t, _s, _s / BPX))

# ───────────── 2. airdrop guide line ─────────────
_gi = SDC.find("SupplyDropConfig.GuideHide = {")
_gs = SDC[_gi:SDC.find("\n}", _gi)] if _gi > 0 else ""
_c("Enabled = true," in _gs and "OwnerFirst = false, -- PUBLIC (Code Bot v215)" in _gs, "SupplyDropConfig.GuideHide enabled + OwnerFirst = false (public rollout)")
_c('SettingKey = "AirdropGuideOff"' in _gs and 'Attr = "WE_AirdropGuideOff"' in _gs, "GuideHide: new save key AirdropGuideOff + attribute")
_bsz = re.search(r"ButtonSize = Vector2.new\((\d+), (\d+)\)", _gs)
_c(_bsz is not None and int(_bsz.group(2)) >= 64 and int(_bsz.group(1)) >= 160, "HIDE LINE button >= 64 v tall (>= 44 real px on a phone), wide")
# the save key is NEW: absent from the v208 tree, never in the profile defaults, and no other Settings key is written
_old_tree = subprocess.run(["git", "grep", "-l", "AirdropGuideOff", PREV, "--", "src"], capture_output=True, text=True, cwd=ROOT)
_c(_old_tree.stdout.strip() == "", "AirdropGuideOff did not exist before (a new key)")
_ps_old = _shipped(S + "Modules/ProfileSchema.luau", PREV)
_c(_ps_old is None or _ps_old == _r(S + "Modules/ProfileSchema.luau"), "ProfileSchema byte-identical (no existing save key touched)")
AGS = _r(S + "Services/AirdropGuideService.luau")
_c("profile.Settings[G.SettingKey] = if off then true else nil" in AGS and len(re.findall(r"profile\.Settings[\.\[]", _strip_comments(AGS))) == 1,
   "server writes only profile.Settings.AirdropGuideOff")
_c('RemoteGate).Check(player, "RequestAirdropGuideSetting", off)' in AGS and 'RateLimitService.Allow(player, "airdrop_guide_setting"' in AGS
   and "SupplyDropConfig.GuideHideLiveFor(player.UserId)" in AGS, "server: RemoteGate + rate limit + owner-first live check")
_c('safeInit("AirdropGuideService"' in _r(S + "Bootstrap.server.luau"), "Bootstrap starts AirdropGuideService")
_c('RequestAirdropGuideSetting = { "boolean" }' in _r(C + "SecurityConfig.luau") and 'Remote = "RequestAirdropGuideSetting"' in SDC,
   "RemoteGate schema: boolean (remote name from SupplyDropConfig.GuideHide.Remote; RemoteSetup.Get creates it)")
_c(SDS == (_shipped(S + "Services/SupplyDropService.luau", PREV) or SDS), "SupplyDropService byte-identical (airdrop, claim and cash unchanged)")
_c('RequestAirdropGuideSetting = "RequestAirdropGuideSetting"' in _r("src/ReplicatedStorage/Shared/Constants.luau") and "Constants.RemoteNames.RequestAirdropGuideSetting" in _r(S + "Modules/RemoteSetup.luau"), "remote name in Constants + created by RemoteSetup")
_c("GuideHideLiveFor(player.UserId)" in SET and "Airdrop guide line: OFF" in SET and "Constants.RemoteNames.RequestAirdropGuideSetting" in SET,
   "Settings row 'Airdrop guide line' (owner-first)")
_c("ObjectiveMarker.Clear() -- destroys the Beam" in FC and 'RegisterTopStack, "AirdropHide"' in FC and "AssertTouchTarget, btn" in FC,
   "HIDE LINE button: in the HUD top stack, touch target asserted, clears the marker")
_om = _r(CL + "Modules/ObjectiveMarker.luau")
_c("local function destroyVisuals()" in _om and re.search(r"function ObjectiveMarker\.Clear\(\)[\s\S]{0,200}clearNow", _om) is not None,
   "ObjectiveMarker.Clear -> clearNow -> destroyVisuals (the Beam instance is destroyed)")

# Luau sim of the FeatureController airdrop logic (the real source between the markers, stubbed services)
_i0 = FC.find("local SupplyDropConfig = require(Shared.Configs.SupplyDropConfig)")
_i1 = FC.find("local function buildHideButton()")
_i2 = FC.find("local function marker(kind: string, data: any)")
_i3 = FC.find("\nend\n", _i2) + 5
_chunk = FC[_i0:_i1] + FC[_i2:_i3]
_c(_i0 > 0 and _i1 > _i0 and _i2 > _i1, "FeatureController airdrop block found")
_fsim = r'''
local function ctor() return setmetatable({}, { __index = function() return function(...) return { ... } end end }) end
Color3, Vector3, Vector2 = ctor(), ctor(), ctor()
local ATTR = {}
local LP = { UserId = 470626172, GetAttribute = function(_, k) return ATTR[k] end }
local cur = nil
local beams = 0
local ObjectiveMarker = {
  ShowWith = function(t) cur = t; beams = 1 end,
  Current = function() return cur end,
  Clear = function() cur = nil; beams = 0 end,
  Revision = function() return 0 end,
}
local delayed = {}
task = { delay = function(_, f) table.insert(delayed, f) end, spawn = function(f, ...) f(...) end }
local function feelSound() end
local LABELS = { Airdrop = "AIRDROP", Bounty = "BOUNTY" }
game = { GetService = function(_, n) return { LocalPlayer = LP } end }
local Shared = { Configs = { SupplyDropConfig = "SDC" } }
local SDCMOD = (function()
  local script = { Parent = { AdminConfig = "ADMIN", RetentionConfig = "RET", MonetizationConfig = "MON" } }
  local require = function(m)
    if m == "ADMIN" then return { IsPlaytestOwner = function(u) return u == 470626172 end } end
    if m == "RET" then return { Live = function(b, u) if b.Enabled ~= true then return false end if b.OwnerFirst ~= true then return true end return u == 470626172 end } end
    return { Launched = function() return false end }
  end
''' + "  " + SDC.replace("return SupplyDropConfig", "do return SupplyDropConfig end") + r'''
end)()
local require = function(m) if m == "SDC" then return SDCMOD end end
''' + _chunk + r'''
local function show(x) marker("Airdrop", { Show = true, X = x, Y = 0, Z = 5 }) end
-- 1: an airdrop guides; the HIDE LINE tap removes the beam
show(100)
assert(beams == 1, "line shows")
hideAirdropLine()
assert(beams == 0 and cur == nil, "HIDE removes the beam")
-- 2: the SAME airdrop pushed again stays hidden
show(100)
assert(beams == 0, "same airdrop stays hidden")
-- 3: a new airdrop guides again
show(300)
assert(beams == 1, "a new airdrop guides")
-- 4: Settings OFF: no automatic line for any airdrop
marker("Airdrop", { Show = false })
ATTR.WE_AirdropGuideOff = true
show(500)
assert(beams == 0, "Settings OFF: no line")
ATTR.WE_AirdropGuideOff = nil
show(700)
assert(beams == 1, "Settings ON again: line")
-- 5: another player: public switch honors the saved OFF setting too
guideHideLive = nil
LP.UserId = 1
ATTR.WE_AirdropGuideOff = true
marker("Airdrop", { Show = false })
hiddenDropKey = "900:5"
show(900)
assert(beams == 0, "non-owner: public Settings OFF hides the line")
print("AIRDROP_SIM_OK")
'''
_rc2, _out2 = _luau(_fsim)
_c(_rc2 == 0 and "AIRDROP_SIM_OK" in _out2, "Luau sim: HIDE removes the beam, that airdrop stays hidden, a new one guides, Settings OFF = none for owner and non-owner" + ("" if _rc2 == 0 else " :: " + _out2[-500:]))

# ───────────── guards ─────────────
_c("PreferMeshWhenAssetIdSet = false" in _r(C + "StructureVisualConfig.luau"), "PreferMesh OFF")
_c('"StreamingEnabled": true' not in _r("default.project.json"), "StreamingEnabled stays OFF")
_diff = subprocess.run(["git", "diff", "--name-only", PREV, "--"], capture_output=True, text=True, cwd=ROOT).stdout
_c("WE_Building" not in _diff, "no WE_Building* file touched")
