# Code Bot Roblox v216 (2026-10-02): the owner's phone bug "my army fights at another base, I am far away, and every time
# my soldiers shoot, MY gun comes out and I stop walking (holster -> it happens again)". The only automatic draw is
# CombatController onDamaged (AutoDrawOnDamage) and it drew on ANY health drop / Damaged with no check of the source;
# the shoulder cam that comes with a drawn gun is the "stops walking". Behind HudConfig.Hotbar.AutoDrawGuard
# (RetentionConfig.Live: Enabled + OwnerFirst): a gun / blast hit still draws; an army / defence hit draws only if its
# shooter (Damaged.From, now the REAL unit, Unit = true) is within NearStuds or unknown; a bare health drop draws only
# if another player / a soldier not mine / an NPC is within NearStuds (one task.delay per drop, no new loop).
import os
import re
import subprocess
from pathlib import Path

ROOT = Path.cwd()
PREV = os.environ.get("CODEBOT_V216_PREV", "1c6b294")
C = "src/ReplicatedStorage/Shared/Configs/"
S = "src/ServerScriptService/Server/"
CL = "src/StarterPlayer/StarterPlayerScripts/Client/Controllers/CombatController.luau"
LUAU = os.environ.get("LUAU", os.path.expanduser("~/.local/bin/luau"))


def _r(rel):
    p = ROOT / rel
    return p.read_text(encoding="utf-8").replace("\r\n", "\n") if p.is_file() else ""


def _shipped(rel, rev):
    r = subprocess.run(["git", "show", rev + ":" + rel], capture_output=True, text=True, cwd=ROOT)
    return (r.stdout or "").replace("\r\n", "\n") if r.returncode == 0 else None


def _c(cond, label):
    label = "CODEBOT v216: " + label
    if "ok" in globals() and "bad" in globals():
        (ok if cond else bad)(label)
    else:
        print(("PASS " if cond else "FAIL ") + label)
        if not cond:
            raise SystemExit(1)


_bud = (ROOT / S / "Services/ExperienceNotifyService.luau").is_file()  # claude/desktop-bud: ship-only pins skip
if not _bud:
    for _rel in (S + "Services/BaseService.luau", S + "Services/DataService.luau", S + "EarlyRemotes.server.luau"):
        _m = re.search(r'SetAttribute\("WE_Build", (\d+)\)', _r(_rel))
        _c(_m is not None and int(_m.group(1)) >= 216, "WE_Build >= 216 " + _rel.rsplit("/", 1)[-1])

HUD = _r(C + "HudConfig.luau")
_c("AutoDrawGuard = { Enabled = true, OwnerFirst = true, NearStuds = 160, ConfirmSeconds = 0.6 }" in HUD,
   "HudConfig.Hotbar.AutoDrawGuard Enabled + OwnerFirst (owner's phone test)")
_c("AutoDrawOnDamage = true" in HUD, "AutoDrawOnDamage itself stays on (being attacked still draws)")

CC = _r(CL)
_od = CC[CC.find("local function onDamaged(src: any?)"):]
_od = _od[: _od.find("\n---------------------------------------------------------------------------------------------------------------")]
_c(len(_od) > 200, "onDamaged(src) present")
_c("RC.Live(g, player.UserId) == true" in CC, "guard gated by RetentionConfig.Live (OwnerFirst)")
_c("if not ADG.live() then\n\t\tsetDrawn(true) -- v214 behaviour" in _od, "flag off = the v214 draw")
_c("src.Unit == true and typeof(from) == \"Vector3\"" in _od and "> ADG.near() then\n\t\t\treturn" in _od,
   "army / defence hit with a FAR known shooter never draws")
_c("task.delay(" in _od and "ADG.bodyNear()" in _od and "ADG.Pending" in _od,
   "bare health drop: one delayed body-near check per drop")
