#!/usr/bin/env python3
"""claude-bud JOB 15 (2026-09-29): executes the real RemoteGate + SecurityConfig with the Luau CLI (luau.exe).

Checks, for the owner (enforced) and a non-owner (observe):
  * valid requests pass; wrong types, NaN / inf, over-long strings, extra arguments, too-deep / too-big tables and
    Instances inside a table are rejected (enforced) and only logged (observe, still allowed);
  * the rate ceiling drops a flood above Burst and refills over time;
  * logs are throttled (one line per LogSeconds, with counts);
  * an extreme flood kicks once (enforced), never in observe mode; a sink fire counts as a bad request;
  * Others = "off" does nothing at all.
Prints PASS / FAIL, exits 1 on any FAIL. Used by tools/checks/claude_bud_q3.py (skipped without luau).
"""
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

HARNESS = r'''
local CLOCK = 0
local LOGS, KICKS = {}, {}
local function V3(x, y, z) return { __t = "Vector3", X = x, Y = y, Z = z } end
local INST = { __t = "Instance" }
local function mytypeof(v)
	if type(v) == "table" and v.__t then return v.__t end
	return type(v)
end
local MODS = { AdminConfig = { IsPlaytestOwner = function(uid) return uid == 470626172 end } }
local SRC = { SecurityConfig = [========[%s]========], RemoteGate = [========[%s]========] }
local CACHE = {}
local load
local SHARED = { Configs = setmetatable({}, { __index = function(_, k) return k end }) }
local game = { GetService = function() return { WaitForChild = function() return SHARED end } end }
local PARENT = setmetatable({}, { __index = function(_, k) return MODS[k] or k end })
load = function(name)
	if CACHE[name] ~= nil then return CACHE[name] end
	if SRC[name] == nil then return MODS[name] end
	local fn, err = loadstring(SRC[name], name)
	if not fn then error(name .. ": " .. tostring(err)) end
	local env = setmetatable({ script = { Parent = PARENT }, game = game, typeof = mytypeof, warn = print,
		require = function(x) if type(x) == "string" then return load(x) end return x end }, { __index = getfenv(0) })
	setfenv(fn, env)
	CACHE[name] = fn()
	return CACHE[name]
end
local SC = load("SecurityConfig")
SC.RemoteGate.Rollout = "owner" -- exercise both paths: the owner enforced, the other observed
local G = load("RemoteGate")
G._clock = function() return CLOCK end
G._log = function(s) table.insert(LOGS, s) end
G._kick = function(p, msg) table.insert(KICKS, p.UserId) end
local OWNER = { UserId = 470626172, Name = "owner" }
local OTHER = { UserId = 1234567, Name = "other" }
local fails = 0
local function check(ok, label) print((ok and "PASS " or "FAIL ") .. label); if not ok then fails += 1 end end
local function reset() G._Reset(); LOGS = {}; KICKS = {}; CLOCK = CLOCK + 1000 end

-- valid requests
check(G.Check(OWNER, "RequestSpawnVehicle", "Jeep") == true, "valid string arg passes")
check(G.Check(OWNER, "RequestClaimSpinner") == true, "no-arg remote passes")
check(G.Check(OWNER, "RequestFire", { Origin = V3(1, 2, 3), Dir = V3(0, 0, 1), Seq = 4 }) == true, "valid fire table (Vector3 fields) passes")
check(G.Check(OWNER, "RequestPurchaseDevProduct", "CashSmall") == true, "optional 2nd arg may be nil")
check(G.Check(OWNER, "RequestPurchaseUpgrade", "Barracks") == true and G.Check(OWNER, "RequestPurchaseUpgrade", { StructureId = "Barracks" }) == true, "table|string alternatives")
check(G.Check(OWNER, "RequestPremiumWeapon", "Fire", V3(0, 0, 1)) == true, "Vector3 arg passes")
check(G.Check(OWNER, "RequestRecruitSoldiers", 5) == true and G.Check(OWNER, "RequestRecruitSoldiers") == true, "optional number")
check(G.Check(OWNER, "SomeRemoteWithoutSchema", 1, 2, 3) == true, "a remote without a schema is only rate-limited")
reset()
-- bad requests (enforced for the owner)
check(G.Check(OWNER, "RequestSpawnVehicle", 5) == false, "wrong type rejected")
check(G.Check(OWNER, "RequestSpawnVehicle") == false, "missing required arg rejected")
check(G.Check(OWNER, "RequestSpawnVehicle", string.rep("x", 65)) == false, "string over MaxString rejected")
check(G.Check(OWNER, "RedeemCode", string.rep("x", 41)) == false, "string:40 enforced")
check(G.Check(OWNER, "RequestRecruitSoldiers", 0/0) == false, "NaN rejected")
check(G.Check(OWNER, "RequestRecruitSoldiers", math.huge) == false, "inf rejected")
check(G.Check(OWNER, "RequestSpawnVehicle", "Jeep", "extra") == false, "extra arguments rejected")
check(G.Check(OWNER, "RequestFire", { A = { B = { C = 1 } } }) == false, "table deeper than MaxDepth rejected")
local big = {}
for i = 1, 17 do big["k" .. i] = i end
check(G.Check(OWNER, "RequestFire", big) == false, "table with more than MaxTableKeys rejected")
check(G.Check(OWNER, "RequestFire", { Target = INST }) == false, "an Instance inside a request table rejected")
check(G.Check(OWNER, "RequestFire", { Dir = V3(0/0, 0, 1) }) == false, "NaN Vector3 inside a table rejected")
check(G.Check(OWNER, "RequestPremiumWeapon", "Fire", V3(math.huge, 0, 0)) == false, "inf Vector3 arg rejected")
check(G.Check(OWNER, "RequestSetDrawn", "yes") == false, "boolean schema enforced")
check(#LOGS == 1 and string.find(LOGS[1], "rejected owner", 1, true) ~= nil, "bad requests logged ONCE per LogSeconds (with counts): " .. tostring(LOGS[1]))
CLOCK += SC.RemoteGate.LogSeconds
G.Check(OWNER, "RequestSetDrawn", "yes")
check(#LOGS == 2, "the next log line comes after LogSeconds")
reset()
-- observe mode for a non-owner: logged, never dropped
check(G.Check(OTHER, "RequestSpawnVehicle", 5) == true, "observe: a bad request is still allowed (OFF = old play)")
check(#LOGS == 1 and string.find(LOGS[1], "would reject", 1, true) ~= nil, "observe: logged as 'would reject'")
reset()
-- rate ceiling
local lim = SC.RemoteGate.Limits.RequestFire
local okN = 0
for i = 1, lim.Burst + 5 do if G.Check(OWNER, "RequestFire", { Seq = i }) then okN += 1 end end
check(okN == lim.Burst, "rate ceiling: a same-instant flood passes exactly Burst (" .. okN .. "/" .. lim.Burst .. ")")
CLOCK += 1
local okR = 0
for i = 1, lim.Rate + 5 do if G.Check(OWNER, "RequestFire", { Seq = i }) then okR += 1 end end
check(okR == lim.Rate, "rate ceiling refills Rate per second (" .. okR .. ")")
local d = SC.RemoteGate.Default
local okD = 0
for i = 1, d.Burst + 1 do if G.Check(OWNER, "RequestReload") then okD += 1 end end
check(okD == d.Burst, "Default ceiling for a remote without its own limit")
check(SC.RemoteGate.Limits.RequestFire.Rate > 20 and SC.RemoteGate.Limits.VehicleDriveInput.Rate > 15 and SC.RemoteGate.Limits.RequestVehicleFire.Rate > 14 and SC.RemoteGate.Limits.RequestPremiumWeapon.Rate > 14, "ceilings sit above every handler's own rate (fire 20, drive 15, vehicle fire 14, premium 14)")
reset()
-- flood kick
local fk = SC.RemoteGate.FloodKick
for i = 1, fk.Rejects + 50 do G.Check(OWNER, "RequestSpawnVehicle", 1) end
check(#KICKS == 1, "an extreme flood kicks once (" .. #KICKS .. ")")
check(G.Check(OWNER, "RequestSpawnVehicle", "Jeep") == false, "after the kick nothing more is handled")
reset()
for i = 1, fk.Rejects - 1 do G.Check(OWNER, "RequestSpawnVehicle", 1) end
check(#KICKS == 0, "just under the flood line: no kick")
reset()
for i = 1, fk.Rejects - 1 do G.Check(OWNER, "RequestSpawnVehicle", 1) end
CLOCK += fk.WindowSeconds + 1
for i = 1, 10 do G.Check(OWNER, "RequestSpawnVehicle", 1) end
check(#KICKS == 0, "rejects outside the window do not add up to a kick")
reset()
for i = 1, fk.Rejects + 50 do G.Check(OTHER, "RequestSpawnVehicle", 1) end
check(#KICKS == 0, "observe mode never kicks")
reset()
-- sink
G.Sink(OWNER, "PlayerStateUpdate")
check(#LOGS == 1 and string.find(LOGS[1], "PlayerStateUpdate:not_client", 1, true) ~= nil, "a fire on a push remote is a logged bad request")
reset()
-- off
SC.RemoteGate.Others = "off"
check(G.Check(OTHER, "RequestSpawnVehicle", 5) == true and #LOGS == 0, "Others = off: nothing checked, nothing logged")
G.Sink(OTHER, "PlayerStateUpdate")
check(#LOGS == 0, "Others = off: sink silent")
print(fails == 0 and "ALL PASS" or ("FAILS " .. fails))
'''


def luau():
    exe = os.environ.get("LUAU")
    if exe:
        return exe
    lc = os.environ.get("LUAU_COMPILE")
    if lc:
        for n in ("luau.exe", "luau"):
            p = os.path.join(os.path.dirname(lc), n)
            if os.path.exists(p):
                return p
    return None


def main():
    exe = luau()
    if not exe:
        print("SKIP remotegate_test: no luau CLI (set LUAU)")
        return 0
    sc = (ROOT / "src/ReplicatedStorage/Shared/Configs/SecurityConfig.luau").read_text(encoding="utf-8")
    rg = (ROOT / "src/ServerScriptService/Server/Modules/RemoteGate.luau").read_text(encoding="utf-8")
    code = HARNESS % (sc, rg)
    with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False, encoding="utf-8") as f:
        f.write(code)
        tmp = f.name
    try:
        r = subprocess.run([exe, tmp], capture_output=True, text=True, timeout=60)
    finally:
        os.unlink(tmp)
    out = (r.stdout + r.stderr).strip()
    print(out)
    return 0 if r.returncode == 0 and "ALL PASS" in out else 1


if __name__ == "__main__":
    sys.exit(main())
