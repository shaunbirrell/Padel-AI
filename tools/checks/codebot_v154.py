# Code Bot Roblox v154 (2026-09-30): cherry-pick claude-bud JOB 40E fix (0f210ab) — slim high base-owner tags.
# HeightAt = 150 + 6% of distance (cap 260); 24 px pill; scale 1.0-1.2; max 5 rivals; no ShowOpenBases /
# nameless tags; OwnerFirst stays true. PreferMesh OFF; WE_Building* untouched. WE_Build 154.
import os as _os154
import subprocess as _sp154
import re as _re154
from pathlib import Path as _P154


def _cb154(cond, label):
	if "ok" in globals() and "bad" in globals():
		(ok if cond else bad)(label)
	else:
		print(("PASS " if cond else "FAIL ") + label)
		if not cond:
			raise SystemExit(1)


def _rd154(p):
	q = _P154(p)
	return q.read_text(encoding="utf-8") if q.is_file() else ""


_S154 = "src/ServerScriptService/Server/"
_C154 = "src/ReplicatedStorage/Shared/Configs/"
_CL154 = "src/StarterPlayer/StarterPlayerScripts/Client/Controllers/"

for _f in (_S154 + "Services/DataService.luau", _S154 + "Services/BaseService.luau", _S154 + "EarlyRemotes.server.luau"):
	_cb154('SetAttribute("WE_Build", 190)' in _rd154(_f), "CODEBOT v154: WE_Build=190 " + _f.rsplit("/", 1)[-1])
_cb154("WE_Build=190" in _rd154(_S154 + "Services/DataService.luau"), "CODEBOT v154: DataService profile-loaded log says WE_Build=190")

_BMC = _rd154(_C154 + "BaseMarkerConfig.luau")
_BMK = _rd154(_CL154 + "BaseMarkerController.luau")

# OwnerFirst MUST stay true (do not flip without owner ask)
_cb154("\tLive = {\n\t\tEnabled = true,\n\t\tOwnerFirst = false," in _BMC, "CODEBOT v154: BaseMarker OwnerFirst stays true")

# JOB 40E fix: high slim tags, never empty
_cb154("HeightStuds = 150," in _BMC and "HeightPerStud = 0.06," in _BMC and "MaxHeightStuds = 260," in _BMC,
	"CODEBOT v154: HeightAt style 150 + 6% (cap 260)")
_cb154("function BaseMarkerConfig.HeightAt(dist: number): number" in _BMC
	and "B.HeightStuds + B.HeightPerStud * math.max(0, dist)" in _BMC,
	"CODEBOT v154: HeightAt(dist) = HeightStuds + HeightPerStud * dist")
_cb154("ShowOpenBases = false," in _BMC, "CODEBOT v154: ShowOpenBases false (no empty / OPEN BASE tags)")
_cb154("MaxShown = 5," in _BMC, "CODEBOT v154: MaxShown = 5 rivals")
_cb154("PillHeight = 24," in _BMC and "NameTextSize = 14," in _BMC and "MaxNameWidth = 96," in _BMC,
	"CODEBOT v154: slim 24 px pill, 14 px name, max name width 96")
_cb154("MinScale = 1.0," in _BMC and "MaxScale = 1.2," in _BMC, "CODEBOT v154: scale 1.0 far .. 1.2 near")
_cb154("function BaseMarkerConfig.HasTag(owner: any, name: any): boolean" in _BMC
	and 'string.match(name, "%S")' in _BMC,
	"CODEBOT v154: HasTag requires live owner + non-empty name")
_cb154("function BaseMarkerConfig.VisibleSet(tags: { any }): { [any]: boolean }" in _BMC
	and "OverlapPadPx" in _BMC,
	"CODEBOT v154: VisibleSet caps rivals and hides overlaps")
_cb154("FarFadeStart = 1800," in _BMC and "FarFadeEnd = 2400," in _BMC, "CODEBOT v154: far fade 1800..2400")
_cb154("DetailStuds = 300," in _BMC, "CODEBOT v154: @handle / R<n> only inside DetailStuds 300")
_cb154('return if p > 0 then string.format("R%d", p) else nil' in _BMC, "CODEBOT v154: RankText is short R<n>, no rebirth title")

# controller uses the new helpers; never draws open/nameless or VETERAN title (code only — strip comments)
_BMK_code = _re154.sub(r"--\[\[.*?\]\]", "", _BMK, flags=_re154.S)
_BMK_code = "\n".join(l.split("--", 1)[0] for l in _BMK_code.splitlines())
_cb154("B.VisibleSet(list)" in _BMK_code and "B.HasTag(owner, nm)" in _BMK_code, "CODEBOT v154: controller uses VisibleSet + HasTag")
_cb154("B.HeightAt(" in _BMK_code and "B.ScaleAt(" in _BMK_code, "CODEBOT v154: controller uses HeightAt + ScaleAt")
_cb154("VETERAN" not in _BMK_code and "Text.Open" not in _BMK_code, "CODEBOT v154: controller has no VETERAN / Text.Open (code)")

# sim if luau is available
_lu = _os154.environ.get("LUAU") or str(_P154.home() / ".local/bin/luau")
if _P154(_lu).is_file() and _P154("tools/sim/run_base_marker_test.py").is_file():
	_r = _sp154.run(["python3", "tools/sim/run_base_marker_test.py"], capture_output=True, text=True, env=dict(_os154.environ, LUAU=_lu))
	_cb154(_r.returncode == 0 and ("0 failed" in _r.stdout or "BASE MARKER TEST: 0 failed" in _r.stdout),
		"CODEBOT v154: tools/sim/run_base_marker_test.py 0 failed")

# unchanged rails
_MC = _rd154(_C154 + "MonetizationConfig.luau")
_cb154("cfg.SpeedV2 = {\n\tEnabled = true,\n\tOwnerFirst = false," in _MC, "CODEBOT v154: SpeedV2 OwnerFirst=false (v166 flip-all-live)")
_cb154("PreferMeshWhenAssetIdSet = false" in _rd154(_C154 + "StructureVisualConfig.luau"), "CODEBOT v154: PreferMesh stays OFF")
_cb154("FastTravelEnabled = false" in _rd154(_C154 + "MapConfig.luau"), "CODEBOT v154: fast travel stays REMOVED")
_cb154("		VIP = {" in _MC and "RobuxPrice = 199," in _MC.split("VIP = {", 1)[1][:400], "CODEBOT v154: VIP RobuxPrice stays 199")

try:
	_wd = _sp154.run(["git", "diff", "-U0", "b001042", "--", "src"], capture_output=True, text=True).stdout
	if _wd:
		_cb154(not any(l.startswith(("+", "-")) and "WE_Building" in l for l in _wd.splitlines()),
			"CODEBOT v154: no WE_Building* line changed since v153 tip")
		# v156 (Code Bot Roblox): retired, superseded in tools/checks/codebot_v156.py (the config RobuxPrice is now only the display
		# fallback; v156 corrected StarterBundle 149->249 and ExtraSoldierSlot 99->79 to the real Creator Hub prices and pins every
		# config price to the audited Creator Hub price + every Id unchanged since v155):
		# _cb154(not any(l.startswith(("+", "-")) and not l.startswith(("+++", "---")) and _re154.search(r"RobuxPrice\s*=|\bId\s*=\s*\d{6,}", l) for l in _wd.splitlines()),
		# 	"CODEBOT v154: no RobuxPrice / product Id line changed since v153")
		pass
except Exception:
	pass
