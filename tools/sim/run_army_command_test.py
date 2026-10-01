"""Code Bot (army command bug, 2026-10-01): Shaun's "SEND -> Crossroads -> GO and the army stays beside me" and
"ATTACK says No enemies near", end to end in the Studio-free sim.

CLIENT half (real MapController + OrdersController, tools/sim/army_cmd_env.luau + army_cmd_client.luau): FOLLOW lit ->
Army SEND -> tap Crossroads Town -> GO. Asserts the map opened in ArmySend mode, GO fired RequestArmySend "A:Town",
no player pin was set. The payload the client fired is handed to the SERVER half verbatim.

SERVER half (real ArmyPlan / ArmyRoute / ArmyController / SoldierController / FormationController / ArmyState /
ArmyTargets / ArmyCommand / RemoteGate + SecurityConfig; the march test's mock world): the RequestArmySend handler
ArmyPlan.Init registered receives that payload. Asserts TravellingToBase, the destination = a Crossroads approach
point (never his pin, never the plaza centre), a route, the block's distance from the STANDING player grows, FOLLOW
never takes over, arrival -> Engaging -> Holding, 0 teleports (PivotTo), the formation stays together.
Then the transitions: SEND while Following / Holding / Travelling, ATTACK while Following (a target / none: the state
is kept) and while Travelling, HOLD / RECALL while Travelling, RETREAT while Attacking. Logs -> docs/proof/army-command/.
"""
import json, os, subprocess, sys, tempfile
from pathlib import Path
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
from run_kit_detail_test import PRELUDE
import run_army_march_test as M
from army_cmd_mods import army_cmd_mods

LUAU = os.environ.get("LUAU", os.path.expanduser("~/.local/bin/luau"))
SH = ROOT / "src/ReplicatedStorage/Shared"; SV = ROOT / "src/ServerScriptService/Server"
CL = ROOT / "src/StarterPlayer/StarterPlayerScripts/Client"
PROOF = ROOT / "docs/proof/army-command"


def luau(chunks):
    with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False) as f:
        f.write("\n".join(chunks)); p = f.name
    r = subprocess.run([LUAU, p], capture_output=True, text=True, timeout=900)
    return r.stdout + r.stderr


# ── the client half ───────────────────────────────────────────────────────────────────────────────────────────────
def client_run(normal=False):
    mods = army_cmd_mods(server=False)
    mods["Client/Controllers/MapController"] = CL / "Controllers/MapController.luau"
    mods["Client/Controllers/OrdersController"] = CL / "Controllers/OrdersController.luau"
    pre = PRELUDE.replace('game = { GetService = function(_, n) if n == "ReplicatedStorage" then return RS end return any end }', 'RS_ = RS')
    chunks = [pre, (HERE / "army_cmd_env.luau").read_text(), (HERE / "army_cmd_client.luau").read_text(), "NORMAL = %s" % ("true" if normal else "false")]
    for k, p in mods.items():
        chunks.append("SOURCES[%r] = function(script)\n%s\nend" % (k, p.read_text()))
    chunks.append(r'''
local owner = Instance.new("Player"); owner.UserId = 470626172; owner.Name = "shaunie6"
local pg = Instance.new("PlayerGui"); pg.Name = "PlayerGui"; pg.Parent = owner
owner:SetAttribute("WE_ArmyDebug", true)
local ch = Instance.new("Model"); ch.Name = "Char"; local hrp = Instance.new("Part"); hrp.Name = "HumanoidRootPart"; hrp.CFrame = CFrame.new(-500, 3, 0); hrp.Parent = ch
local hum = Instance.new("Humanoid"); hum.Health = 100; hum.Parent = ch
owner.Character = ch
PLAYERS = { owner }
local MC, OC, ok = startClient(owner)
pushToClient("SquadOrderStateUpdate", { Order = "Follow", Soldiers = 75, State = "Following" })
pushToClient("SoldierStateUpdate", { Soldiers = 75, MaxSoldiers = 87 })
if NORMAL then
  -- a Normal-mode map (the M key / the HUD map button) still pins with GO, fires no army remote
  MC.Open(); print("C_MODE", MC.Mode()); tapWorld(0, 0); press(findInst("Go", "TextButton"))
  print("C_NORMAL_PINS", #PIN_LOG)
  local n = 0; for _, r in ipairs(REMOTE_LOG) do if r.name == "RequestArmySend" then n += 1 end end
  print("C_NORMAL_SENDS", n)
else
OC.Open()
local send = findInst("Order_Send", "TextButton")
press(send)
print("C_MODE", MC.Mode and MC.Mode() or "none")
tapWorld(0, 0)
local go = findInst("Go", "TextButton")
print("C_GOTEXT", P(go, "Text"))
press(go)
print("C_OPEN_AFTER", MC.IsOpen())
print("C_MODE_AFTER", MC.Mode and MC.Mode() or "none")
for _, r in ipairs(REMOTE_LOG) do if r.name == "RequestArmySend" or r.name == "RequestSquadOrder" then print("C_REMOTE", r.name, table.unpack(r.args)) end end
print("C_PINS", #PIN_LOG)
-- the highlight is the SERVER's: a press does not light ATTACK; the push does
local atk = findInst("Order_Attack", "TextButton")
press(atk)
local folB = findInst("Order_Follow", "TextButton")
local function lit(b) local s = b:FindFirstChildOfClass("UIStroke"); return s ~= nil and P(s, "Thickness") == 2.5 end
print("C_LIT_FOLLOW", lit(folB)); print("C_LIT_ATTACK", lit(atk))
print("C_LIT_AFTER_PRESS", if lit(atk) then "same" else "differs")
pushToClient("SquadOrderStateUpdate", { Order = "Attack", Soldiers = 75, State = "TravellingToBase", Plan = { Text = "Marching to Crossroads Town" } })
local sendB = findInst("Order_Send", "TextButton")
print("C_SEND_LIT", lit(sendB) and not lit(folB))
end
''')
    return luau(chunks)


