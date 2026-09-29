# Code Bot v105 (2026-09-29): BUDSQUAD redeem code, live for all players.
# Runs inside tools/BuyPathStatic.py (same globals). Helpers start with _cb105_.
import re as _cb105_re

_cb105_S = "src/ServerScriptService/Server/"
_cb105_CFG = _cb105_S + "Configs/CodesConfig.luau"
_cb105_SVC = _cb105_S + "Services/CodesService.luau"

# ── build ──
# v106 (Code Bot): retired build pins, superseded in tools/checks/codebot_v106.py:
#for _f in (_cb105_S + "Services/DataService.luau", _cb105_S + "Services/BaseService.luau", _cb105_S + "EarlyRemotes.server.luau"):
#    must_contain(_f, 'SetAttribute("WE_Build", 105)', "CODEBOT v105: WE_Build=105 " + _f.rsplit("/", 1)[-1])
#must_contain(_cb105_S + "Services/DataService.luau", "WE_Build=105", "CODEBOT v105: DataService profile-loaded log says WE_Build=105")

# ── BUDSQUAD: active, no expiry, Discord display name, exact cash reward ──
_cb105_C = read(_cb105_CFG) or ""
must_contain(_cb105_CFG, '\t\tBUDSQUAD = {\n\t\t\tActive = true,\n\t\t\tExpires = nil,\n\t\t\tDisplayName = "Bud Studios Discord",\n\t\t\tRewards = { Cash = 25000 },\n\t\t},',
             "CODEBOT v105: BUDSQUAD active, no expiry, $25,000")
must_contain(_cb105_SVC, "profile.RedeemedCodes[code]", "CODEBOT v105: redemption is tracked per player in RedeemedCodes")
must_contain(_cb105_SVC, "profile.RedeemedCodes[code] = os.time()", "CODEBOT v105: code is marked used before reward grant")

# ── untouched ──
must_contain(_cb105_S + "Modules/HollowBuildingBuilder.luau", 'local MODEL_NAME = "WE_Building"', "CODEBOT v105: WE_Building untouched")
must_not_contain("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau", "PreferMesh = true", "CODEBOT v105: PreferMesh stays OFF")
