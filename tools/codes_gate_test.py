#!/usr/bin/env python3
"""Code Bot v102 (2026-09-29): executes the REAL redeem-codes code with the Luau CLI (no Studio needed).

Loads the real Server/Configs/CodesConfig.luau, Server/Services/CodesService.luau and Server/Services/RateLimitService.luau
(plus the real EconomyService.CashBoostMult and ProfileSchema ensureCodesFields function bodies, sliced from their files)
under small mocks for the Roblox globals / DataService / EconomyService / RemoteSetup, then drives the RedeemCode
RemoteFunction handler the way a client would. Checks: BUDSTUDIOS pays $50,000 (reason "code") + a 30 min 2x boost and
is saved; case / spaces ignored; once per player (AlreadyUsed); unknown / junk = Invalid; inactive + past-expiry =
Expired; a bad date never makes a code live; 5 tries per minute then RateLimited; boost stacking; save sanitising.
Prints PASS / FAIL lines, exits 1 on any FAIL; SKIP (exit 0) without the luau binary.
"""
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRV = ROOT / "src/ServerScriptService/Server"


def slice_fn(path: Path, header: str) -> str:
    src = path.read_text(encoding="utf-8")
    i = src.index(header)
    j = src.index("\nend\n", i) + 5
    return src[i:j]


def lstr(s: str) -> str:
    eq = "=" * 8
    return "[%s[%s]%s]" % (eq, s, eq)


