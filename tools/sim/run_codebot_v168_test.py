"""Code Bot v168 (Shaun 2026-10-01): the four owner asks, on the REAL modules (Luau CLI, stand-ins only around them).

A. TARGETS card + list (RivalService + RivalConfig + the real ArmySendRules verdict; harness run_rival_targets_test):
   every row carries the victim's Level; the card's lines = the server's suggested rival (rows[1]): name, distance,
   loot bucket; empty = "No target now" + a short reason for every WhyText; row lines name / Lv / Army / loot +
   distance; RivalConfig.Layout on a 1024x471 phone (topbar inset 58): the card is under the compass / BASE row,
   right of the centred top stack (toasts), above the MED KIT side button, the ammo readout, RELOAD / scope and
   FIRE; the 3-row list ends above the content bottom; every text column fits its longest line. 844x390 / 800x360 too.
B. /setrebirth (the real PrestigeService + AdminService on stubs): the admin's chat line and the Settings remote set
   profile.Prestige to N, Cash / Level / XP / BaseUpgrades / Gold untouched, the rebirth unlock flags + granted items
   follow (lowering keeps the items), SaveProfile is called, the pushes run; a non-admin's line does nothing;
   leaderboards exclude the admin (static on EngagementService).
C. Billboard overlap (the real ObjectiveMarker.BoxesOverlap + RebirthZoneBuilder.Locked): the "EAST YARD / Unlocks at
   Rebirth 5" sign is tagged WE_ObjectiveYield; the screenshot's AIRDROP label box over the sign box overlaps -> the
   label steps aside; apart -> shown.
D. Intel Office guidance (the real EndgameService, harness run_endgame_test; the real client Modules/IntelGuide.Decide):
   a done daily contract / weekly HVT sets WE_IntelGuide to the Intel Office NPC point; the claim clears it; a stale
   day does not guide; not live = nothing; the client shows INTEL OFFICE on the one tracker at completion, re-shows
   only when the tracker is free and he is away, clears only its own marker.
Run: LUAU=path/to/luau python tools/sim/run_codebot_v168_test.py   (exit 1 on any failure; VERBOSE=1 prints all)"""
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
LUAU = os.environ.get("LUAU", "luau")
FAILS = []
SH = ROOT / "src/ReplicatedStorage/Shared"
SV = ROOT / "src/ServerScriptService/Server"
CL = ROOT / "src/StarterPlayer/StarterPlayerScripts/Client"


def run(name, prelude, extra, mods, test, marker):
    chunks = [prelude, extra]
    for key, path in mods.items():
        chunks.append("SOURCES[%r] = function(script)\n%s\nend" % (key, Path(path).read_text(encoding="utf-8")))
    chunks.append(test)
    with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False, encoding="utf-8") as f:
        f.write("\n".join(chunks))
        path = f.name
    r = subprocess.run([LUAU, path], capture_output=True, text=True, timeout=300)
    os.unlink(path)
    out = (r.stdout + r.stderr).strip()
    ok = r.returncode == 0 and (marker + ": 0 failed") in out
    if not ok and os.environ.get("DEBUG"):
        print("rc", r.returncode, out[-1500:])
    lines = out.splitlines()
    shown = lines if os.environ.get("VERBOSE") else [l for l in lines if l.startswith("FAIL") or marker in l or "error" in l.lower()]
    print("\n".join(shown) or out[-2500:])
    if not ok:
        FAILS.append(name)


def check_static(label, cond):
    print(("ok    " if cond else "FAIL  ") + label)
    if not cond:
        FAILS.append(label)


# ── A. TARGETS ──────────────────────────────────────────────────────────────────────────────────────────────────
import run_rival_targets_test as RT  # noqa: E402

