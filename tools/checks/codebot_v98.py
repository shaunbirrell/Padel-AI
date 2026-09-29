# Code Bot v98 (2026-09-29): ship Claude Bud JOB 6–8 (Extra Garage Slot, first-5-min tutorial, QualityGovernor).
# Merged origin/claude/desktop-bud (e791323). Feature pins live in claude_bud_q2.py; this file pins WE_Build + key rollout needles.
must_contain("src/ServerScriptService/Server/Services/DataService.luau", 'SetAttribute("WE_Build", 98)', "CODEBOT v98: WE_Build=98 DataService")
must_contain("src/ServerScriptService/Server/Services/BaseService.luau", 'SetAttribute("WE_Build", 98)', "CODEBOT v98: WE_Build=98 BaseService")
must_contain("src/ServerScriptService/Server/EarlyRemotes.server.luau", 'SetAttribute("WE_Build", 98)', "CODEBOT v98: WE_Build=98 EarlyRemotes")
must_contain("src/ServerScriptService/Server/Services/DataService.luau", "WE_Build=98", "CODEBOT v98: DataService profile-loaded log says WE_Build=98")
# JOB 6–8 critical needles
must_contain("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau", "ExtraGarageSlot", "CODEBOT v98: ExtraGarageSlot pass present")
must_contain("src/ServerScriptService/Server/Services/VehicleService.luau", "VehicleService._HasExtraSlot", "CODEBOT v98: Extra Garage Slot helper")
must_contain("src/ReplicatedStorage/Shared/Configs/TutorialConfig.luau", "TutorialConfig.FirstMinutes", "CODEBOT v98: FirstMinutes tutorial config")
must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Modules/QualityGovernor.luau", "QualityGovernor", "CODEBOT v98: QualityGovernor module")
must_contain("src/ReplicatedStorage/Shared/Configs/QualityConfig.luau", 'Rollout = "owner"', "CODEBOT v98: QualityConfig owner-only")
