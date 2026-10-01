"""Code Bot v163 (Shaun 2026-10-01): the three owner asks, on the REAL modules (Luau CLI, stand-ins only around them).

A. TARGETS (RivalService + RivalConfig + the real ArmySendRules verdict; harness: run_rival_targets_test):
   an EMPTY list is still pushed with a one-line reason (Why): alone in the server / no soldiers / everyone protected /
   nobody with $10k+ in the ATM / the Guided hold; a non-empty list carries no Why. Static: RivalController builds the
   pill VISIBLE, never hides it for 0 targets, shows RivalConfig.EmptyText in the list.
B. GUIDED REPLAY (TutorialService + GuidedService + ProfileSchema; harness: run_first_minutes_test): a finished owner
   save (Level 100-style: every building, Home Outpost taken, $50M) replays Guided in test mode: Income -> Recruit ->
   FIRST FIGHT (a fresh 2-Recruit camp) -> Reward banner -> Jeep; owned steps skipped; NO cash, NO funnel / Guided
   analytics; the end, SKIP and a rejoin mid-replay each put the tutorial fields back exactly. Static: AdminService
   reaches it only after the allowlist check (remote + chat), Settings shows the row only to AdminConfig.UserIds.
C. TOP SUPPORTERS (EngagementService; harness: engagement_gate_test mocks): a saved dev-product grant writes the board
   AT ONCE (inside the 90 s write throttle); a leave right after a purchase still writes it even when the profile is
   already gone; a pass owned but never counted is credited once at its real price; a confirmed in-game pass purchase
   is never counted twice; a legacy profile is recorded without a credit; admin / owner never written; opt-out kept.
Run: LUAU=path/to/luau python tools/sim/run_codebot_v163_test.py   (exit 1 on any failure; VERBOSE=1 prints all)"""
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(ROOT / "tools"))
LUAU = os.environ.get("LUAU", "luau")
FAILS = []