A_TEST = r'''
local fails = 0
local function check(ok, msg) print((ok and "ok    " or "FAIL  ") .. msg); if not ok then fails += 1 end end
local RC = require(node("Configs/RivalConfig"))
local RS = require(node("Services/RivalService"))
LEVELS = { [5005] = 23, [5008] = 41, [5009] = 7 }
DEPS.DataService = { GetProfile = function(p) return { Level = LEVELS[p.UserId] or 1 } end }
RS.Init(DEPS)
FACTS = {}
for i = 1, 9 do FACTS[i] = facts() end
FACTS[1] = facts({ ShieldLeft = 300 }); FACTS[2] = facts({ Ally = true }); FACTS[3] = facts({ NewPlayerLeft = 200 }); FACTS[4] = facts({ ArmyPower = 100 })
FACTS[8] = facts({ ArmyPower = 5000 })
BAL = { [5005] = 2e6, [5006] = 10000, [5007] = 300000, [5008] = 2e6, [5009] = 300000 }
PUSHES = {}
RS.Tick()
local rows
for _, e in ipairs(PUSHES) do if e.p == VIEWER and e.kind == "RivalTargets" then rows = e.data.Rows end end
check(rows ~= nil and #rows == 3, "the server still pushes the top 3 (" .. tostring(rows and #rows) .. ")")
check(rows[1].PlotId == 5 and rows[1].Level == 23 and rows[2].Level == 41 and rows[3].Level == 7, "every row carries the victim's level (23 / 41 / 7)")
local exact = false
for _, r in ipairs(rows) do for _, v in pairs(r) do if type(v) == "number" and v >= 1000 and v ~= r.Dist then exact = true end end end
check(not exact and type(rows[1].Loot) == "string", "still never the exact loot number")
-- the card (suggested rival = rows[1])
local L = RC.PillLines(rows, nil)
check(L.Has and L.Count == 3 and L.Name == "Rival5" and L.Detail == "500m · $100k+", "card: 'TARGETS' 3 / 'Rival5' / '500m · $100k+' (" .. L.Detail .. ")")
local far = RC.PillLines({ { Name = "Far", Dist = 1460, Loot = "$10k+" } }, nil)
check(far.Detail == "1.5km · $10k+" and RC.DistText(95) == "95m" and RC.DistText(1000) == "1.0km", "distance like the compass pill: 95m / 1.0km / 1.5km")
check(RC.PillLines({ { Name = "X", Dist = 0, Loot = "$1k+" } }, nil).Detail == "$1k+ loot", "no base of his own (dist 0): just the loot")
local E = RC.PillLines({}, RC.WhyText.Alone)
check(not E.Has and E.Count == 0 and E.Name == "No target now" and E.Detail == RC.ShortWhy.Alone, "empty card: 'No target now' + '" .. E.Detail .. "'")
local allShort, longest = true, 0
for key, full in pairs(RC.WhyText) do
  local s = RC.PillLines({}, full).Detail
  longest = math.max(longest, utf8.len(s))
  if s ~= RC.ShortWhy[key] or utf8.len(s) > 16 then allShort = false end
end
check(allShort and RC.PillLines({}, nil).Detail == RC.ShortWhyDefault, "every server reason has a short card reason <= 16 chars (longest " .. longest .. ")")
local R = RC.RowLines(rows[2])
check(R.Name == "Rival8" and R.Level == "Lv 41" and R.Army == "Army 12" and R.Loot == "$10k+ loot" and R.Dist == "200m" and R.Chip == "EASY",
  string.format("row: %s / %s / %s / %s · %s / %s", tostring(R.Name), tostring(R.Level), tostring(R.Army), tostring(R.Loot), tostring(R.Dist), tostring(R.Chip)))
-- geometry (real px). Screen = content + the 58 px topbar inset on top.
local function geo(W, H, inset)
  local cw, ch = W, H - inset
  local G = RC.Layout(cw, ch, 3)
  local S = 0.70 -- HudLayout.Scale: clamp(min(W,H)/800, 0.70, 1.15)
  local p = { x0 = G.Pill.X, y0 = inset + G.Pill.Y, x1 = G.Pill.X + G.Pill.W, y1 = inset + G.Pill.Y + G.Pill.H }
  local l = { x0 = G.List.X, y0 = inset + G.List.Y, x1 = G.List.X + G.List.W, y1 = inset + G.List.Y + G.List.H }
  local stackRight = cw / 2 + cw * 0.62 / 2 -- HudConfig.TopStack.MaxWidthScale, centred in the content rect
  local medTop = inset + ch * 0.42 - 64 * S / 2 -- EndgameController MED KIT: (1,-12, 0.42) AnchorY 0.5, TAP 64 v
  local ammoTop = H - (252 + 60) * S -- HudConfig.Ammo BottomTouch + SizeTouch.Y
  local scopeTop = H - (152 + 64 + 12 + 56) * S -- RELOAD + the scope button above it
  local fireTop = H - (152 + 88) * S
  return G, p, l, stackRight, medTop, ammoTop, scopeTop, fireTop
end
for _, vp in ipairs({ { 1024, 471 }, { 844, 390 }, { 800, 360 }, { 956, 440 } }) do
  local W, H = vp[1], vp[2]
  local G, p, l, stackRight, medTop, ammoTop, scopeTop, fireTop = geo(W, H, 58)
  local tag = W .. "x" .. H
  check(p.y0 >= 58 + 6, tag .. ": the card (top " .. p.y0 .. ") is under the topbar row (the compass / BASE pill ends at 56)")
  check(p.x0 > stackRight, string.format("%s: the card (x %d) is right of the centred top stack / toasts (x %.0f)", tag, p.x0, stackRight))
  check(p.x1 <= W - 8, tag .. ": the card stays on screen (right " .. p.x1 .. ")")
  check(p.y1 + 8 <= medTop and p.y1 + 8 <= ammoTop and p.y1 + 8 <= scopeTop and p.y1 + 16 <= fireTop,
    string.format("%s: the card (bottom %d) clears MED KIT %.0f, ammo %.0f, scope %.0f, FIRE %.0f", tag, p.y1, medTop, ammoTop, scopeTop, fireTop))
  check(p.y1 - p.y0 >= 44 and G.Pill.W >= RC.Pill.MinWidth, tag .. ": a >= 44 px tap target, " .. G.Pill.W .. " px wide")
  check(l.y1 <= H - 4 and l.x0 >= 0 and l.y0 >= 58, string.format("%s: the 3-row list (y %d..%d) fits the screen", tag, l.y0, l.y1))
  check(G.Pill.TextW >= 98 and G.Pill.TitleW >= 70, tag .. ": card text column " .. G.Pill.TextW .. " px (title " .. G.Pill.TitleW .. ")")
  check(G.List.H >= RC.List.Header + 3 * (RC.List.RowHeight + RC.List.RowGap), tag .. ": the list is tall enough for 3 rows (no clipping)")
end
local G = RC.Layout(1024, 413, 3)
check(G.Pill.W == 180, "1024x471: the card is 180 px wide (" .. G.Pill.W .. ")")
-- text fit: GothamBold ~0.62 px per px of size per char (the widest common glyphs), the card's text column
check(G.Pill.Icon == 30, "1024x471: the big 30 px crosshair beside the lines")
check(RC.Layout(844, 332, 3).Pill.Icon == RC.Pill.SmallIcon, "844x390: a smaller crosshair in the title row, lines use the width")
-- text fit (GothamBold em widths: narrow . , : · space i l I 0.3, wide m M W 0.9, the rest 0.64 to stay pessimistic)
local function width(s, px)
  local w = 0
  for _, c in utf8.codes(s) do
    local ch = utf8.char(c)
    if ch:match("[%.,:%s il|I]") or ch == "·" then w += 0.3 elseif ch:match("[mMW]") then w += 0.9 else w += 0.64 end
  end
  return w * px
end
local function fits(s, px, w) return width(s, px) <= w end
for _, cw in ipairs({ { 1024, 413 }, { 956, 382 }, { 844, 332 }, { 800, 302 } }) do
  local P = RC.Layout(cw[1], cw[2], 3).Pill
  check(fits("TARGETS", 16, P.TitleW) and fits("1.5km · $100k+", 14, P.TextW) and fits("No target now", 15, P.TextW) and fits("Check back soon", 14, P.TextW),
    string.format("%dx%d: the card's lines fit (text %d px, title %d px)", cw[1], cw[2] + 58, P.TextW, P.TitleW))
end
local rowW = RC.List.Width - 16
local textW = rowW - 10 - RC.List.SendWidth - RC.List.ViewWidth - 24
check(fits("$100k+ loot · 1.5km", 14, textW) and fits("Army 12345", 14, textW - 64) and fits("Lv 123", 14, 50) and fits("SEND ARMY", 15, RC.List.SendWidth) and RC.List.ButtonHeight >= 44,
  "the list row: loot + distance fits " .. textW .. " px; SEND ARMY / VIEW are >= 44 px tall")
print(string.format("V168 TARGETS TEST: %d failed", fails))
if fails > 0 then error("failed") end
'''
run("A targets", RT.PRELUDE, RT.EXTRA, RT.MODS, A_TEST, "V168 TARGETS TEST")
ctl = (CL / "Controllers/RivalController.luau").read_text(encoding="utf-8")
check_static("RivalController draws RivalConfig.PillLines / RowLines / Layout (the tested strings and numbers)",
             "RivalConfig.PillLines(rows, why)" in ctl and "RivalConfig.RowLines(r)" in ctl and "RivalConfig.Layout(cs.X, cs.Y, #rows)" in ctl)
