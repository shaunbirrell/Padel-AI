# claude-bud JOB 37 (2026-09-30): the REAL road checkpoint (WorldKits Detail.Checkpoint, its own detail share, WorldPOI's
# plain rebuild of a refused detailed cluster) + killable guards (CheckpointGuardConfig / CheckpointGuardService, owner-
# first), the client searchlight sweep, the map rows and the mission GO. Static pins + the real-code tests
# (tools/sim/run_kit_detail_test.py for the kit, tools/sim/run_checkpoint_guards_test.py for the guards).
import os as _j37_os
import re as _j37_re
import subprocess as _j37_sp
import sys as _j37_sys
from pathlib import Path as _J37P

if "ok" not in globals():
    _j37_fails = []

    def ok(msg):
        print("PASS " + msg)

    def bad(msg):
        _j37_fails.append(msg)
        print("FAIL " + msg)

if "read" not in globals():
    def read(p):
        q = _J37P(p)
        return q.read_text(encoding="utf-8") if q.is_file() else None


def _j37(cond, msg):
    (ok if cond else bad)("CLAUDE-BUD J37: " + msg)


def _j37_src(path):
    return (read(path) or "").replace("\r\n", "\n")


def _j37_code(path):
    return "\n".join(l.split("--", 1)[0] for l in _j37_src(path).splitlines())


_SV = "src/ServerScriptService/Server/"
_CGC = _j37_src("src/ReplicatedStorage/Shared/Configs/CheckpointGuardConfig.luau")
_CGS = _j37_re.sub(r"--\[\[.*?\]\]", "", _j37_src(_SV + "Services/CheckpointGuardService.luau"), flags=_j37_re.S)
_CGS = "\n".join(l.split("--", 1)[0] for l in _CGS.splitlines())
_WK = _j37_src(_SV + "Modules/WorldKits.luau")
_WDC = _j37_src("src/ReplicatedStorage/Shared/Configs/WorldDetailConfig.luau")
_CC = _j37_code("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/CheckpointController.luau")
_det = _WK[_WK.index("Detail.Checkpoint = function"):_WK.index("-- exact part counts of the detailed builds")] if "Detail.Checkpoint = function" in _WK else ""

# flags
_j37("\tLive = {\n\t\tEnabled = true,\n\t\tOwnerFirst = true, -- only UserId 470626172" in _CGC and "RetentionConfig.Live(CheckpointGuardConfig.Live, userId)" in _CGC,
     "guards: one owner-first kill switch (CheckpointGuardConfig.Live)")
_j37("Checkpoint = true, -- claude-bud JOB 37" in _WDC and "Checkpoint = 546," in _WDC and "MaxExtraParts = 1446," in _WDC,
     "detail: WorldDetailConfig.Kits.Checkpoint, its own share 546 (MaxExtraParts 900 -> 1446: the JOB 31 kits keep 900)")
_j37("RespawnSeconds = 180," in _CGC, "the group respawns 180 s after the last guard died")
# no forced damage / no teleport in the new service; combat through CombatService only
_j37(_j37_re.search(r"\.Health\s*=[^=]", _CGS) is None and "TakeDamage" not in _CGS and "PivotTo" not in _CGS and "TeleportService" not in _CGS,
     "CheckpointGuardService never sets Health, never calls TakeDamage, never teleports")
_j37("pcall(cs.SpawnNPC, G.NpcType, cf, {" in _CGS and "TargetFilter = function(p: Player): boolean" in _CGS and "Leash = G.SiteRadius + G.LeashExtra," in _CGS,
     "guards spawn through CombatService.SpawnNPC (group, leash, live-only target filter)")
_j37("(filter == nil or filter(player))" in _j37_code(_SV + "Services/CombatService/CombatNPC.luau")
     and "target, dist = CombatNPC.NearestPlayer(rec.Root.Position, rec.Def.AggroRange, rec.TargetFilter)" in _j37_code(_SV + "Services/CombatService/CombatNPC.luau"),
     "CombatNPC target pick honours the spawn TargetFilter (nil = every player, unchanged)")
