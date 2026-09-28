# Code Bot v87 (2026-09-28): owner-only store bodies for the helicopters, bombers, transports and ships. Runs inside
# tools/BuyPathStatic.py (its globals: must_contain, must_not_contain, read, ok, bad, ROOT). Helper names start with
# _cb87_. Supersedes the frozen-body pins retired in this commit (v41 PatrolBoat / Attack Boat, v42 Frigate, the vscale
# 0.05 clamp line, the RescueHeli / MedevacHeli Part-kit rows, the AirBodyRig.Apply no-op condition).
_cb87_vac = "src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau"
_cb87_vas = "src/ServerScriptService/Server/Services/VisualAssetService.luau"
_cb87_rig = "src/ServerScriptService/Server/Modules/AirBodyRig.luau"
_cb87_veh = "src/ServerScriptService/Server/Services/VehicleService.luau"

# the rollout: owner only, every new body carries Rollout = "Body"
must_contain(_cb87_vac, '\tBodyRollout = "owner",\n', "CODEBOT v87: VisualAssetConfig.BodyRollout ships \"owner\" (only the playtest owner's vehicles wear the new bodies)")
_cb87_map = {
    # v91 (Code Bot): every heli key moved to the attack heli 11240665977 (codebot_v91.py); the tables stay, unused
    "BODY_LIGHT_HELI": ("3130894523", ()),
    "BODY_TRANSPORT_HELI": ("109615982233602", ()),
    "BODY_BOMBER": ("14669079591", ("StrikeBomber", "HeavyBomber", "StrategicBomber")),
    "BODY_PATROL_BOAT": ("16692908395", ("PatrolBoat", "FastAttackCraft", "RiverBoat", "CoastCutter", "TorpedoBoat")),
    "BODY_GUNBOAT": ("15838664806", ("Gunboat", "MissileBoat", "MineLayer", "CoastalMonitor")),
    "BODY_FRIGATE": ("473576954", ("Corvette", "Frigate", "CarrierEscort")),
    "BODY_CARRIER": ("7941124517", ("FleetCarrier",)),
    "BODY_AMPHIB": ("5545544418", ("AmphibAssault",)),
    "BODY_SUB": ("116924692473761", ("SubSurfaceRunner", "AttackSub")),
}
_cb87_src = read(_cb87_vac)
for _cb87_tb, (_cb87_id, _cb87_keys) in _cb87_map.items():
    _cb87_i = _cb87_src.find(f"local {_cb87_tb} = {{\n")
    _cb87_j = _cb87_src.find("\n}\n", _cb87_i)
    _cb87_body = _cb87_src[_cb87_i:_cb87_j] if _cb87_i >= 0 and _cb87_j > _cb87_i else ""
    for _cb87_need in (f"\tModelAssetId = {_cb87_id},\n", '\tRollout = "Body",\n', '\tFit = "Kit",\n', "\tHideKit = true,\n", '\t\tDriverSeat = Vector3.new(', '\tBodyAnchor = "DriverSeat",\n'):
        if _cb87_need in _cb87_body:
            ok(f"CODEBOT v87: {_cb87_tb} holds {_cb87_need.strip()}")
        else:
            bad(f"CODEBOT v87: {_cb87_tb} holds {_cb87_need.strip()}")
    for _cb87_k in _cb87_keys:
        must_contain(_cb87_vac, f'\t\t{_cb87_k} = bodyRef({_cb87_tb}, "v87 owner pick {_cb87_id} ', f"CODEBOT v87: Vehicles.{_cb87_k} wears {_cb87_tb} ({_cb87_id}), owner-only")
