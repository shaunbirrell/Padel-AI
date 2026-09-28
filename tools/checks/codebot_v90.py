# Code Bot v90 (2026-09-28): Claude's WIP lanes shipped (01 army fix owner-only, 05 harbour, 06 faces, 08 air fix-2) and
# the owner's answers to Claude's 6 questions (jets on 14589101870 with one colour per key, bigger runway + hangar, the
# Bridge Layer crosses water owner-only). Runs inside tools/BuyPathStatic.py (its globals). Helpers start with _cb90_.
_cb90_vac = "src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau"
_cb90_vas = "src/ServerScriptService/Server/Services/VisualAssetService.luau"
_cb90_army = "src/ReplicatedStorage/Shared/Configs/ArmyConfig.luau"
_cb90_sos = "src/ServerScriptService/Server/Services/SquadOrdersService.luau"
_cb90_gds = "src/ServerScriptService/Server/Services/GateDefenseService.luau"
_cb90_vc = "src/ReplicatedStorage/Shared/Configs/VehicleConfig.luau"
_cb90_wg = "src/ServerScriptService/Server/Modules/VehicleWaterGuard.luau"
_cb90_vdc = "src/StarterPlayer/StarterPlayerScripts/Client/Modules/VehicleDriveClient.luau"
_cb90_blc = "src/ReplicatedStorage/Shared/Configs/BaseLayoutConfig.luau"
_cb90_svc = "src/ReplicatedStorage/Shared/Configs/StructureVisualConfig.luau"
_cb90_af = "src/ServerScriptService/Server/Modules/Installations/Airfield.luau"

# 01 army fix: owner-only (Rollout.Fix), v85 FollowPace stays for everyone else
must_contain(_cb90_army, '\t\tFix = "owner",', "CODEBOT v90: ArmyConfig.Rollout.Fix is owner-only")
must_contain(_cb90_sos, 'SquadOrdersService._FixLive = st ~= nil and ArmyConfig.LiveFor("Fix", player.UserId)', "CODEBOT v90: the army fix is live per owner (LiveFor Fix) in the think pass")
if (read(_cb90_sos) or "").count("SquadOrdersService._FixLive = false") >= 3:
    ok("CODEBOT v90: _FixLive is reset after each owner and after the loop (never leaks to the next player)")
else:
    bad("CODEBOT v90: _FixLive must be reset after each owner and after the loop")
# v91 (Code Bot): retired, superseded in tools/checks/codebot_v91.py: #must_contain(_cb90_sos, 'return ArmyConfig.LiveFor("Fix", uid) and typeof(rc) == "table"', "CODEBOT v90: reformRootless obeys Rollout.Fix")
must_contain(_cb90_gds, 'and ArmyConfig.LiveFor("Fix", def.OwnerUserId)', "CODEBOT v90: the gate-open part of the army fix obeys Rollout.Fix")

# answer 1-3: every jet key on the owner's jet 14589101870, pilot inside, its own colour on the grey panels
_cb90_src = read(_cb90_vac) or ""
if _cb90_src.count("ModelAssetId = 14589101870,") == 8 and "PendingAssetId = 14589101870" not in _cb90_src:
    ok("CODEBOT v90: the jet 14589101870 is on all 8 jet refs (FighterJet, InterceptorJet, TrainerJet, LightFighter, StrikeJet, CASJet, StealthStrike, StealthStrikeJet)")
else:
    bad(f"CODEBOT v90: the jet must be on exactly 8 refs — found {_cb90_src.count('ModelAssetId = 14589101870,')}")
must_contain(_cb90_vac, 'local JET_PAINT_PARTS = { "Cube", "Cube.001", "Cube.003", "Cylinder.003" }', "CODEBOT v90: only the jet's grey panels take the colour (black trim + glass canopy keep the approved look)")
_cb90_cols = {}
for _cb90_k, _cb90_owner in (("FighterJet", False), ("InterceptorJet", False), ("TrainerJet", False), ("LightFighter", False),
                             ("StrikeJet", True), ("CASJet", True), ("StealthStrike", True), ("StealthStrikeJet", True)):
    _i = _cb90_src.find(f"\t\t{_cb90_k} = {{\n\t\t\tModelAssetId = 14589101870,\n")
    _j = _cb90_src.find("\t\t} :: AssetRef,", _i)
    _blk = _cb90_src[_i:_j] if _i >= 0 and _j > _i else ""
    _need = ["\t\t\tDriverSeat = Vector3.new(0.04, 0.72, 2.35)", "\t\t\tBodyScale = 2.5,\n", "\t\t\tBodyHitBoxes = JET_HIT_BOXES,\n",
             "\t\t\tBodyGear = JET_GEAR,\n", "\t\t\tBodyColorParts = JET_PAINT_PARTS,\n", "\t\t\tBodyColor = Color3.fromRGB("]
    if _cb90_owner:
        _need.append('\t\t\tRollout = "Body",\n')
    _miss = [n for n in _need if n not in _blk]
    if _blk and not _miss and (_cb90_owner or 'Rollout = "Body"' not in _blk):
        ok(f"CODEBOT v90: Vehicles.{_cb90_k} wears the jet with the pilot inside and its own BodyColor" + (" (owner-only)" if _cb90_owner else ""))
        _c = _blk.split("BodyColor = Color3.fromRGB(")[1].split(")")[0]
        _cb90_cols.setdefault(_c, []).append(_cb90_k)
    else:
        bad(f"CODEBOT v90: Vehicles.{_cb90_k} jet ref — missing {_miss or 'the block'}")
