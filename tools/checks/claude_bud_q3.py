# claude-bud queue 3 (2026-09-29, jobs 13-15). Runs inside tools/BuyPathStatic.py (its globals). Helpers: _q3_.
import os as _q3_os
import subprocess as _q3_sp
import tempfile as _q3_tf
import sys as _q3_sys
_q3_ec = "src/ReplicatedStorage/Shared/Configs/EngagementConfig.luau"
_q3_es = "src/ServerScriptService/Server/Services/EngagementService.luau"

# ── JOB 13 bring players back ──
_q3_e = read(_q3_ec) or ""
_q3_ro = re.search(r"\tRollout = \{(.*?)\n\t\}", _q3_e, re.S)
(ok if _q3_ro and set(re.findall(r'(\w+) = "owner"', _q3_ro.group(1))) == {"Events", "Leaderboards", "Invite", "Friends", "Comeback"} else bad)(
    "CLAUDE-BUD J13: events / leaderboards / invite / friends / comeback ship owner-only")
(ok if len(re.findall(r'\{ Id = "\w+", Name = "[A-Z ]+", Window = "(?:Weekend|Week)"', _q3_e)) >= 3 else bad)("CLAUDE-BUD J13: a weekly event rotation from a data table (3+ events)")
must_contain(_q3_ec, "function EngagementConfig.EventAt(now: number): (any?, number, any?)", "CLAUDE-BUD J13: the schedule is one pure function (server + client banner)")
must_contain("src/ServerScriptService/Server/Services/EconomyService.luau", "mult *= (ES :: any).CashMult(player)", "CLAUDE-BUD J13: Double Cash events apply in the cash stack")
must_contain("src/ServerScriptService/Server/Services/SupplyDropService.luau", "(frenzy or SupplyDropConfig.Airdrop.IntervalSeconds)", "CLAUDE-BUD J13: Airdrop Frenzy shortens the interval")
must_contain("src/ServerScriptService/Server/Modules/PlazaBounty.luau", 'econ.AddCash(player, math.floor(PlazaBountyConfig.Cash * mult), "plaza_bounty")', "CLAUDE-BUD J13: Plaza War Week multiplies the bounty")
for _b in ("WE_LB_Cash_v1", "WE_LB_Plaza_v1", "WE_LB_Rebirths_v1"):
    must_contain(_q3_ec, _b, f"CLAUDE-BUD J13: leaderboard store {_b}")
must_contain(_q3_es, "DataStoreService:GetOrderedDataStore(b.Store):SetAsync(tostring(player.UserId), v)", "CLAUDE-BUD J13: scores written to OrderedDataStores (pcall)")
must_contain(_q3_es, "DataStoreService:GetOrderedDataStore(b.Store):GetSortedAsync(false, E.TopN)", "CLAUDE-BUD J13: top N read (pcall)")
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

# ── claude-bud JOB 14: game feel (kill feed, vehicle numbers, raid report, sound pass), owner-only ──
_q3_gc = "src/ReplicatedStorage/Shared/Configs/GameFeelConfig.luau"
_q3_gs = "src/ServerScriptService/Server/Services/GameFeelService.luau"
_q3_gcl = "src/StarterPlayer/StarterPlayerScripts/Client/Modules/GameFeelClient.luau"
for _feat in ("KillFeed", "VehicleNumbers", "RaidReport", "SoundPass"):
    must_contain(_q3_gc, f'\t\t{_feat} = "all"', f"CLAUDE-BUD J14: {_feat} live for all (owner's v101 rule)")
