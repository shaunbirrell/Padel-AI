# Code Bot Roblox v171 (2026-10-01, Shaun 12:08 Dublin, R10 on v169/v170): three live bugs.
#  1. TARGETS card gone: v168's crosshair() set AnchorPoint = spec[5] (nil, the specs have 4 fields); Roblox throws on a
#     nil typed property, so RivalController.build() died after parenting a sizeless empty pill. Fixed + the card is
#     placed before any decoration (pcall). Proof: tools/sim/run_codebot_v171_test.py (the real v170 vs v171 source).
#  2. Scout report "did nothing": the result was a 1.8 s toast + a grey INFO row 5th in the Intel list, held only in
#     this server's memory (lost on a server move). Now: built before the charge (a failure charges nothing), saved
#     in profile.Endgame, pushed as a "ScoutReport" result card, leads the Intel list (VIEW).
#  3. Recruit Pack "gold base trim": it was only a thicker stroke on the base sign's (already gold) title. Now real
#     gold geometry on his walls / gate posts (BaseTierBuilder RecruitTrim), from the saved entitlement, rebuilt the
#     moment WE_Ent_RecruitPack is set. Cash30m-sized cash + 2x / 30 min boost on the receipt path unchanged.
# No flag / price change. PreferMesh OFF; WE_Building* untouched.
from pathlib import Path

ROOT = Path.cwd()


def read(rel):
    return (ROOT / rel).read_text(encoding="utf-8")


def check(cond, label):
    if "ok" in globals() and "bad" in globals():
        (ok if cond else bad)(label)
    else:
        print(("PASS " if cond else "FAIL ") + label)
        if not cond:
            raise SystemExit(1)


S = "src/ServerScriptService/Server/"
CL = "src/StarterPlayer/StarterPlayerScripts/Client/"
for rel, needle in (
    (S + "Services/BaseService.luau", 'SetAttribute("WE_Build", 208)'),
    (S + "Services/DataService.luau", 'SetAttribute("WE_Build", 208)'),
    (S + "Services/DataService.luau", "WE_Build=208"),
    (S + "EarlyRemotes.server.luau", 'SetAttribute("WE_Build", 208)'),
):
    check(needle in read(rel), "CODEBOT v171: WE_Build=208 " + rel.rsplit("/", 1)[-1])

RC = read(CL + "Controllers/RivalController.luau")
check("f.AnchorPoint = spec[5]" not in RC and "f.AnchorPoint = spec[4]" in RC, "CODEBOT v171: TARGETS crosshair reads spec[4] (spec[5] was nil -> build() threw)")
check("local okX, errX = pcall(crosshair, b," in RC and RC.find("b.Size = UDim2.fromOffset(C0.W, C0.H)") < RC.find("pcall(crosshair, b,"),
      "CODEBOT v171: the TARGETS card is sized / placed before its icon, the icon in a pcall")

ES = read(S + "Services/EndgameService.luau")
plan = ES[ES.find('elseif kind == "Claim" or kind == "Scout" then'):ES.find('elseif kind == "Heal" or kind == "MedKit"')]
check("pcall(EndgameService.BuildScoutReport, player, tgt, pid :: number)" in plan and 'return nil, "Scouting failed, try again (nothing charged)"' in plan
      and plan.find("BuildScoutReport, player") < plan.find("Price = price,"), "CODEBOT v171: the scout report is built before the charge (failure charges nothing)")
check("EndgameService.Data(prof).ScoutReport = rep" in plan and "pendingScoutCard[uid] = rep" in plan, "CODEBOT v171: the scout report is saved in profile.Endgame + queued as a result card")
check('(ev :: RemoteEvent):FireClient(player, "ScoutReport", rep)' in ES and "EndgameService.PushScoutCard(player)" in ES, "CODEBOT v171: the ScoutReport card is pushed after the buy")
EC = read(CL + "Controllers/EndgameController.luau")
check('if kind == "ScoutReport" and typeof(data) == "table" then' in EC and 'Kind = "ScoutView", Id = "Report", Label = "VIEW"' in EC
      and 'if r.Kind == "ScoutView" then' in EC, "CODEBOT v171: the client shows the scout card and leads the Intel list with VIEW")
check('Name = "REPORT: "' not in EC and 'Kind = "Info", Id = "Report"' not in EC, "CODEBOT v171: the old grey INFO report row is gone")
PS = read(S + "Modules/ProfileSchema.luau")
check("e.ScoutReport = nil" in PS, "CODEBOT v171: ProfileSchema drops a malformed saved ScoutReport")

BT = read(S + "Modules/BaseTierBuilder.luau")
check("if ctx.RecruitTrim then" in BT and '"RecruitWallBand"' in BT and '"RecruitPostBand"' in BT and "RecruitGold = Color3.fromRGB(236, 190, 52)" in BT,
      "CODEBOT v171: BaseTierBuilder builds the Recruit gold trim (wall bands, post bands)")
check("Neon" not in BT and 'Instance.new("Humanoid")' not in BT, "CODEBOT v171: the trim uses no Neon / Humanoid")
check("ctx.RecruitTrim = recruit" in ES and "EndgameService.HasRecruitTrim(player, profile)" in ES and 'profile.Entitlements.RecruitPack == true' in ES,
      "CODEBOT v171: SyncBaseTier applies the trim from the SAVED entitlement (persists on rejoin)")
check('player:GetAttributeChangedSignal("WE_Ent_RecruitPack"):Connect' in ES, "CODEBOT v171: the trim goes on the moment the entitlement lands")
MON = read(S + "Services/MonetizationService.luau")
check("pcall(CS.GrantCashBoost, player, o.BoostMinutes, o.BoostMult)" in MON and "cashGrant = nonNegInt(MCx.RecruitPackCashFor(player.UserId, perMin))" in MON
      and "pcall(BSS.Refresh, profile.BasePlotId)" in MON, "CODEBOT v171: Recruit Pack receipt = cash + 2x boost + an immediate sign refresh")
check("Endgame" not in MON, "CODEBOT v171: no Robux path to the endgame")
check(Path(ROOT / "tools/sim/run_codebot_v171_test.py").exists() and Path(ROOT / "tools/sim/rival_controller_harness.py").exists(), "CODEBOT v171: the proof sims exist")
