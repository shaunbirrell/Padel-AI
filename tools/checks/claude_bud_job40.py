# claude-bud JOB 40 (2026-09-30): part E (PRIORITY) the base owner markers; parts A-D follow in this file.
# Static pins + the real-code tests (tools/sim/run_base_marker_test.py, ...).
import os as _j40_os
import re as _j40_re
import subprocess as _j40_sp
import sys as _j40_sys
from pathlib import Path as _J40P

if "ok" not in globals():
    _j40_fails = []

    def ok(msg):
        print("PASS " + msg)

    def bad(msg):
        _j40_fails.append(msg)
        print("FAIL " + msg)

if "read" not in globals():
    def read(p):
        q = _J40P(p)
        return q.read_text(encoding="utf-8") if q.is_file() else None


def _j40(cond, msg):
    (ok if cond else bad)("CLAUDE-BUD J40: " + msg)


def _j40_src(path):
    return (read(path) or "").replace("\r\n", "\n")


def _j40_code(path):
    s = _j40_re.sub(r"--\[\[.*?\]\]", "", _j40_src(path), flags=_j40_re.S)
    return "\n".join(l.split("--", 1)[0] for l in s.splitlines())


_SV = "src/ServerScriptService/Server/"
_CL = "src/StarterPlayer/StarterPlayerScripts/Client/"
_CF = "src/ReplicatedStorage/Shared/Configs/"

# ── part E: the base owner markers ──
_BMC = _j40_src(_CF + "BaseMarkerConfig.luau")
_BMS = _j40_code(_SV + "Services/BaseMarkerService.luau")
_BMK = _j40_code(_CL + "Controllers/BaseMarkerController.luau")
_j40("\tLive = {\n\t\tEnabled = true,\n\t\tOwnerFirst = true, -- only UserId 470626172" in _BMC and "RetentionConfig.Live(BaseMarkerConfig.Live, userId)" in _BMC,
     "E: one owner-first kill switch (BaseMarkerConfig.Live, by viewer)")
_j40("MaxDistance = 5000," in _BMC and "HeightStuds = 70," in _BMC and "HideInsideStuds = 60," in _BMC and "FadeInsideStuds = 90," in _BMC,
     "E: visible from anywhere (5000), 70 studs up, hidden inside 60 / full past 90 (the v123 sign takes over)")
_on_top = sorted(p.relative_to(_J40P("src")).as_posix() for p in _J40P("src").rglob("*.luau") if "AlwaysOnTop = true" in p.read_text(encoding="utf-8"))
_j40(_on_top == ["ReplicatedStorage/Shared/Configs/BaseMarkerConfig.luau", "StarterPlayer/StarterPlayerScripts/Client/Controllers/TerritoryController.luau",
                 "StarterPlayer/StarterPlayerScripts/Client/Modules/ArmyDebugClient.luau", "StarterPlayer/StarterPlayerScripts/Client/Modules/ConsoleWaypoint.luau",
                 "StarterPlayer/StarterPlayerScripts/Client/Modules/ObjectiveMarker.luau"]
     and "g.AlwaysOnTop = BaseMarkerConfig.AlwaysOnTop" in _BMK,
     "E: AlwaysOnTop only in the base marker (the ONE documented exception) + the existing objective / waypoint / debug / contested labels")
_j40("RenderStepped" not in _BMS and "Heartbeat" not in _BMS and "task.wait(BaseMarkerConfig.RefreshSeconds)" in _BMS,
     "E: the server publishes data only (5 s refresh + events), nothing per frame")
_j40("task.wait(1 / BaseMarkerConfig.UpdateHz)" in _BMK and "RenderStepped" not in _BMK and "UpdateHz = 10," in _BMC, "E: the client step is 10 Hz for all markers together")
_j40('require(Shared.Util.NationTexture)' in _BMK and "rbxassetid" not in _BMK, "E: flag images only from the nation art (NationTexture / NationFlagIds), no new ids")
_j40("if BaseMarkerConfig.Live.Enabled ~= true or not BaseMarkerConfig.LiveFor(player.UserId) then" in _BMK, "E: OFF / not live for the viewer = no marker")
_j40("ReplicatedStorage:WaitForChild(BaseMarkerConfig.FolderName, 120)" in _BMK and "FolderName = \"WE_BaseMarkers\"" in _BMC,
     "E: streaming-safe data (ReplicatedStorage), bounded wait")
