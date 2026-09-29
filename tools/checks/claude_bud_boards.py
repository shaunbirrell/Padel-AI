# claude-bud BOARDS (2026-09-29): the Town Centre notice boards (LeaderboardConfig + EngagementService +
# EngagementClient + the Robux accounting in MonetizationService). Throttled writes, confirmed-only Robux, kill
# validation, one shared fetch, opt-out, crowns. Executes LeaderboardConfig's pure helpers with the Luau CLI.
import os as _b_os
import subprocess as _b_sp
import tempfile as _b_tf

_b_cfg = "src/ReplicatedStorage/Shared/Configs/LeaderboardConfig.luau"
_b_es = "src/ServerScriptService/Server/Services/EngagementService.luau"
_b_ec = "src/StarterPlayer/StarterPlayerScripts/Client/Modules/EngagementClient.luau"
_b_ms = "src/ServerScriptService/Server/Services/MonetizationService.luau"
_b_c = read(_b_cfg) or ""
_b_s = read(_b_es) or ""
_b_m = read(_b_ms) or ""

# the six boards, all-time + weekly where asked
for _id, _title in (("Kills", "MOST KILLS"), ("Richest", "RICHEST"), ("Supporters", "TOP SUPPORTERS"), ("Plaza", "PLAZA CONQUEROR"), ("Rebirths", "REBIRTH KINGS"), ("Army", "TOP ARMY")):
    must_contain(_b_cfg, f'{{ Id = "{_id}", Title = "{_title}"', f"CLAUDE-BUD BOARDS: board {_title}")
must_contain(_b_cfg, '{ Id = "Kills", Title = "MOST KILLS", Unit = "kills", AllTime = true, Weekly = true }', "CLAUDE-BUD BOARDS: kills all-time + weekly")
must_contain(_b_cfg, '{ Id = "Plaza", Title = "PLAZA CONQUEROR", Unit = "captures", AllTime = false, Weekly = true }', "CLAUDE-BUD BOARDS: plaza weekly")
must_not_contain(_b_cfg, "IsPlaytestOwner", "CLAUDE-BUD BOARDS: live for all (no owner gate)")
must_not_contain(_b_es, 'if not live("Leaderboards", player) then', "CLAUDE-BUD BOARDS: board writes no longer sit behind the Engagement owner gate")

# throttled writes (60-120 s per player, plus on leave), shared reads (60-90 s), pcall + back-off
_w = re.search(r"WriteMinSeconds = (\d+)", _b_c)
_r = re.search(r"ReadSeconds = (\d+)", _b_c)
(ok if _w and 60 <= int(_w.group(1)) <= 120 else bad)(f"CLAUDE-BUD BOARDS: per-player write throttle 60-120 s ({_w.group(1) if _w else '?'})")
(ok if _r and 60 <= int(_r.group(1)) <= 90 else bad)(f"CLAUDE-BUD BOARDS: shared board refresh 60-90 s ({_r.group(1) if _r else '?'})")
must_contain(_b_es, "if not force and not LeaderboardConfig.WriteDue(lastWriteAt[player.UserId], now) then", "CLAUDE-BUD BOARDS: writes throttled per player")
must_contain(_b_es, "writeScores(p, true) -- claude-bud BOARDS: once on leave (ignores the per-player throttle)", "CLAUDE-BUD BOARDS: a write on leave")
must_contain(_b_es, "if v > 0 and prev[key] ~= v and budgetOk(Enum.DataStoreRequestType.SetIncrementSortedAsync) then", "CLAUDE-BUD BOARDS: only changed, non-zero values; request budget respected")
must_contain(_b_es, "storeFor(key, unix):SetAsync(tostring(player.UserId), v)", "CLAUDE-BUD BOARDS: OrderedDataStore write inside pcall")
must_contain(_b_es, "return storeFor(key, unix):GetSortedAsync(false, LB.FetchN):GetCurrentPage()", "CLAUDE-BUD BOARDS: one shared top-N fetch per board (pcall)")
must_contain(_b_es, 'fail("Write")', "CLAUDE-BUD BOARDS: write back-off")
must_contain(_b_es, 'fail("Read")', "CLAUDE-BUD BOARDS: read back-off")
must_contain(_b_es, "if now - lastRead >= LeaderboardConfig.ReadSeconds then", "CLAUDE-BUD BOARDS: one server-wide refresh timer (not per player)")
must_contain(_b_cfg, 'return LeaderboardConfig.StorePrefix .. id .. "_W" .. LeaderboardConfig.IsoWeek(now)', "CLAUDE-BUD BOARDS: a separate weekly store per ISO week")