must_contain(_q3_gs, "if killer == nil or killer == victim or (typeof(info) == \"table\" and info.Quiet == true) then", "CLAUDE-BUD J14: kill feed = PvP kills only, blast deaths stay quiet")
must_contain(_q3_gs, "if feedCount >= G.KillFeed.MaxPerSecond then", "CLAUDE-BUD J14: kill feed rate cap (dropped, never queued)")
must_contain(_q3_gs, "K = killer.DisplayName,", "CLAUDE-BUD J14: kill feed uses DisplayNames (never a nation)")
must_contain(_q3_gs, "task.delay(G.VehicleNumbers.AggregateSeconds, flushVehicle, model)", "CLAUDE-BUD J14: vehicle numbers merged (<= 4 pushes/s per vehicle)")
must_contain(_q3_gs, "if now - r.Last >= G.RaidReport.QuietSeconds then", "CLAUDE-BUD J14: one raid report after the attack goes quiet")
must_contain("src/ServerScriptService/Server/Modules/VehicleHealth.luau", "cue(model, rec.OwnerUserId, e.Def.DisplayName, dealt, attacker, hit.HitPos, false, inRadius)", "CLAUDE-BUD J14: vehicle damage cue hook")
must_contain("src/ServerScriptService/Server/Services/CombatService/init.luau", "Pos = opts.HitPos or CombatService._VehicleNumberPos(attacker, veh), -- claude-bud JOB 14", "CLAUDE-BUD J14: vehicle hit number without a hit point")
must_contain("src/ServerScriptService/Server/Services/PremiumWeaponService.luau", "VH.ApplyRadiusDamage(pos, radius, amount, player, P.Missile.Class, {", "CLAUDE-BUD J14: premium missile splash reaches vehicles")
must_contain("src/ServerScriptService/Server/Services/PremiumWeaponService.luau", "return uid == player.UserId or (o ~= nil and cs.IsClanAlly ~= nil and cs.IsClanAlly(player, o) == true)", "CLAUDE-BUD J14: missile splash spares own + clan vehicles")
must_contain("src/ServerScriptService/Server/Services/GateDefenseService.luau", 'require(script.Parent.GameFeelService).NoteRaid(ownerUserId, "Hit", attacker)', "CLAUDE-BUD J14: base hits open the raid report")
must_contain("src/ServerScriptService/Server/Services/MoneyCollectorService.luau", 'require(script.Parent.GameFeelService).NoteRaid(victim.UserId, "Robbed", thief, moved)', "CLAUDE-BUD J14: a robbery makes it YOU WERE RAIDED")
must_contain(_q3_gcl, r'b.Text = "BASE DEFENDED\n"', "CLAUDE-BUD J14: base defended banner")
must_contain(_q3_gcl, r'b.Text = string.format("YOU WERE RAIDED\n-$%s%s"', "CLAUDE-BUD J14: raided banner")
must_contain(_q3_gcl, 'pcall(H.RegisterTopStack, "KillFeed", frame, K.Order)', "CLAUDE-BUD J14: kill feed in the managed top stack")
must_contain(_q3_gcl, "bb.MaxDistance = 40", "CLAUDE-BUD J14: vehicle numbers MaxDistance <= 40")
must_not_contain(_q3_gcl, "AlwaysOnTop = true", "CLAUDE-BUD J14: no AlwaysOnTop numbers")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Modules/AudioController.luau", "v = math.clamp(v, band[1], band[2]) -- claude-bud JOB 14 sound pass (SoundConfig.Mix.Bands)", "CLAUDE-BUD J14: volume bands")
must_contain("src/ReplicatedStorage/Shared/Configs/SoundConfig.luau", "\tBandsLive = false,", "CLAUDE-BUD J14: bands off by default (OFF = old)")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Modules/PremiumWeaponsClient.luau", 'GF.Sound("PremiumGun", d.F)', "CLAUDE-BUD J14: premium gun not silent")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Modules/PremiumWeaponsClient.luau", 'GF.Sound("PremiumMissile", d.F)', "CLAUDE-BUD J14: missile launch not silent")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/FeatureController.luau", 'feelSound("Marker")', "CLAUDE-BUD J14: markers not silent")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/FeatureController.luau", 'feelSound("Tap")', "CLAUDE-BUD J14: AIRSTRIKE tap not silent")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Modules/EngagementClient.luau", 'pcall((GF :: any).Sound, "EventStart")', "CLAUDE-BUD J14: event banner not silent")
_r14 = _q3_sp.run([_q3_sys.executable, str(ROOT / "tools" / "sound_audit.py")], capture_output=True, text=True, timeout=60)
(ok if _r14.returncode == 0 else bad)("CLAUDE-BUD J14: sound audit (every played key exists, every bus has a band) " + (_r14.stdout.strip().splitlines() or ["?"])[-1])
if _q3_luau:
    _r14b = _q3_sp.run([_q3_sys.executable, str(ROOT / "tools" / "gamefeel_test.py")], capture_output=True, text=True, timeout=120, env=dict(_q3_os.environ, LUAU=_q3_luau))
    _last = (_r14b.stdout.strip().splitlines() or ["?"])[-1]
    (ok if _r14b.returncode == 0 else bad)("CLAUDE-BUD J14: GameFeelService executed (kill feed, merged vehicle numbers, raid report; owner-only) " + _last)

# ── claude-bud JOB 15: anti-exploit sweep (RemoteGate + SecurityConfig) ──
must_contain("src/ReplicatedStorage/Shared/Configs/SecurityConfig.luau", '\t\tRollout = "observe",', "CLAUDE-BUD J15: gate observe-only for everyone until the owner reads the logs")
must_contain("src/ReplicatedStorage/Shared/Configs/SecurityConfig.luau", '\t\tOthers = "observe", -- "observe" | "off"', "CLAUDE-BUD J15: everyone else observe-only (logs, never drops)")
must_contain("src/ServerScriptService/Server/Modules/RemoteSetup.luau", "\tsinkClientOnly(folder :: Folder)", "CLAUDE-BUD J15: push-only remotes get a sink listener")
_r15 = _q3_sp.run([_q3_sys.executable, str(ROOT / "tools" / "remote_audit.py")], capture_output=True, text=True, timeout=60)
(ok if _r15.returncode == 0 else bad)("CLAUDE-BUD J15: remote audit (every handler gated + schema; every client-fired remote has a schema) " + (_r15.stdout.strip().splitlines() or ["?"])[-1])
if _q3_luau:
    _r15b = _q3_sp.run([_q3_sys.executable, str(ROOT / "tools" / "remotegate_test.py")], capture_output=True, text=True, timeout=120, env=dict(_q3_os.environ, LUAU=_q3_luau))
    (ok if _r15b.returncode == 0 else bad)("CLAUDE-BUD J15: RemoteGate executed (schemas, ceilings, throttled logs, flood kick, observe) " + (_r15b.stdout.strip().splitlines() or ["?"])[-1])
