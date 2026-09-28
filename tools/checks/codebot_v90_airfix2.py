# v90 (Code Bot): Claude's air fix-2 pins (handoff/wip/08), moved out of the frozen BuyPathStatic.py per LANES.md.
# air fix2 (fb4/air fix round 2, 2026-09-28): RotorParts.Under (store rotors that share one part name: the owner's pick
# 9120014090 names every rotor piece "MeshPart" and both hubs "Spinner"), a part is never jointed twice, the seated chase
# camera keeps a span under another module's max-zoom cap, and a rotor joint is not a "pin" in the NO-DRIVE diagnostic.
AIRF2_VS = "src/ServerScriptService/Server/Services/VehicleService.luau"
must_contain(AIRLOOKS_VAC, "\tUnder: string?,\n\tHub: string?,", "AIRLOOKS fix2: AirRotor declares Under (an ancestor Model name that scopes the part names)")
must_contain(AIRLOOKS_RIG, "\t\t\tif under ~= nil then\n\t\t\t\tscope = d:FindFirstAncestor(under)\n", "AIRLOOKS fix2: with Under, a rotor part belongs to its own ancestor Model (Rotor1 / Rotor2) [mutant: Under ignored -> the tail rotor orbits the main mast]")
must_contain(AIRLOOKS_RIG, "\t\t\tand d:FindFirstChild(AirBodyRig.RotorJointName) == nil\n", "AIRLOOKS fix2: a part already on a rotor joint is never jointed twice [mutant: removed -> two specs make 14 joints for 7 parts]")
must_contain(AIRLOOKS_RIG, "local hub = if typeof(spec.Hub) == \"string\" then g.scope:FindFirstChild(spec.Hub, true) else nil", "AIRLOOKS fix2: Hub is looked up inside the rotor's own scope (both hubs are named Spinner) [mutant: the whole body]")
must_not_contain(AIRLOOKS_RIG, "local function namedParts(", "AIRLOOKS fix2: the old name-only rotor lookup is gone")
must_contain(AIRLOOKS_CLI, '\t\tmaxConn = plr:GetPropertyChangedSignal("CameraMaxZoomDistance"):Connect(applyMin)\n', "AIRLOOKS fix2: while seated, a change of the max zoom (another module's cap) re-checks the min")
must_contain(AIRLOOKS_CLI, "local function restoreZoom()\n\tif maxConn then\n\t\tmaxConn:Disconnect()\n\t\tmaxConn = nil\n\tend\n", "AIRLOOKS fix2: leaving the seat (or dying, respawning) drops the max-zoom watch before the player's own min comes back")
must_contain(AIRLOOKS_CLI, "\tlocal span = ok and VisualAssetConfig and VisualAssetConfig.AirBody and VisualAssetConfig.AirBody.ChaseCameraSpan\n", "AIRLOOKS fix2: the span is config-first (VisualAssetConfig.AirBody.ChaseCameraSpan)")
must_contain(AIRF2_VS, '\t\tor n == "WE_RotorJoint" -- air fix2: a store body\'s spinning rotor (AirBodyRig), not a pin\n', "AIRLOOKS fix2: a rotor joint is not counted as a pin in the NO-DRIVE diagnostic line")