# per-body specifics from the owner's decisions
for _cb87_need, _cb87_label in (
    ('\tOmitParts = { "Part" },\n', "light helicopter drops its two transparent rotor discs (both named Part)"),
    ('KitRotor = { Parts = { "RotorHub", "RotorA", "RotorB" }, Hub = "RotorHub", At = Vector3.new(0, 8.7, -3.3), Span = 25.5 }', "light helicopter: the kit rotor on the body's mast, as wide as the body's own rotor"),
    ('RotorParts = { { Parts = { "RotorHub", "RotorA", "RotorB" }, Hub = "RotorHub", Axis = "Y", Rps = 5, Kit = true } }', "light helicopter: the kit rotor spins"),
    ('\tOmitParts = { "Group1", "Group2" },\n', "patrol boat drops its seated crew figures"),
    ("\tBodyScale = 0.027,\n\tBodyMinScale = 0.02,\n", "gunboat fits at 0.027 with its own scale floor (0.02)"),
    ("\tBodyColor = Color3.fromRGB(58, 62, 66),\n", "bomber recoloured dark military"),
    ("\tBodyMounts = { Bay = Vector3.new(0, 2, 0) },\n", "bomber bomb bay (AirWeaponService muzzle Bay) under the centre"),
    ("\tBodyClearTexture = true,\n", "frigate: the dead texture path is cleared, grey shows"),
    ('\tBodyKitNoCollide = { "Deck", "Superstructure", "Bridge" },\n', "carrier: the kit deck / island stop colliding under the fitted deck"),
    ('RotorParts = { { Parts = { "Meshes/newsubmarine_Propellor Blades", "Meshes/newsubmarine_Propellor Cap" }, Axis = "Z", Rps = 3 } }', "submarine propeller spins about the hull axis"),
    ("\tBodyWaterline = 11,\n", "submarine rides 11 studs deep (surface runner)"),
):
    must_contain(_cb87_vac, _cb87_need, f"CODEBOT v87: {_cb87_label}")
if _cb87_src.count("BodyMinScale = ") == 1:
    ok("CODEBOT v87: only the gunboat lowers the scale floor (every other body keeps 0.05)")
else:
    bad("CODEBOT v87: only the gunboat lowers the scale floor (every other body keeps 0.05)")
