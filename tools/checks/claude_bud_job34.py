# claude-bud JOB 34 (2026-09-30): achievements + chat shout-outs + Roblox badges, owner-first (AchievementConfig.Live):
# AchievementConfig / Services/AchievementService / Client AchievementController + the Missions page, hooks in
# MissionService / PrestigeService / NukeService / EngagementService, docs/BADGES.md. Static pins + the real-code test
# (tools/sim/run_achievement_test.py).
import os as _j34_os
import subprocess as _j34_sp
import sys as _j34_sys
from pathlib import Path as _J34P

if "ok" not in globals():
    _j34_fails = []

    def ok(msg):
        print("PASS " + msg)

    def bad(msg):
        _j34_fails.append(msg)
        print("FAIL " + msg)

if "read" not in globals():
    def read(p):
        q = _J34P(p)
        return q.read_text(encoding="utf-8") if q.is_file() else None


def _j34(cond, msg):
    (ok if cond else bad)("CLAUDE-BUD J34: " + msg)


def _j34_src(path):
    return (read(path) or "").replace("\r\n", "\n")


def _j34_code(path):
    return "\n".join(l.split("--", 1)[0] for l in _j34_src(path).splitlines())


_SV = "src/ServerScriptService/Server/"
_CL = "src/StarterPlayer/StarterPlayerScripts/Client/"
_AC = _j34_src("src/ReplicatedStorage/Shared/Configs/AchievementConfig.luau")
_AS = _j34_code(_SV + "Services/AchievementService.luau")
_ACL = _j34_code(_CL + "Controllers/AchievementController.luau")
_MS = _j34_code(_SV + "Services/MissionService.luau")
_PS = _j34_code(_SV + "Services/PrestigeService.luau")
_NS = _j34_code(_SV + "Services/NukeService.luau")
_ES = _j34_code(_SV + "Services/EngagementService.luau")
_MC = _j34_code(_CL + "Controllers/MissionController.luau")
_PSC = _j34_code(_SV + "Modules/ProfileSchema.luau")

# gate: owner-first kill switch; off = the old 3-achievement path
_j34("\tLive = {\n\t\tEnabled = true,\n\t\tOwnerFirst = true, -- only UserId 470626172" in _AC and "RetentionConfig.Live(AchievementConfig.Live, uid)" in _AS,
     "one owner-first kill switch (AchievementConfig.Live, the RetentionConfig.Live rule)")
_j34("if ach and ach.Check and ach.Check(player) then" in _MS and 'MissionService.GrantAchievement(player, "FirstUpgrade")' in _MS
     and "if deps.DataService == nil or not live(player.UserId) then\n\t\treturn false" in _AS,
     "not live = MissionService's original CheckAchievements / GrantAchievement run unchanged")
# once per player, saved
_j34("if profile.Achievements[id] == true then\n\t\treturn false" in _AS and "profile.Achievements[id] = true" in _AS and "profile.AchievementsAt[id] = os.time()" in _AS,
     "each achievement fires once (the saved profile.Achievements map + AchievementsAt)")
_j34("profile.AchievementsAt = at" in _PSC and "profile.AchievementsSeeded = if profile.AchievementsSeeded == true then true else nil" in _PSC,
     "ProfileSchema: additive AchievementsAt / AchievementsSeeded, sanitised on migrate")
_j34("local seeding = profile.AchievementsSeeded ~= true" in _AS and "{ Quiet = seeding }" in _AS,
     "first check of an old profile backfills quietly (no chat flood)")
# reuse existing counters; hooks
for _stat in ('"Stats.TotalCashEarned"', '"LB.Kills"', '"Prestige"', '"NukeStats.Launched"', '"BaseUpgrades.CommandCenter"', '"Stats.PlazaCaptures"', '"Soldiers"', '"DailyLogin.Streak"'):
    _j34("Stat = " + _stat in _AC, "achievement progress reads the existing counter " + _stat)
