"""claude-bud JOB 41 part C: rival TARGETS on the REAL RivalService + RivalConfig, with the REAL ArmySendRules.Verdict
deciding every base (ArmyPlan.CheckSend is a stand-in that runs Rules.Verdict on a per-plot facts table, exactly what
the real CheckSend does with its gathered facts). Stand-ins: run_kit_detail_test.PRELUDE.

1. The list == the set ArmySendRules allows (8 cases: shielded, ally, new player, too strong, sender cooldown, one
   active SEND, allowed-rich, allowed-poor).
2. Sort: loot (desc), then distance (asc); MaxShown 3; loot only as a bucket ($100k+ / $10k+), never the number; poor
   (< MinLootToShow) not listed; the bully (much stronger) target shows half loot and the "easy" chip.
3. ONE tick for all players: every live viewer gets one push; a viewer it is not live for gets none (OFF == OLD).
4. Nothing during the Guided / onboarding hold.
5. Telemetry: open / send (with the verdict of a LISTED target only) / RivalRaidWon only for a send from the list.
6. The client's SEND ARMY uses the same JOB 38 remote as the map (static check on RivalController).
Run: LUAU=path/to/luau(.exe) python tools/sim/run_rival_targets_test.py   (exit 1 on any failure)"""
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
    "Configs/RivalConfig": SH / "Configs/RivalConfig.luau",
    "Configs/RetentionConfig": SH / "Configs/RetentionConfig.luau",
    "Configs/AdminConfig": SH / "Configs/AdminConfig.luau",
    "Configs/ArmyOrdersConfig": SH / "Configs/ArmyOrdersConfig.luau",
    "Modules/ArmySendRules": SV / "Modules/ArmySendRules.luau",
    "Services/RivalService": SV / "Services/RivalService.luau",
}

EXTRA = r'''
task = { spawn = function() end, delay = function() end, defer = function() end, wait = function() end }
local function signal() local s = { fns = {} }; s.Connect = function(self, fn) table.insert(self.fns, fn); return { Disconnect = function() end } end; return s end
local function mkPlayer(uid, name) return { UserId = uid, Name = name, DisplayName = name, Parent = true } end
VIEWER = mkPlayer(470626172, "Shaun")
OTHER = mkPlayer(1234, "Rookie")
VICTIMS = {}
for i = 1, 9 do VICTIMS[i] = mkPlayer(5000 + i, "Rival" .. i) end
local ALL = { VIEWER, OTHER }
for _, v in ipairs(VICTIMS) do table.insert(ALL, v) end
local byUid = {}
for _, p in ipairs(ALL) do byUid[p.UserId] = p end
local Players = { PlayerAdded = signal(), PlayerRemoving = signal(), GetPlayers = function() return ALL end, GetPlayerByUserId = function(_, u) return byUid[u] end }
local RunService = { IsStudio = function() return false end }
local prevGame = game
game = { GetService = function(_, n)
  if n == "Players" then return Players elseif n == "RunService" then return RunService end
  return prevGame:GetService(n) end }
SOURCES["Configs/BaseConfig"] = function() return { MaxPlots = 10 } end
SOURCES["Configs/RaidConfig"] = function() return { Raid = { StealFraction = 0.10 } } end
-- plot n sits at x = 100 n; the viewer owns plot 10 (x = 1000)
SOURCES["Util/PlotFrame"] = function() return { PlotPosition = function(id) return Vector3.new(100 * id, 0, 0) end } end
FACTS = {}
SOURCES["Modules/ArmyPlan"] = function()
  local Rules = require(node("Modules/ArmySendRules"))
  return { CheckSend = function(sender, plotId) return Rules.Verdict(FACTS[plotId]) end }
end
PUSHES = {}
LOGS = {}
HOLD = false
local remote = { IsA = function(_, c) return c == "RemoteEvent" end, OnServerEvent = signal(),
  FireClient = function(_, p, kind, data) table.insert(PUSHES, { p = p, kind = kind, data = data }) end }
BAL = {}
DEPS = {
  RemoteSetup = { Get = function() return remote end },
  BaseService = { GetOwnerUserId = function(id) if id == 10 then return VIEWER.UserId end; local v = VICTIMS[id]; return v and v.UserId end,
    GetOwnedPlotId = function(p) if p == VIEWER then return 10 end end },
  MoneyCollectorService = { GetRaidableBalance = function(v) return BAL[v.UserId] or 0 end },
  SquadOrdersService = { UnitPower = function(v) return 12, 100, 10 end },
  AnalyticsService = { Log = function(ev, uid, props) table.insert(LOGS, { ev = ev, props = props }) end },
  RetentionService = { IsOnboarding = function() return HOLD end },
}
function facts(over)
  local f = { Self = false, VictimOnline = true, VictimHasBase = true, Ally = false, PvpOff = false, ShieldLeft = 0, NewPlayerLeft = 0,
    Novice = false, ProtectLeft = 0, CooldownLeft = 0, ActiveSend = false, Units = 12, ArmyPower = 2000, DefencePower = 1000 }
  for k, v in pairs(over or {}) do f[k] = v end
  return f
end
'''

