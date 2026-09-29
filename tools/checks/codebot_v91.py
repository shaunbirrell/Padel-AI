# Code Bot v91 (2026-09-28): every heli key on the attack heli 11240665977 with its own colour (owner-only like every heli
# body), and the army FOLLOW overhaul (Modules/ArmyFollow, ArmyConfig.Follow2) for everyone. Helpers start with _cb91_.
_cb91_vac = "src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau"
_cb91_src = read(_cb91_vac) or ""
_cb91_heli = {
    "TransportHeli": ("0.52", "54, 78, 56", True), "LightTransportHeli": ("0.48", "118, 134, 112", True),
    "HeavyLiftHeli": ("0.6", "116, 92, 66", True), "MedevacHeli": ("0.48", "160, 164, 168", True),
    "LightScoutHeli": ("0.45", "100, 108, 68", False), "RescueHeli": ("0.45", "190, 168, 122", False),
    "UtilityHeli": ("0.45", "150, 138, 100", False), "GunshipHeli": ("0.45", "74, 80, 88", False),
    "EscortHeli": ("0.45", "78, 98, 124", False), "NightAttackHeli": ("0.45", "58, 62, 40", False),
}
for _k, (_s, _c, _cab) in _cb91_heli.items():
    must_contain(_cb91_vac, f"\t\t{_k} = heliRef({_s}, Color3.fromRGB({_c}), {'true' if _cab else 'false'}, \"v91 owner pick: attack heli 11240665977", f"CODEBOT v91: Vehicles.{_k} wears the attack heli 11240665977 in its own colour ({_c}), scale {_s}{', cabin seat' if _cab else ''}")
must_contain(_cb91_vac, '\t\tAttackHelicopter = bodyRef(BODY_ATTACK_HELI, "v88 owner pick 11240665977 ', "CODEBOT v91: AttackHelicopter keeps its own dark navy (no recolour)")
must_contain(_cb91_vac, '\t\tStealthHeli = bodyRef(BODY_STEALTH_HELI, "v88 owner pick 11240665977 ', "CODEBOT v91: StealthHeli keeps its near-black")
_cols = [c for (_s, c, _cab) in _cb91_heli.values()] + ["27, 42, 53", "20, 22, 26"]
if len(set(_cols)) == len(_cols) == 12:
    ok("CODEBOT v91: 12 heli keys, 12 distinct colours")
else:
    bad(f"CODEBOT v91: heli colours must be distinct — {_cols}")
must_contain(_cb91_vac, "local function heliRef(scale: number, color: Color3?, cabin: boolean, note: string): AssetRef\n\tlocal r: { [string]: any } = {}\n\tfor k, v in pairs(BODY_ATTACK_HELI) do", "CODEBOT v91: heliRef copies BODY_ATTACK_HELI (Rollout Body = owner-only, the Blades rotor spec)")
must_contain(_cb91_vac, 'local HELI_PAINT_PARTS = { "BAP 1", "Body", "Doors", "Thing for Blades" }', "CODEBOT v91: only the heli body panels take the colour (glass, seats, blades, wheels keep theirs)")
must_contain(_cb91_vac, "\tseats.DriverSeat = Vector3.new(-4, 5.4, -30)\n\tseats.PassengerSeat1 = Vector3.new(4, 5.4, -30)\n\tseats.PassengerSeat2 = Vector3.new(-3.5, 5.0, -21) -- the cabin\n\tseats.PassengerSeat3 = Vector3.new(3.5, 5.0, -21)\n\tseats.PassengerSeat4 = Vector3.new(0, 5.0, -25)\n\tr.BodySeats = seats", "CODEBOT v91: every heli key: crew 3.5+ studs under the glass, passengers inside the cabin (live v87 raycasts)")
for _t in ("local BODY_LIGHT_HELI = {", "local BODY_TRANSPORT_HELI = {"):
    must_contain(_cb91_vac, _t, f"CODEBOT v91: {_t.split()[1]} stays defined for a one-line revert")
if "bodyRef(BODY_LIGHT_HELI" not in _cb91_src and "bodyRef(BODY_TRANSPORT_HELI" not in _cb91_src:
    ok("CODEBOT v91: no key wears the light / transport heli bodies any more")
else:
    bad("CODEBOT v91: a key still wears BODY_LIGHT_HELI / BODY_TRANSPORT_HELI")