HARNESS = r'''
typeof = function(v) return type(v) end
local fails, passes = 0, 0
local function check(cond, label)
	if cond then passes += 1; print("PASS " .. label) else fails += 1; print("FAIL " .. label) end
end
-- days-from-civil (UTC), so the DateTime mock never depends on the box time zone
local function unixUTC(y, m, d, h, mi, s)
	y = if m <= 2 then y - 1 else y
	local era = (if y >= 0 then y else y - 399) // 400
	local yoe = y - era * 400
	local mp = (m + 9) % 12
	local doy = (153 * mp + 2) // 5 + d - 1
	local doe = yoe * 365 + yoe // 4 - yoe // 100 + doy
	local days = era * 146097 + doe - 719468
	return days * 86400 + h * 3600 + mi * 60 + s
end
DateTime = {
	fromUniversalTime = function(y, m, d, h, mi, s)
		assert(m >= 1 and m <= 12 and d >= 1 and d <= 31, "bad date")
		return { UnixTimestamp = unixUTC(y, m, d, h, mi, s) }
	end,
	fromIsoDate = function(str)
		local y, m, d, h, mi, s = string.match(str, "^(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d):(%d%d)Z$")
		if not y then return nil end
		return { UnixTimestamp = unixUTC(tonumber(y), tonumber(m), tonumber(d), tonumber(h), tonumber(mi), tonumber(s)) }
	end,
}
check(DateTime.fromUniversalTime(2026, 9, 29, 0, 0, 0).UnixTimestamp == 1790640000, "harness: UTC date maths")
warn = function(...) print("WARN", ...) end
task = { spawn = function(f, ...) local co = coroutine.create(f); coroutine.resume(co, ...) end, wait = function() coroutine.yield() end }

local function proxy(name)
	return setmetatable({ __name = name }, { __index = function(t, k) local p = proxy(k); rawset(t, k, p); return p end })
end
local Shared = proxy("Shared")
game = { GetService = function(_, n)
	if n == "ReplicatedStorage" then return { WaitForChild = function() return Shared end } end
	return { GetPlayers = function() return {} end, PlayerRemoving = { Connect = function() end } }
end }
script = proxy("script")
local MODS = {}
local SRC = {}
SRC.CodesConfig = @CODESCONFIG@
SRC.CodesService = @CODESSERVICE@
SRC.RateLimitService = @RATELIMIT@
MODS.Constants = { RemoteNames = { RedeemCode = "RedeemCode", CodeStateUpdate = "CodeStateUpdate" } }
MODS.AnalyticsConfig = { Events = { CODE_REDEEM = "CODE_REDEEM" } }
local function load(name) local f = assert(loadstring(SRC[name], name)); return f() end
require = function(p) local n = rawget(p, "__name"); if MODS[n] == nil then MODS[n] = load(n) end; return MODS[n] end

-- config under test: the real CodesConfig + a few test-only codes (added BEFORE CodesService builds its lookup)
local CC = require(proxy("CodesConfig"))
check(CC.Codes.BUDSTUDIOS ~= nil and CC.Codes.BUDSTUDIOS.Active == true, "config: BUDSTUDIOS active")
check(CC.Codes.BUDSTUDIOS.Rewards.Cash == 50000 and CC.Codes.BUDSTUDIOS.Rewards.CashBoostMinutes == 30, "config: BUDSTUDIOS = $50,000 + 30 min boost")
check(CC.Codes.BUDSTUDIOS.Expires == nil, "config: BUDSTUDIOS has no expiry")
check(CC.TriesPerMinute == 5 and CC.CashBoostMult == 2, "config: 5 tries/min, 2x boost")
CC.Codes.OLDCODE = { Active = true, Expires = "2000-01-01", Rewards = { Cash = 1 } }
CC.Codes.lowerfuture = { Active = true, Expires = "2999-12-31", Rewards = { Cash = 7, Gold = 3 } }
CC.Codes.BADDATE = { Active = true, Expires = "31/12/2999", Rewards = { Cash = 1 } }
CC.Codes.EXACTPAST = { Active = true, Expires = "2001-02-03T04:05:06Z", Rewards = { Cash = 1 } }
CC.Codes.BOOST2 = { Active = true, Rewards = { CashBoostMinutes = 30 } }

-- mocks
local profiles, saves, cash, gold, pushes = {}, {}, {}, {}, 0
local function mkPlayer(id)
	local p = { UserId = id, attrs = {} }
	function p:SetAttribute(k, v) self.attrs[k] = v end
	function p:GetAttribute(k) return self.attrs[k] end
	profiles[id] = { RedeemedCodes = {}, CashBoost = { Until = 0, Mult = 1 } }
	cash[id], gold[id], saves[id] = {}, 0, 0
	return p
end
local DataService = {
	GetProfile = function(p) return profiles[p.UserId] end,
	IsLoaded = function(p) return profiles[p.UserId] ~= nil end,
	MarkDirty = function() end,
	SaveProfile = function(p) saves[p.UserId] += 1; return true end,
	OnProfileLoaded = function() end,
}
local EconomyService = {
	AddCash = function(p, n, reason) table.insert(cash[p.UserId], { n, reason }); return true end,
	AddGold = function(p, n) gold[p.UserId] += n; return true end,
}
local fn = {}
local RemoteSetup = { Get = function(name)
	if name == "RedeemCode" then return fn end
	return { FireClient = function() pushes += 1 end }
end }
local CodesService = require(proxy("CodesService"))
CodesService.Init({ DataService = DataService, EconomyService = EconomyService, RateLimitService = require(proxy("RateLimitService")),
	RemoteSetup = RemoteSetup, NotificationService = { Notify = function() end }, AnalyticsService = nil })
check(type(fn.OnServerInvoke) == "function", "RedeemCode RemoteFunction has an OnServerInvoke handler")

local a = mkPlayer(1)
local now = os.time()
local r = fn.OnServerInvoke(a, "budstudios")
check(r.Result == "Success", "lowercase budstudios -> Success (" .. tostring(r.Message) .. ")")
check(#cash[1] == 1 and cash[1][1][1] == 50000 and cash[1][1][2] == "code", "Success paid exactly $50,000 with reason code (multiplier-exempt)")
local b = profiles[1].CashBoost
check(b.Mult == 2 and b.Until >= now + 1800 and b.Until <= now + 1802, "Success started a 30 min 2x Cash boost")
check(a.attrs.WE_CashBoostUntil == b.Until, "boost end replicated as WE_CashBoostUntil")
check(type(profiles[1].RedeemedCodes.BUDSTUDIOS) == "number", "RedeemedCodes.BUDSTUDIOS stored in the profile")
check(saves[1] == 1, "profile saved right after the redeem")
check(string.find(r.Message, "$50,000", 1, true) ~= nil, "result message names $50,000")
r = fn.OnServerInvoke(a, "  Bud Studios ")
check(r.Result == "AlreadyUsed", "second try (other case + spaces) -> AlreadyUsed")
check(#cash[1] == 1, "AlreadyUsed pays nothing")

local c = mkPlayer(2)
check(fn.OnServerInvoke(c, "NOPE").Result == "Invalid", "unknown code -> Invalid")
check(fn.OnServerInvoke(c, 12345).Result == "Invalid", "non-string -> Invalid")
check(fn.OnServerInvoke(c, string.rep("A", 100)).Result == "Invalid", "100-char string -> Invalid")
check(fn.OnServerInvoke(c, "bud-studios").Result == "Invalid", "punctuation -> Invalid")
check(fn.OnServerInvoke(c, "WARFOUNDING").Result == "Expired", "inactive code -> Expired")
local d = mkPlayer(3)
check(fn.OnServerInvoke(d, "OLDCODE").Result == "Expired", "past date -> Expired")
check(fn.OnServerInvoke(d, "BADDATE").Result == "Expired", "unparseable date -> Expired (never live forever)")
check(fn.OnServerInvoke(d, "EXACTPAST").Result == "Expired", "past exact UTC time -> Expired")
r = fn.OnServerInvoke(d, "LowerFuture")
check(r.Result == "Success" and gold[3] == 3, "future expiry + lowercase config key -> Success with Gold")
check(fn.OnServerInvoke(d, "NOPE").Result == "Invalid", "5th try inside a minute still answered")
check(fn.OnServerInvoke(d, "LowerFuture").Result == "RateLimited", "6th try inside a minute -> RateLimited")
check(#cash[3] == 1, "expired / invalid / rate-limited tries paid nothing")

local e = mkPlayer(4)
fn.OnServerInvoke(e, "BUDSTUDIOS")
local u1 = profiles[4].CashBoost.Until
fn.OnServerInvoke(e, "BOOST2")
check(profiles[4].CashBoost.Until == u1 + 1800, "a second boost code adds its minutes on top of the running boost")

-- a fresh server (rejoin): the saved RedeemedCodes still blocks the code
local f = mkPlayer(5)
profiles[5].RedeemedCodes = { BUDSTUDIOS = 1790640000 }
check(fn.OnServerInvoke(f, "BUDSTUDIOS").Result == "AlreadyUsed", "saved RedeemedCodes (after rejoin) -> AlreadyUsed")
profiles[5].RedeemedCodes = { BUDSTUDIOS = true }
check(fn.OnServerInvoke(f, "budstudios").Result == "AlreadyUsed", "pre-v102 true flag -> AlreadyUsed")

-- EconomyService.CashBoostMult (real body)
local EconomyService2 = {}
@CASHBOOSTMULT@
check(EconomyService2.CashBoostMult({ CashBoost = { Until = os.time() + 60, Mult = 2 } }) == 2, "CashBoostMult = 2 while the boost runs")
check(EconomyService2.CashBoostMult({ CashBoost = { Until = os.time() - 1, Mult = 2 } }) == 1, "CashBoostMult = 1 after it ends")
check(EconomyService2.CashBoostMult({}) == 1 and EconomyService2.CashBoostMult(nil) == 1, "CashBoostMult = 1 with no boost")

-- ProfileSchema ensureCodesFields (real body)
local MAX_COUNTER = 1e15
@NONNEGINT@
@ENSURE@
local prof = { RedeemedCodes = { BUDSTUDIOS = 1790640000, OLD = true, [5] = true, BAD = "x", NAN = 0/0 }, CashBoost = { Until = "junk", Mult = 99 } }
ensureCodesFields(prof)
check(prof.RedeemedCodes.BUDSTUDIOS == 1790640000 and prof.RedeemedCodes.OLD == true, "save sanitising keeps real redeems")
check(prof.RedeemedCodes[5] == nil and prof.RedeemedCodes.BAD == nil and prof.RedeemedCodes.NAN == nil, "save sanitising drops junk")
check(prof.CashBoost.Until == 0 and prof.CashBoost.Mult == 1, "save sanitising resets a junk boost")
local fresh = {}
ensureCodesFields(fresh)
check(type(fresh.RedeemedCodes) == "table" and fresh.CashBoost.Until == 0, "old saves get RedeemedCodes + CashBoost defaults")

print(string.format("codes_gate_test PASS=%d FAIL=%d", passes, fails))
if fails > 0 then error("FAIL") end
'''