TEST = r'''
local fails = 0
local function check(ok, msg) print((ok and "ok    " or "FAIL  ") .. msg); if not ok then fails += 1 end end
local RC = require(node("Configs/RivalConfig"))
local RS = require(node("Services/RivalService"))
RS.Init(DEPS)
local function setup()
  FACTS = {
    [1] = facts({ ShieldLeft = 300 }),
    [2] = facts({ Ally = true }),
    [3] = facts({ NewPlayerLeft = 200 }),
    [4] = facts({ ArmyPower = 100, DefencePower = 1000 }), -- too strong for him (TooWeak)
    [5] = facts(), -- allowed, rich
    [6] = facts(), -- allowed, poor
    [7] = facts(), -- allowed, mid
    [8] = facts({ ArmyPower = 5000, DefencePower = 1000 }), -- allowed, much stronger: bully (half loot)
    [9] = facts(), -- allowed, mid: the same loot as 7 but closer to his base (x 900 vs 700; he is at x 1000)
  }
  BAL = { [5001] = 2e6, [5002] = 2e6, [5003] = 2e6, [5004] = 2e6, [5005] = 2e6, [5006] = 10000, [5007] = 300000, [5008] = 2e6, [5009] = 300000 }
end
local function rowsFor(p)
  local got = nil
  for _, e in ipairs(PUSHES) do if e.p == p and e.kind == "RivalTargets" then got = e.data.Rows end end
  return got
end

-- 1 + 2
setup(); PUSHES = {}
RS.Tick()
local rows = rowsFor(VIEWER)
local ids = {}
for _, r in ipairs(rows) do table.insert(ids, r.PlotId) end
check(table.concat(ids, ",") == "5,8,9", "the list = the allowed set, sorted by loot then distance (9 beats 7: same loot, closer), top 3: " .. table.concat(ids, ","))
local cands = RS.Candidates(VIEWER)
local allowed = {}
for _, c in ipairs(cands) do allowed[c.PlotId] = true end
check(not allowed[1] and not allowed[2] and not allowed[3] and not allowed[4] and allowed[5] and allowed[6] and allowed[7] and allowed[8],
  "shielded / ally / new player / too strong are never candidates; allowed-rich / allowed-poor are")
local byId = {}
for _, r in ipairs(rows) do byId[r.PlotId] = r end
check(byId[5].Loot == "$100k+" and byId[8].Loot == "$10k+" and byId[9].Loot == "$10k+" and byId[7] == nil, "loot buckets: rich $100k+, bully (half loot) $10k+, mid $10k+; the 4th (plot 7) cut by MaxShown 3")
check(byId[6] == nil, "allowed-poor (loot $500 < MinLootToShow) is not listed")
check(byId[8].Verdict == "easy" and byId[5].Verdict == "even", "the verdict chip: much stronger = easy, ratio 2 = even")
local exact = false
for _, r in ipairs(rows) do for k, v in pairs(r) do if type(v) == "number" and (v == 100000 or v == 50000 or v == 15000) then exact = true end end end
check(not exact and type(byId[5].Loot) == "string", "never the exact loot number in the push")
check(byId[5].Army == 12 and byId[5].Name == "Rival5" and byId[5].Dist == 500, "row: name, army size, distance between the bases")
-- sender-level blocks: cooldown / one active SEND
for _, case in ipairs({ { "sender cooldown", { CooldownLeft = 120 } }, { "one active SEND", { ActiveSend = true } } }) do
  setup()
  for id, f in pairs(FACTS) do for k, v in pairs(case[2]) do f[k] = v end end
  PUSHES = {}; RS.Tick()
  check(#rowsFor(VIEWER) == 0, case[1] .. ": nothing listed (the verdict blocks every base)")
end

-- 3. one tick, live viewers only (codebot_v166: launched; the owner-first rule is still proved with OwnerFirst = true)
local launched = RC.OwnerFirst
RC.OwnerFirst = true
setup(); PUSHES = {}; RS.Tick()
local toViewer, toOther = 0, 0
for _, e in ipairs(PUSHES) do if e.p == VIEWER then toViewer += 1 elseif e.p == OTHER then toOther += 1 end end
check(toViewer == 1 and toOther == 0, "owner-first rule: one push per live viewer per tick; none for a viewer it is not live for (OFF == OLD)")
RC.OwnerFirst = launched
check(launched == false and RC.LiveFor(OTHER.UserId), "codebot_v166: RivalConfig live for everyone (OwnerFirst=false)")
setup(); PUSHES = {}; RS.Tick()
toViewer, toOther = 0, 0
for _, e in ipairs(PUSHES) do if e.p == VIEWER then toViewer += 1 elseif e.p == OTHER then toOther += 1 end end
check(toViewer == 1 and toOther == 1, "codebot_v166: one push per viewer per tick, the non-owner included")
-- 4. the hold
HOLD = true; PUSHES = {}; RS.Tick(); HOLD = false
check(#rowsFor(VIEWER) == 0, "during the Guided / onboarding hold: an empty list (no pill)")

-- 5. telemetry
setup(); RS.Tick(); LOGS = {}
RS.Action(VIEWER, "open")
RS.Action(VIEWER, "send", 8)
RS.Action(VIEWER, "send", 1) -- not listed: no event
RS.OnRaidWon(VIEWER, 8, 4000)
RS.OnRaidWon(VIEWER, 7, 4000) -- not sent from the list
local names = {}
for _, l in ipairs(LOGS) do table.insert(names, l.ev .. (if l.props.verdict then ":" .. l.props.verdict else "")) end
check(table.concat(names, ",") == "RIVAL_LIST_OPENED,RIVAL_SEND_TAPPED:easy,RIVAL_RAID_WON", "telemetry: " .. table.concat(names, ","))

print(string.format("RIVAL TARGETS TEST: %d failed", fails))
if fails > 0 then error("failed") end
'''