check_static("RivalController: crosshair icon, the content rect (IgnoreGuiInset false + CoreUISafeInsets), SEND = JOB 38 remote, VIEW = map",
             "local function crosshair(" in ctl and "g.IgnoreGuiInset = false" in ctl and "Enum.ScreenInsets.CoreUISafeInsets" in ctl
             and "Remotes.FireServer, Constants.RemoteNames.RequestArmySend, plotId" in ctl and "MC.OpenBase(plotId)" in ctl
             and "PivotTo" not in ctl and "Teleport" not in ctl)
check_static("RivalController: no text under 14 px", all(int(n) >= 14 for n in re.findall(r"TextSize = (\d+)", ctl)) and all(int(n) >= 14 for n in re.findall(r", (\d+), Enum\.Font\.", ctl)))

# ── B. /setrebirth ──────────────────────────────────────────────────────────────────────────────────────────────
from run_kit_detail_test import PRELUDE  # noqa: E402
B_MODS = {
    "Constants": SH / "Constants.luau",
    "Configs/PrestigeConfig": SH / "Configs/PrestigeConfig.luau",
    "Configs/RebirthConfig": SH / "Configs/RebirthConfig.luau",
    "Configs/RetentionConfig": SH / "Configs/RetentionConfig.luau",
    "Configs/AdminConfig": SH / "Configs/AdminConfig.luau",
    "Configs/BaseConfig": SH / "Configs/BaseConfig.luau",
    "Configs/BaseLayoutConfig": SH / "Configs/BaseLayoutConfig.luau",
    "Configs/EconomyConfig": SH / "Configs/EconomyConfig.luau",
    "Configs/VehicleConfig": SH / "Configs/VehicleConfig.luau",
    "Configs/WeaponConfig": SH / "Configs/WeaponConfig.luau",
    "Modules/RemoteGuard": SV / "Modules/RemoteGuard.luau",
    "Services/PrestigeService": SV / "Services/PrestigeService.luau",
    "Services/AdminService": SV / "Services/AdminService.luau",
}
B_EXTRA = r'''
RUN_SPAWN = false
SPAWNED = 0
task = { spawn = function(fn, ...) if RUN_SPAWN and type(fn) == "function" then SPAWNED += 1; fn(...) end end, wait = function() end, delay = function() end, defer = function() end }
local function signal() local s = { fns = {} }; s.Connect = function(self, fn) table.insert(self.fns, fn); return { Disconnect = function() end } end; return s end
function mkPlayer(uid, name)
  local p = { UserId = uid, Name = name, DisplayName = name, Parent = true, attrs = {}, Chatted = signal() }
  p.SetAttribute = function(self, k, v) self.attrs[k] = v end
  p.GetAttribute = function(self, k) return self.attrs[k] end
  p.Kick = function() end
  return p
end
SHAUN = mkPlayer(470626172, "shaunie6")
RANDO = mkPlayer(424242, "Rando")
local Players = { PlayerAdded = signal(), PlayerRemoving = signal(), GetPlayers = function() return {} end, LocalPlayer = SHAUN,
  GetPlayerByUserId = function(_, u) if u == SHAUN.UserId then return SHAUN elseif u == RANDO.UserId then return RANDO end end }
local RunService = { IsStudio = function() return false end }
local prevGame = game
game = { GetService = function(_, n)
  if n == "Players" then return Players elseif n == "RunService" then return RunService end
  return prevGame:GetService(n) end }
'''
B_TEST = r'''
local fails = 0
local function check(ok, msg) print((ok and "ok    " or "FAIL  ") .. msg); if not ok then fails += 1 end end
local PC = require(node("Configs/PrestigeConfig"))
local PS = require(node("Services/PrestigeService"))
local AS = require(node("Services/AdminService"))
local profiles = {}
local function prof() return { Cash = 123456789, Gold = 777, Level = 64, XP = 4321, Prestige = 2, BaseUpgrades = { CommandCenter = 5, Barracks = 3 },
  Vehicles = { Jeep = true }, Weapons = { M4 = true }, RebirthUnlocks = {}, KeepBaseRebirths = 0, Endgame = { EmpireLevel = 9 } } end
profiles[SHAUN.UserId] = prof()
profiles[RANDO.UserId] = prof()
local log = { dirty = 0, saved = 0, eco = 0, xp = 0, base = 0, fired = 0, notes = {}, grants = {} }
local remotes = {}
local function remote(name)
  if remotes[name] == nil then
    local r = { OnServerEvent = { fns = {} }, IsA = function(_, c) return c == "RemoteEvent" end }
    r.OnServerEvent.Connect = function(self, fn) table.insert(self.fns, fn) end
    r.FireClient = function() log.fired += 1 end
    remotes[name] = r
  end
  return remotes[name]
end
local deps = {
  DataService = { GetProfile = function(p) return profiles[p.UserId] end, MarkDirty = function() log.dirty += 1 end, OnProfileLoaded = function() end,
    SaveProfile = function(p) log.saved += 1; return true end },
  EconomyService = { Push = function() log.eco += 1 end, AddGold = function() error("no gold for an admin set") end, AddCash = function() error("no cash") end,
    SyncOutpostIncomeStacks = function() end },
  XPService = { Push = function() log.xp += 1 end, SetLevel = function() end, AddXP = function() end },
  BaseService = { PushState = function() log.base += 1 end },
  VehicleService = { GrantVehicle = function(p, id) table.insert(log.grants, id) end },
  NotificationService = { Notify = function(p, text) table.insert(log.notes, { p = p, text = text }) end },
  RateLimitService = { Allow = function() return true end },
  AnalyticsService = { Log = function() end },
  RemoteSetup = { Get = function(n) return remote(n) end },
  MonetizationService = {},
}
deps.PrestigeService = PS
PS.Init(deps)
AS.Init(deps)
RUN_SPAWN = true
local before = table.clone(profiles[SHAUN.UserId])
local bu = table.clone(before.BaseUpgrades)
-- the chat line
AS._OnAdminChat(SHAUN, "/setrebirth 10")
local p = profiles[SHAUN.UserId]
check(p.Prestige == 10, "/setrebirth 10: profile.Prestige = 10 (" .. tostring(p.Prestige) .. ")")
check(p.Cash == before.Cash and p.Gold == before.Gold and p.Level == before.Level and p.XP == before.XP and p.BaseUpgrades.CommandCenter == bu.CommandCenter
  and p.BaseUpgrades.Barracks == bu.Barracks and p.Endgame.EmpireLevel == 9 and p.Vehicles.Jeep and p.Weapons.M4,
  "cash, gold, level, XP, base upgrades, Empire and owned items untouched")
local want, extra, grantsOk = 0, 0, true
for _, u in ipairs(PC.RebirthUnlocks) do
  if u.Gate == nil then
    if u.AtPrestige <= 10 then
      want += 1
      if p.RebirthUnlocks[u.Flag] ~= true then grantsOk = false end
      if u.GrantOwned and u.Kind == "Weapon" and p.Weapons[u.Id] ~= true then grantsOk = false end
      if u.GrantOwned and u.Kind == "Vehicle" and p.Vehicles[u.Id] ~= true then grantsOk = false end
    elseif p.RebirthUnlocks[u.Flag] then extra += 1 end
  end
end
check(grantsOk and extra == 0 and want > 0, "every R1-R10 rebirth unlock flag (" .. want .. ") + its granted vehicle / gun, nothing above R10")
check(log.dirty >= 1 and log.saved == 1, "MarkDirty + SaveProfile at once (saved " .. log.saved .. ")")
check(log.eco >= 1 and log.xp >= 1 and log.base >= 1 and log.fired >= 1, "cash / XP / base / rebirth-state pushes ran (multiplier, prices, the Rebirth panel)")
check(#log.notes > 0 and string.find(log.notes[#log.notes].text, "rebirth set to 10", 1, true) ~= nil, "reply: '" .. tostring(log.notes[#log.notes] and log.notes[#log.notes].text) .. "'")
-- the Settings > ADMIN > SET REBIRTH button (the remote)
local h = remotes["RequestAdminCommand"].OnServerEvent.fns[1]
log.saved = 0
h(SHAUN, "setrebirth", 3)
check(p.Prestige == 3 and log.saved == 1, "Settings SET REBIRTH 3 (remote): Prestige 3, saved")
local above = 0
for _, u in ipairs(PC.RebirthUnlocks) do if u.AtPrestige > 3 and p.RebirthUnlocks[u.Flag] then above += 1 end end
check(above == 0 and p.Vehicles.Jeep and p.Cash == before.Cash, "lowering: flags above R3 cleared; items + cash kept")
h(SHAUN, "setrebirth", 999)
check(p.Prestige == PC.MaxPrestige, "clamped to MaxPrestige " .. PC.MaxPrestige)
AS._OnAdminChat(SHAUN, "/setrebirth abc")
check(p.Prestige == PC.MaxPrestige and string.find(log.notes[#log.notes].text, "Usage", 1, true) ~= nil, "junk argument: usage reply, unchanged")
AS._OnAdminChat(SHAUN, "/setrebirth 10")
check(p.Prestige == 10, "back to 10 for Shaun")
-- not an admin
local rp = profiles[RANDO.UserId]
AS._OnAdminChat(RANDO, "/setrebirth 30")
h(RANDO, "setrebirth", 30)
check(rp.Prestige == 2, "a non-admin's /setrebirth (chat or remote) does nothing")
print(string.format("V168 SETREBIRTH TEST: %d failed", fails))
if fails > 0 then error("failed") end
'''
run("B setrebirth", PRELUDE, B_EXTRA, B_MODS, B_TEST, "V168 SETREBIRTH TEST")
eng = (SV / "Services/EngagementService.luau").read_text(encoding="utf-8")
adm = (SH / "Configs/AdminConfig.luau").read_text(encoding="utf-8")
ads = (SV / "Services/AdminService.luau").read_text(encoding="utf-8")
check_static("leaderboards: the admin / owner is excluded at write (isBoardExcluded before any SetAsync) and 470626172 is an admin",
             "if isBoardExcluded(player.UserId) then" in eng and "470626172" in adm)
