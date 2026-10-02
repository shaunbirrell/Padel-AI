#!/usr/bin/env python3
"""claude-bud JOB 14 (2026-09-29): executes the real GameFeelService + GameFeelConfig with the Luau CLI (luau.exe).

Stubs Players / Remotes / task / os.clock and checks, for the owner (live) and a non-owner (not live):
  * kill feed: a PvP kill reaches only live players, with DisplayNames + weapon; a blast (Quiet) death is not fed;
    more than MaxPerSecond kills in one second are dropped;
  * vehicle numbers: two quick hits on the owner's vehicle arrive as ONE merged number; a splash hit gives a live
    attacker a hit marker (Splash) and a non-live attacker nothing; a player's vehicle kill is fed;
  * raid report: hits + a robbery -> one "Lost" report after QuietSeconds (not before); hits only -> Lost 0
    (Defended); raids on a non-live owner are ignored.
Prints PASS / FAIL lines, exits 1 on any FAIL. Used by tools/checks/claude_bud_q3.py (skipped without luau).
"""
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OWNER, OTHER = 470626172, 1234567

HARNESS = r'''
local CLOCK = 1000
local SENT = {}
local DELAYS = {}
local LOOPS = {}
local function mkPlayer(uid, name) return { UserId = uid, DisplayName = name, Parent = true } end
local A = mkPlayer(%d, "Owner")
local B = mkPlayer(%d, "Bob")
local LIST = { A, B }
local Players = {
	GetPlayers = function() return LIST end,
	GetPlayerByUserId = function(_, uid) for _, p in ipairs(LIST) do if p.UserId == uid then return p end end return nil end,
	PlayerRemoving = { Connect = function() end },
}
local function ev(name) return { FireClient = function(_, p, a, b) table.insert(SENT, { R = name, P = p, A = a, B = b }) end } end
local EVENTS = { FP = ev("FP"), HF = ev("HF") }
local MODS = {
	Constants = { RemoteNames = { FeaturePush = "FP", CombatHitFeedback = "HF" } },
	Remotes = { TryGetEvent = function(n) return EVENTS[n] end },
	WeaponConfig = { Weapons = { Rifle = { DisplayName = "Rifle" } } },
	AdminConfig = { IsPlaytestOwner = function(uid) return uid == %d end },
	VehicleHealth = {},
}
local SRC = { GameFeelConfig = [========[%s]========], GameFeelService = [========[%s]========] }
local CACHE = {}
local function path(names) return setmetatable({}, { __index = function(_, k) return MODS[k] or k end }) end
local load
local function req(x)
	if type(x) == "string" then return load(x) end
	return x
end
local TASK = {
	spawn = function(fn, ...) local co = coroutine.create(fn); table.insert(LOOPS, co); coroutine.resume(co, ...) end,
	delay = function(s, fn, ...) table.insert(DELAYS, { At = CLOCK + s, Fn = fn, Args = { ... } }) end,
	wait = function() coroutine.yield() end,
}
local OS = setmetatable({ clock = function() return CLOCK end }, { __index = os })
local SHARED = { Constants = MODS.Constants, Remotes = MODS.Remotes, Configs = setmetatable({}, { __index = function(_, k) return k end }) }
local game = { GetService = function(_, s)
	if s == "Players" then return Players end
	return { WaitForChild = function() return SHARED end }
end }
local PARENT = setmetatable({}, { __index = function(_, k)
	if k == "Parent" then return { Modules = { VehicleHealth = MODS.VehicleHealth } } end
	return MODS[k] or k
end })
load = function(name)
	if CACHE[name] ~= nil then return CACHE[name] end
	if SRC[name] == nil then return MODS[name] end
	local fn, err = loadstring(SRC[name], name)
	if not fn then error(name .. ": " .. tostring(err)) end
	local env = setmetatable({ script = { Parent = PARENT }, require = req, game = game, task = TASK, os = OS,
		typeof = function(v) return type(v) end, warn = print }, { __index = getfenv(0) })
	setfenv(fn, env)
	CACHE[name] = fn()
	return CACHE[name]
end
local G = load("GameFeelConfig")
for k in pairs(G.Rollout) do G.Rollout[k] = "owner" end -- exercise the gate: owner live, the other not
local S = load("GameFeelService")
local deathFn
S.Init({ CombatService = { OnPlayerDeath = function(fn) deathFn = fn end } })
local fails = 0
local function check(ok, label) print((ok and "PASS " or "FAIL ") .. label); if not ok then fails += 1 end end
local function sent(r, kind, to)
	local out = {}
	for _, s in ipairs(SENT) do
		if s.R == r and (kind == nil or s.A == kind) and (to == nil or s.P == to) then table.insert(out, s) end
	end
	return out
end
local function runDelays()
	local list = DELAYS; DELAYS = {}
	for _, d in ipairs(list) do if d.At <= CLOCK then d.Fn(table.unpack(d.Args)) else table.insert(DELAYS, d) end end
end
local function tick() for _, co in ipairs(LOOPS) do if coroutine.status(co) == "suspended" then coroutine.resume(co) end end end

-- kill feed
deathFn(A, B, { WeaponId = "Rifle", Quiet = false })
local f = sent("FP", "KillFeed")
check(#f == 1 and f[1].P == A, "kill feed reaches only the live player (owner), not the non-owner")
check(f[1] and f[1].B.K == "Bob" and f[1].B.V == "Owner" and f[1].B.W == "Rifle" and f[1].B.Me == true, "kill feed line: DisplayNames + weapon, Me for the victim")
SENT = {}
deathFn(A, B, { WeaponId = "Rifle", Quiet = true })
check(#sent("FP", "KillFeed") == 0, "a blast (quiet) death is not fed")
deathFn(A, nil, { Quiet = false })
check(#sent("FP", "KillFeed") == 0, "a death with no killer is not fed")
CLOCK += 1
SENT = {}
for i = 1, 6 do deathFn(A, B, { WeaponId = "Rifle", Quiet = false }) end
check(#sent("FP", "KillFeed") == G.KillFeed.MaxPerSecond, "kill feed capped at MaxPerSecond in one second (" .. #sent("FP", "KillFeed") .. ")")
CLOCK += 1
SENT = {}

-- vehicle numbers
local VH = MODS.VehicleHealth
local car = { GetPivot = function() return { Position = "PIV" } end }
VH.OnDamage(car, A.UserId, "Tank", 30, B, "HIT1", false, false)
VH.OnDamage(car, A.UserId, "Tank", 12, B, "HIT2", false, false)
check(#sent("FP", "VehDmg") == 0, "vehicle numbers wait for the merge window")
CLOCK += G.VehicleNumbers.AggregateSeconds
runDelays()
local v = sent("FP", "VehDmg", A)
check(#v == 1 and v[1].B.D == 42 and v[1].B.P == "HIT2", "two quick hits on the owner's vehicle = ONE merged number (42)")
check(#sent("HF") == 0, "a direct hit gives no extra attacker feedback (CombatService already sends it)")
SENT = {}
local bcar = { GetPivot = function() return { Position = "BPIV" } end }
VH.OnDamage(bcar, B.UserId, "Jeep", 20, A, nil, false, true)
local h = sent("HF", nil, A)
check(#h == 1 and h[1].A.Splash == true and h[1].A.Pos == "BPIV" and h[1].A.Kind == "Hit", "splash hit on a vehicle: live attacker gets a marker + number at the vehicle")
check(#sent("FP", "VehDmg", B) == 0, "the non-live owner gets no number")
SENT = {}
VH.OnDamage(car, A.UserId, "Tank", 5, B, "HIT3", false, true)
check(#sent("HF", nil, B) == 0, "a non-live attacker gets no splash marker")
SENT = {}
VH.OnDamage(bcar, B.UserId, "Jeep", 99, A, "X", true, false)
local k = sent("FP", "KillFeed", A)
check(#k == 1 and k[1].B.V == "Bob's Jeep" and k[1].B.Mine == true, "a player's vehicle kill is fed (Bob's Jeep)")
CLOCK += 1
runDelays()
SENT = {}

-- raid report
S.NoteRaid(A.UserId, "Hit", B)
S.NoteRaid(A.UserId, "Robbed", B, 1234)
CLOCK += G.RaidReport.QuietSeconds - 5
tick()
check(#sent("FP", "RaidReport") == 0, "no report while the raid is still going")
CLOCK += 6
tick()
local r = sent("FP", "RaidReport", A)
check(#r == 1 and r[1].B.Lost == 1234 and r[1].B.By == "Bob", "robbed -> ONE 'YOU WERE RAIDED' report (Lost 1234, by Bob)")
tick()
check(#sent("FP", "RaidReport") == 1, "the report is sent once")
SENT = {}
S.NoteRaid(A.UserId, "Hit", B)
S.NoteRaid(A.UserId, "Breach", nil)
S.NoteRaid(A.UserId, "AtmDefended", B)
CLOCK += G.RaidReport.QuietSeconds + 1
tick()
r = sent("FP", "RaidReport", A)
check(#r == 1 and r[1].B.Lost == 0 and r[1].B.Breached == true, "hits + breach, no robbery -> 'BASE DEFENDED' (gate down, cash safe)")
SENT = {}
S.NoteRaid(B.UserId, "Robbed", A, 50)
CLOCK += G.RaidReport.QuietSeconds + 1
tick()
check(#sent("FP", "RaidReport") == 0, "a raid on a non-live owner is ignored (OFF = old behaviour)")
S.NoteRaid(A.UserId, "Hit", A)
CLOCK += G.RaidReport.QuietSeconds + 1
tick()
check(#sent("FP", "RaidReport") == 0, "hitting your own base is not a raid")
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
        print("SKIP gamefeel_test: no luau CLI (set LUAU)")
        return 0
    cfg = (ROOT / "src/ReplicatedStorage/Shared/Configs/GameFeelConfig.luau").read_text(encoding="utf-8")
    svc = (ROOT / "src/ServerScriptService/Server/Services/GameFeelService.luau").read_text(encoding="utf-8")
    # the service reads Configs through require(Shared.Configs.X) -> the harness maps X to its source by name
    code = HARNESS % (OWNER, OTHER, OWNER, cfg, svc)
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
