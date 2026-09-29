# Code Bot v99 (2026-09-29): army follow root-cause fix (one controller per unit, persistent unique seats, root-CFrame
# slots, no shared fallback point, staged stuck, rare far reposition out of view, ArmyNPCs group at spawn) + hotbar
# re-tap holster (touch + keys 1-4, full weapon-state reset) + Creator Hub Ids for JOB 5a-6 passes / JOB 5c products.
# Runs inside tools/BuyPathStatic.py (same globals). Helpers start with _cb99_.
import re as _cb99_re

_cb99_af = "src/ServerScriptService/Server/Modules/ArmyFollow.luau"
_cb99_so = "src/ServerScriptService/Server/Services/SquadOrdersService.luau"
_cb99_ac = "src/ReplicatedStorage/Shared/Configs/ArmyConfig.luau"
_cb99_cc = "src/StarterPlayer/StarterPlayerScripts/Client/Controllers/CombatController.luau"
_cb99_cf = "src/StarterPlayer/StarterPlayerScripts/Client/Modules/CameraFx.luau"
_cb99_wv = "src/StarterPlayer/StarterPlayerScripts/Client/Modules/WeaponVisuals.luau"
_cb99_hc = "src/ReplicatedStorage/Shared/Configs/HudConfig.luau"
_cb99_mc = "src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau"
_cb99_ms = "src/ServerScriptService/Server/Services/MonetizationService.luau"
_cb99_A = read(_cb99_af) or ""
_cb99_S = read(_cb99_so) or ""
_cb99_C = read(_cb99_ac) or ""


def _cb99_strip(code: str) -> str:
    code = _cb99_re.sub(r"--\[(=*)\[.*?\]\1\]", "", code, flags=_cb99_re.S)
    return _cb99_re.sub(r"--[^\n]*", "", code)


def _cb99_fn(code: str, head: str) -> str:
    i = code.find(head)
    if i < 0:
        return ""
    m = _cb99_re.search(r"^(?:local function \w+|function [\w.]+)\(", code[i + len(head):], _cb99_re.M)
    return code[i:i + len(head) + (m.start() if m else len(code))]


def _cb99_check(cond: bool, label: str) -> None:
    (ok if cond else bad)(label)


# ── build ──
#must_contain("src/ServerScriptService/Server/Services/DataService.luau", 'SetAttribute("WE_Build", 99)', "CODEBOT v99: WE_Build=99 DataService")
#must_contain("src/ServerScriptService/Server/Services/BaseService.luau", 'SetAttribute("WE_Build", 99)', "CODEBOT v99: WE_Build=99 BaseService")
#must_contain("src/ServerScriptService/Server/EarlyRemotes.server.luau", 'SetAttribute("WE_Build", 99)', "CODEBOT v99: WE_Build=99 EarlyRemotes")
#must_contain("src/ServerScriptService/Server/Services/DataService.luau", "WE_Build=99", "CODEBOT v99: DataService profile-loaded log says WE_Build=99")
# v100 (Code Bot): WE_Build pins retired, superseded in tools/checks/codebot_v100.py

# ── army: kill switches + gate hold / ATTACK seats kept ──
must_contain(_cb99_ac, '\tFollow2 = {\n\t\tEnabled = true,\n\t\tRollout = "all",', "CODEBOT v99: Follow2 kill switch kept")
# v101 (Code Bot): retired, superseded in tools/checks/codebot_v101.py: #must_contain(_cb99_ac, '\t\tTidy = {\n\t\t\tRollout = "owner",', "CODEBOT v99: Tidy kill switch kept (owner-only)")
must_contain(_cb99_af, "function ArmyFollow.AttackPoint(", "CODEBOT v99: ATTACK per-seat spots kept")
must_contain(_cb99_af, "local holdOut = st._afTidy and st._afInBase", "CODEBOT v99: gate hold outside the base kept")

# ── army 1: unique persistent slot, rotated by the root CFrame ──
_cb99_plan = _cb99_strip(_cb99_fn(_cb99_A, "local function plan("))
_cb99_check("assignSeats(st, order)" in _cb99_plan and "u._afRank = i" not in _cb99_plan and "u._afRank = u._afSeat" in _cb99_plan,
            "CODEBOT v99: every squad ranks by its persistent unique seat (no index ranking)")