# ── the server half ───────────────────────────────────────────────────────────────────────────────────────────────
SERVER_EXTRA = r'''
-- Code Bot: the remotes ArmyPlan.Init registers (the client's RequestArmySend lands on the real handler)
HANDLERS = {}; PUSHES = {}
local function remote(name)
  local ev = { Name = name, IsA = function(_, c) return c == "RemoteEvent" end }
  ev.OnServerEvent = { Connect = function(_, fn) HANDLERS[name] = fn; return { Disconnect = function() end } end }
  ev.FireClient = function(_, p, kind, data) table.insert(PUSHES, { name = name, kind = kind, data = data }) end
  return ev
end
DEPS.RemoteSetup = { Get = function(name) return remote(name) end }
DEPS.RateLimitService = { Allow = function() return true end }
warn = function(...) print("WARN", ...) end
local WS = game:GetService("Workspace")
WS.Raycast = function() return nil end
'''

SERVER_TEST = r'''
local AP = require(node("Modules/ArmyPlan"))
local AC = require(node("Modules/ArmyController"))
local Route = require(node("Modules/ArmyRoute"))
local AS = require(node("Modules/ArmyState"))
local ACmd = require(node("Modules/ArmyCommand"))
local AT = require(node("Modules/ArmyTargets"))
local AL = require(node("Util/ArmyLog"))
AL.ForceOn = true
Route._SetComputer(function(a, b)
  local out = {}; local d = b - a; local n = math.max(1, math.ceil(Vector3.new(d.X, 0, d.Z).Magnitude / 8))
  for i = 1, n do local p = a + d * (i / n); table.insert(out, Vector3.new(p.X, 0, p.Z)) end
  return out end)
local N = NUNITS
local owner = mkPlayer(470626172, "shaunie6", OWNERAT)
PLAYERS = { owner }
PROFILES[owner.UserId] = { Raid = {}, FirstJoinUnix = 1 }
local st = { Units = {}, Order = "Follow" }
for i = 1, N do table.insert(st.Units, mkUnit(i, OWNERAT + Vector3.new(-10 - (i // 8) * 3, 0, (i % 8) * 3 - 10.5))) end
for _, u in ipairs(st.Units) do u.Model:SetAttribute("WE_Escorts", 0) end
local realSpawn = task.spawn
task.spawn = function() end
AC.Start({ Squads = function() return { [owner.UserId] = st } end, CharacterRoot = function(p) return p._root end, UnitWalkSpeed = function() return 14 end })
task.spawn = realSpawn
-- the NPCs: { pos, alive } - the pick sees the living ones within opts.Reach of opts.Centre (the one hostility rule's stand-in)
local function npc(pos) return { Kind = "NPC", Hum = { Health = 100, Parent = { GetAttribute = function() return "npc" end, Name = "Def" } }, Root = { Position = pos, Parent = true } } end
ENEMIES = {}
for _, p in ipairs(ENEMYAT or {}) do table.insert(ENEMIES, npc(p)) end
local pick = function(player, s, proot, opts)
  s._acTarget = nil
  local best, bd = nil, math.huge
  for _, e in ipairs(ENEMIES) do
    if e.Hum.Health > 0 and opts and opts.Centre then
      local d = Vector3.new(e.Root.Position.X - opts.Centre.X, 0, e.Root.Position.Z - opts.Centre.Z).Magnitude
      if d <= (opts.Reach or 0) and d < bd then best, bd = e, d end
    end
  end
  s._acTarget = best
end
local STATES = {}
DEPS.SquadOrdersService = { Push = function() end, UnitPower = function() return 20, 150, 20 end,
  SetOrder = function(p, o, src) return (ACmd.Order(p, st, o, src)) end, StateOf = function() return st end }
AP.Init(DEPS)
AP._SetClock(function() return NOW end)
-- SquadOrdersService.Init's bindings (the real service is not loaded in the sim)
AS.Bind({ OnChange = function() end, Push = function(p) table.insert(STATES, AS.Of(st)) end })
ACmd.Bind({ StateOf = function() return st end, Pick = pick, Push = function() end, OwnerRoot = function(p) return p._root end,
  HomePos = function() return HOMEAT end, NotificationService = DEPS.NotificationService })
local DT = 0.05
local function centre()
  local s, n = Vector3.zero, 0
  for _, u in ipairs(st.Units) do s += u.Root.Position; n += 1 end
  return s / n
end
local function flat(a, b) return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude end
FOLLOW_TAKEOVER = 0; SPREAD = 0; MAXSTEP = 0; SNAPS = 0; MAXWS = 0; SPREAD_ENGAGE = 0; SLOTLAG = 0; DEPTH = 0; WIDTH = 0
local acc, acc2 = 0, 0
local function run(secs, each)
  local stop = NOW + secs
  while NOW < stop do
    NOW += DT
    acc += DT; acc2 += DT
    local before, ws0 = {}, {}
    for i, u in ipairs(st.Units) do before[i] = u.Root.Position; ws0[i] = u.Humanoid.WalkSpeed end
    stepUnits(st.Units, DT)
    if acc >= 0.2 - 1e-9 then acc = 0; AC._StepArmy(owner, st, NOW) end
    if acc2 >= 0.4 - 1e-9 then
      acc2 = 0
      if AP.Owns(owner.UserId) then AP.Think(owner, st, owner._root, pick, NOW) end
      -- the enemies die once the block stands on them (the steered ATTACK's stand-in)
      local c = centre()
      for _, e in ipairs(ENEMIES) do if flat(e.Root.Position, c) < 40 then e.Hum.Health = 0 end end
      if each then each() end
    end
    for i, u in ipairs(st.Units) do
      local stp = flat(u.Root.Position, before[i])
      MAXWS = math.max(MAXWS, u.Humanoid.WalkSpeed)
      if stp > ws0[i] * DT + 0.01 then SNAPS += 1 end -- a move faster than its own walk = a snap
      MAXSTEP = math.max(MAXSTEP, stp)
    end
  end
end
local function stateNow() return AS.Of(st) end
local function say(k, v) print("S_" .. k .. " " .. tostring(v)) end
local function sendRemote(payload) HANDLERS.RequestArmySend(owner, payload) end
local function order(o) local ok, why = ACmd.Order(owner, st, o, "test " .. o); return ok, why end
-- warm up: FOLLOW forms behind him
run(6)
say("WARM", stateNow())
SCENARIO()
'''