def main():
    chunks = [PRELUDE, EXTRA]
    for key, path in MODS.items():
        chunks.append("SOURCES[%r] = function(script)\n%s\nend" % (key, path.read_text(encoding="utf-8")))
    chunks.append(TEST)
    with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False, encoding="utf-8") as f:
        f.write("\n".join(chunks))
        path = f.name
    r = subprocess.run([os.environ.get("LUAU", "luau"), path], capture_output=True, text=True)
    out = r.stdout.strip()
    ctl = (ROOT / "src/StarterPlayer/StarterPlayerScripts/Client/Controllers/RivalController.luau").read_text(encoding="utf-8")
    same = "Remotes.FireServer, Constants.RemoteNames.RequestArmySend, plotId" in ctl
    out += "\n" + ("ok    " if same else "FAIL  ") + "the list's SEND ARMY fires the same JOB 38 RequestArmySend remote as the map"
    bad = r.returncode != 0 or not same
    if not same:
        out = out.replace("RIVAL TARGETS TEST: 0 failed", "RIVAL TARGETS TEST: 1 failed")
    print(out if os.environ.get("VERBOSE") else ("\n".join(l for l in out.splitlines() if l.startswith("FAIL") or l.startswith("RIVAL TARGETS TEST")) or out))
    if bad:
        print(r.stderr.strip()[-2500:])
        sys.exit(1)


if __name__ == "__main__":
    main()
