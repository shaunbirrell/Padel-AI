# Code Bot Roblox v134 (2026-09-30): wire the 5 created Roblox badges (Shaun saw every badge at 0% "Impossible":
# AchievementConfig BadgeIds were all 0, so AchievementService never called AwardBadge).
#  * BadgeIds (Creator Hub, universe 10767159222, verified enabled via badges.roblox.com + BadgeService:GetBadgeInfoAsync):
#    FirstKillNPC = First Blood 772051421546625, FirstPlayerKill = Duelist 2489884143486750,
#    FirstUpgrade = First Building 583497417329015, Cash10k = War Chest 1847488248714137,
#    PlayerKills10 = Hunter 2976613716370877. Originally 16 stayed 0; codebot_v170 wired 5 more (11 remain for the daily routine).
#  * Award on unlock unchanged (pcall, UserHasBadgeAsync first, retried). Backfill on join (BackfillBadges): every
#    already-unlocked achievement with a BadgeId is awarded if not owned, throttled, pcall, NOT gated by Live, admins
#    included; one in-flight award per player + badge.
import os as _os134
import subprocess as _sp134
import sys as _sys134
from pathlib import Path as _P134


def _cb134(cond, label):
    if "ok" in globals() and "bad" in globals():
        (ok if cond else bad)(label)
    else:
        print(("PASS " if cond else "FAIL ") + label)
        if not cond:
            raise SystemExit(1)


def _rd134(p):
    q = _P134(p)
    return q.read_text(encoding="utf-8") if q.is_file() else ""


def _block134(src, key):
    i = src.find("\t\t" + key + " = {")
    j = src.find("\n\t\t},", i)
    return src[i:j] if i >= 0 and j > i else ""


_S134 = "src/ServerScriptService/Server/"
# v135 (Code Bot Roblox): retired WE_Build pins, superseded in tools/checks/codebot_v135.py
# for _f in (_S134 + "Services/DataService.luau", _S134 + "Services/BaseService.luau", _S134 + "EarlyRemotes.server.luau"):
#     _cb134('SetAttribute("WE_Build", 134)' in _rd134(_f), "CODEBOT v134: WE_Build=134 " + _f.rsplit("/", 1)[-1])
# _cb134("WE_Build=134" in _rd134(_S134 + "Services/DataService.luau"), "CODEBOT v134: DataService profile-loaded log says WE_Build=134")

# ── the 5 badge ids ──
_AC = _rd134("src/ReplicatedStorage/Shared/Configs/AchievementConfig.luau")
_IDS = {"FirstKillNPC": 772051421546625, "FirstPlayerKill": 2489884143486750, "FirstUpgrade": 583497417329015,
        "Cash10k": 1847488248714137, "PlayerKills10": 2976613716370877}
for _k, _v in _IDS.items():
    _b = _block134(_AC, _k)
    _cb134(_b != "" and ("BadgeId = %d," % _v) in _b, "CODEBOT v134: %s BadgeId = %d" % (_k, _v))
_cb134(_AC.count("BadgeId = 0,") == 11, "CODEBOT v134: 11 achievements keep BadgeId 0 (v170 wired batch 2; daily routine): %d" % _AC.count("BadgeId = 0,"))
_cb134('"Build your first base building."' not in _AC and "Title = \"First Building\"" in _block134(_AC, "FirstUpgrade"),
       "CODEBOT v134: First Building badge = FirstUpgrade (Title First Building)")

# ── award path + backfill ──
_AS = _rd134(_S134 + "Services/AchievementService.luau")
_cb134("BadgeService:UserHasBadgeAsync(player.UserId, bid)" in _AS and "BadgeService:AwardBadge(player.UserId, bid)" in _AS
       and "if okH and has == true then\n\t\t\tbreak" in _AS and "local okA, res = pcall(function()" in _AS,
       "CODEBOT v134: award = pcall, UserHasBadgeAsync first (owned = skip), AwardBadge retried")
_cb134("task.spawn(awardBadge, player, def)" in _AS, "CODEBOT v134: awarded on unlock (Grant)")
_cb134("local badgeInFlight: { [Player]: { [number]: boolean } } = {}" in _AS and "if fl[bid] then\n\t\treturn\n\tend" in _AS,
       "CODEBOT v134: one in-flight award per player + badge (unlock + backfill never double-award)")
_cb134("function AchievementService.BackfillBadges(player: Player): { string }" in _AS
       and "profile.Achievements[def.Id] == true and (tonumber(def.BadgeId) or 0) > 0" in _AS
       and "local ok, err = pcall(awardBadge, player, def)" in _AS and "task.wait(AchievementConfig.Badges.SyncGapSeconds)" in _AS,
       "CODEBOT v134: BackfillBadges awards every unlocked achievement's non-zero badge, pcall, throttled SyncGapSeconds")
_ol = _AS[_AS.find("d.DataService.OnProfileLoaded(function(player: Player)"):][:700]
_cb134("if not live(player.UserId) then\n\t\t\t\treturn" not in _ol and "local ok, err = pcall(syncBadges, player)" in _ol
       and "if live(player.UserId) then\n\t\t\t\t\t\tAchievementService.Check(player)" in _ol,
       "CODEBOT v134: the backfill runs on every profile load (not gated by Live), after the Live Check")
_cb134("admin" not in _AS[_AS.find("local function syncBadges"):_AS.find("function AchievementService.BackfillBadges")].lower(),
       "CODEBOT v134: no admin exclusion in the badge backfill (admins get badges; only leaderboards exclude them)")
_cb134("badgeInFlight[player] = nil" in _AS, "CODEBOT v134: in-flight map cleared on PlayerRemoving")

# ── untouched ──
_cb134("PreferMesh = true" not in _rd134("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau"), "CODEBOT v134: PreferMesh stays OFF")
_cb134("FastTravelEnabled = false" in _rd134("src/ReplicatedStorage/Shared/Configs/MapConfig.luau"), "CODEBOT v134: fast travel stays REMOVED")

# ── the Luau CLI achievement test (incl. the v134 backfill cases) ──
_luau = _os134.environ.get("LUAU")
if _luau is None and _os134.environ.get("LUAU_COMPILE"):
    _cand = _os134.environ["LUAU_COMPILE"].replace("luau-compile", "luau")
    _luau = _cand if _os134.path.isfile(_cand) else None
if _luau:
    _r = _sp134.run([_sys134.executable, "tools/sim/run_achievement_test.py"], capture_output=True, text=True, env=dict(_os134.environ, LUAU=_luau))
    _cb134(_r.returncode == 0 and "ACHIEVEMENT TEST: 0 failed" in _r.stdout, "CODEBOT v134: run_achievement_test.py (wired ids + join backfill)")
else:
    print("SKIP CODEBOT v134: Luau CLI achievement test (set LUAU)")
