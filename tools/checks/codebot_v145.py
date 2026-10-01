# Code Bot Roblox v145 (2026-09-30): JOB 38 army orders fix (owner phone test: "Sending my army to a location they
# don't go and attack"). Routes start at the ARMY block (not the owner inside his walled base: NoPath through the
# closed gate -> "No route" + HOLD); the lead is placed Standoff along the route; the gap is measured past the
# block's standoff; RETURN goes to his gate while he is inside his base; a failed middle leg tries the rest whole.
# Live state kept: ArmyOrders OwnerFirst=true; ShopOverhaul + CheckpointGuard OwnerFirst=false; VIP 199; pass Ids;
# RPG hold 3972151362; WeaponsLive; FastTravel removed; PreferMesh OFF; WE_Building* untouched; WE_Build 145.
import os as _os145
import re as _re145
import subprocess as _sp145
from pathlib import Path as _P145


def _cb145(cond, label):
	if "ok" in globals() and "bad" in globals():
		(ok if cond else bad)(label)
	else:
		print(("PASS " if cond else "FAIL ") + label)
		if not cond:
			raise SystemExit(1)


def _rd145(p):
	q = _P145(p)
	return q.read_text(encoding="utf-8") if q.is_file() else ""


_S145 = "src/ServerScriptService/Server/"
_C145 = "src/ReplicatedStorage/Shared/Configs/"
# v146 (Code Bot Roblox): the WE_Build=145 pins are superseded in tools/checks/codebot_v146.py (WE_Build=146).

# the fix
_AP = _rd145(_S145 + "Modules/ArmyPlan.luau")
_AR = _rd145(_S145 + "Modules/ArmyRoute.luau")
_ACt = _rd145(_S145 + "Modules/ArmyController.luau")
_cb145("local start = if c then c else plan.Lead" in _AP and "ArmyRoute.PointAlong(start, route, standoff)" in _AP,
	"CODEBOT v145: an army route starts at the block (not the owner) and the lead is placed Standoff along it")
_cb145("setDest(plan, plan.Dest :: Vector3, Vector3.new(centre.X, plan.Lead.Y, centre.Z))" not in _AP,
	"CODEBOT v145: the stuck re-plan never puts the lead back onto the block (it walked backwards)")
_cb145("centre = centre + toLead.Unit * math.min(standoffOf(plan.Squad), toLead.Magnitude)" in _AP,
	"CODEBOT v145: the lead waits only while the block is LeadMaxGap past its own standoff")
_cb145("function ArmyController.Standoff(st: any): number" in _ACt, "CODEBOT v145: ArmyController.Standoff (FirstRowStuds + half depth, radius + bubble)")
_cb145("local function returnDest(plan: Plan): Vector3" in _AP and "plan.ReturnGate = true" in _AP,
	"CODEBOT v145: RETURN goes to his gate spot while he is inside his base / cannot be reached")
_cb145("if got == nil and li < #legs then" in _AR and "got = compute(start, to)" in _AR,
	"CODEBOT v145: a failed middle leg tries the rest of the way as one path")
_code = "\n".join(l.split("--", 1)[0] for l in _re145.sub(r"--\[\[.*?\]\]", "", _AP + "\n" + _AR, flags=_re145.S).splitlines())
_cb145(not any(w in _code for w in ("PivotTo", "TeleportService", "Root.CFrame =", ":MoveTo(")),
	"CODEBOT v145: no teleport / PivotTo / forced MoveTo in ArmyPlan / ArmyRoute")
_cb145("MarchSpeed = 14," in _rd145(_C145 + "ArmyOrdersConfig.luau") and "LeadMaxGap = 18," in _rd145(_C145 + "ArmyOrdersConfig.luau"),
	"CODEBOT v145: march speed / gap unchanged (no faster catch-up)")
_luau = _os145.environ.get("LUAU") or str(_P145.home() / ".local/bin/luau")
if _P145(_luau).is_file():
	_r = _sp145.run(["python3", "tools/sim/run_army_march_test.py"], capture_output=True, text=True, env=dict(_os145.environ, LUAU=_luau))
	_cb145(_r.returncode == 0 and "ARMY MARCH TEST: 0 failed" in _r.stdout,
		"CODEBOT v145: run_army_march_test (real ArmyPlan + ArmyController + Formation + SoldierController) 0 failed")
	_r2 = _sp145.run(["python3", "tools/sim/run_army_orders_test.py"], capture_output=True, text=True, env=dict(_os145.environ, LUAU=_luau))
	_cb145(_r2.returncode == 0, "CODEBOT v145: run_army_orders_test 0 failed")

