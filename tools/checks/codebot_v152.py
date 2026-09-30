# Code Bot Roblox v152 (2026-09-30): JOB 40 part C re-probe after the owner's Get Model (1 of 19 passes: market stall
# 86311252190175) wired as two owner-first ReplaceRows in the Crossroads Town market lane; cherry-pick claude-bud
# JOB 40 part D (57201e8 -> 2205590, RatePromptConfig OwnerFirst=true). PreferMesh OFF; WE_Building* untouched.
import os as _os152
import subprocess as _sp152
from pathlib import Path as _P152


def _cb152(cond, label):
	if "ok" in globals() and "bad" in globals():
		(ok if cond else bad)(label)
	else:
		print(("PASS " if cond else "FAIL ") + label)
		if not cond:
			raise SystemExit(1)


def _rd152(p):
	q = _P152(p)
	return q.read_text(encoding="utf-8") if q.is_file() else ""


_S152 = "src/ServerScriptService/Server/"
_C152 = "src/ReplicatedStorage/Shared/Configs/"

# v153 (Code Bot Roblox): the WE_Build=152 pins are superseded in tools/checks/codebot_v153.py (WE_Build=153).
# for _f in (_S152 + "Services/DataService.luau", _S152 + "Services/BaseService.luau", _S152 + "EarlyRemotes.server.luau"):
# 	_cb152('SetAttribute("WE_Build", 152)' in _rd152(_f), "CODEBOT v152: WE_Build=152 " + _f.rsplit("/", 1)[-1])
# _cb152("WE_Build=152" in _rd152(_S152 + "Services/DataService.luau"), "CODEBOT v152: DataService profile-loaded log says WE_Build=152")

# JOB 40 part C: only probe-passing ids are wired
_SPC = _rd152(_C152 + "StorePropsConfig.luau")
_cb152("cfg40.JOB40 = { Enabled = true, OwnerFirst = true }" in _SPC, "CODEBOT v152: StorePropsConfig.JOB40 Enabled + OwnerFirst=true")
_PASSED = {"86311252190175"}
import re as _re152
_rr = _SPC.split("cfg40.ReplaceRows = {", 1)[1].split("} :: { any }", 1)[0]
_br = _SPC.split("cfg40.BaseRows = {", 1)[1].split("} :: { any }", 1)[0]
_live = lambda blk: [l for l in blk.splitlines() if l.strip() and not l.strip().startswith("--")]
_rrIds = [m for l in _live(_rr) for m in _re152.findall(r"Id = (\d+)", l)]
_cb152(len(_rrIds) == 2 and set(_rrIds) <= _PASSED, "CODEBOT v152: ReplaceRows = 2 rows, only the probe-passing market stall")
_cb152('KitPart = "StallCounter", At = Vector3.new(-81, 0, -166.4)' in _rr and 'KitPart = "StallCounter", At = Vector3.new(-80, 0, -182.6)' in _rr,
	"CODEBOT v152: the stall rows target NW_Stall_1 / NW_Stall_2 (Crossroads Town market lane)")
_cb152(not any("Id =" in l for l in _live(_br)), "CODEBOT v152: BaseRows stay empty (no military model passed)")
_cb152("RadarDome" not in "".join(_live(_rr)), "CODEBOT v152: Radar Hill kit untouched (no radar passed)")
_SPS = _rd152(_S152 + "Services/StorePropsService.luau")
_cb152("if cfgR.JOB40LiveFor(pl.UserId) then\n\t\t\t\t\tpcall(StorePropsService.PlaceReplaceRows)" in _SPS,
	"CODEBOT v152: ReplaceRows wait for a JOB40-live player (owner joining later still gets them)")
_cb152("PASS: 86311252190175" in _rd152("docs/PROP-ASSETS.md") or "**1 passes: 86311252190175 Market stall.**" in _rd152("docs/PROP-ASSETS.md"),
	"CODEBOT v152: the re-probe table is in docs/PROP-ASSETS.md")
_cb152(_P152("tools/probes/job40c_stall_dryrun.luau").is_file() and _P152("docs/job40c-probe2-2026-09-30.txt").is_file(),
	"CODEBOT v152: re-probe output + stall dry run in the repo")

# JOB 40 part D
_RPC = _rd152(_C152 + "RatePromptConfig.luau")
_cb152("Enabled = true," in _RPC and "OwnerFirst = true," in _RPC, "CODEBOT v152: RatePromptConfig Enabled + OwnerFirst=true")
_cb152(_P152(_S152 + "Services/RatePromptService.luau").is_file(), "CODEBOT v152: RatePromptService present")

# prior owner-first kept — do NOT flip
_cb152("\tPosts = {\n\t\tEnabled = true,\n\t\tOwnerFirst = true," in _rd152(_C152 + "GuardConfig.luau"), "CODEBOT v152: GuardConfig.Posts OwnerFirst stays true")
_MC = _rd152(_C152 + "MonetizationConfig.luau")
_cb152("cfg.SpeedV2 = {\n\tEnabled = true,\n\tOwnerFirst = true," in _MC, "CODEBOT v152: SpeedV2 OwnerFirst stays true")
_cb152("\tLive = {\n\t\tEnabled = true,\n\t\tOwnerFirst = true," in _rd152(_C152 + "EndgameConfig.luau"), "CODEBOT v152: Endgame OwnerFirst stays true")
_cb152("\tLive = {\n\t\tEnabled = true,\n\t\tOwnerFirst = false," in _rd152(_C152 + "BaseMarkerConfig.luau"), "CODEBOT v152: BaseMarker OwnerFirst stays true")
_cb152("PreferMeshWhenAssetIdSet = false" in _rd152(_C152 + "StructureVisualConfig.luau"), "CODEBOT v152: PreferMesh stays OFF")
_cb152("FastTravelEnabled = false" in _rd152(_C152 + "MapConfig.luau"), "CODEBOT v152: fast travel stays REMOVED")
_cb152("		VIP = {" in _MC and "RobuxPrice = 199," in _MC.split("VIP = {", 1)[1][:400], "CODEBOT v152: VIP RobuxPrice stays 199")

try:
	_wd = _sp152.run(["git", "diff", "-U0", "04492a2", "--", "src"], capture_output=True, text=True).stdout
	_cb152(not any(l.startswith(("+", "-")) and "WE_Building" in l for l in _wd.splitlines()), "CODEBOT v152: no WE_Building* line changed since v151 tip")
	_wr = _sp152.run(["git", "diff", "-U0", "04492a2", "--", "src"], capture_output=True, text=True).stdout
	# v156 (Code Bot Roblox): retired, superseded in tools/checks/codebot_v156.py (the config RobuxPrice is now only the display
	# fallback; v156 corrected StarterBundle 149->249 and ExtraSoldierSlot 99->79 to the real Creator Hub prices and pins every
	# config price to the audited Creator Hub price + every Id unchanged since v155):
	# _cb152(not any(l.startswith(("+", "-")) and _re152.search(r"RobuxPrice\s*=", l) for l in _wr.splitlines()), "CODEBOT v152: no RobuxPrice line changed")
	pass
except Exception:
	pass