_j37("CheckpointGuard = {" in _j37_src("src/ReplicatedStorage/Shared/Configs/CombatConfig.luau") and '"CheckpointGuard"' not in _j37_src("src/ReplicatedStorage/Shared/Configs/CombatConfig.luau").split("SpecialNPCTypes", 1)[1].split("\n", 1)[0],
     "CheckpointGuard NPC type, not a SpecialNPCType (the regular 18-slot pool)")
_j37('CheckpointGuard = { ModelAssetId = 187790284, Rig = "R6"' in _j37_src("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau"),
     "guards use the bank guards' animated R6 rig")
# rewards / mission / map
_j37('pcall(deps.MissionService.TrackProgress, p, "Checkpoint", 1)' in _CGS and "s.PaidCycle[uid] ~= s.Cycle" in _CGS and "now - lastPaid[uid] >= G.PlayerCooldownSeconds" in _CGS,
     "cleared bonus once per cycle per player (+ cooldown), mission objective Checkpoint +1")
_j37('"checkpoint_guard_kill"' in _CGS and '"checkpoint_cleared"' in _CGS, "telemetry checkpoint_guard_kill / checkpoint_cleared")
_j37("Checkpoints = checkpointRows(player)," in _j37_code(_SV + "Services/MapService.luau") and 'if kind == "Checkpoint" then' in _j37_code(_SV + "Services/MissionService.luau"),
     "world map rows (hostile / cleared + countdown) and the mission GO (tap-to-pin, no fast travel)")
# lights / shadows / the kit
_j37(_det.count('Instance.new("SpotLight")') == 1 and _WK.count('Instance.new("SpotLight")') == 1 and "spot.Shadows = false" in _det and 'Instance.new("PointLight")' not in _det,
     "replaces BPS W3s2 K: exactly one SpotLight in WorldKits (the checkpoint searchlight), Shadows = false, no other light in the kit")
_j37("\tMaxExtraParts = 1446," in _WDC and "KitCaps = {\n\t\tCheckpoint = 546," in _WDC and "over = (WorldKits.DetailStats.Extra - othersExtra) + extra > math.max(0, shared)" in _WK,
     "replaces claude_bud_job31 (ONE allowance): the JOB 31 kits keep the shared 900, the checkpoint its 546")
_j37("RenderStepped:Connect(step)" in _CC and "SWEEP_STUDS = 250" in _CC and "conn:Disconnect()" in _CC,
     "the searchlight sweeps on the client only, within 250 studs, the loop stops when none is near")
_j37("WorldKits.RefundDetail(model)" in _j37_src(_SV + "Modules/WorldPOI.luau") and "buildCluster(true)" in _j37_src(_SV + "Modules/WorldPOI.luau"),
     "a detailed cluster WorldPOI refuses is rebuilt plain (never dropped for its detail)")
_j37("Neon" not in _det.replace("never Neon", ""), "no Neon in the checkpoint kit")

_luau = _j37_os.environ.get("LUAU")
if _luau is None and _j37_os.environ.get("LUAU_COMPILE"):
    _cand = _j37_os.environ["LUAU_COMPILE"].replace("luau-compile", "luau")
    _luau = _cand if _j37_os.path.isfile(_cand) else None
if _luau:
    for _t, _w in (("tools/sim/run_kit_detail_test.py", "KIT DETAIL TEST: 0 failed"), ("tools/sim/run_checkpoint_guards_test.py", "CHECKPOINT GUARDS TEST: 0 failed")):
        _r = _j37_sp.run([_j37_sys.executable, _t], capture_output=True, text=True, env=dict(_j37_os.environ, LUAU=_luau))
        _j37(_r.returncode == 0 and _w in _r.stdout, _t)
else:
    print("SKIP CLAUDE-BUD J37: Luau CLI tests (set LUAU)")