check_static("/setrebirth only after AdminService.IsAdmin (chat) and the allowlist check (remote); not a Studio-open money command",
             ads.index("if not AdminService.IsAdmin(player) then") < ads.index("local isSetRebirthCmd") and 'elseif cmd == "setrebirth" then' in ads
             and '"setrebirth"' not in adm)

# ── C. billboard overlap ────────────────────────────────────────────────────────────────────────────────────────
import run_rebirth_test as RB  # noqa: E402
C_MODS = dict(RB.MODS)
C_MODS["Configs/ConsoleBuyConfig"] = SH / "Configs/ConsoleBuyConfig.luau"
C_MODS["Configs/WorldLabelConfig"] = SH / "Configs/WorldLabelConfig.luau"
C_MODS["Modules/ObjectiveMarker"] = CL / "Modules/ObjectiveMarker.luau"
C_TEST = r'''
local fails = 0
local function check(ok, msg) print((ok and "ok    " or "FAIL  ") .. msg); if not ok then fails += 1 end end
local tags = {}
local G0 = game
game = { GetService = function(_, n)
  if n == "CollectionService" then return { AddTag = function(_, inst, tag) table.insert(tags, { inst = inst, tag = tag }) end } end
  return G0:GetService(n) end }
local B = require(node("Modules/RebirthZoneBuilder"))
local folder = Instance.new("Folder")
B.Locked("EastYard", 5, CFrame.new(0, 0.5, 0), 74, 60, folder)
local sign
for _, d in ipairs(folder:GetDescendants()) do if d.ClassName == "BillboardGui" and d.Name == "WE_ZoneLockedSign" then sign = d end end
local tagged = false
for _, t in ipairs(tags) do if t.inst == sign and t.tag == "WE_ObjectiveYield" then tagged = true end end
check(sign ~= nil and tagged, "the locked-zone sign ('EAST YARD / Unlocks at Rebirth 5') is tagged WE_ObjectiveYield")
local WLC = require(node("Configs/WorldLabelConfig"))
check(WLC.ObjectiveYieldTag == "WE_ObjectiveYield", "WorldLabelConfig.ObjectiveYieldTag = the builder's tag")
game = G0
local OM = require(node("Modules/ObjectiveMarker"))
-- screenshot-like: the sign 190x44 at (512, 210); the AIRDROP label (7 chars: 7*12+16 = 100 wide clamped, 44 tall)
local W = require(node("Configs/ConsoleBuyConfig")).Waypoint
local mw = math.clamp(7 * 12 + 16, W.MarkerMinWidth, W.MarkerMaxWidth)
local pad = WLC.ObjectiveYieldPadPx
check(OM.BoxesOverlap(530, 226, mw, 44, 512, 210, 190, 44, pad), "AIRDROP 1.8km drawn on the sign: overlap -> the label steps aside")
check(not OM.BoxesOverlap(512, 120, mw, 44, 512, 210, 190, 44, pad), "AIRDROP well above the sign: shown")
check(not OM.BoxesOverlap(760, 210, mw, 44, 512, 210, 190, 44, pad), "AIRDROP beside the sign: shown")
check(OM.BoxesOverlap(512 + 95 + mw / 2 + 2, 210, mw, 44, 512, 210, 190, 44, pad), "2 px apart: still yields (the pad keeps a clear gap)")
print(string.format("V168 OVERLAP TEST: %d failed", fails))
if fails > 0 then error("failed") end
'''
run("C overlap", RB.PRELUDE if hasattr(RB, "PRELUDE") else PRELUDE, RB.EXTRA, C_MODS, C_TEST, "V168 OVERLAP TEST")
om = (CL / "Modules/ObjectiveMarker.luau").read_text(encoding="utf-8")
check_static("ObjectiveMarker: only the LABEL yields (mOn = on and not covered; the GO line keeps `on`), checked in step at <= 10 Hz, tag signals (no tree scan)",
             "local mOn = on and not covered" in om and "local cv = coversSign()" in om and "GetInstanceAddedSignal(tag)" in om
             and "inst.MaxDistance" in om and "GetDescendants" not in om)

