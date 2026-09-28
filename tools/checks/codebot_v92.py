# Code Bot v92 (2026-09-28): Claude's plaza-capture lane (02) shipped from handoff/wip/02-capture_on_e506c9c.patch
# onto phase-7-polish. PersistClaims off + ReleaseOnLeave + StandingBar as Claude wrote them. Helpers start with _cb92_.
_cb92_ec = "src/ReplicatedStorage/Shared/Configs/EconomyConfig.luau"
_cb92_tc = "src/ReplicatedStorage/Shared/Configs/TerritoryConfig.luau"
_cb92_ts = "src/ServerScriptService/Server/Services/TerritoryService/init.luau"
_cb92_cl = "src/StarterPlayer/StarterPlayerScripts/Client/Controllers/TerritoryController.luau"
_cb92_ty = "src/ReplicatedStorage/Shared/Types.luau"

must_contain("src/ServerScriptService/Server/Services/DataService.luau", 'SetAttribute("WE_Build", 92)', "CODEBOT v92: WE_Build=92 DataService")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", 'SetAttribute("WE_Build", 92)', "CODEBOT v92: WE_Build=92 BaseService")
must_contain("src/ServerScriptService/Server/EarlyRemotes.server.luau", 'SetAttribute("WE_Build", 92)', "CODEBOT v92: WE_Build=92 EarlyRemotes")
must_contain("src/ServerScriptService/Server/Services/DataService.luau", "WE_Build=92", "CODEBOT v92: DataService profile-loaded log says WE_Build=92")

must_contain(_cb92_ec, "\t\tPersistClaims = false,", "CODEBOT v92: PersistClaims off (no outpost comes back on rejoin)")
must_contain(_cb92_tc, "\tReleaseOnLeave = true,\n", "CODEBOT v92: ReleaseOnLeave on (leaver's zones go Neutral)")
must_contain(_cb92_tc, "\tStandingBar = {\n\t\tHeld = true,\n\t\tContested = true,\n", "CODEBOT v92: StandingBar Held+Contested on")
must_contain(_cb92_tc, "\t\tHeldSeconds = 5,\n", "CODEBOT v92: YOURS cue is 5 seconds")
must_contain(_cb92_tc, "\t\tHeldAfterCapture = false,\n", "CODEBOT v92: no YOURS cue on top of the capture toast")
must_contain(_cb92_tc, "\t\tOnDisc = true,\n", "CODEBOT v92: YOURS follows the painted disc")

must_contain(_cb92_ts, "local function standingZoneOf(player: Player): (TerritoryRuntime?, boolean, boolean)", "CODEBOT v92: TerritoryService standingZoneOf")
must_contain(_cb92_ts, "local function countedIn(rt: TerritoryRuntime, player: Player): boolean", "CODEBOT v92: TerritoryService countedIn (capturer bar only when inside)")
must_contain(_cb92_ts, "local persist = persistClaimsOn() or (TerritoryConfig :: any).ReleaseOnLeave == true", "CODEBOT v92: leave release follows ReleaseOnLeave or PersistClaims")
must_contain(_cb92_ts, "\t\tsyncEmpireTax(player)\n", "CODEBOT v92: join recounts Empire Tax after ownership sync")
must_contain(_cb92_cl, "local function heldAfterCapture(): boolean", "CODEBOT v92: client HeldAfterCapture gate")
must_contain(_cb92_cl, "local PULSE_STEP = 0.1", "CODEBOT v92: contested pulse capped at 10 Hz")
must_contain(_cb92_ty, "\t\tHeld: boolean?, -- fb4 capture lane", "CODEBOT v92: LocalCapture.Held in Types")
must_contain("BALANCE.md", "(`TerritoryConfig.ReleaseOnLeave = true`) and nothing comes back when you rejoin (`PersistClaims = false`)",
             "CODEBOT v92: BALANCE Empire Tax says outposts do not persist")
must_not_contain("BALANCE.md", "Persists across servers (`PersistClaims = true`)", "CODEBOT v92: BALANCE no longer says claims persist")
