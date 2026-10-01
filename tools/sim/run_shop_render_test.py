"""codebot_v140: the REAL ShopController.Init in the Luau CLI (stand-ins: run_kit_detail_test.PRELUDE + permissive stubs
for the UI modules), then the rows that actually render in List_Supply.

Owner bug (v139): "cash packs no longer appear in the Shop". Root cause: the JOB 36 overhaul order (ShopOverhaulConfig.Order)
puts the four cash packs after ~30 pass rows, while ShopController.OpenCashPacks (the cash "+") still scrolled the list to
the TOP ("CashMega is first"), so the packs were never on screen. This test builds the Shop for the owner (overhaul live)
and for another player (old shop) and asserts:
  1. Init finishes; every cash pack row exists, is visible and shows "+$<amount> Cash".
  2. The three JOB 36 passes render for the owner only (owner-first).
  3. OpenCashPacks scrolls to the Cash Pack Mega row: CanvasPosition.Y = the heights of every visible row before it.
Run: LUAU=path/to/luau python tools/sim/run_shop_render_test.py   (SHOP_CONTROLLER=<file> tests another copy)"""
import os
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from run_kit_detail_test import PRELUDE  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
SH = ROOT / "src/ReplicatedStorage/Shared"
CTL = Path(os.environ.get("SHOP_CONTROLLER") or (ROOT / "src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ShopController.luau"))
MODS = {
    "Configs/ShopOverhaulConfig": SH / "Configs/ShopOverhaulConfig.luau",
    "Configs/MonetizationConfig": SH / "Configs/MonetizationConfig.luau",
    "Util/LivePrices": SH / "Util/LivePrices.luau",  # Code Bot v156: the real Roblox price / name (config fallback here)
    "Configs/RetentionConfig": SH / "Configs/RetentionConfig.luau",
    "Configs/AdminConfig": SH / "Configs/AdminConfig.luau",
    "Configs/PremiumGunsConfig": SH / "Configs/PremiumGunsConfig.luau",
    "Configs/WeaponConfig": SH / "Configs/WeaponConfig.luau",
    "Client/Controllers/ShopController": CTL,
}

EXTRA = r'''
ALL = {}
local newI = Instance.new
Instance.new = function(c) local i = newI(c); table.insert(ALL, i); return i end
local GUI = { Frame = true, TextLabel = true, TextButton = true, ScrollingFrame = true, ImageLabel = true, ImageButton = true }
local baseI = INST.__index
INST.__index = function(t, k)
  if k == "FindFirstChild" or k == "WaitForChild" then return function(s, n) for _, c in ipairs(rawget(s, "__kids") or {}) do if c.Name == n then return c end end return nil end end
  if k == "FindFirstChildOfClass" then return function(s, n) for _, c in ipairs(rawget(s, "__kids") or {}) do if c.ClassName == n then return c end end return nil end end
  if k == "IsA" then return function(s, c) return s.ClassName == c or c == "Instance" or (c == "GuiObject" and GUI[s.ClassName] == true) end end
  local v = baseI(t, k)
  if v == nil and k ~= "Parent" and k ~= "Visible" and k ~= "LayoutOrder" and string.match(k, "^%u") then return any end
  return v
end
local amt = getmetatable(any)
local function anyop() return any end
amt.__newindex = function() end; amt.__add = anyop; amt.__sub = anyop; amt.__mul = anyop; amt.__div = anyop; amt.__unm = anyop
amt.__concat = function() return "any" end; amt.__lt = function() return false end; amt.__le = function() return false end
amt.__len = function() return 0 end; amt.__iter = function() return function() return nil end end; amt.__tostring = function() return "any" end
Vector2 = { new = function(x, y) return { X = x, Y = y } end }
local LP = Instance.new("Player"); LP.UserId = TEST_UID; LP.Name = "tester"
LP.GetAttributeChangedSignal = function() return any end
LP.AttributeChanged = any
local PG = Instance.new("PlayerGui"); PG.Name = "PlayerGui"; PG.Parent = LP
local Players = { LocalPlayer = LP, PlayerAdded = any, PlayerRemoving = any, GetPlayers = function() return { LP } end }
local RunService = { IsStudio = function() return false end, IsServer = function() return false end, IsClient = function() return true end, Heartbeat = any, RenderStepped = any }
game = { GetService = function(_, n) if n == "ReplicatedStorage" then return RS_ elseif n == "Players" then return Players elseif n == "RunService" then return RunService end return any end, PlaceId = 1 }
task = { spawn = function() end, delay = function() end, defer = function(fn, ...) fn(...) end, wait = function() return 0 end }
-- Code Bot v156: ReplicatedStorage attributes (the live prices) + AttributeChanged for LivePrices
RS_ATTR, RS_CHANGED = {}, {}
do
  local mt = getmetatable(RS_)
  local oldIndex = mt.__index
  mt.__index = function(t, k)
    if k == "GetAttribute" then return function(_, n) return RS_ATTR[n] end end
    if k == "AttributeChanged" then return { Connect = function(_, f) table.insert(RS_CHANGED, f); return any end } end
    return oldIndex(t, k)
  end
end
SOURCES["Client/Modules/PanelShell"] = function() return setmetatable({ Text = function(n) return n end, TouchMinV = function() return 44 end }, { __index = function() return any end }) end
'''

