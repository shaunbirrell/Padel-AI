# Code Bot Roblox v151 (2026-09-30): cherry-pick claude-bud JOB 40 part C (a46a46a -> phase-7) store-props plumbing
# (ReplaceRows landmark swap + BaseRows live-owner dressing, owner-first JOB40). The Open Cloud load probe
# (tools/probes/job40c_codebot_probe.luau) passed 0 of 19 candidates, so ReplaceRows / BaseRows stay EMPTY (no world
# change). JOB40 OwnerFirst=true; PreferMesh OFF; WE_Building* untouched; WE_Build 151.
import os as _os151
import subprocess as _sp151
from pathlib import Path as _P151


def _cb151(cond, label):
	if "ok" in globals() and "bad" in globals():
		(ok if cond else bad)(label)
	else:
		print(("PASS " if cond else "FAIL ") + label)
		if not cond:
			raise SystemExit(1)


def _rd151(p):
	q = _P151(p)
	return q.read_text(encoding="utf-8") if q.is_file() else ""


_S151 = "src/ServerScriptService/Server/"
_C151 = "src/ReplicatedStorage/Shared/Configs/"

for _f in (_S151 + "Services/DataService.luau", _S151 + "Services/BaseService.luau", _S151 + "EarlyRemotes.server.luau"):
	_cb151('SetAttribute("WE_Build", 151)' in _rd151(_f), "CODEBOT v151: WE_Build=151 " + _f.rsplit("/", 1)[-1])
_cb151("WE_Build=151" in _rd151(_S151 + "Services/DataService.luau"), "CODEBOT v151: DataService profile-loaded log says WE_Build=151")

# JOB 40 part C
_SPC = _rd151(_C151 + "StorePropsConfig.luau")
_cb151("cfg40.JOB40 = { Enabled = true, OwnerFirst = true }" in _SPC, "CODEBOT v151: StorePropsConfig.JOB40 Enabled + OwnerFirst=true")
_rr = _SPC.split("cfg40.ReplaceRows = {", 1)[1].split("} :: { any }", 1)[0] if "cfg40.ReplaceRows = {" in _SPC else "x"
_br = _SPC.split("cfg40.BaseRows = {", 1)[1].split("} :: { any }", 1)[0] if "cfg40.BaseRows = {" in _SPC else "x"
_cb151("Id =" not in "".join(l for l in _rr.splitlines() if not l.strip().startswith("--")), "CODEBOT v151: ReplaceRows empty (probe: 0 of 19 load + pass)")
_cb151("Id =" not in "".join(l for l in _br.splitlines() if not l.strip().startswith("--")), "CODEBOT v151: BaseRows empty (probe: 0 of 19 load + pass)")
_cb151("function StorePropsService.PlaceReplaceRows" in _rd151(_S151 + "Services/StorePropsService.luau"), "CODEBOT v151: StorePropsService.PlaceReplaceRows present")
_cb151(_P151("tools/probes/job40c_codebot_probe.luau").is_file() and "0 of 19 pass" in _rd151("docs/PROP-ASSETS.md"),
	"CODEBOT v151: the Code Bot load probe + its result are in the repo")
_cb151("OwnerFirst = false, -- codebot_v136 launch" in _SPC, "CODEBOT v151: STORE-PROPS world rows stay launched (v136)")

# prior owner-first kept — do NOT flip
_GC = _rd151(_C151 + "GuardConfig.luau")
_cb151("\tPosts = {\n\t\tEnabled = true,\n\t\tOwnerFirst = true," in _GC, "CODEBOT v151: GuardConfig.Posts OwnerFirst stays true")
_MC = _rd151(_C151 + "MonetizationConfig.luau")
_cb151("cfg.SpeedV2 = {\n\tEnabled = true,\n\tOwnerFirst = true," in _MC, "CODEBOT v151: SpeedV2 OwnerFirst stays true")
_cb151("\tLive = {\n\t\tEnabled = true,\n\t\tOwnerFirst = true," in _rd151(_C151 + "EndgameConfig.luau"), "CODEBOT v151: Endgame OwnerFirst stays true")
_cb151("\tLive = {\n\t\tEnabled = true,\n\t\tOwnerFirst = true," in _rd151(_C151 + "BaseMarkerConfig.luau"), "CODEBOT v151: BaseMarker OwnerFirst stays true")
_cb151("PreferMeshWhenAssetIdSet = false" in _rd151(_C151 + "StructureVisualConfig.luau"), "CODEBOT v151: PreferMesh stays OFF")
_cb151("FastTravelEnabled = false" in _rd151(_C151 + "MapConfig.luau"), "CODEBOT v151: fast travel stays REMOVED")
_cb151("		VIP = {" in _MC and "RobuxPrice = 199," in _MC.split("VIP = {", 1)[1][:400], "CODEBOT v151: VIP RobuxPrice stays 199")

try:
	_wb = _sp151.run(["git", "diff", "--name-only", "79115d9"], capture_output=True, text=True).stdout
	_cb151(not any("WE_Building" in l for l in _wb.splitlines()), "CODEBOT v151: no WE_Building* file touched since v150 tip")
	_wd = _sp151.run(["git", "diff", "-U0", "79115d9", "--", "src"], capture_output=True, text=True).stdout
	_cb151(not any(l.startswith(("+", "-")) and "WE_Building" in l for l in _wd.splitlines()), "CODEBOT v151: no WE_Building* line changed since v150 tip")
except Exception:
	pass