_j34("ach.Note(player, objectiveType)" in _MS and "MissionService.CheckAchievements(player)" in _MS, "MissionService TrackProgress feeds events + checks")
_j34("pcall(AS.OnRebirth, player)" in _PS, "PrestigeService: rebirth achievements + the rebirth line")
_j34("profile.NukeStats.Launched = (tonumber(profile.NukeStats.Launched) or 0) + 1" in _NS and "pcall(deps.AchievementService.Check, player)" in _NS,
     "NukeService: the existing NukeStats.Launched counter + the nuke achievement")
_j34('pcall(ach.Note, p, "Crown", { Label = label })' in _ES, "EngagementService: the weekly #1 crown (admins are never crowned: boards unchanged)")
_j34("d.SoldierService.OnArmyChanged(function(player: Player)" in _AS, "army size via SoldierService.OnArmyChanged")
# rewards server-side, no Robux
_j34('pcall(econ.AddCash, player, def.RewardCash, "achievement")' in _AS and "MarketplaceService" not in _AS + _ACL and "ProductId" not in _AC,
     "rewards are server-side Cash / Gold / XP (reason \"achievement\"); no Robux item")
# chat + banner + rate limit
_j34('push(nil, "AchShout", { Name = e.Name, Text = text, Big = e.Big })' in _AS and "AchievementService.Combine(queue," in _AS
     and "lastSent + AchievementConfig.Shout.GapSeconds - clock()" in _AS,
     "one server-wide chat line per achievement, rate limited (combine / gap / queue cap)")
_j34(":DisplaySystemMessage(AchievementController.Format(name, text, big))" in _ACL and "AchievementController.Escape" in _ACL,
     "client: TextChatService system line with escaped rich text")
_j34('"WE_AchBanner", "AchBanner", 16' in _ACL and "name ~= player.Name" in _ACL, "big ones: a top-stack banner for everyone else (the earner gets the popup)")
# badges
_j34("if bid <= 0 then\n\t\treturn\n\tend" in _AS and "BadgeService:UserHasBadgeAsync(player.UserId, bid)" in _AS and "BadgeService:AwardBadge(player.UserId, bid)" in _AS,
     "badges: only BadgeId ~= 0, UserHasBadgeAsync first, pcall + retries")
_BD = _j34_src("docs/BADGES.md")
_j34(_BD != "" and all(("`" + i + "`") in _BD for i in ("FirstKillNPC", "Rebirth20", "WeeklyCrown", "Cash100M")), "docs/BADGES.md lists the badges for Code Bot")
# remote + page + analytics
_j34('RemoteGate).Check(player, "RequestAchievements")' in _AS and "RequestAchievements = {}," in _j34_src("src/ReplicatedStorage/Shared/Configs/SecurityConfig.luau"),
     "RequestAchievements: gated, schema'd, rate limited")
_j34("achievementRows(listFrame)" in _MC and '"AchievementsHeader"' in _MC and 'child.Name == "ActivitiesHeader"' in _MC,
     "the Missions panel ACHIEVEMENTS page (earned / locked + progress bars); section headers no longer stack")
_j34("ACHIEVEMENT_UNLOCKED" in _AS and "backfill = o.Quiet == true" in _AS, "analytics per unlock")

_luau = _j34_os.environ.get("LUAU")
if _luau is None and _j34_os.environ.get("LUAU_COMPILE"):
    _cand = _j34_os.environ["LUAU_COMPILE"].replace("luau-compile", "luau")
    _luau = _cand if _j34_os.path.isfile(_cand) else None
if _luau:
    _r = _j34_sp.run([_j34_sys.executable, "tools/sim/run_achievement_test.py"], capture_output=True, text=True, env=dict(_j34_os.environ, LUAU=_luau))
    _j34(_r.returncode == 0 and "ACHIEVEMENT TEST: 0 failed" in _r.stdout, "run_achievement_test.py (real service / config / ProfileSchema / client format)")
else:
    print("SKIP CLAUDE-BUD J34: Luau CLI test (set LUAU)")
