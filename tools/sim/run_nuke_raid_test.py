"""claude-bud JOB 65: the NUKE INSTANT RAID, on the REAL NukeService + RebirthZonesConfig.NukeRaid (+ RebirthConfig,
NukeConfig, TerritoryConfig, BaseConfig, PlotFrame). The services around it are recording fakes; the fake
MoneyCollectorService moves the ATM exactly like the real _MoveLoot (victim ATM -> attacker, 1:1) and a Double Weekend
x2 multiplier is armed on every OTHER cash path, to prove the transfer never touches it.

1. PREVIEW: the card gets the target's name, base level and the EXACT full ATM (GetRaidableBalance).
2. LAUNCH: preview amount == stolen amount, the target ATM = 0 after, the attacker's cash +amount (never x2), one
   warhead spent, the cooldown saved (NukeLastLaunch), the strike VFX packet (MissileStrikeFx) sent.
3. FAIRNESS: a shielded / new player (raid rules), a spawn-protected player (the ONE protection rule), an ally, an
   admin, a base on his JOB 63 cooldown, his own base: refused, nothing moves.
4. COOLDOWN: a second launch inside CooldownSeconds is refused and the preview shows the time left; after it, allowed.
5. NO WARHEAD / NO SILO: refused. A race where nothing moves gives the warhead + cooldown back.
6. OWNER-FIRST: another attacker sees nothing.
Run: LUAU=path/to/luau(.exe) python tools/sim/run_nuke_raid_test.py   (exit 1 on any failure; VERBOSE=1 prints all)"""
import os
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from run_kit_detail_test import PRELUDE  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
SH = ROOT / "src/ReplicatedStorage/Shared"
SV = ROOT / "src/ServerScriptService/Server"
MODS = {
    "Constants": SH / "Constants.luau",
    "Configs/RebirthZonesConfig": SH / "Configs/RebirthZonesConfig.luau",
    "Configs/RebirthConfig": SH / "Configs/RebirthConfig.luau",
    "Configs/NukeConfig": SH / "Configs/NukeConfig.luau",
    "Configs/TerritoryConfig": SH / "Configs/TerritoryConfig.luau",
    "Configs/BaseConfig": SH / "Configs/BaseConfig.luau",
    "Configs/BaseLayoutConfig": SH / "Configs/BaseLayoutConfig.luau",
    "Configs/BusinessConfig": SH / "Configs/BusinessConfig.luau",
    "Configs/RetentionConfig": SH / "Configs/RetentionConfig.luau",
    "Configs/AdminConfig": SH / "Configs/AdminConfig.luau",
    "Configs/EconomyConfig": SH / "Configs/EconomyConfig.luau",
    "Util/PlotFrame": SH / "Util/PlotFrame.luau",
    "Services/NukeService": SV / "Services/NukeService.luau",
}