# kill validation: the server's creator tag (CombatService.OnPlayerDeath), never self / clan mate, anti-farm 3 / 10 min
must_contain(_b_es, "d.CombatService.OnPlayerDeath(function(victim: Player, killer: Player?, _info: any)", "CLAUDE-BUD BOARDS: kills from the server's death listener (creator tag)")
must_contain(_b_es, "if killer == nil or killer == victim or killer.Parent == nil then", "CLAUDE-BUD BOARDS: no self / unknown killer")
must_contain(_b_es, "local allied = cs ~= nil and cs.IsClanAlly ~= nil and cs.IsClanAlly(killer, victim) == true", "CLAUDE-BUD BOARDS: no teammate (clan) kills")
must_contain(_b_es, "if not LeaderboardConfig.AllowKill(killLog, killer.UserId, victim.UserId, allied, os.clock()) then", "CLAUDE-BUD BOARDS: anti-farm pair window")
must_contain(_b_cfg, "KillPairMax = 3,", "CLAUDE-BUD BOARDS: same victim at most 3 times ...")
must_contain(_b_cfg, "KillPairWindowSeconds = 600,", "CLAUDE-BUD BOARDS: ... per 10 minutes")

# Robux: confirmed only (receipt CurrencySpent saved before the ack; a pass after UserOwnsGamePassAsync, real price)
_rp = _b_m.find("event.FirstPurchase = recordPurchase(profile, event.CurrencySpent)")
_mp = _b_m.find("markProcessed(profile, receiptId)", _rp)
_sv = _b_m.find("DataService.SaveProfile", _mp)
(ok if 0 <= _rp < _mp < _sv else bad)("CLAUDE-BUD BOARDS: dev product Robux (CurrencySpent) recorded in ProcessReceipt with the grant, saved before PurchaseGranted")
_cf = _b_m.find("local function confirmPassPurchase(")
_own = _b_m.find("MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)", _cf)
_price = _b_m.find("MarketplaceService:GetProductInfo(passId, Enum.InfoType.GamePass)", _cf)
_rec = _b_m.find("first = recordPurchase(profile, price)", _cf)
(ok if 0 <= _cf < _own < _price < _rec else bad)("CLAUDE-BUD BOARDS: a game pass counts only after UserOwnsGamePassAsync confirms it, at the real PriceInRobux")
must_contain(_b_ms, "if not wasOwned then", "CLAUDE-BUD BOARDS: a pass counts once")
must_contain(_b_es, "if spent > 0 and settings.SupporterBoardOptOut ~= true then", "CLAUDE-BUD BOARDS: Robux never shown for non-buyers or opted-out players")
must_contain(_b_es, 'storeFor("Supporters", os.time()):RemoveAsync(tostring(player.UserId))', "CLAUDE-BUD BOARDS: opting out removes the entry")
must_contain("src/ReplicatedStorage/Shared/Configs/SecurityConfig.luau", 'RequestBoardSetting = { "boolean" },', "CLAUDE-BUD BOARDS: opt-out remote schema (RemoteGate)")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/SettingsController.luau", 'supBtn.Text = if hidden then "Supporter board: HIDDEN" else "Supporter board: SHOWN"', "CLAUDE-BUD BOARDS: Settings toggle")