_j40("one documented exception" in (_j40_src("CLAUDE.md")).lower() or "base owner marker" in _j40_src("CLAUDE.md").lower(), "E: the world-label exception is written in CLAUDE.md")

# ── part A: real base guards + the one hostility rule ──
_GC = _j40_src(_CF + "GuardConfig.luau")
_BG = _j40_code(_SV + "Modules/BaseGuards.luau")
_GD = _j40_code(_SV + "Services/GateDefenseService.luau")
_j40("\tPosts = {\n\t\tEnabled = true,\n\t\tOwnerFirst = true," in _GC and "Live((GuardConfig :: any).Posts, ownerUserId)" in _GC,
     "A: GuardConfig.Posts kill switch, owner-first by the base owner")
_post = _BG.split("function BaseGuards.ThinkPost")[1].split("function BaseGuards.PostDamageMult")[0]
_j40("TakeDamage" not in _post and [l.strip() for l in _post.splitlines() if ".Health =" in l] == ["g.Humanoid.Health = g.Humanoid.MaxHealth"],
     "A: the post guard brain never deals raw damage; its one Health write is the at-post regen of the guard itself")
_one = _BG.split("function BaseGuards.PlayerHostileOneRule")[1].split("local function friendlyPlayer")[0]
_j40("cs.UnitMayHitPlayer(owner, p)" in _one and "cs.ArmyHostility(owner, uo)" in _one and "AreFriends" not in _one and "areFriends" not in _one,
     "A: the live rule calls only UnitMayHitPlayer / ArmyHostility (no friends exemption, no private rule)")
_j40("if live then BaseGuards.PlayerHostileOneRule" in _BG and "if live then BaseGuards.UnitHostileOneRule" in _BG,
     "A: every guard / tower target check goes through the one rule when live (off = JOB 20 exactly)")
_j40("pcall(cs.ApplyDefenceHit, owner, victim, amt, sourceId)" in _BG and "pcall(cs.ApplyHit, owner, t.Root, amt," in _BG,
     "A: live hits go through CombatService (ApplyDefenceHit / ApplyHit), no TakeDamage")
_j40("bgMod.PlayerHostileOneRule(ownerUserId, player" in _GD and "pcall(bgH.DefenceHit, liveOwner, player, amount" in _GD and "bgH.AttackerMay(attacker, owner)" in _GD
     and "return cs.ApplyDefenceHit(owner, victim, amount, kind)" in _BG and "return cs.ArmyHostility(attacker, owner)" in _BG,
     "A: the AutoGuns / gate guards use the same rule and hit path; attackers need ArmyHostility the other way round")
_j40("PivotTo" not in _BG and "SetPrimaryPartCFrame" not in _BG, "A: no PivotTo / SetPrimaryPartCFrame in BaseGuards")
_j40(all(("\"%s\"" % s) in _GC for s in ("IDLE", "ALERT", "ATTACK", "RETURN", "DEAD")), "A: the states IDLE / ALERT / ATTACK / RETURN / DEAD")
_spawn = _GD.split("local function spawnGuardModel")[1].split("\nend\n")[0]
_j40("root.Anchored = false" in _spawn and "WE_RigStatic" not in _spawn, "A: the live guards are unanchored Humanoid rigs (never WE_RigStatic)")
_j40("bgR.RestoreStatues, plotId" in _GD and "bgMod.CollectPosts(plotFolder, plotId)" in _GD, "A: the statues are parked for a live plot and restored when it clears")