_cb90_dups = [v for v in _cb90_cols.values() if len(v) > 1 and set(v) != {"StealthStrike", "StealthStrikeJet"}]
if len(_cb90_cols) == 7 and not _cb90_dups:
    ok("CODEBOT v90: 7 distinct jet colours (StealthStrikeJet is an alias ref of StealthStrike)")
else:
    bad(f"CODEBOT v90: every jet needs its own colour — {_cb90_cols}")
must_contain(_cb90_vas, 'if d:IsA("BasePart") and (only == nil or only[d.Name] == true) then', "CODEBOT v90: BodyColorParts limits BodyColor to the named parts")
for _cb90_k in ("StrikeJet", "CASJet", "StealthStrike", "StealthStrikeJet"):
    must_not_contain(_cb90_vac, f"\t\t{_cb90_k} = bodyRef(", f"CODEBOT v90: {_cb90_k} no longer wears the v88 body")

# answer 4: bigger runway + hangar, clear of the plot edge and the helipad apron
must_contain(_cb90_blc, '{ Name = "Runway", X = -63, Z = -80, SizeX = 190, SizeZ = 29 }', "CODEBOT v90: runway 190 x 29 (was 170 x 24)")
_rx0, _rx1 = -63 - 95, -63 + 95
if _rx0 > -160 and _rx1 < 34:
    ok("CODEBOT v90: the runway stays inside the plot (X > -160) and short of the HeliApron (X 34)")
else:
    bad("CODEBOT v90: the runway overlaps the plot edge or the HeliApron")
must_contain(_cb90_blc, "\t\tAirfield = { Site = { X = -100, Z = -125 }, Yaw = 0,", "CODEBOT v90: the hangar site moves back 3 studs for the bigger hangar")
must_contain(_cb90_svc, '\t\tAirfield = { Enabled = true, Module = "Airfield", Width = 68, Depth = 40 },', "CODEBOT v90: hangar foundation 68 x 40 (was 58 x 34)")
must_contain(_cb90_af, "\tlocal S = math.clamp((tonumber(ictx.W) or 58) / 58, 1, 1.3)\n", "CODEBOT v90: the hangar shell scales with the foundation width")
must_contain(_cb90_af, "\t\tlocal tx, tz, th = halfW - 5.5, 9, 18\n", "CODEBOT v90: the control tower stays at the foundation edge, clear of the wider hangar")

# answer 5: the Bridge Layer wades across water, owner-only, decided on the server
must_contain(_cb90_vc, '\t\t\tAmphibiousRollout = { BridgeLayer = "owner" } :: { [string]: string },', "CODEBOT v90: the Bridge Layer is a rollout wader (owner-only)")
must_contain(_cb90_wg, 'if gate == "owner" and typeof(owner) == "Instance" and owner:IsA("Player") and AdminConfig.IsPlaytestOwner(owner.UserId) == true then', "CODEBOT v90: the server decides the wader by the vehicle's owner")
must_contain(_cb90_vdc, 'or d.WaterServer == "Wade", -- v90', "CODEBOT v90: the driver's client follows the server's Wade state")
must_contain(_cb90_vc, "\t\t\tAmphibious = { AmphibiousAPC = true } :: { [string]: boolean },", "CODEBOT v90: the Amphibious APC stays a wader for everyone")
must_contain(_cb90_sos, "\tif SquadOrdersService._FixLive then\n\t\treturn false -- v90: the army fix (Rollout.Fix) drives this owner's pace", "CODEBOT v90: for a Fix-live owner the fix replaces v85 FollowPace (everyone else keeps v85)")