def run(name, src, marker):
    with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False, encoding="utf-8") as f:
        f.write(src)
        path = f.name
    r = subprocess.run([LUAU, path], capture_output=True, text=True, timeout=120)
    os.unlink(path)
    out = (r.stdout + r.stderr).strip()
    ok = r.returncode == 0 and (marker + " 0 failed") in out
    lines = out.splitlines()
    shown = lines if os.environ.get("VERBOSE") else [l for l in lines if l.startswith("FAIL") or marker in l or "error" in l.lower()]
    print("\n".join(shown) or out[-2000:])
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
RS.Init(DEPS)
local W = RC.WhyText
local function last(p) local got; for _, e in ipairs(PUSHES) do if e.p == p and e.kind == "RivalTargets" then got = e.data end end; return got end
local function allFacts(over) FACTS = {}; for i = 1, 9 do FACTS[i] = facts(over) end end
-- every other base is shielded / new: an EMPTY push, with the reason
allFacts({ NewPlayerLeft = 300 }); BAL = {}; for i = 1, 9 do BAL[5000 + i] = 2e6 end
PUSHES = {}; RS.Tick()
local d = last(VIEWER)
check(d ~= nil and #d.Rows == 0 and d.Why == W.Protected, "0 targets is still pushed (the pill stays) with the reason: " .. tostring(d and d.Why))
-- no soldiers: the viewer's own state wins
allFacts({ Units = 0 }); PUSHES = {}; RS.Tick(); d = last(VIEWER)
check(#d.Rows == 0 and d.Why == W.NoArmy, "no soldiers -> 'Recruit soldiers' (" .. tostring(d.Why) .. ")")
-- allowed but nobody has $10k+ in the ATM
allFacts(); BAL = {}; for i = 1, 9 do BAL[5000 + i] = 5000 end
PUSHES = {}; RS.Tick(); d = last(VIEWER)
check(#d.Rows == 0 and d.Why == W.Poor, "allowed bases under MinLootToShow -> 'Nobody here has $10k+' (" .. tostring(d.Why) .. ")")
-- too strong
allFacts({ ArmyPower = 10, DefencePower = 1000 }); for i = 1, 9 do BAL[5000 + i] = 2e6 end
PUSHES = {}; RS.Tick(); d = last(VIEWER)
check(#d.Rows == 0 and d.Why == W.Strong, "every base too strong -> 'defences too strong' (" .. tostring(d.Why) .. ")")
-- hold
HOLD = true; PUSHES = {}; RS.Tick(); HOLD = false; d = last(VIEWER)
check(#d.Rows == 0 and d.Why == W.Held, "Guided hold -> 'Finish the guided first minutes first'")
-- alone (pure)
check(RS.WhyEmpty(false, {}) == W.Alone, "nobody else with a base in the server -> 'No other players with a base'")
-- a real list carries no Why
allFacts(); for i = 1, 9 do BAL[5000 + i] = 2e6 end
PUSHES = {}; RS.Tick(); d = last(VIEWER)
check(#d.Rows == 3 and d.Why == nil, "a non-empty list: 3 rows, no Why")
check(type(RC.EmptyText) == "string" and RC.EmptyText:find("No targets right now", 1, true) ~= nil, "RivalConfig.EmptyText = 'No targets right now - rivals appear when other players have cash to raid'")
check(RC.OwnerFirst == false, "RivalConfig.OwnerFirst=false (codebot_v166: everyone; v163 kept it true)")
print(string.format("V163 TARGETS: %d failed", fails))
if fails > 0 then error("failed") end
'''
chunks = [RT.PRELUDE, RT.EXTRA]
for key, path in RT.MODS.items():
    chunks.append("SOURCES[%r] = function(script)\n%s\nend" % (key, path.read_text(encoding="utf-8")))
chunks.append(A_TEST)
run("A targets", "\n".join(chunks), "V163 TARGETS:")
ctl = (ROOT / "src/StarterPlayer/StarterPlayerScripts/Client/Controllers/RivalController.luau").read_text(encoding="utf-8")
check_static("RivalController: the pill is built Visible = true", "b.Visible = true" in ctl)
check_static("RivalController: never 'pl.Visible = #rows > 0' (hidden when empty)", "pl.Visible = #rows > 0" not in ctl)
check_static("RivalController: the empty state uses RivalConfig.EmptyText + Why", "RivalConfig.EmptyText" in ctl and "data.Why" in ctl)
check_static("RivalController: steps aside for Modal / Dead / the Recruit Pack card", 'GetFlag("Modal")' in ctl and 'GetFlag("Dead")' in ctl and "WE_RecruitPack" in ctl)

# ── B. GUIDED REPLAY ────────────────────────────────────────────────────────────────────────────────────────────
fm = (HERE / "run_first_minutes_test.py").read_text(encoding="utf-8")
ns = {"__file__": str(HERE / "run_first_minutes_test.py")}
exec(compile(fm.split("TEST = r'''", 1)[0], "fm_head", "exec"), ns)
B_TEST = r'''
local fails = 0
local function check(ok, msg) print((ok and "ok    " or "FAIL  ") .. msg); if not ok then fails += 1 end end
local TC = require(node("Configs/TutorialConfig"))
-- claude-bud JOB 48: this proves the v4 replay, so the (owner-first) Hook is off here; the owner's replay with the
-- Hook on (OrderVersion 5) is pinned in run_first_minutes_test (section 11)
if TC.Guided.Hook then TC.Guided.Hook.Enabled = false end
local function enc(v, d) d = d or 0; if type(v) ~= "table" then return tostring(v) end; local ks = {}; for k in pairs(v) do table.insert(ks, tostring(k)) end; table.sort(ks)
  local o = {}; for _, k in ipairs(ks) do local x = v[k]; if x == nil then x = v[tonumber(k)] end; table.insert(o, k .. "=" .. enc(x, d + 1)) end; return "{" .. table.concat(o, ",") .. "}" end
local FIELDS = { "TutorialComplete", "TutorialStep", "TutorialOrderVersion", "TutorialDoneAhead", "Guided" }
local function snap(pr) local t = {}; for _, k in ipairs(FIELDS) do t[k] = enc(pr[k]) end; return enc(t) end
local function veteran()
  local BC = require(node("Configs/BaseConfig"))
  local pr = newProfile(OWNER, { Cash = 50000000, FirstJoinUnix = UNIX - 30 * 86400, StarterOutpostTaken = true, Level = 100 })
  pr.TutorialComplete = true; pr.TutorialStep = 10; pr.TutorialOrderVersion = TC.OrderVersion
  pr.Guided = nil
  for id in pairs(BC.Structures) do pr.BaseUpgrades[id] = 3 end
  return pr
end
local function guidedEvents() local n = 0; for _, e in ipairs(LOG.ev) do if tostring(e.ev):match("^GUIDED") then n += 1 end end; return n end

-- the full replay
local pr = veteran()
TS, GS = boot(); load(OWNER); clearLog()
local before = snap(pr)
local cashBefore, levelBefore = pr.Cash, pr.Level
local ok, msg = TS.ReplayGuided(OWNER); runTo(NOW + 1)
check(ok == true and pr.GuidedReplay ~= nil and pr.TutorialOrderVersion == TC.Guided.OrderVersion, "ReplayGuided starts the Guided order (v4) in test mode: " .. tostring(msg))
check(lastTut(OWNER).Id == "Income", "ClaimBase done by the plot, Command Center skipped (owned): first open step = Income (" .. tostring(lastTut(OWNER).Id) .. ")")
local again = TS.ReplayGuided(OWNER)
check(again == false, "a second ReplayGuided while one runs is refused")
TS.Notify(OWNER, "PassiveIncome"); runTo(NOW + 1)
check(lastTut(OWNER).Id == "RecruitSoldiers", "-> Recruit soldiers")
TS.Notify(OWNER, "RecruitSoldiers"); runTo(NOW + 1)
check(lastTut(OWNER).Id == "FirstFight" and #LOG.spawned == 2, "-> FIRST FIGHT with a fresh 2-Recruit camp, although his Home Outpost was taken long ago")
killCamp(OWNER.UserId); runTo(NOW + 5)
local banner = false
for _, e in ipairs(LOG.push) do if e.kind == "GuidedReward" then banner = true end end
check(banner, "camp cleared -> Outpost skipped (taken) -> the REWARD banner shows")
check(lastTut(OWNER).Id == "Jeep", "-> Barracks skipped (owned) -> Jeep (" .. tostring(lastTut(OWNER).Id) .. ")")
TS.Notify(OWNER, "SpawnVehicle"); runTo(NOW + 1)
check(#LOG.cash == 0 and pr.Cash == cashBefore, "test mode: no cash at all (no recruit top-up, no reward cash, no starter payout)")
check(#LOG.funnel == 0 and guidedEvents() == 0, "test mode: no FirstMinutes funnel step and no GUIDED_* event")
check(pr.GuidedReplay == nil and snap(pr) == before and pr.Level == levelBefore, "the end restores the tutorial fields EXACTLY (save unchanged)")
local doneNote = false
for _, m in ipairs(LOG.notify) do if tostring(m):find("Guided replay finished", 1, true) then doneNote = true end; if tostring(m):find("Tutorial complete", 1, true) then doneNote = false end end
check(doneNote, "the end says 'Guided replay finished (test mode)', not the real 'Tutorial complete'")

-- SKIP mid-replay
pr = veteran(); TS, GS = boot(); load(OWNER); clearLog(); before = snap(pr)
TS.ReplayGuided(OWNER); runTo(NOW + 1); TS.Notify(OWNER, "PassiveIncome"); TS.Notify(OWNER, "RecruitSoldiers"); runTo(NOW + 1)
TS.Complete(OWNER); runTo(NOW + 1)
check(pr.GuidedReplay == nil and snap(pr) == before and #LOG.despawned == 2 and guidedEvents() == 0, "SKIP mid-fight: camp cleared, fields restored, no GuidedSkipped event")

-- leave mid-replay: the next load restores
pr = veteran(); TS, GS = boot(); load(OWNER); clearLog(); before = snap(pr)
TS.ReplayGuided(OWNER); runTo(NOW + 1)
check(pr.GuidedReplay ~= nil, "(replay running; the snapshot is in the saved profile)")
TS, GS = boot(); load(OWNER)
check(pr.GuidedReplay == nil and snap(pr) == before and lastTut(OWNER).Complete == true, "a rejoin mid-replay loads the save exactly as before the replay")

-- a NEW player is untouched (the real Guided still pays)
local pn = newProfile(OTHER); TS, GS = boot(); load(OTHER)
check(pn.GuidedReplay == nil, "a normal profile never carries GuidedReplay")
print(string.format("V163 REPLAY: %d failed", fails))
if fails > 0 then error("failed") end
'''
chunks = [ns["PRELUDE"], ns["EXTRA"]]
for key, path in ns["MODS"].items():
    chunks.append("SOURCES[%r] = function(script)\n%s\nend" % (key, Path(path).read_text(encoding="utf-8")))
chunks.append(B_TEST)
run("B replay", "\n".join(chunks), "V163 REPLAY:")
adm = (ROOT / "src/ServerScriptService/Server/Services/AdminService.luau").read_text(encoding="utf-8")
i_admin = adm.find("if not isAdmin and not (moneyCmd and RunService:IsStudio()) then")
i_rep = adm.find('elseif cmd == "replaytutorial" or cmd == "replayguided" then')
check_static("AdminService remote: replaytutorial is reached only after the allowlist check", 0 < i_admin < i_rep)
i_chat = adm.find("local function onAdminChat")
i_chat_admin = adm.find("if not AdminService.IsAdmin(player) then", i_chat)
i_chat_rep = adm.find("if isReplayCmd then", i_chat)
check_static("AdminService chat: /replaytutorial only after AdminService.IsAdmin", 0 < i_chat < i_chat_admin < i_chat_rep)
check_static("AdminService chat: /replaytutorial + /replayguided TextChatCommand, hidden from autocomplete", '"WE_ReplayTutorial", "/replaytutorial", "/replayguided"' in adm and 'spec[1] == "WE_ReplayTutorial"' in adm)
st = (ROOT / "src/StarterPlayer/StarterPlayerScripts/Client/Controllers/SettingsController.luau").read_text(encoding="utf-8")
i_gate = st.find('if table.find(AdminConfig.UserIds, player.UserId) ~= nil then\n\t\tsection("ADMIN")')
check_static("Settings: ADMIN > REPLAY GUIDED TUTORIAL (test) only for AdminConfig.UserIds", i_gate > 0 and "REPLAY GUIDED TUTORIAL (test)" in st[i_gate:i_gate + 600])
tc = (ROOT / "src/ReplicatedStorage/Shared/Configs/TutorialConfig.luau").read_text(encoding="utf-8")
check_static("TutorialConfig.Guided.OwnerFirst=false (codebot_v166: everyone; v163 kept it true)", re.search(r"TutorialConfig\.Guided = \{[^}]*?OwnerFirst = false", tc, re.S) is not None)

# ── C. TOP SUPPORTERS ───────────────────────────────────────────────────────────────────────────────────────────
import engagement_gate_test as EG  # noqa: E402
head = EG.HARNESS.split('local E = require(proxy("EngagementConfig"))', 1)[0]
C_TEST = r'''
local AC = require(proxy("AdminConfig"))
local OWNER = AC.PlaytestOwnerUserId
Enum.InfoType = { GamePass = "GamePass" }
SRC.MonetizationConfig = @MONCFG@
local granted, passOwned = {}, {}
local MS = { OnGranted = function(fn) table.insert(granted, fn) end, OnPassOwned = function(fn) table.insert(passOwned, fn) end }
local profiles, loadedCb = {}, nil
local dropProfileOnLeave = false
local DataService = {
	OnProfileLoaded = function(cb) loadedCb = cb end,
	GetProfile = function(p) return profiles[p.UserId] end,
	IsLoaded = function() return true end, MarkDirty = function() end, SaveProfile = function() return true end,
}
local ownsPass, priceOf = {}, {}
local ES = require(proxy("EngagementService"))
ES._MarketplaceService = {
	UserOwnsGamePassAsync = function(_, uid, id) return ownsPass[uid .. ":" .. id] == true end,
	GetProductInfo = function(_, id) return { PriceInRobux = priceOf[id] } end,
}
ES.Init({ DataService = DataService, EconomyService = { AddCash = function() end }, NotificationService = { Notify = function() end }, MonetizationService = MS })
check(#granted == 1 and #passOwned == 1, "v163: EngagementService listens to MonetizationService.OnGranted + OnPassOwned")
local function mk(uid, prof)
	local p = { UserId = uid, Parent = PlayersSvc, attrs = {}, CharacterAdded = { Connect = function() end } }
	function p:SetAttribute(k, v) self.attrs[k] = v end
	function p:GetJoinData() return {} end
	function p:IsFriendsWithAsync() return false end
	profiles[uid] = prof
	return p
end
local function join(p) table.insert(list, p); loadedCb(p, profiles[p.UserId]) end
local function leave(p)
	for i, q in ipairs(list) do if q == p then table.remove(list, i); break end end
	p.Parent = nil
	if dropProfileOnLeave then profiles[p.UserId] = nil end -- DataService.UnloadProfile ran first
	for _, f in ipairs(removing) do f(p) end
	p.Parent = PlayersSvc
end
local function tick(seconds)
	CLOCK += seconds
	local s = sleepers; sleepers = {}
	for _, co in ipairs(s) do coroutine.resume(co); if coroutine.status(co) == "suspended" then table.insert(sleepers, co) end end
end
local function sup(uid) return (ordered["WE_LB2_Supporters"] or {})[tostring(uid)] end
local function buy(p, robux) local m = profiles[p.UserId].Monetization; m.RobuxSpent += robux; m.Purchases += 1
	profiles[p.UserId].ProcessedReceipts["r" .. m.Purchases] = true; for _, fn in ipairs(granted) do fn(p, "CashSmall", { CurrencySpent = robux }) end end
local function prof(cash) return { Cash = cash or 100, Prestige = 0, Stats = {}, FirstJoinUnix = NOW - 86400, PrevJoinUnix = NOW,
	Monetization = { FirstPurchaseUnix = 0, LastPurchaseUnix = 0, Purchases = 0, RobuxSpent = 0 }, ProcessedReceipts = {} } end

-- 1. the reported case: Cash Pack S (49 R$) bought inside the write throttle, then he leaves
local B = mk(9001, prof()); join(B); tick(6)
check(sup(9001) == nil, "a player who never spent is not on TOP SUPPORTERS")
buy(B, 49)
check(sup(9001) == 49, "Cash Pack S (49 R$): written AT ONCE after the saved grant, inside the 90 s throttle (" .. tostring(sup(9001)) .. ")")
-- 2. leave right after a purchase, profile already unloaded
local C = mk(9002, prof()); join(C); tick(6)
profiles[9002].Monetization.RobuxSpent = 99 -- a receipt saved whose listener has not run yet
tick(1) -- inside the throttle: the periodic writer does not write
dropProfileOnLeave = true
-- the periodic writer saw the new value? it did not (throttled): the cache holds the last seen, so set it the way a grant would
for _, fn in ipairs(granted) do fn(C, "SpeedBoost", {}) end
leave(C); dropProfileOnLeave = false
check(sup(9002) == 99, "a leave right after a purchase still ends with the supporter value written")
-- 2b. leave inside the throttle with the profile still there and no listener yet
local C2 = mk(9003, prof()); join(C2); tick(6)
profiles[9003].Monetization.RobuxSpent = 25
leave(C2)
check(sup(9003) == 25, "the leave flush writes a changed supporter value even inside the 90 s throttle")
-- 3. a pass owned on Roblox (bought on the website), never counted: credited once at the real price
local MC = require(proxy("MonetizationConfig"))
local passKey, passDef
for k, d in pairs(MC.GamePasses) do if type(d.Id) == "number" and d.Id ~= 0 and passKey == nil then passKey, passDef = k, d end end
local D = mk(9004, prof()); join(D); tick(6)
ownsPass["9004:" .. passDef.Id] = true; priceOf[passDef.Id] = 149
for _, fn in ipairs(passOwned) do fn(D, passKey, "join") end
check(profiles[9004].Monetization.RobuxSpent == 149 and sup(9004) == 149, "a pass owned but never counted: +149 R$ (PriceInRobux) and written (" .. tostring(sup(9004)) .. ")")
for _, fn in ipairs(passOwned) do fn(D, passKey, "join") end
check(profiles[9004].Monetization.RobuxSpent == 149, "the same pass on the next join: never counted twice")
-- 4. an implied pass (a bundle part, UserOwnsGamePassAsync false) is never credited
local E2 = mk(9005, prof()); join(E2)
for _, fn in ipairs(passOwned) do fn(E2, passKey, "join") end
check(profiles[9005].Monetization.RobuxSpent == 0 and sup(9005) == nil, "owned only through a bundle (not bought itself): nothing credited")
-- 5. an in-game confirmed purchase (MonetizationService already added the price): ledgered, no second add
local F = mk(9006, prof()); join(F); tick(6)
profiles[9006].Monetization.RobuxSpent = 149; profiles[9006].Monetization.Purchases = 1
for _, fn in ipairs(passOwned) do fn(F, passKey, "purchase") end
ownsPass["9006:" .. passDef.Id] = true
for _, fn in ipairs(passOwned) do fn(F, passKey, "join") end
check(profiles[9006].Monetization.RobuxSpent == 149 and sup(9006) == 149, "a confirmed in-game pass purchase: on the board once, never re-credited on a later join")
-- 6. a legacy profile (an in-game pass counted before the ledger existed) is recorded without a credit
local G = mk(9007, prof()); profiles[9007].Monetization.RobuxSpent = 149; profiles[9007].Monetization.Purchases = 1; join(G)
ownsPass["9007:" .. passDef.Id] = true
for _, fn in ipairs(passOwned) do fn(G, passKey, "join") end
check(profiles[9007].Monetization.RobuxSpent == 149, "legacy profile (Purchases > receipts): the owned pass is recorded, never double counted")
-- 7. owner / admin never written, opt-out respected
local O = mk(OWNER, prof()); join(O); tick(6); buy(O, 49)
check(sup(OWNER) == nil, "the owner / admin account is never written to TOP SUPPORTERS")
local H = mk(9008, prof()); profiles[9008].Settings = { SupporterBoardOptOut = true }; join(H); tick(6); buy(H, 49)
check(sup(9008) == nil, "an opted-out buyer stays off the board")
-- 8. the published board shows the buyer within one read
tick(95) -- Code Bot v175: ReadSeconds 90
local sv = RS:FindFirstChild("WE_Leaderboards") and RS:FindFirstChild("WE_Leaderboards"):FindFirstChild("Supporters")
local found = false
for _, r in ipairs(sv and sv.Value and sv.Value.Rows or {}) do if r.U == 9001 and r.V == 49 then found = true end end
check(found, "the next shared read publishes the 49 R$ buyer on TOP SUPPORTERS")
print(string.format("V163 SUPPORTERS: %d failed", fails))
if fails > 0 then error("FAIL") end
'''
src = (head + C_TEST)
src = (src.replace("@ENGCFG@", EG.lstr((EG.CFG / "EngagementConfig.luau").read_text(encoding="utf-8")))
       .replace("@ADMINCFG@", EG.lstr((EG.CFG / "AdminConfig.luau").read_text(encoding="utf-8")))
       .replace("@LBCFG@", EG.lstr((EG.CFG / "LeaderboardConfig.luau").read_text(encoding="utf-8")))
       .replace("@CONSTANTS@", EG.lstr('return { RemoteNames = { RequestBoardSetting = "RequestBoardSetting" } }'))
       .replace("@REMOTES@", EG.lstr('return { TryGetEvent = function() return nil end }'))
       .replace("@ENGSVC@", EG.lstr((EG.SRV / "Services/EngagementService.luau").read_text(encoding="utf-8")))
       .replace("@MONCFG@", EG.lstr("return { GamePasses = " + "{ VIP = { Id = 111, RobuxPrice = 149 }, Cheap = { Id = 0, RobuxPrice = 5 } } }")))
run("C supporters", src, "V163 SUPPORTERS:")

print("CODEBOT V163 TEST: %d failed%s" % (len(FAILS), (" (" + ", ".join(FAILS) + ")") if FAILS else ""))
sys.exit(1 if FAILS else 0)