SCEN = {}
SCEN["crossroads"] = r'''
function SCENARIO()
  say("BEFORE", stateNow())
  local d0 = flat(centre(), owner._root.Position)
  sendRemote(PAYLOAD)
  say("AFTER_SEND", stateNow())
  local p = AP.Current(owner.UserId)
  say("DEST", p and p.Dest and string.format("%.0f,%.0f", p.Dest.X, p.Dest.Z) or "nil")
  say("DESTATTR", tostring(owner:GetAttribute("WE_ArmyDest")))
  say("ROUTE", p and p.Route and #p.Route or 0)
  local dists = {}
  local samples = 0
  local arrived, engaged, held = false, false, false
  run(80, function()
    samples += 1
    local c = centre()
    local s = stateNow()
    local p0 = AP.Current(owner.UserId)
    for _, u in ipairs(st.Units) do
      local d = flat(u.Root.Position, c)
      if p0 and p0.Phase == "March" and samples > 20 then
        SPREAD = math.max(SPREAD, d)
        if u._target then SLOTLAG = math.max(SLOTLAG, flat(u.Root.Position, u._target)) end
      else SPREAD_ENGAGE = math.max(SPREAD_ENGAGE, d) end
    end
    if p0 and p0.Phase == "March" and samples > 20 then
      -- the block's own shape: its extent along / across the march (a long column is coherent, a scatter is not)
      local fwd = p0.LeadVel.Magnitude > 0.5 and p0.LeadVel.Unit or Vector3.new(1, 0, 0)
      local right = Vector3.new(-fwd.Z, 0, fwd.X)
      local a0, a1, r0, r1 = math.huge, -math.huge, math.huge, -math.huge
      for _, u in ipairs(st.Units) do
        local o = u.Root.Position - c
        local a, r = o.X * fwd.X + o.Z * fwd.Z, o.X * right.X + o.Z * right.Z
        a0 = math.min(a0, a); a1 = math.max(a1, a); r0 = math.min(r0, r); r1 = math.max(r1, r)
      end
      DEPTH = math.max(DEPTH, a1 - a0); WIDTH = math.max(WIDTH, r1 - r0)
    end
    if s == "Following" then FOLLOW_TAKEOVER += 1 end
    if s == "EngagingTarget" then engaged = true end
    if s == "Holding" then held = true end
    if samples % 10 == 0 then table.insert(dists, string.format("%.0f", flat(c, owner._root.Position))) end
  end)
  say("DISTS", table.concat(dists, ","))
  say("D0", string.format("%.0f", d0))
  say("FOLLOW_TAKEOVER", FOLLOW_TAKEOVER)
  say("ENGAGED", engaged)
  say("HELD", held)
  say("FINAL", stateNow())
  local c = centre()
  say("FINALPOS", string.format("%.0f,%.0f", c.X, c.Z))
  say("SPREAD", string.format("%.1f", SPREAD))
  say("TELEPORTS", TELEPORTS)
  say("MAXSTEP", string.format("%.2f", MAXSTEP))
  say("SLOTLAG", string.format("%.1f", SLOTLAG)); say("DEPTH", string.format("%.1f", DEPTH)); say("WIDTH", string.format("%.1f", WIDTH))
  say("SNAPS", SNAPS); say("MAXWS", string.format("%.1f", MAXWS)); say("SPREAD_OTHER", string.format("%.1f", SPREAD_ENGAGE))
  for _, n in ipairs(LOG.notify) do print("notify", n.t) end
end
'''
SCEN["send_while_holding"] = r'''
function SCENARIO()
  order("Hold"); run(2)
  say("BEFORE", stateNow())
  sendRemote("A:Town")
  say("AFTER", stateNow())
  local c0 = centre(); run(10); say("MOVED", string.format("%.0f", flat(centre(), c0)))
end
'''
SCEN["send_while_travelling"] = r'''
function SCENARIO()
  sendRemote("A:Town"); run(6)
  say("BEFORE", stateNow())
  local d1 = AP.Current(owner.UserId).Target.Key
  sendRemote("S:CampViper")
  local p = AP.Current(owner.UserId)
  say("AFTER", stateNow())
  say("TARGETS", d1 .. "->" .. (p and p.Target and p.Target.Key or "nil"))
end
'''
SCEN["attack_following_target"] = r'''
function SCENARIO()
  say("BEFORE", stateNow())
  local ok = order("Attack")
  say("OK", ok)
  say("AFTER", stateNow())
  run(15)
  say("LATER", stateNow())
end
'''
SCEN["attack_following_none"] = r'''
function SCENARIO()
  say("BEFORE", stateNow())
  local ok, why = order("Attack")
  say("OK", ok); say("WHY", why)
  say("AFTER", stateNow())
  for _, n in ipairs(LOG.notify) do print("notify", n.t) end
end
'''
SCEN["attack_while_travelling"] = r'''
function SCENARIO()
  sendRemote("A:Town"); run(8)
  say("BEFORE", stateNow())
  local ok, why = order("Attack")
  say("OK", ok); say("WHY", why)
  say("AFTER", stateNow())
  local p = AP.Current(owner.UserId); say("PLAN", p and p.Kind or "none")
end
'''
SCEN["hold_while_travelling"] = r'''
function SCENARIO()
  sendRemote("A:Town"); run(8)
  say("BEFORE", stateNow())
  order("Hold")
  say("AFTER", stateNow())
  say("PLAN", AP.Current(owner.UserId) and "yes" or "none")
  local c0 = centre(); run(6); say("DRIFT", string.format("%.0f", flat(centre(), c0)))
end
'''
SCEN["recall_while_travelling"] = r'''
function SCENARIO()
  sendRemote("A:Town"); run(14)
  say("BEFORE", stateNow())
  local far = flat(centre(), owner._root.Position)
  order("Recall")
  say("AFTER", stateNow())
  run(60)
  say("LATER", stateNow())
  say("FAR", string.format("%.0f", far)); say("NEAR", string.format("%.0f", flat(centre(), owner._root.Position)))
  say("TELEPORTS", TELEPORTS)
end
'''
SCEN["retreat_while_attacking"] = r'''
function SCENARIO()
  order("Attack"); run(3)
  say("BEFORE", stateNow())
  order("Retreat")
  say("AFTER", stateNow())
  say("PLAN", AP.Current(owner.UserId) and AP.Current(owner.UserId).Kind or "none")
end
'''
SCEN["bad_target"] = r'''
function SCENARIO()
  sendRemote("A:Nowhere")
  say("AFTER", stateNow())
  sendRemote({ 1, 2 })
  say("AFTER2", stateNow())
end
'''