# army FOLLOW overhaul
_cb91_af = "src/ServerScriptService/Server/Modules/ArmyFollow.luau"
_cb91_sos = "src/ServerScriptService/Server/Services/SquadOrdersService.luau"
_cb91_ac = "src/ReplicatedStorage/Shared/Configs/ArmyConfig.luau"
must_contain(_cb91_ac, '\tFollow2 = {\n\t\tEnabled = true,\n\t\tRollout = "all",', "CODEBOT v91: ArmyFollow is live for everyone (Follow2.Rollout all; off = the old follow)")
must_contain(_cb91_af, "PhysicsService:CollisionGroupSetCollidable(ArmyFollow.Group, ArmyFollow.Group, false)", "CODEBOT v91: squad units never collide with each other")
must_contain(_cb91_af, "hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)", "CODEBOT v91: no trip / ragdoll states (no flings)")
must_contain(_cb91_af, "\tlocal back = num(\"WedgeBack\", 3) + row * num(\"RowBack\", 3)\n", "CODEBOT v91: each unit has its own wedge slot behind the owner")
# v99: superseded (the push is now capped by SeparationMaxStuds; codebot_v99.py pins the new form)
must_contain(_cb91_af, "\tlocal pushOff = push * num(\"SeparationGain\", 3)\n", "CODEBOT v91: separation steering (v99 capped form)")
must_contain(_cb91_af, "\tif clearLine(pos, goal) then\n\t\tunit._afPath = nil\n\t\tmoveTo(unit, goal, now)\n", "CODEBOT v91: straight MoveTo while the slot is in sight, a path only when blocked")
must_contain(_cb91_af, "\tunit._afPathAt = now + num(\"PathCooldown\", 1.5)\n", "CODEBOT v91: pathfinding is throttled per unit")
must_contain(_cb91_af, "local cap = math.max(ownerPace * num(\"CatchUpMaxMult\", 1.8), num(\"CatchUpMin\", 34))", "CODEBOT v91: catch-up is faster than the owner's sprint (WalkSpeed incl. Speed Pass, or measured)")
# v114 (Code Bot Roblox): retired, superseded in tools/checks/codebot_v114_army.py (every soldier MoveTo is SoldierController.Move, the one PivotTo is SoldierController.Reposition): #must_contain(_cb91_af, "\tunit.Model:PivotTo(cf)\n", "CODEBOT v91: a far / stuck / fallen unit is moved (PivotTo), never deleted")
must_contain("src/ServerScriptService/Server/Modules/SoldierController.luau", "\tunit.Model:PivotTo(cf)\n", "CODEBOT v91 (v114): a far / stuck / fallen unit is moved (PivotTo, SoldierController.Reposition), never deleted")
must_not_contain(_cb91_af, ":Destroy()", "CODEBOT v91: ArmyFollow never destroys anything")
must_contain(_cb91_af, "\tif st._afInBase and st._afPlot then\n\t\tlocal w = waitSpot(st._afPlot, rank)\n", "CODEBOT v91: in his own base the army waits outside his main gate")
must_contain(_cb91_af, "\tlocal x = side * (gateHalf + num(\"BaseWaitGap\", 5)", "CODEBOT v91: the wait line stands beside the gate lane, never in it")
must_contain(_cb91_sos, "\t\tif SquadOrdersService._AFOn then\n", "CODEBOT v91: SquadOrdersService hands FOLLOW movement to ArmyFollow")
must_contain(_cb91_sos, "SquadOrdersService._AFOn = st ~= nil and SquadOrdersService._AF.LiveFor(player.UserId)", "CODEBOT v91: ArmyFollow is live per owner (Follow2 rollout)")
must_contain(_cb91_sos, "not SquadOrdersService._AFOn and SquadOrdersService._PaceBegin(player, proot)", "CODEBOT v91: the v85 FollowPace (and its teleports) is off under ArmyFollow")
must_contain(_cb91_sos, "(ArmyConfig.LiveFor(\"Fix\", uid) or SquadOrdersService._AF.LiveFor(uid))", "CODEBOT v91: a unit that lost its root is re-formed for everyone (no invisible ghosts)")
must_contain(_cb91_sos, "SquadOrdersService._AF.LogRemoval(u, ", "CODEBOT v91: every unit removal is logged with its reason")
# superseded frozen pins (the cull / trim now log a reason first; the ArmyFollow branch runs before recoverUnit)
must_contain(_cb91_sos, "\t\tif u.Alive and u.Model.Parent and (not rootless or u.Root.Parent == u.Model) and u.Humanoid.Health > 0 then\n\t\t\ttable.insert(living, u)\n\t\telse\n", "CODEBOT v91: SyncArmy's not-living cull still tests only Alive / in the world / root in its model / hp (no distance)")
must_contain(_cb91_sos, "\t\tlocal u = table.remove(st.Units, worst)\n\t\tif u then\n\t\t\tSquadOrdersService._AF.LogRemoval(u, \"fewer soldiers than units (trim)\") -- v91\n\t\t\tdestroyUnit(u)\n", "CODEBOT v91: the SyncArmy trim removes only above the desired count (logged)")
_cb91_s = read(_cb91_sos) or ""
_i_af, _i_rec = _cb91_s.find("\t\tif SquadOrdersService._AFOn then\n"), _cb91_s.find("\t\tif recoverUnit(player, st, unit, playerRoot, now) then")
_i_esc = _cb91_s.find("\t\tif not escortUnit(player, st, unit, playerRoot, escortHum, escortRoot, now) then")
if 0 <= _i_af < _i_rec < _i_esc:
    ok("CODEBOT v91: FOLLOW think = ArmyFollow when live, else RECOVER before the escort / follow move (as before)")
else:
    bad("CODEBOT v91: thinkUnit FOLLOW order must be ArmyFollow, then recoverUnit, then escortUnit")