_c("flashEdge()" in _od and "markCombat()" in _od, "edge flash + RecentCombat stay on every drop")
_c('onDamaged(raw) -- codebot v216' in CC, "Damaged feedback hands its source to the guard")
_c(CC.count("onDamaged()") == 2, "health-drop callers (CombatStateUpdate + HealthChanged) pass no source")
_hk = CC[CC.find("local function onHitFeedback"):]
_hk = _hk[: _hk.find('elseif kind == "Damaged"')]
_c("setDrawn" not in _hk and "onDamaged" not in _hk, "Hit / Kill markers (my army's hits) never draw")
_c('m:GetAttribute("OwnerUserId") ~= player.UserId' in CC, "my own soldiers never count as a body near me")
_c('setDrawn(true) -- dimmed FIRE while holstered: this press draws, then fires' in CC, "own FIRE still draws + fires")

CS = _r(S + "Services/CombatService/init.luau")
_c("FromPos: Vector3?," in CS, "FbOpts.FromPos")
_c("RC.Live(HC.Hotbar.AutoDrawGuard, victim.UserId) == true" in CS and "from = fb.FromPos" in CS,
   "victim-live: Damaged.From = the real unit / defence, not the far owner")
_c("Unit = if unitSrc then true else nil" in CS, "Damaged carries Unit")
_c("damage: number, fromPos: Vector3?): (number, boolean, string)" in CS, "ApplyUnitPlayerHit takes the shooter pos")
_c("kind: string?, fromPos: Vector3?): (number, boolean, string)" in CS, "ApplyDefenceHit takes an optional shooter pos")
_c(CS.count("local may, why = CombatService.UnitMayHitPlayer(owner, victim)") >= 2, "the shared hostility rule still gates both")
SQ = _r(S + "Services/SquadOrdersService.luau")
_c("pcall(CombatService.ApplyUnitPlayerHit, player, tgt.Player, dmg, unit.Root.Position)" in SQ, "army shot passes its unit pos")

# no new per-frame loop, Streaming / PreferMesh untouched
for _rel in (CL, S + "Services/CombatService/init.luau", S + "Services/SquadOrdersService.luau"):
    _old = _shipped(_rel, PREV)
    if _old is not None:
        _c(_r(_rel).count("Heartbeat") == _old.count("Heartbeat") and _r(_rel).count("RenderStepped") == _old.count("RenderStepped"),
           "no new Heartbeat / RenderStepped " + _rel.rsplit("/", 1)[-1])

# Luau sim of the decision table (mirrors onDamaged; the static pins above hold the real code to it)
_SIM = r'''
local NEAR = 160
-- From / me are 1-D positions here (plain Luau has no Vector3)
local function decide(live, src, me, bodyNear)
	if not live then return true end
	if src ~= nil then
		if src.Unit == true and type(src.From) == "number" and me ~= nil and math.abs(src.From - me) > NEAR then
			return false
		end
		return true
	end
	return bodyNear
end
assert(decide(false, nil, 0, false) == true, "off = v214")
assert(decide(true, { Unit = true, From = 900 }, 0, false) == false, "far army shot")
assert(decide(true, { Unit = true, From = 40 }, 0, false) == true, "near army shot")
assert(decide(true, { Unit = true }, 0, false) == true, "unknown defence shot")
assert(decide(true, { From = 900 }, 0, false) == true, "gun hit from a sniper")
assert(decide(true, nil, 0, false) == false, "bare drop, nobody near")
assert(decide(true, nil, 0, true) == true, "bare drop, enemy near")
print("SIM OK")
'''
if os.path.isfile(LUAU):
    _p = ROOT / ".codebot_v216_sim.luau"
    _p.write_text(_SIM)
    try:
        _o = subprocess.run([LUAU, str(_p)], capture_output=True, text=True)
        _c("SIM OK" in (_o.stdout or ""), "decision sim " + (_o.stderr or "").strip()[:200])
    finally:
        _p.unlink()