# ── part B: speed (JOB 40 replacements for the retired codebot_v133 / v126 speed pins) ──
_MCF = _j40_src(_CF + "MonetizationConfig.luau")
_j40("WalkSpeedMultV2 = 1.75," in _MCF and "WalkSpeedMultV2 = 2.5," in _MCF and "cfg.MaxWalkSpeedMult = 2.5" in _MCF
     and "cfg.SpeedV2 = {\n\tEnabled = true,\n\tOwnerFirst = true," in _MCF,
     "B: Speed Pass x1.75 (28) / Speed Boost x2.5 (40), cap 2.5, owner-first (SpeedV2); off = x1.5 / x2")
_j40("cfg.GamePasses.ImpulseSpeed.Description = cfg.SpeedText(" in _MCF and "cfg.DevProducts.SpeedBoost.Description = cfg.SpeedText(" in _MCF
     and 'Description = "Run' not in _MCF, "B: the speed Descriptions come from the helper (no typed speed string)")
_speed_strings = [p.as_posix() for p in _J40P("src").rglob("*.luau") if p.name != "MonetizationConfig.luau"
                  and _j40_re.search(r'"[^"\n]*\d+(\.\d+)?(%|x) faster', p.read_text(encoding="utf-8"))]
_j40(_speed_strings == [], "B: no hard-coded speed string outside the helper (" + ", ".join(_speed_strings) + ")")
_MSV = _j40_code(_SV + "Services/MonetizationService.luau")
_j40("local MAX_WALK_SPEED_MULT = tonumber((MonetizationConfig :: any).MaxWalkSpeedMult) or 2.0" in _MSV and "walkSpeedMultOf(def, player.UserId)" in _MSV,
     "B: the cap from config; SpeedMultFor reads the player's (V2 while live) multiplier")
_SHC = _j40_code(_CL + "Controllers/ShopController.luau")
_j40(_SHC.count("DescFor(def,") >= 5 and "(MonetizationConfig :: any).SpeedText(mult, true)" in _SHC, "B: Shop rows / toast / death card read the helper")
_AY = _j40_src(_CF + "ArmyConfig.luau")
_j40("MaxSpeed = 58, -- claude-bud JOB 40: x1.45" in _AY and "MaxOwnerSpeed = 48," in _AY and "MaxSpeed = 60, -- claude-bud JOB 40: 40 x 1.5" in _AY
     and "MaxSpeed = 58, -- claude-bud JOB 40: was 50" in _AY and "SpeedUpPerTick = 6," in _AY and "SpeedDownPerTick = 5," in _AY,
     "B: the army keeps up (Follow3 58, Lead 48, CatchUp 60, Follow2 58; no lurch: +6 / -5 per tick)")

_luau = _j40_os.environ.get("LUAU")
if _luau is None and _j40_os.environ.get("LUAU_COMPILE"):
    _cand = _j40_os.environ["LUAU_COMPILE"].replace("luau-compile", "luau")
    _luau = _cand if _j40_os.path.isfile(_cand) else None
if _luau:
    _r = _j40_sp.run([_j40_sys.executable, "tools/sim/run_base_marker_test.py"], capture_output=True, text=True, env=dict(_j40_os.environ, LUAU=_luau))
    _j40(_r.returncode == 0 and "BASE MARKER TEST: 0 failed" in _r.stdout, "E: run_base_marker_test.py (real config / data service)")
    _r = _j40_sp.run([_j40_sys.executable, "tools/sim/run_base_guards_test.py"], capture_output=True, text=True, env=dict(_j40_os.environ, LUAU=_luau))
    _j40(_r.returncode == 0 and "BASE GUARDS TEST: 0 failed" in _r.stdout, "A: run_base_guards_test.py (state machine, the hostility table, budgets)")
    _r = _j40_sp.run([_j40_sys.executable, "tools/sim/run_speed_test.py"], capture_output=True, text=True, env=dict(_j40_os.environ, LUAU=_luau))
    _j40(_r.returncode == 0 and "SPEED ALL: 0 failed" in _r.stdout, "B: run_speed_test.py (the helper, the values, the 40-stud/s army sim: 0 teleports)")
else:
    print("SKIP CLAUDE-BUD J40: Luau CLI tests (set LUAU)")