# ── D. Intel Office guidance ────────────────────────────────────────────────────────────────────────────────────
import run_endgame_test as EGT  # noqa: E402
D_MODS = dict(EGT.MODS)
D_MODS["Modules/IntelGuide"] = CL / "Modules/IntelGuide.luau"
D_TEST = r'''
local fails = 0
local function check(ok, msg) print((ok and "ok    " or "FAIL  ") .. msg); if not ok then fails += 1 end end
local EG = require(node("Configs/EndgameConfig"))
local ES = require(node("Services/EndgameService"))
local profiles = {}
local notes = {}
local deps = {
  DataService = { GetProfile = function(p) return profiles[p.UserId] end, MarkDirty = function() end, OnProfileLoaded = function() end },
  EconomyService = { SpendCash = function() return true end, AddCash = function() return true end, AddGold = function() return true end },
  NotificationService = { Notify = function(p, text) table.insert(notes, text) end },
}
ES.Init(deps)
ES._SetStation("Intel", CFrame.new(-300, 5, 300))
local office = ES.StationPoint("Intel")
local owner = mkPlayer(470626172, Vector3.new(500, 5, 500))
local other = mkPlayer(9, Vector3.new(500, 5, 500))
profiles[470626172] = { Cash = 1e6, Prestige = 3, Endgame = { EmpireLevel = 0 }, BasePlotId = 1 }
profiles[9] = { Cash = 1e6, Prestige = 3, Endgame = { EmpireLevel = 0 } }
local st = ES.State(owner)
local r1 = st.Intel.Rows[1]
ES.SyncAttributes(owner)
check(owner.attrs.WE_IntelGuide == nil, "nothing to claim: no guide")
ES.NoteContract(owner, r1.Kind, r1.Need)
check(notes[#notes] == "Contract done: claim it at the Intel Office", "the toast")
local g = owner.attrs.WE_IntelGuide
check(typeof(g) == "Vector3" and (g - office).Magnitude < 1e-6, "at the toast: WE_IntelGuide = the Intel Office NPC point")
ES.SyncAttributes(owner)
check(owner.attrs.WE_IntelGuide ~= nil, "the 5 s sweep keeps it while unclaimed")
owner.Root.Position = office
local ok = ES.Purchase(owner, "Claim", "D1")
check(ok and owner.attrs.WE_IntelGuide == nil, "claimed at the office: the guide clears")
local hv = ES.State(owner).Intel.Hvt
ES.NoteContract(owner, hv.Kind, hv.Need)
check(owner.attrs.WE_IntelGuide ~= nil and notes[#notes] == "Weekly target done: claim it at the Intel Office", "the weekly HVT done: toast + guide")
ES.Purchase(owner, "Claim", "HVT")
check(owner.attrs.WE_IntelGuide == nil, "HVT claimed: cleared")
-- a stale day's done row never guides (contractsOf resets the day on the next read)
local c = profiles[470626172].Endgame.Contracts
c.Rows[2].Have = c.Rows[2].Need
check(ES.IntelClaimable(profiles[470626172]) == true, "a done unpaid row today: claimable")
c.Day -= 1
check(ES.IntelClaimable(profiles[470626172]) == false, "the same row from yesterday: not claimable (no stale guide)")
c.Day += 1
-- not live (owner-first) = nothing
ES.NoteContract(other, "Anything", 99)
ES.SyncAttributes(other)
check(other.attrs.WE_IntelGuide == nil or EG.LiveFor(9, "Contracts"), "not live for him: no guide")
-- /setrebirth's endgame side: lowering clears the endgame unlock flags above the count only
profiles[470626172].Endgame.Unlocks = { HeavyWarhead = true, MythicTraining = true }
profiles[470626172].Prestige = 26
ES.AdminSyncRebirth(owner, 26)
local u = profiles[470626172].Endgame.Unlocks
check(u.HeavyWarhead == true and u.MythicTraining == nil, "AdminSyncRebirth(26): Heavy Warhead (R25) kept, Mythic Training (R30) flag cleared")

-- the client: Modules/IntelGuide.Decide (the one tracker)
local IG = require(node("Modules/IntelGuide"))
local at = Vector3.new(-297.5, 5.3, 301.1)
local mine = { Short = IG.LABEL, X = at.X, Y = at.Y, Z = at.Z }
local airdrop = { Short = "AIRDROP", X = 900, Y = 0, Z = 900 }
check(IG.LABEL == "INTEL OFFICE", "the compass pill / world marker label: INTEL OFFICE")
check(IG.Decide(at, nil, Vector3.new(0, 0, 0), true) == "show", "contract done (fresh), tracker free: point at the Intel Office")
check(IG.Decide(at, airdrop, Vector3.new(0, 0, 0), true) == "show", "contract done while an AIRDROP is tracked: the completion moment takes the tracker once")
check(IG.Decide(at, airdrop, Vector3.new(0, 0, 0), false) == nil, "later: never fights a live AIRDROP / mission target")
check(IG.Decide(at, mine, Vector3.new(0, 0, 0), false) == nil, "already tracking the office: no rebuild")
check(IG.Decide(at, nil, at + Vector3.new(5, 0, 0), false) == nil, "arrived (tracker cleared by arrival) and still at the office: stays off")
check(IG.Decide(at, nil, at + Vector3.new(80, 0, 0), false) == "show", "walked off without claiming / the airdrop ended: back on")
check(IG.Decide(nil, mine, at, true) == "clear", "claimed (attribute cleared): our marker clears")
check(IG.Decide(nil, airdrop, at, true) == nil, "claimed while an AIRDROP is tracked: the airdrop is left alone")
print(string.format("V168 INTEL TEST: %d failed", fails))
if fails > 0 then error("failed") end
'''
run("D intel", PRELUDE, EGT.EXTRA, D_MODS, D_TEST, "V168 INTEL TEST")
ig = (CL / "Modules/IntelGuide.luau").read_text(encoding="utf-8")
egc = (CL / "Controllers/EndgameController.luau").read_text(encoding="utf-8")
check_static("IntelGuide uses the ONE tracker (ObjectiveMarker.ShowWith / Clear; the compass pill follows it), no travel; started by EndgameController",
             "ObjectiveMarker.ShowWith(" in ig and "ObjectiveMarker.Clear()" in ig and "PivotTo" not in ig and "Teleport" not in ig
             and "Modules.IntelGuide" in egc and "IG.Start" in egc)

print("\nCODEBOT V168 TESTS: %d failed%s" % (len(FAILS), "" if not FAILS else " (" + ", ".join(FAILS) + ")"))
if __name__ == "__main__":
    sys.exit(1 if FAILS else 0)