# live state kept
_AOC = _rd145(_C145 + "ArmyOrdersConfig.luau")
_cb145("\tLive = {\n\t\tEnabled = true,\n\t\tOwnerFirst = false," in _AOC, "CODEBOT v145: ArmyOrdersConfig OwnerFirst=false (v166 flip-all-live)")
_cb145("OwnerFirst = false, -- codebot_v142 launch" in _rd145(_C145 + "ShopOverhaulConfig.luau"), "CODEBOT v145: ShopOverhaul stays OwnerFirst=false")
_cb145("OwnerFirst = false, -- codebot_v142 launch" in _rd145(_C145 + "CheckpointGuardConfig.luau"), "CODEBOT v145: CheckpointGuard stays OwnerFirst=false")
_cb145("\tLive = {\n\t\tEnabled = true,\n\t\tOwnerFirst = false," in _rd145(_C145 + "EndgameConfig.luau"), "CODEBOT v145: EndgameConfig OwnerFirst=false (v166 flip-all-live)")
_cb145("PreferMeshWhenAssetIdSet = false" in _rd145(_C145 + "StructureVisualConfig.luau"), "CODEBOT v145: PreferMesh stays OFF")
_cb145("FastTravelEnabled = false" in _rd145(_C145 + "MapConfig.luau"), "CODEBOT v145: fast travel stays REMOVED")
try:
	_wb = _sp145.run(["git", "diff", "--name-only", "aa7f88e"], capture_output=True, text=True).stdout
	_cb145(not any("WE_Building" in l for l in _wb.splitlines()), "CODEBOT v145: no WE_Building* file touched since v144 tip")
	# claude-bud JOB 39 phase 2: retired "no config changed since v144 tip" (every later job adds config: EndgameConfig parts,
	# PlazaServicesConfig stations). Replacement: the configs this guard protected (VIP / pass Ids = MonetizationConfig,
	# RPG hold = WeaponConfig, WeaponsLive = RebirthConfig) are still untouched since the v144 tip.
	# claude-bud JOB 40 part B: MonetizationConfig now carries the speed helper (no price / Id change): the guard is the
	# Robux lines themselves. WeaponConfig / RebirthConfig stay untouched.
	# claude-bud JOB 50 D: WeaponConfig may now differ ONLY in hotbar ShortName labels (distinct captions: DMR /
	# HAVOC RL / SOV RIFLE); RebirthConfig stays untouched. Replacement for the whole-file guard:
	import re as _re50145
	_wd145 = _sp145.run(["git", "diff", "-U0", "aa7f88e", "--", _C145 + "WeaponConfig.luau"], capture_output=True, text=True).stdout
	_ch145 = [l for l in _wd145.splitlines() if l[:1] in "+-" and not l.startswith(("+++", "---"))]
	_nm145 = lambda l: _re50145.sub(r'"[A-Z][A-Z ]*", (\d+), \{', 'SHORT, \\1, {', l[1:].split(" -- ")[0].rstrip())
	_cb145(not any(l == _C145 + "RebirthConfig.luau" for l in _wb.splitlines())
		and sorted(_nm145(l) for l in _ch145 if l[0] == "-") == sorted(_nm145(l) for l in _ch145 if l[0] == "+"),
		"CODEBOT v145: RPG hold / WeaponsLive configs untouched since v144 tip (claude-bud JOB 39 replacement)")
	_md = _sp145.run(["git", "diff", "-U0", "aa7f88e", "--", _C145 + "MonetizationConfig.luau"], capture_output=True, text=True).stdout
	# v156 (Code Bot Roblox): retired, superseded in tools/checks/codebot_v156.py (the config RobuxPrice is now only the display
	# fallback; v156 corrected StarterBundle 149->249 and ExtraSoldierSlot 99->79 to the real Creator Hub prices and pins every
	# config price to the audited Creator Hub price + every Id unchanged since v155):
	# _cb145(not any(_re145.search(r"\bRobuxPrice\s*=|(^|[\s{,])Id\s*=\s*\d", l) for l in _md.splitlines() if l[:1] in "+-" and not l.startswith(("+++", "---"))),
	# 	"CODEBOT v145: no Robux price / Id line changed in MonetizationConfig since v144 tip (claude-bud JOB 40 replacement)")
	pass
except Exception:
	pass