def server_run(name, n=24, owner="Vector3.new(-500, 3, 0)", enemies="{}", payload='"A:Town"', home="Vector3.new(-900, 0, 0)"):
    mods = {**army_cmd_mods(), **M.MODS}
    mods["Configs/SecurityConfig"] = SH / "Configs/SecurityConfig.luau"
    mods["Modules/RemoteGate"] = SV / "Modules/RemoteGate.luau"
    mods["Constants"] = SH / "Constants.luau"
    chunks = [PRELUDE, M.EXTRA, SERVER_EXTRA,
              f"NUNITS = {n}\nESC = 0\nOWNERAT = {owner}\nHOMEPLOT = nil\nMIDPLOT = nil\nCAMP = nil\nCAMPN = 0\nENEMYAT = {enemies}\nPAYLOAD = {payload}\nHOMEAT = {home}\n"]
    for key, path in mods.items():
        body = path.read_text(encoding="utf-8") if isinstance(path, Path) else path
        chunks.append("SOURCES[%r] = function(script)\n%s\nend" % (key, body))
    chunks.append(SERVER_TEST.replace("\nSCENARIO()\n", "\n" + SCEN[name] + "\nSCENARIO()\n"))
    return luau(chunks)


def vals(out):
    d = {}
    for line in out.splitlines():
        if line.startswith("S_") or line.startswith("C_"):
            k, _, v = line.replace("\t", " ").partition(" ")
            d[k] = v.strip()
    return d


