# claude-bud queue 3 (2026-09-29, jobs 13-15). Runs inside tools/BuyPathStatic.py (its globals). Helpers: _q3_.
import os as _q3_os
import subprocess as _q3_sp
import tempfile as _q3_tf
_q3_ec = "src/ReplicatedStorage/Shared/Configs/EngagementConfig.luau"
_q3_es = "src/ServerScriptService/Server/Services/EngagementService.luau"

# ── JOB 13 bring players back ──
_q3_e = read(_q3_ec) or ""
_q3_ro = re.search(r"\tRollout = \{(.*?)\n\t\}", _q3_e, re.S)
# v104 (Code Bot): moved pin (owner-only -> "all", owner 2026-09-29); the all-players pin is in tools/checks/codebot_v104.py
(ok if _q3_ro and set(re.findall(r'(\w+) = "(?:owner|all)"', _q3_ro.group(1))) == {"Events", "Leaderboards", "Invite", "Friends", "Comeback"} else bad)(
    "CLAUDE-BUD J13: events / leaderboards / invite / friends / comeback each have a Rollout (owner-only in v103, all in v104)")
(ok if len(re.findall(r'\{ Id = "\w+", Name = "[A-Z ]+", Window = "(?:Weekend|Week)"', _q3_e)) >= 3 else bad)("CLAUDE-BUD J13: a weekly event rotation from a data table (3+ events)")
must_contain(_q3_ec, "function EngagementConfig.EventAt(now: number): (any?, number, any?)", "CLAUDE-BUD J13: the schedule is one pure function (server + client banner)")
must_contain("src/ServerScriptService/Server/Services/EconomyService.luau", "mult *= (ES :: any).CashMult(player)", "CLAUDE-BUD J13: Double Cash events apply in the cash stack")
must_contain("src/ServerScriptService/Server/Services/SupplyDropService.luau", "(frenzy or SupplyDropConfig.Airdrop.IntervalSeconds)", "CLAUDE-BUD J13: Airdrop Frenzy shortens the interval")
must_contain("src/ServerScriptService/Server/Modules/PlazaBounty.luau", 'econ.AddCash(player, math.floor(PlazaBountyConfig.Cash * mult), "plaza_bounty")', "CLAUDE-BUD J13: Plaza War Week multiplies the bounty")
for _b in ("WE_LB_Cash_v1", "WE_LB_Plaza_v1", "WE_LB_Rebirths_v1"):
    must_contain(_q3_ec, _b, f"CLAUDE-BUD J13: leaderboard store {_b}")
must_contain(_q3_es, "DataStoreService:GetOrderedDataStore(b.Store):SetAsync(tostring(player.UserId), v)", "CLAUDE-BUD J13: scores written to OrderedDataStores (pcall)")
# v104 (Code Bot): moved pin (reads TopN + 5 so admin rows can be dropped; the new pin is in tools/checks/codebot_v104.py)
must_contain(_q3_es, "DataStoreService:GetOrderedDataStore(b.Store):GetSortedAsync(false, math.min(100, E.TopN + 5))", "CLAUDE-BUD J13: top N read (pcall)")
must_contain("src/ServerScriptService/Server/Services/TerritoryService/init.luau", "st.PlazaCaptures = (tonumber(st.PlazaCaptures) or 0) + 1", "CLAUDE-BUD J13: plaza captures counted for the board")
must_contain(_q3_es, "if ref == nil or ref <= 0 or ref == player.UserId or profile.ReferredBy ~= nil then", "CLAUDE-BUD J13: an invite pays once per invited account (never self)")
must_contain(_q3_es, "local room = math.max(0, E.InviteDailyCap - (tonumber(profile.InviteCount) or 0))", "CLAUDE-BUD J13: inviter rewards capped per day")
must_contain(_q3_es, "n = math.min(n, E.FriendsCap)", "CLAUDE-BUD J13: friends bonus capped")
must_contain(_q3_es, "if prev == nil or prev <= 0 or os.time() - prev < E.ComebackDays * 86400 then", "CLAUDE-BUD J13: comeback after 3+ days away")
must_contain("src/ServerScriptService/Server/Services/DataService.luau", ";(profile :: any).PrevJoinUnix = profile.LastJoinUnix", "CLAUDE-BUD J13: the previous join is kept for the comeback check")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ShopController.luau", 'game:GetService("SocialService"):PromptGameInvite(lp)', "CLAUDE-BUD J13: invite through Roblox's social prompt")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Modules/EngagementClient.luau", 'pcall((HudLayout :: any).RegisterTopStack, "EventBanner", label, 45)', "CLAUDE-BUD J13: event banner in the HUD top stack")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Modules/EngagementClient.luau", "sg.MaxDistance = 80", "CLAUDE-BUD J13: board SurfaceGui MaxDistance <= 80")
# the schedule, executed with the Luau CLI when available (Saturday = weekend event on, Wednesday = weekend event off)
_q3_luau = _q3_os.environ.get("LUAU")
if not _q3_luau and _q3_os.environ.get("LUAU_COMPILE"):
    for _n in ("luau.exe", "luau"):
        _p = _q3_os.path.join(_q3_os.path.dirname(_q3_os.environ["LUAU_COMPILE"]), _n)
        if _q3_os.path.exists(_p):
            _q3_luau = _p
if _q3_luau:
    _src = _q3_e.replace("(require(script.Parent.AdminConfig) :: any).IsPlaytestOwner(userId)", "false")
    _code = "local E = (function()\n" + _src + "\nend)()\n" + r'''
local base = 1759536000 -- 2025-10-04 00:00 UTC, a Saturday
local out = {}
for w = 0, 5 do
	local sat = base + w * 7 * 86400
	local wed = sat - 3 * 86400
	local a = E.EventAt(sat)
	local b, _, nxt = E.EventAt(wed)
	table.insert(out, (a and a.Id or "none") .. "/" .. (b and b.Id or ("next:" .. (nxt and nxt.Id or "none"))))
end
print(table.concat(out, ","))
'''
    with _q3_tf.NamedTemporaryFile("w", suffix=".luau", delete=False, encoding="utf-8") as _f:
        _f.write(_code)
        _tmp = _f.name
    _r = _q3_sp.run([_q3_luau, _tmp], capture_output=True, text=True, timeout=60)
    _q3_os.unlink(_tmp)
    _res = _r.stdout.strip()
    _parts = _res.split(",") if _res else []
    _weekend_ok = all(("/" in x) and not x.split("/")[0] == "none" for x in _parts)
    (ok if len(_parts) == 6 and _weekend_ok else bad)(f"CLAUDE-BUD J13: event schedule runs (every Saturday has an event; weekday / weekend windows) {_res or _r.stderr[:200]}")