TEST = r'''
local fails = 0
local function check(ok, msg) print((ok and "ok    " or "FAIL  ") .. msg); if not ok then fails += 1 end end
-- claude-bud JOB 42: TIME_IDS = the five time-pack Ids pasted (TimePacksReady); shown only where TimePacks is live
local TIMEKEYS = { "Cash4h", "Cash2h", "Cash1h", "Cash30m", "Cash15m" }
if TIME_IDS then
  local MCx = require(node("Configs/MonetizationConfig"))
  for i, k in ipairs(TIMEKEYS) do MCx.DevProducts[k].Id = 800 + i end
end
local SOx = require(node("Configs/ShopOverhaulConfig"))
local timeShown = TIME_IDS and SOx.TimePacksShown(TEST_UID)
local SC = SOURCES["Client/Controllers/ShopController"](node("Client/Controllers/ShopController"))
local ok, err = xpcall(SC.Init, debug.traceback)
check(ok, "uid " .. TEST_UID .. ": ShopController.Init finishes " .. tostring(err or ""))
local list
for _, i in ipairs(ALL) do if i.Name == "List_Supply" then list = i end end
check(list ~= nil, "List_Supply built")
local function P(x, k) return rawget(x, "__props")[k] end
local rows, byName = {}, {}
for _, c in ipairs(list and list:GetChildren() or {}) do
  if c.ClassName == "Frame" and string.sub(c.Name, 1, 8) == "ShopRow_" then table.insert(rows, c); byName[c.Name] = c end
end
table.sort(rows, function(a, b) return P(a, "LayoutOrder") < P(b, "LayoutOrder") end)
local names = {}
for _, r in ipairs(rows) do table.insert(names, (string.gsub(r.Name, "ShopRow_", ""))) end
print("        rows: " .. table.concat(names, " > "))
-- Code Bot v156: a cash pack row now reads "Get $50,000 cash right away" (plain words; was "+$50,000 Cash")
local function subText(r) for _, c in ipairs(r:GetChildren()) do if c.ClassName == "TextLabel" and type(P(c, "Text")) == "string" and string.sub(P(c, "Text"), 1, 5) == "Get $" then return P(c, "Text") end end return nil end
if not timeShown then
for _, k in ipairs({ "CashMega", "CashLarge", "CashMedium", "CashSmall" }) do
  local r = byName["ShopRow_" .. k]
  check(r ~= nil and P(r, "Visible") ~= false and P(r, "Parent") == list and subText(r) ~= nil, k .. " row renders (" .. tostring(r and subText(r)) .. ")")
end
for _, k in ipairs(TIMEKEYS) do check(byName["ShopRow_" .. k] == nil, k .. ": no time row while the time packs are not shown (OFF == OLD)") end
else
  local function lblT(r, n) for _, c in ipairs(r:GetChildren()) do if c.ClassName == "TextLabel" and c.Name == n then return tostring(P(c, "Text")) end end return "" end
  local function btnT(r) for _, c in ipairs(r:GetChildren()) do if c.ClassName == "TextButton" then return tostring(P(c, "Text")) end end return "" end
  local want = { Cash4h = { "BEST VALUE · 4 HOURS OF CASH", "$200,000 (minimum)", "279 R$" }, Cash2h = { "2 HOURS OF CASH", "$100,000 (minimum)", "159 R$" },
    Cash1h = { "1 HOUR OF CASH", "$50,000 (minimum)", "89 R$" }, Cash30m = { "30 MIN OF CASH", "$25,000 (minimum)", "49 R$" }, Cash15m = { "15 MIN OF CASH", "$10,000 (minimum)", "25 R$" } }
  local lastOrder = -math.huge
  for _, k in ipairs(TIMEKEYS) do
    local r = byName["ShopRow_" .. k]
    local w = want[k]
    check(r ~= nil and lblT(r, "Title") == w[1] and lblT(r, "Sub") == w[2] and btnT(r) == w[3],
      k .. " time row: " .. (r and (lblT(r, "Title") .. " | " .. lblT(r, "Sub") .. " | " .. btnT(r)) or "missing"))
    if r then check(P(r, "LayoutOrder") > lastOrder, k .. " in order (4h first)"); lastOrder = P(r, "LayoutOrder") end
  end
  for _, k in ipairs({ "CashMega", "CashLarge", "CashMedium", "CashSmall" }) do check(byName["ShopRow_" .. k] == nil, k .. ": the old pack is hidden while the time packs are shown") end
end
-- codebot_v142: ShopOverhaulConfig.Live.OwnerFirst = false -> the new shop for everyone (owner and uid 9 alike)
local live = true
for _, k in ipairs({ "WarChest", "SuperSoldiers", "DoubleHP" }) do
  check((byName["ShopRow_Pass_" .. k] ~= nil) == live, k .. " row renders for uid " .. TEST_UID .. " (overhaul live for everyone)")
end
-- codebot_v142: the VIP row shows the real Creator Hub price (199), never 349
local function texts(x, out) for _, c in ipairs(x:GetChildren()) do local t = P(c, "Text"); if type(t) == "string" then table.insert(out, t) end; texts(c, out) end return out end
local vip = byName["ShopRow_Pass_VIP"]
local vt = if vip then table.concat(texts(vip, {}), " | ") else ""
check(vip ~= nil and string.find(vt, "199 R$", 1, true) ~= nil and string.find(vt, "349", 1, true) == nil, "VIP row shows 199 R$ (not 349): " .. vt)
check(vip ~= nil and string.find(vt, "PERMANENT", 1, true) ~= nil, "VIP row is the overhaul row (PERMANENT)")
-- Code Bot v156: every Robux row: the real price / name, plain words, nothing a phone (1024x471) would truncate
local function lbl(r, n) for _, c in ipairs(r:GetChildren()) do if c.ClassName == "TextLabel" and c.Name == n then return tostring(P(c, "Text")) end end return "" end
local function btnText(r) for _, c in ipairs(r:GetChildren()) do if c.ClassName == "TextButton" then return tostring(P(c, "Text")) end end return "" end
for _, r in ipairs(rows) do
  local t, s, b = lbl(r, "Title"), lbl(r, "Sub"), btnText(r)
  print(string.format("        ROW %s | %s | %s | %s", string.gsub(r.Name, "ShopRow_", ""), t, s, b))
  check(string.find(t .. s, "ProcessReceipt", 1, true) == nil and string.find(t .. s, "Grants ", 1, true) == nil, r.Name .. ": no developer text")
  -- phone 1024x471: HUD scale 0.70 -> the panel caps at 900 v; the text column is 900 - 32 - 170 = ~698 v. GothamMedium /
  -- GothamBold at 20 v run ~11-12 v a character, so <= 56 characters always fits (the budget used here)
  check(utf8.len(s) ~= nil and utf8.len(s) <= 56, r.Name .. ": sub fits a phone row (" .. tostring(utf8.len(s)) .. " chars)")
  check(utf8.len(t) ~= nil and utf8.len(t) <= 48, r.Name .. ": title fits a phone row (" .. tostring(utf8.len(t)) .. " chars)")
end
local sb = byName["ShopRow_StarterBundle"]
check(sb ~= nil and lbl(sb, "Title") == "Commander Starter Bundle" and btnText(sb) == "249 R$", "Starter row = the Roblox product: Commander Starter Bundle 249 R$ (" .. (sb and (lbl(sb, "Title") .. " " .. btnText(sb)) or "none") .. ")")
check(sb ~= nil and lbl(sb, "Sub") == "$50,000 cash plus Auto Collect forever", "Starter row says what you get")
local bp = byName["ShopRow_PremiumPass"]
check(bp ~= nil and lbl(bp, "Sub") == "Unlock premium rewards on every Battle Pass tier" and btnText(bp) == "499 R$", "Battle Pass Premium row: plain words, 499 R$")
-- the live Roblox price wins over the config value (the server publishes WE_Px_* on ReplicatedStorage)
RS_ATTR["WE_Px_DP_CashSmall"] = 59
RS_ATTR["WE_PxN_DP_CashSmall"] = "Cash Pack S (live)"
for _, f in ipairs(RS_CHANGED) do f("WE_Px_DP_CashSmall") end
local cs = byName["ShopRow_CashSmall"]
if not timeShown then
check(cs ~= nil and btnText(cs) == "59 R$" and lbl(cs, "Title") == "Cash Pack S (live)", "a live price / name that arrives later updates the row (" .. (cs and (lbl(cs, "Title") .. " " .. btnText(cs)) or "none") .. ")")
end
RS_ATTR["WE_Px_DP_CashSmall"] = nil
RS_ATTR["WE_PxN_DP_CashSmall"] = nil
for _, f in ipairs(RS_CHANGED) do f("WE_Px_DP_CashSmall") end
-- the cash "+": OpenCashPacks scrolls to the Mega row
SC.OpenCashPacks()
local mega = byName[if timeShown then "ShopRow_Cash4h" else "ShopRow_CashMega"] -- claude-bud JOB 42: the + lands on 4h while shown
local want = 0
for _, c in ipairs(list:GetChildren()) do
  if c ~= mega and type(P(c, "LayoutOrder")) == "number" and P(c, "LayoutOrder") < P(mega, "LayoutOrder") and P(c, "Visible") ~= false then
    want += (tonumber(c:GetAttribute("WE_RowH")) or 0) + 6
  end
end
local cp = P(list, "CanvasPosition")
check(cp ~= nil and cp.Y == want, "OpenCashPacks scrolls to " .. (if timeShown then "4 HOURS OF CASH" else "Cash Pack Mega") .. ": CanvasPosition.Y=" .. tostring(cp and cp.Y) .. " want " .. want)
if live then check(want > 1000, "uid " .. TEST_UID .. ": Mega sits " .. want .. " px down (after the passes): reachable through the cash + scroll") end
print(string.format("SHOP RENDER TEST uid %d%s: %d failed", TEST_UID, if TIME_IDS then " (time Ids)" else "", fails))
if fails > 0 then error("failed") end
'''


