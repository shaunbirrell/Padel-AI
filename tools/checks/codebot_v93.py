# Code Bot v93 (2026-09-29): ship Claude Bud Robux products (owner-only) + runway WE_LayoutSig rebuild.
# Merged origin/claude/desktop-bud (72c2b12 + d9c2b77). Feature pins live in claude_bud_*.py; this file pins WE_Build.
# v94 (Code Bot): retired WE_Build pins, superseded in tools/checks/codebot_v94.py
#must_contain("src/ServerScriptService/Server/Services/DataService.luau", 'SetAttribute("WE_Build", 93)', "CODEBOT v93: WE_Build=93 DataService")
#must_contain("src/ServerScriptService/Server/Services/BaseService.luau", 'SetAttribute("WE_Build", 93)', "CODEBOT v93: WE_Build=93 BaseService")
#must_contain("src/ServerScriptService/Server/EarlyRemotes.server.luau", 'SetAttribute("WE_Build", 93)', "CODEBOT v93: WE_Build=93 EarlyRemotes")
#must_contain("src/ServerScriptService/Server/Services/DataService.luau", "WE_Build=93", "CODEBOT v93: DataService profile-loaded log says WE_Build=93")
