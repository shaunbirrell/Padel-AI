# Code Bot v97 (2026-09-29): ship Claude Bud JOB 5b–5e (Bigger Army, VIP lounge/tag, army refill, plaza airstrike, purchase prompts, retention FREE rows).
# Merged origin/claude/desktop-bud (7d5837c). Feature pins live in claude_bud_money.py / claude_bud_monetization.py; this file pins WE_Build + key rollout needles.
# v98 (Code Bot): retired WE_Build + JOB 5b–5e pins, superseded in tools/checks/codebot_v98.py
#must_contain("src/ServerScriptService/Server/Services/DataService.luau", 'SetAttribute("WE_Build", 97)', "CODEBOT v97: WE_Build=97 DataService")
#must_contain("src/ServerScriptService/Server/Services/BaseService.luau", 'SetAttribute("WE_Build", 97)', "CODEBOT v97: WE_Build=97 BaseService")
#must_contain("src/ServerScriptService/Server/EarlyRemotes.server.luau", 'SetAttribute("WE_Build", 97)', "CODEBOT v97: WE_Build=97 EarlyRemotes")
#must_contain("src/ServerScriptService/Server/Services/DataService.luau", "WE_Build=97", "CODEBOT v97: DataService profile-loaded log says WE_Build=97")
# JOB 5b–5e critical needles
#must_contain("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau", "BiggerArmy", "CODEBOT v97: BiggerArmy pass present")
#must_contain("src/ServerScriptService/Server/Modules/VIPLounge.luau", "VIPLounge", "CODEBOT v97: VIPLounge module")
#must_contain("src/ServerScriptService/Server/Modules/PlazaAirstrike.luau", "PlazaAirstrike", "CODEBOT v97: PlazaAirstrike module")
#must_contain("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau", "SoldierRefill", "CODEBOT v97: SoldierRefill product")
#must_contain("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ShopController.luau", "FREE", "CODEBOT v97: retention FREE rows needle")