def run(uid: int, time_ids: bool = False) -> bool:
    pre = PRELUDE.replace('game = { GetService = function(_, n) if n == "ReplicatedStorage" then return RS end return any end }',
                          'RS_ = RS\ngame = { GetService = function(_, n) if n == "ReplicatedStorage" then return RS end return any end }')
    pre = pre.replace("  return realRequire(n)\nend", "  return any\nend")
    chunks = ["TEST_UID = %d\nTIME_IDS = %s" % (uid, "true" if time_ids else "false"), pre, EXTRA]
    for key, path in MODS.items():
        chunks.append("SOURCES[%r] = function(script)\n%s\nend" % (key, path.read_text(encoding="utf-8")))
    chunks.append(TEST)
    with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False, encoding="utf-8") as f:
        f.write("\n".join(chunks))
        path = f.name
    r = subprocess.run([os.environ.get("LUAU", "luau"), path], capture_output=True, text=True)
    out = r.stdout.strip()
    print(out if os.environ.get("VERBOSE") else "\n".join(l for l in out.splitlines() if l.startswith("FAIL") or l.startswith("SHOP RENDER")) or out)
    if r.returncode != 0:
        print(r.stderr.strip()[-2500:])
    return r.returncode == 0


if __name__ == "__main__":
    # claude-bud JOB 42: + the five time-pack Ids pasted: the owner (TimePacks live) sees the time rows, uid 9 the old ones
    ok = run(470626172) & run(9) & run(470626172, True) & run(9, True)
    sys.exit(0 if ok else 1)
