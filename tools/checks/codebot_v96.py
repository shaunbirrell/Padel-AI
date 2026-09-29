# Code Bot v96 (2026-09-29): ship Claude Bud army gate-hold fix + JOB 5a Robux-only vehicles (owner-only).
# Merged origin/claude/desktop-bud (a063154). Feature pins live in claude_bud_army.py / claude_bud_money.py; this file pins WE_Build + key rollout needles.
must_contain("src/ServerScriptService/Server/Services/DataService.luau", 'SetAttribute("WE_Build", 96)', "CODEBOT v96: WE_Build=96 DataService")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", 'SetAttribute("WE_Build", 96)', "CODEBOT v96: WE_Build=96 BaseService")
must_contain("src/ServerScriptService/Server/EarlyRemotes.server.luau", 'SetAttribute("WE_Build", 96)', "CODEBOT v96: WE_Build=96 EarlyRemotes")
must_contain("src/ServerScriptService/Server/Services/DataService.luau", "WE_Build=96", "CODEBOT v96: DataService profile-loaded log says WE_Build=96")
# Army gate-hold uniqueness + ATTACK spots (owner phone-test fix on Follow2.Tidy)
must_contain("src/ServerScriptService/Server/Modules/ArmyFollow.luau", "local holdOut = st._afTidy and st._afInBase and st._afPlot ~= nil and not inPlot(st._afPlot, pos, 0)", "CODEBOT v96: army holdOut walk (no path through gate)")
must_contain("src/ServerScriptService/Server/Services/SquadOrdersService.luau", "unit.Humanoid:MoveTo(af.AttackPoint(st, unit, playerRoot.Position, playerRoot.CFrame.LookVector, \"march\"))", "CODEBOT v96: ATTACK per-seat march spots")
# JOB 5a premium vehicle rollout keys
must_contain("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau", "PV_Skylance = true", "CODEBOT v96: PV_Skylance in RolloutKeys")
must_contain("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau", "PV_Stormwing = true", "CODEBOT v96: PV_Stormwing in RolloutKeys")
must_contain("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau", "PV_Leviathan = true", "CODEBOT v96: PV_Leviathan in RolloutKeys")
must_contain("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau", "PV_Tidebreaker = true", "CODEBOT v96: PV_Tidebreaker in RolloutKeys")
must_contain("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau", "PV_Warlord = true", "CODEBOT v96: PV_Warlord in RolloutKeys")
must_contain("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau", "PV_Razorfang = true", "CODEBOT v96: PV_Razorfang in RolloutKeys")
must_contain("src/ReplicatedStorage/Shared/Configs/VehicleConfig.luau", 'PremiumSkylance = P(V("PremiumSkylance"', "CODEBOT v96: PremiumSkylance vehicle def")
must_contain("src/ServerScriptService/Server/Services/VehicleService.luau", 'return false, "RobuxOnly" -- claude-bud JOB 5a', "CODEBOT v96: RobuxOnly cash refusal")