# rejected / kept on the kit
must_not_contain(_cb87_vac, "16675798409", "CODEBOT v87: the Lütjens model 16675798409 is never wired (no real-world copies)")
# v88 / v89: the v87 kit list now wears the wc6 / wc7 bodies (codebot_v88.py, codebot_v89.py)
# the gate: resolved ref (own or family) checked against the owner before any load; parked plot dress never uses them
must_contain(_cb87_vas, "function VisualAssetService.TryAttachVehicleVisual(hostModel: Model, vehicleId: string, kitFamily: string?, ownerUserId: number?): boolean\n\tlocal ref = resolveVehicleRef(vehicleId, kitFamily)\n\tif not ref then\n\t\treturn false\n\tend\n\t-- v87: an owner-only store body (Rollout = \"Body\") on anyone else's vehicle: the Part kit stays (no load at all)\n\tif not VisualAssetService.BodyAllowed(ref, ownerUserId) then\n\t\treturn false\n\tend", "CODEBOT v87: TryAttachVehicleVisual refuses an owner-only body before templateForRef (no load for other players)")
must_contain(_cb87_vas, "\tif typeof(ref) ~= \"table\" or ref.Rollout ~= \"Body\" then\n\t\treturn true\n\tend", "CODEBOT v87: BodyAllowed leaves every non-rollout ref alone (cars, jets unchanged)")
must_contain(_cb87_vas, "return ok and typeof(admin) == \"table\" and admin.IsPlaytestOwner(ownerUserId) == true", "CODEBOT v87: owner mode = AdminConfig.IsPlaytestOwner(ownerUserId)")
must_contain(_cb87_vas, "\t\t\t\t\tif ref and ref.Rollout == \"Body\" then\n\t\t\t\t\t\tref = nil", "CODEBOT v87: the Dock's parked PatrolBoat silhouette never takes the owner-only body")
must_contain(_cb87_veh, 'VisualAssetService.TryAttachVehicleVisual(model, def.Id or "", family, ownerUserId)', "CODEBOT v87: buildVehicleModel passes the vehicle's owner to the body gate")
# fit: per-ref scale floor, waterline sink, OmitParts on whole models, recolour
must_contain(_cb87_vas, "\tlocal s = AirBodyRig.ClampScale(ref, fitScale or primary.Size.Z / bodyLen)", "CODEBOT v87: fit scale clamped by AirBodyRig.ClampScale (BodyMinScale per ref, else 0.05)")
must_contain(_cb87_vas, "\tlocal s = AirBodyRig.ClampScale(ref, ref.BodyScale or 1)", "CODEBOT v87: placeKitOnBody uses the same clamp")
must_contain(_cb87_rig, "\tlocal s = AirBodyRig.ClampScale(ref, tonumber(ref.BodyScale) or 1)", "CODEBOT v87: AirBodyRig.Apply uses the same clamp")
must_contain(_cb87_rig, "local floor = if typeof(ref.BodyMinScale) == \"number\" then math.clamp(ref.BodyMinScale, 0.005, 0.05) else 0.05\n", "CODEBOT v87: ClampScale floor 0.05 unless BodyMinScale (never under 0.005); v88 cap in codebot_v88.py")
must_contain(_cb87_vas, "\tlift -= if fitScale and typeof(ref.BodyWaterline) == \"number\" then math.clamp(ref.BodyWaterline, 0, 30) else 0", "CODEBOT v87: a ship body sinks BodyWaterline studs")
must_contain(_cb87_vas, "\tif typeof(ref.ChildName) ~= \"string\" and typeof(ref.OmitParts) == \"table\" then", "CODEBOT v87: whole-model bodies drop OmitParts before the fit")
# AirBodyRig: the extended no-op condition, deck plates, kit rotor
must_contain(_cb87_rig, '\tif\n\t\tref.BodyMounts == nil\n\t\tand ref.RotorParts == nil\n\t\tand ref.ChaseCamera ~= true\n\t\tand ref.BodyHitBoxes == nil\n\t\tand ref.BodyGear == nil\n\t\tand ref.TailGuard ~= true\n\t\tand ref.KitRotor == nil\n\t\tand ref.BodyDeck == nil\n\t\tand ref.BodyKitNoCollide == nil\n\tthen\n\t\treturn 0', "CODEBOT v87: AirBodyRig.Apply stays a no-op for every ref without the air-looks / v87 fields")
must_contain(_cb87_rig, '\t\t\tp.Name = "WE_BodyDeck"\n\t\t\tp.Size = hb.Size * s\n\t\t\tp.CFrame = base * CFrame.new(hb.At * s)\n\t\t\tp.Transparency = 1\n\t\t\tp.CanCollide = true\n\t\t\tp.CanTouch = false\n\t\t\tp.CanQuery = false\n\t\t\tp.Massless = true', "CODEBOT v87: deck plates are invisible, collidable, massless, never touch / query")
must_contain(_cb87_veh, 'if d:IsA("BasePart") and d.CanCollide and d:GetAttribute("WE_BodyDeck") == nil then', "CODEBOT v87: the footprint (WE_HalfLength / spawn box) skips the deck plates")
must_contain(_cb87_rig, "\t\tif p ~= primary and not p:IsDescendantOf(clone) then\n\t\t\ttable.insert(parts, p)", "CODEBOT v87: KitRotor moves kit parts only (never the chassis or the body)")
# preserved: v81 owner unlocks, v85 FollowPace
must_contain("src/ReplicatedStorage/Shared/Configs/AdminConfig.luau", "IsPlaytestOwner = function(userId: any): boolean", "CODEBOT v87: v81 AdminConfig.IsPlaytestOwner kept")
must_contain("src/ServerScriptService/Server/Services/DataService.luau", "applyAdminPlaytestUnlocks", "CODEBOT v87: v81 DataService owner unlocks kept")
must_contain("src/ReplicatedStorage/Shared/Configs/ArmyConfig.luau", "FollowPace", "CODEBOT v87: v85 ArmyConfig.FollowPace kept")