TEST = r'''
local fails = 0
local function check(ok, msg) print((ok and "ok    " or "FAIL  ") .. msg); if not ok then fails += 1 end end
task = { spawn = function(fn, ...) fn(...) end, delay = function() end, defer = function() end, wait = function() end }
local BYID = {}
local prevG = game
game = { GetService = function(_, n)
  if n == "Players" then return { GetPlayers = function() local o = {} for _, p in pairs(BYID) do table.insert(o, p) end return o end, GetPlayerByUserId = function(_, u) return BYID[u] end } end
  if n == "RunService" then return { IsStudio = function() return false end } end
  if n == "Workspace" then return { GetServerTimeNow = function() return 1000 end } end
  return prevG:GetService(n) end }
local ZC = require(node("Configs/RebirthZonesConfig"))
local NR = ZC.NukeRaid
local NS = require(node("Services/NukeService"))
local OWNER, VICTIM, OTHER = 470626172, 9, 11
local function mkP(uid, name) local p = { UserId = uid, DisplayName = name, Name = name }; BYID[uid] = p; return p end
local A, V, O = mkP(OWNER, "Shaun"), mkP(VICTIM, "Rival"), mkP(OTHER, "Other")
local PROF = {
  [OWNER] = { Level = 100, Cash = 1000, PendingCash = 50, NukeSilo = { Ready = 2, ChargeFrom = 0 }, NukeLastLaunch = 0 },
  [VICTIM] = { Level = 37, Cash = 0, PendingCash = 123456 },
  [OTHER] = { Level = 5, Cash = 0, PendingCash = 900, NukeSilo = { Ready = 1, ChargeFrom = 0 } },
}
local PLOT = { [OWNER] = 1, [VICTIM] = 2, [OTHER] = 3 }
local OWNEROF = { [1] = OWNER, [2] = VICTIM, [3] = OTHER }
local SHIELD, NEW, PROTECT, ALLY, ADMIN, CAMP = false, false, false, false, false, 0
local DOUBLE = 2 -- the Double Weekend multiplier on every OTHER cash path (never on a transfer)
local PUSH, FX, NOTE = {}, {}, {}
local remote = { IsA = function() return true end, FireClient = function(_, p, k, d) table.insert(PUSH, { p = p, k = k, d = d }) end, FireAllClients = function(_, d) table.insert(FX, d) end,
  OnServerEvent = { Connect = function() end } }
local MC: any
MC = {
  GetRaidableBalance = function(v) return PROF[v.UserId].PendingCash end,
  CanArmyRaid = function(a, v)
    if SHIELD then return false, "Shielded" end
    if NEW then return false, "NewPlayer" end
    if PROF[v.UserId].PendingCash < 100 then return false, "LowBalance" end
    return true
  end,
  -- = the real NukeRaid money path: _MoveLoot (TransferPendingCash 1:1) then PendingToCash 1:1 (no multiplier)
  NukeRaid = function(a, v)
    local ok = MC.CanArmyRaid(a, v)
    if not ok then return 0 end
    local take = PROF[v.UserId].PendingCash
    PROF[v.UserId].PendingCash -= take
    PROF[a.UserId].Cash += take
    return take
  end,
  AddCash = function(p, n) PROF[p.UserId].Cash += n * DOUBLE end, -- an earned-income path (x2 on the weekend)
}
NS.Init({
  DataService = { GetProfile = function(p) return PROF[p.UserId] end, MarkDirty = function() end },
  RemoteSetup = { Get = function() return remote end },
  RebirthZoneService = { SiloLevel = function(p) return if p.UserId == OTHER then 1 else (PROF[p.UserId].SiloLv or 1) end },
  BaseService = { GetOwnerUserId = function(pid) return OWNEROF[pid] end, GetOwnedPlotId = function(p) return PLOT[p.UserId] end },
  MoneyCollectorService = MC,
  CombatService = { ProtectedReason = function() return if PROTECT then "spawn" else nil end },
  GateDefenseService = { IsAlly = function() return ALLY end },
  AdminService = { IsAdmin = function(p) return ADMIN and p.UserId == VICTIM end },
  NotificationService = { Notify = function(p, t) table.insert(NOTE, { p = p, t = t }) end },
})
SOURCES["Services/AntiCampService"] = function() return { CooldownLeft = function() return CAMP end } end

local function lastPreview() for i = #PUSH, 1, -1 do if PUSH[i].k == "NukeRaidPreview" then return PUSH[i].d end end return nil end

-- 1. preview
NS.RaidPreview(A, 2)
local pv = lastPreview()
check(pv and pv.Ok == true and pv.Name == "Rival" and pv.Level == 37 and pv.Amount == 123456, string.format("preview: %s, base level %s, steals $%s (the full ATM)", tostring(pv and pv.Name), tostring(pv and pv.Level), tostring(pv and pv.Amount)))

-- 2. launch
local cashBefore = PROF[OWNER].Cash
local ok, why = NS.RaidLaunch(A, 2)
local stolen = PROF[OWNER].Cash - cashBefore
check(ok and stolen == pv.Amount, string.format("launch: stolen $%d == preview $%d", stolen, pv.Amount))
check(PROF[VICTIM].PendingCash == 0, "the target's ATM is 0 after the nuke")
check(stolen ~= pv.Amount * DOUBLE, "no Double Weekend x2 on the stolen amount (a transfer, not income)")
check(PROF[OWNER].NukeSilo.Ready == ZC.Zones.StrategicYard.SiloCapacity[1] - 1 and PROF[OWNER].NukeLastLaunch > 0, "one warhead spent (silo L1 holds 1: 1 -> 0), the cooldown saved (NukeLastLaunch)")
check(#FX == 1 and FX[1].Outcome == "Hit" and FX[1].VictimUserId == VICTIM and FX[1].FlightSeconds == NR.FlightSeconds, "the strike VFX packet (MissileStrikeFx) flies to the target base")

-- 4. cooldown
PROF[VICTIM].PendingCash = 5000
local ok2, why2 = NS.RaidLaunch(A, 2)
NS.RaidPreview(A, 2)
local pv2 = lastPreview()
check(not ok2 and why2 == "Cooldown" and pv2.CooldownLeft > 0 and pv2.CooldownLeft <= NR.CooldownSeconds and PROF[VICTIM].PendingCash == 5000, string.format("inside the %d s cooldown: refused, the card shows %d s", NR.CooldownSeconds, pv2.CooldownLeft))
PROF[OWNER].NukeLastLaunch = os.time() - NR.CooldownSeconds - 1

-- 3. fairness (each refused, nothing moves)
local function refused(label, setup, undo, want)
  setup()
  local c0, v0 = PROF[OWNER].Cash, PROF[VICTIM].PendingCash
  local okX, whyX = NS.RaidLaunch(A, 2)
  check(not okX and (want == nil or whyX == want) and PROF[OWNER].Cash == c0 and PROF[VICTIM].PendingCash == v0, label .. " -> refused (" .. tostring(whyX) .. "), nothing moves")
  undo()
end
refused("a shielded player (raid shield)", function() SHIELD = true end, function() SHIELD = false end, "Shielded")
refused("a new player", function() NEW = true end, function() NEW = false end, "NewPlayer")
refused("a spawn / novice protected player (the ONE protection rule)", function() PROTECT = true end, function() PROTECT = false end, "Protected")
refused("an ally", function() ALLY = true end, function() ALLY = false end, "Ally")
refused("an admin", function() ADMIN = true end, function() ADMIN = false end, "Admin")
refused("a base on his JOB 63 same-base cooldown", function() CAMP = 90 end, function() CAMP = 0 end, "CampCooldown")
local okSelf, whySelf = NS.RaidLaunch(A, 1)
check(not okSelf and whySelf == "Self", "his own base -> refused")

-- 5. warhead / silo / race refund
PROF[OWNER].NukeSilo = { Ready = 0, ChargeFrom = os.time() }
check(select(2, NS.RaidLaunch(A, 2)) == "NotReady", "no warhead ready -> refused")
PROF[OWNER].NukeSilo = { Ready = 1, ChargeFrom = 0 }
PROF[OWNER].SiloLv = 0
check(select(2, NS.RaidLaunch(A, 2)) == "NoSilo", "no silo built -> refused")
PROF[OWNER].SiloLv = nil
local realRaid = MC.NukeRaid
MC.NukeRaid = function() return 0 end
local okR, whyR = NS.RaidLaunch(A, 2)
MC.NukeRaid = realRaid
check(not okR and whyR == "Blocked" and PROF[OWNER].NukeSilo.Ready == 1 and (os.time() - PROF[OWNER].NukeLastLaunch) > NR.CooldownSeconds, "nothing moved at the last moment -> the warhead and the cooldown come back")
local okAfter = NS.RaidLaunch(A, 2)
check(okAfter == true and PROF[VICTIM].PendingCash == 0, "after the cooldown: allowed again")

-- 6. owner-first
local n0 = #PUSH
NS.RaidPreview(O, 2)
check(#PUSH == n0 and select(2, NS.RaidLaunch(O, 2)) == "Off", "another attacker (OwnerFirst): no card, no launch")

print(string.format("NUKE RAID LUA: %d failed", fails))
if fails > 0 then error("failed") end
'''


def main():
    chunks = [PRELUDE]
    for key, path in MODS.items():
        chunks.append("SOURCES[%r] = function(script)\n%s\nend" % (key, path.read_text(encoding="utf-8")))
    chunks.append(TEST)
    with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False, encoding="utf-8") as f:
        f.write("\n".join(chunks))
        path = f.name
    r = subprocess.run([os.environ.get("LUAU", "luau"), path], capture_output=True, text=True, timeout=120)
    out = r.stdout.strip().splitlines()
    fails = 0
    if r.returncode != 0 or "NUKE RAID LUA: 0 failed" not in r.stdout:
        fails = 1
        out.append(r.stderr.strip()[-2500:])
    out.append("NUKE RAID TEST: %d failed" % fails)
    print("\n".join(out) if os.environ.get("VERBOSE") else "\n".join(l for l in out if l.startswith(("FAIL", "NUKE RAID TEST"))))
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