# the boards on the client: MaxDistance, no AlwaysOnTop, spotlights without shadows, "You:" line, medals
must_contain(_b_ec, "sg.MaxDistance = L.MaxDistance", "CLAUDE-BUD BOARDS: SurfaceGui MaxDistance from config")
must_contain(_b_cfg, "MaxDistance = 80, -- SurfaceGui cap (CLAUDE.md budget)", "CLAUDE-BUD BOARDS: MaxDistance <= 80")
must_not_contain(_b_ec, "AlwaysOnTop = true", "CLAUDE-BUD BOARDS: no AlwaysOnTop")
must_contain(_b_ec, "light.Shadows = false", "CLAUDE-BUD BOARDS: spotlights never cast shadows")
must_contain(_b_ec, 'return string.format("You: %s · %s%s", rt, valueText(v, b.Def.Money == true), unit)', "CLAUDE-BUD BOARDS: your own rank near a board")
must_contain(_b_es, "bb.MaxDistance = LB.CrownMaxDistance", "CLAUDE-BUD BOARDS: weekly #1 crown (MaxDistance capped)")

# the pure helpers, executed
_b_luau = _b_os.environ.get("LUAU")
if not _b_luau and _b_os.environ.get("LUAU_COMPILE"):
    for _n in ("luau.exe", "luau"):
        _p = _b_os.path.join(_b_os.path.dirname(_b_os.environ["LUAU_COMPILE"]), _n)
        if _b_os.path.exists(_p):
            _b_luau = _p
if _b_luau:
    _src = _b_c.replace("Vector3.new(14, 22, 1)", "{ X = 14, Y = 22, Z = 1 }")
    _code = "local L = (function()\n" + _src + "\nend)()\n" + r'''
local fails = 0
local function check(ok, label) print((ok and "PASS " or "FAIL ") .. label); if not ok then fails += 1 end end
local function day(y, m, d) return os.time({ year = y, month = m, day = d, hour = 12 }) end
check(L.IsoWeek(day(2026, 1, 1)) == "2026W01", "ISO 2026-01-01 (Thu) = 2026W01 " .. L.IsoWeek(day(2026, 1, 1)))
check(L.IsoWeek(day(2024, 12, 30)) == "2025W01", "ISO 2024-12-30 (Mon) = 2025W01 " .. L.IsoWeek(day(2024, 12, 30)))
check(L.IsoWeek(day(2021, 1, 3)) == "2020W53", "ISO 2021-01-03 (Sun) = 2020W53 " .. L.IsoWeek(day(2021, 1, 3)))
check(L.IsoWeek(day(2026, 9, 28)) == L.IsoWeek(day(2026, 10, 4)) and L.IsoWeek(day(2026, 10, 4)) ~= L.IsoWeek(day(2026, 10, 5)), "a week runs Monday to Sunday")
local log = {}
local n = 0
for i = 1, 5 do if L.AllowKill(log, 10, 20, false, i) then n += 1 end end
check(n == 3, "the same victim counts 3 times per window (" .. n .. ")")
check(L.AllowKill(log, 10, 21, false, 6) == true, "another victim still counts")
check(L.AllowKill(log, 10, 20, false, 1 + L.KillPairWindowSeconds) == true, "the window slides: the pair counts again after 10 min")
check(L.AllowKill(log, 10, 10, false, 9999) == false, "no self kills")
check(L.AllowKill(log, 10, 30, true, 9999) == false, "no clan-mate kills")
check(L.WriteDue(nil, 0) and not L.WriteDue(100, 100 + L.WriteMinSeconds - 1) and L.WriteDue(100, 100 + L.WriteMinSeconds), "per-player write throttle")
check(L.StoreName("Kills", true, day(2026, 10, 1)) == "WE_LB2_Kills_W2026W40" and L.StoreName("Kills", false, 0) == "WE_LB2_Kills", "weekly vs all-time store names")
print(fails == 0 and "ALL PASS" or ("FAILS " .. fails))
'''
    with _b_tf.NamedTemporaryFile("w", suffix=".luau", delete=False, encoding="utf-8") as _f:
        _f.write(_code)
        _tmp = _f.name
    _res = _b_sp.run([_b_luau, _tmp], capture_output=True, text=True, timeout=60)
    _b_os.unlink(_tmp)
    _out = (_res.stdout + _res.stderr).strip()
    (ok if "ALL PASS" in _out else bad)("CLAUDE-BUD BOARDS: ISO week, anti-farm, throttle executed (Luau CLI) " + (_out.splitlines()[-1] if _out else "?") + ("" if "ALL PASS" in _out else " :: " + _out.replace("\n", " | ")[:600]))