if __name__ == "__main__":
    fails = 0

    def check(ok, msg):
        global fails
        print(("ok    " if ok else "FAIL  ") + msg)
        if not ok:
            fails += 1

    PROOF.mkdir(parents=True, exist_ok=True)
    # 1) the client chain
    cout = client_run()
    (PROOF / "after-client.log").write_text(cout)
    c = vals(cout)
    remotes = [l for l in cout.splitlines() if l.startswith("C_REMOTE")]
    sendLine = next((l for l in remotes if "RequestArmySend" in l), None)
    check(c.get("C_MODE") == "ArmySend", f"Army SEND opens the map in ArmySend mode ({c.get('C_MODE')})")
    check(c.get("C_GOTEXT") == "SEND ARMY", f"the card's button reads SEND ARMY in ArmySend mode ({c.get('C_GOTEXT')})")
    check(sendLine is not None and sendLine.split()[-1] == "A:Town", f"GO fired RequestArmySend A:Town ({sendLine})")
    check(c.get("C_PINS") == "0", f"no player pin from the army GO (pins {c.get('C_PINS')})")
    check(c.get("C_OPEN_AFTER") == "false" and c.get("C_MODE_AFTER") == "Normal", "the map closed and is back in Normal mode")
    check(c.get("C_LIT_AFTER_PRESS") == "differs" and c.get("C_LIT_FOLLOW") == "true", "pressing ATTACK does not light it (no optimistic highlight; FOLLOW stays lit until the server says)")
    check(c.get("C_SEND_LIT") == "true", "the server's TravellingToBase lights SEND")
    cn = vals(client_run(normal=True))
    check(cn.get("C_MODE") == "Normal" and cn.get("C_NORMAL_PINS") == "1" and cn.get("C_NORMAL_SENDS") == "0", "the normal map (not army mode) still pins with GO (JOB 40 tap-to-pin unchanged)")
    payload = '"' + sendLine.split()[-1] + '"' if sendLine else '"A:Town"'

    # 2) the Crossroads scenario (server, the client's own payload), 75 soldiers, the plaza defended
    out = server_run("crossroads", n=75, payload=payload, enemies="{ Vector3.new(0, 3, 30), Vector3.new(20, 3, -10) }")
    (PROOF / "after-server-crossroads.log").write_text(out)
    s = vals(out)
    check(s.get("S_BEFORE") == "Following" and s.get("S_AFTER_SEND") == "TravellingToBase", f"Following -> TravellingToBase on the SEND ({s.get('S_BEFORE')} -> {s.get('S_AFTER_SEND')})")
    check(s.get("S_DEST") == "-100,0", f"destination = the Crossroads west approach point (-100,0), not his pin / the plaza centre ({s.get('S_DEST')})")
    check(s.get("S_DESTATTR", "nil") != "nil", "WE_ArmyDest set (the map's ARMY marker)")
    check(int(s.get("S_ROUTE", "0") or 0) > 0, f"a route was computed ({s.get('S_ROUTE')} waypoints)")
    dists = [int(x) for x in s.get("S_DISTS", "").split(",") if x]
    grows = len(dists) >= 4 and dists[3] > int(s.get("S_D0", "0")) + 100 and all(dists[i] <= dists[i + 1] + 3 for i in range(min(len(dists) - 1, 6)))
    check(grows, f"the block walks AWAY from the standing player (start {s.get('S_D0')}, every 4 s: {s.get('S_DISTS')})")
    check(s.get("S_FOLLOW_TAKEOVER") == "0", f"FOLLOW never takes over during the travel ({s.get('S_FOLLOW_TAKEOVER')} samples)")
    check(s.get("S_ENGAGED") == "true" and s.get("S_HELD") == "true" and s.get("S_FINAL") == "Holding", f"arrival -> EngagingTarget -> Holding at Crossroads ({s.get('S_ENGAGED')}, {s.get('S_HELD')}, {s.get('S_FINAL')})")
    fx, fz = (float(v) for v in s.get("S_FINALPOS", "9999,9999").split(","))
    check(abs(fx) < 140 and abs(fz) < 140, f"the army ends at Crossroads ({s.get('S_FINALPOS')})")
    check(s.get("S_TELEPORTS") == "0" and s.get("S_SNAPS") == "0", f"no teleport / snap (PivotTo {s.get('S_TELEPORTS')}, moves faster than the unit's own WalkSpeed {s.get('S_SNAPS')}; max WalkSpeed {s.get('S_MAXWS')}, max step {s.get('S_MAXSTEP')} per 0.05 s)")
    check(float(s.get("S_SLOTLAG", "999")) <= 6 and float(s.get("S_WIDTH", "999")) <= 30,
          f"75-soldier block stays coherent on the march (every soldier within {s.get('S_SLOTLAG')} studs of its formation slot; column {s.get('S_WIDTH')} wide x {s.get('S_DEPTH')} deep)")
    for tag in ["[SERVER ARMY] received", "[ARMY STATE]", "[ARMY DESTINATION]", "[ARMY PATH]", "[ARMY MOVE]"]:
        check(tag in out, f"log chain has {tag}")

    # 3) the transitions
    def scen(name, **kw):
        o = server_run(name, **kw)
        (PROOF / f"after-server-{name}.log").write_text(o)
        return vals(o), o
    v, _ = scen("send_while_holding")
    check(v.get("S_BEFORE") == "Holding" and v.get("S_AFTER") == "TravellingToBase" and int(v.get("S_MOVED", "0")) > 40, f"SEND while Holding: {v.get('S_BEFORE')} -> {v.get('S_AFTER')}, moved {v.get('S_MOVED')}")
    v, _ = scen("send_while_travelling")
    check(v.get("S_BEFORE") == "TravellingToBase" and v.get("S_AFTER") == "TravellingToBase" and v.get("S_TARGETS", "").endswith("->S:CampViper"), f"SEND while Travelling retargets: {v.get('S_TARGETS')}")
    v, _ = scen("attack_following_target", enemies="{ Vector3.new(-400, 3, 60) }")
    check(v.get("S_BEFORE") == "Following" and v.get("S_OK") == "true" and v.get("S_AFTER") == "Attacking", f"ATTACK while Following (enemy 110 studs away): {v.get('S_BEFORE')} -> {v.get('S_AFTER')} later {v.get('S_LATER')}")
    v, o = scen("attack_following_none")
    check(v.get("S_OK") == "false" and v.get("S_WHY") == "NoEnemiesNear" and v.get("S_AFTER") == "Following" and "No enemies near" in o and "REJECTED" in o,
          f"ATTACK with nothing near: rejected NoEnemiesNear (logged + toast), state kept {v.get('S_AFTER')}")
    v, _ = scen("attack_while_travelling", enemies="{ Vector3.new(-330, 3, 40) }")
    check(v.get("S_BEFORE") == "TravellingToBase" and v.get("S_AFTER") == "Attacking" and v.get("S_PLAN") == "Clear", f"ATTACK while Travelling (an enemy by the army): {v.get('S_BEFORE')} -> {v.get('S_AFTER')} ({v.get('S_PLAN')})")
    v, _ = scen("attack_while_travelling")
    check(v.get("S_AFTER") == "TravellingToBase" and v.get("S_WHY") == "NoEnemiesNear", f"ATTACK while Travelling with nothing near: keeps travelling ({v.get('S_AFTER')})")
    v, _ = scen("hold_while_travelling")
    check(v.get("S_BEFORE") == "TravellingToBase" and v.get("S_AFTER") == "Holding" and v.get("S_PLAN") == "none" and int(v.get("S_DRIFT", "99")) <= 12, f"HOLD while Travelling: stops where it is (drift {v.get('S_DRIFT')})")
    v, _ = scen("recall_while_travelling")
    check(v.get("S_BEFORE") == "TravellingToBase" and v.get("S_AFTER") == "Recalling" and v.get("S_LATER") == "Following" and int(v.get("S_NEAR", "999")) < 40 and v.get("S_TELEPORTS") == "0",
          f"RECALL while Travelling: Recalling -> Following, walked back {v.get('S_FAR')} -> {v.get('S_NEAR')} studs, no teleport")
    v, _ = scen("retreat_while_attacking", enemies="{ Vector3.new(-400, 3, 60) }")
    check(v.get("S_BEFORE") == "Attacking" and v.get("S_AFTER") in ("Retreating",), f"RETREAT while Attacking: {v.get('S_BEFORE')} -> {v.get('S_AFTER')} (plan {v.get('S_PLAN')})")
    v, o = scen("bad_target")
    check(v.get("S_AFTER") == "Following" and v.get("S_AFTER2") == "Following" and "reason=UnknownTarget" in o and "reason=BadTarget" in o, "bad targets are rejected with a logged reason, the state unchanged")
    print(f"ARMY COMMAND TEST: {fails} failed")
    sys.exit(1 if fails else 0)