_cb99_cs = _cb99_strip(_cb99_fn(_cb99_A, "local function compactSeats("))
_cb99_check("st._afSeatN ~= n" in _cb99_cs and "SeatCompactSeconds" in _cb99_cs, "CODEBOT v99: seats are renumbered only after the army size changed")
_cb99_sp = _cb99_strip(_cb99_fn(_cb99_A, "local function slotPoint("))
_cb99_check("PointToWorldSpace(Vector3.new(lat, 0, back))" in _cb99_sp and "CFrame.lookAt(root.Position, root.Position + dir)" in _cb99_sp,
            "CODEBOT v99: slot = the unit's own offset via the player's facing CFrame:PointToWorldSpace")
_cb99_check("turnToward(cur, want" in _cb99_plan and "root.CFrame.LookVector" in _cb99_plan, "CODEBOT v99: the formation turns with his root facing, rate-limited (TurnRateDeg)")
# geometry: seat offsets unique and wider than SeparationStuds, both rulesets, 1..24 units
def _cb99_num(block: str, key: str, d: float) -> float:
    m = _cb99_re.search(r"\b" + key + r" = (-?[\d.]+)", block)
    return float(m.group(1)) if m else d
_cb99_f2 = _cb99_C[_cb99_C.find("\tFollow2 = {"):_cb99_C.find("\t\tTidy = {")]
_cb99_td = _cb99_C[_cb99_C.find("\t\tTidy = {"):]
_cb99_sep = _cb99_num(_cb99_f2, "SeparationStuds", 3.5)
for _tidy in (False, True):
    _pts = []
    for _k in range(1, 25):
        _row = -(-_k // 2)
        _side = -1 if _k % 2 == 1 else 1
        _rb = _cb99_num(_cb99_td, "RowBack", 4) if _tidy else _cb99_num(_cb99_f2, "RowBack", 3)
        _rs = _cb99_num(_cb99_td, "RowSide", 3) if _tidy else _cb99_num(_cb99_f2, "RowSide", 2.5)
        _pts.append((_side * (_cb99_num(_cb99_f2, "WedgeSide", 2.5) + _row * _rs), _cb99_num(_cb99_f2, "WedgeBack", 3) + _row * _rb))
    _md = min(((a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2) ** 0.5 for i, a in enumerate(_pts) for b in _pts[i + 1:])
    _cb99_check(_md > _cb99_sep, f"CODEBOT v99: 24 seats ({'tidy' if _tidy else 'wedge'}) all unique, min gap {_md:.2f} > SeparationStuds {_cb99_sep}")

# ── army 2: no despawn / recreate for distance; rare reposition to its own slot, out of view ──
_cb99_check(":Destroy(" not in _cb99_strip(_cb99_A) and ":Clone(" not in _cb99_strip(_cb99_A) and 'Instance.new("Model")' not in _cb99_A,
            "CODEBOT v99: ArmyFollow never destroys / clones / creates a unit")
_cb99_unit = _cb99_strip(_cb99_fn(_cb99_A, "function ArmyFollow.Unit("))
_cb99_check("SetPrimaryPartCFrame" not in _cb99_strip(_cb99_A) and _cb99_unit.count("PivotTo(") == 1, "CODEBOT v99: the follow think's only PivotTo is the hold turn-on-the-spot (repositions go through regroup)")
_cb99_far = _cb99_num(_cb99_f2, "FarStuds", 0)
_cb99_check(80 <= _cb99_far <= 120 and _cb99_num(_cb99_f2, "FarSeconds", 0) >= 2, f"CODEBOT v99: far reposition only at 80-120 studs (FarStuds {_cb99_far}) for >= 2 s")
_cb99_sf = _cb99_strip(_cb99_fn(_cb99_A, "local function spotFor("))
_cb99_check("slot - dir * behind" in _cb99_sf and "RegroupMinOwnerStuds" in _cb99_sf, "CODEBOT v99: reposition = own slot pushed behind the camera, never on top of him")
_cb99_check("not st._afSeated and vel.Magnitude > num(\"OwnerJumpSpeed\"" in _cb99_plan, "CODEBOT v99: a fast vehicle is never an owner jump (no teleport loop behind vehicles)")
_cb99_sync = _cb99_strip(_cb99_fn(_cb99_S, "function SquadOrdersService.SyncArmy("))
_cb99_check(_cb99_strip(_cb99_S).count("destroyUnit(") == 1 + _cb99_sync.count("destroyUnit(") + _cb99_strip(_cb99_fn(_cb99_S, "local function clearSquad(")).count("destroyUnit("),
            "CODEBOT v99: units are destroyed only by SyncArmy (dead / trim) and clearSquad, never for distance")

# ── army 3: network ownership ──
_cb99_su = _cb99_strip(_cb99_fn(_cb99_S, "local function spawnUnit("))
_cb99_check("root:SetNetworkOwner(nil)" in _cb99_su and "SquadOrdersService._AF.PrepUnit(unit)" in _cb99_su, "CODEBOT v99: SetNetworkOwner(nil) + PrepUnit at spawn")
must_contain(_cb99_af, "if r:GetNetworkOwnershipAuto() then\n\t\t\t\t\t\t\tr:SetNetworkOwner(nil)", "CODEBOT v99: a late rig part never flips ownership back to auto")
_cb99_check("SetNetworkOwnershipAuto" not in _cb99_strip(_cb99_A + _cb99_S), "CODEBOT v99: no ownership flip in army code")

# ── army 4/5: MoveTo throttle, pathfinding only when blocked ──
must_contain(_cb99_af, 'flatDist(last, goal) >= num("ReissueStuds", 1.5) or now - (unit._afMoveAt or 0) >= num("ReissueSeconds", 5)', "CODEBOT v99: MoveTo re-sent only past ReissueStuds / ReissueSeconds")
_cb99_check(_cb99_num(_cb99_f2, "ReissueSeconds", 99) < 8 and _cb99_num(_cb99_f2, "ReissueStuds", 0) >= 1, "CODEBOT v99: ReissueSeconds < the 8 s MoveTo timeout, ReissueStuds >= 1")
_cb99_check(_cb99_unit.count("Humanoid:MoveTo(") == 2, "CODEBOT v99: the follow think calls Humanoid:MoveTo directly only for the two stand-still cases (else moveTo, throttled)")
_cb99_check(_cb99_unit.find("if clearLine(pos, goal) then") < _cb99_unit.find("requestPath(unit, pos, goal, now)"), "CODEBOT v99: straight MoveTo on open ground, a path only when blocked")
must_not_contain(_cb99_af, "keepOut(root.Position - (st._afDir or Vector3.zero) * 4)", "CODEBOT v99: no shared fallback point behind the owner (the blob)")
must_contain(_cb99_af, 'now - (path.At or 0) < num("PathKeepSeconds", 2)', "CODEBOT v99: a fresh path is kept (not dropped every think at a run)")
must_contain(_cb99_af, "flatDist(pos, nxt.Position) < flatDist(wp.Position, nxt.Position)", "CODEBOT v99: passed waypoints are skipped")

# ── army 6: smooth catch-up ──
must_contain(_cb99_af, 'local t = math.clamp((d - start) / ramp, 0, 1)', "CODEBOT v99: catch-up speed ramps continuously")
must_contain(_cb99_af, 'speed = math.clamp(speed, curSpeed - num("SpeedDownPerThink", 6), curSpeed + num("SpeedUpPerThink", 8))', "CODEBOT v99: WalkSpeed changes are rate-limited")

# ── army 7: collision group ──
must_contain(_cb99_af, 'ArmyFollow.Group = "ArmyNPCs"', "CODEBOT v99: the ArmyNPCs collision group")
must_contain(_cb99_af, "PhysicsService:CollisionGroupSetCollidable(ArmyFollow.Group, ArmyFollow.Group, false)", "CODEBOT v99: ArmyNPCs never collide with each other")
must_contain(_cb99_af, 'PhysicsService:CollisionGroupSetCollidable(ArmyFollow.Group, "Default", true)', "CODEBOT v99: ArmyNPCs still collide with the world / players")
must_contain(_cb99_so, "SquadOrdersService._AF.EnsureGroup()", "CODEBOT v99: the group is registered at Init")
_cb99_check(_cb99_re.search(r'CollisionGroupSetCollidable\([^)]*"Default"[^)]*false\)', _cb99_strip(_cb99_A + _cb99_S)) is None, "CODEBOT v99: global / player collisions are never disabled")

# ── army 8: staged stuck ──
_cb99_check(_cb99_num(_cb99_f2, "StuckSeconds", 0) < _cb99_num(_cb99_f2, "StuckAltSeconds", 0) < _cb99_num(_cb99_f2, "StuckTeleportSeconds", 0),
            "CODEBOT v99: stuck = repath, then an alternate point, then the reposition (in that order)")
_cb99_check(_cb99_unit.find('num("StuckTeleportSeconds"') >= 0 and "unit._afAlt = { P = alt" in _cb99_unit and "unit._afPathAt = -math.huge" in _cb99_unit,
            "CODEBOT v99: all three stuck stages exist")

# ── army 9: one controller per unit, one loop ──
_cb99_tu = _cb99_strip(_cb99_fn(_cb99_S, "local function thinkUnit("))
_cb99_check('SquadOrdersService._AF.Release(unit) -- v99' in _cb99_fn(_cb99_S, "local function thinkUnit(") and _cb99_tu.count("SquadOrdersService._AF.Release(unit)") == 2,
            "CODEBOT v99: ArmyFollow lets go when HOLD / ATTACK / RETREAT or the escort fight moves the unit")
_cb99_check("acquire(unit, now)" in _cb99_unit and 'num("ThinkGapReset", 1.2)' in _cb99_A, "CODEBOT v99: ArmyFollow (re)acquires with fresh state after any gap")
must_contain(_cb99_af, "unit.Humanoid.AutoRotate = false -- the NPCFaceGyro turns it (faceTo): one yaw owner", "CODEBOT v99: one yaw owner while following")
_cb99_check(_cb99_re.search(r"Heartbeat|RenderStepped|\.Stepped", _cb99_strip(_cb99_A + _cb99_S)) is None, "CODEBOT v99: no per-frame loops in army code")
_cb99_check(_cb99_strip(_cb99_S).count("while true do") == 1 and _cb99_strip(_cb99_A).count("while true do") == 0, "CODEBOT v99: one think loop for every army (started once in Init)")
_cb99_check("unit._afPrep" in _cb99_A and "if unit._afPrep then\n\t\treturn" in _cb99_A, "CODEBOT v99: per-unit connections made once (PrepUnit guard)")

# ── BUG 2: hotbar re-press holsters, full reset ──
must_contain(_cb99_hc, "\tTouchTapHolsters = true,", "CODEBOT v99: a touch re-tap of the drawn slot holsters")
must_contain(_cb99_hc, "\tTapSelectedHolsters = true,", "CODEBOT v99: a click / key re-press of the drawn slot holsters")
_cb99_ss = _cb99_strip(_cb99_fn(read(_cb99_cc) or "", "local function selectSlot("))
_cb99_check("if drawn and id == active then\n\t\tif retapHolsters then\n\t\t\tW2.holster()" in _cb99_ss and "equip(id)" in _cb99_ss, "CODEBOT v99: selectSlot: same slot = holster, other slot = swap")
must_contain(_cb99_cc, "selectSlot(slot, HB.TapSelectedHolsters)", "CODEBOT v99: keyboard 1-4 go through the same toggle")
must_contain(_cb99_cc, "hum:UnequipTools()", "CODEBOT v99: holster unequips any Tool (back to the Backpack)")
must_contain(_cb99_cc, "HolsterAutoDrawGraceSeconds", "CODEBOT v99: being shot does not re-draw right after a holster")
must_contain(_cb99_cc, "setDrawn(false) -- v99: death holsters at once", "CODEBOT v99: death holsters")
must_contain(_cb99_cc, "\tdrawn = HB.DrawnOnSpawn == true\n\tstopFiring()", "CODEBOT v99: every respawn starts holstered, not firing")
must_contain(_cb99_cf, "\t\treleaseShoulder()\n\t\ttrackModel = nil\n\t\t-- v99: holstered = no recoil left in flight", "CODEBOT v99: holster resets camera offset / AutoRotate / aim help / recoil")
must_contain(_cb99_wv, "-- v99: holstered mid-reload: the reload track stops", "CODEBOT v99: holster stops the reload track (hold track + gun model in syncLocalGun)")
_cb99_check(_cb99_re.search(r"ChildRemoved|Backpack\.ChildAdded", _cb99_strip(read(_cb99_cc) or "")) is None, "CODEBOT v99: no auto re-equip on a Backpack / Character child change")

# ── Creator Hub Ids (owner approved 2026-09-29) ──
_cb99_M = read(_cb99_mc) or ""
for _key, _id, _price in (("PV_Skylance", 2001602422, 899), ("PV_Stormwing", 2001722392, 999), ("PV_Leviathan", 2001398410, 1199),
                          ("PV_Tidebreaker", 1999263465, 299), ("PV_Warlord", 2001320428, 799), ("PV_Razorfang", 2002484380, 199),
                          ("BiggerArmy", 2001734404, 249), ("ExtraGarageSlot", 1999359549, 199),
                          ("SoldierRefill", 3715442523, 49), ("PlazaAirstrike", 3715442542, 79)):
    _m = _cb99_re.search(r"\n\t\t" + _key + r" = \{[^\n]*\n\t\t\tId = (\d+),.*?RobuxPrice = (\d+),", _cb99_M, _cb99_re.S)
    _cb99_check(bool(_m) and int(_m.group(1)) == _id and int(_m.group(2)) == _price, f"CODEBOT v99: {_key} Id {_id}, {_price} R$")
    _cb99_check(_key + " = true" in _cb99_M[_cb99_M.find("\tRolloutKeys = {"):_cb99_M.find("\n", _cb99_M.find("\tRolloutKeys = {"))], f"CODEBOT v99: {_key} stays owner-only (RolloutKeys)")
_cb99_dp = _cb99_M[_cb99_M.find("\tDevProducts = {"):_cb99_M.find("\tCounterGrants = {")]
_cb99_ids = [int(x) for x in _cb99_re.findall(r"\n\t\t\tId = (\d+),", _cb99_dp) if int(x) != 0]
_cb99_check(len(_cb99_ids) == len(set(_cb99_ids)), "CODEBOT v99: every DevProduct Id is unique (ProcessReceipt finds one row)")
must_contain(_cb99_mc, "GrantSoldierRefills = 1,", "CODEBOT v99: SoldierRefill banks one refill token")
must_contain(_cb99_mc, "GrantAirstrikes = 1,", "CODEBOT v99: PlazaAirstrike banks one airstrike charge")
_cb99_pr = _cb99_strip(_cb99_fn(read(_cb99_ms) or "", "local function processReceipt("))
_i1, _i2, _i3, _i4 = _cb99_pr.find("if hasProcessed(profile, receiptId) then"), _cb99_pr.find("applyCounterGrant(player, profile, c)"), _cb99_pr.find("markProcessed(profile, receiptId)"), _cb99_pr.rfind("return Enum.ProductPurchaseDecision.PurchaseGranted")
_cb99_check(0 <= _i1 < _i2 < _i3 < _pr_save if (_pr_save := _cb99_pr.find("DataService.SaveProfile(player, false) then\n\t\trememberPendingGrant")) >= 0 else False,
            "CODEBOT v99: receipt: idempotency check, counter grant, mark processed, then save")
_cb99_check(_i4 > _pr_save >= 0, "CODEBOT v99: PurchaseGranted only after the grant is saved")
must_contain(_cb99_ms, 'if productKey == "SoldierRefill" and SoldierService and SoldierService.ConsumeRefills then', "CODEBOT v99: a granted refill is spent at once (post-save listener)")