def build() -> str:
    econ = slice_fn(SRV / "Services/EconomyService.luau", "function EconomyService.CashBoostMult(").replace(
        "function EconomyService.CashBoostMult(", "function EconomyService2.CashBoostMult(")
    ps = SRV / "Modules/ProfileSchema.luau"
    return (HARNESS
            .replace("@CODESCONFIG@", lstr((SRV / "Configs/CodesConfig.luau").read_text(encoding="utf-8")))
            .replace("@CODESSERVICE@", lstr((SRV / "Services/CodesService.luau").read_text(encoding="utf-8")))
            .replace("@RATELIMIT@", lstr((SRV / "Services/RateLimitService.luau").read_text(encoding="utf-8")))
            .replace("@CASHBOOSTMULT@", econ)
            .replace("@NONNEGINT@", slice_fn(ps, "local function nonNegInt("))
            .replace("@ENSURE@", slice_fn(ps, "local function ensureCodesFields(")))


def run() -> int:
    luau = os.environ.get("LUAU") or shutil.which("luau")
    if not luau:
        print("SKIP codes_gate_test: no luau binary")
        return 0
    with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False, encoding="utf-8") as f:
        f.write(build())
        path = f.name
    try:
        r = subprocess.run([luau, path], capture_output=True, text=True, timeout=60)
    finally:
        os.unlink(path)
    out = r.stdout + r.stderr
    print(out.strip())
    return 0 if r.returncode == 0 and "FAIL=0" in out else 1


if __name__ == "__main__":
    sys.exit(run())
