# claude-bud JOB 67 (2026-10-01): asset upgrade. Sub-part 1 = turret tiers (Minigun Turret Pack, PENDING until promoted).
# Executed inside tools/BuyPathStatic.py (ok / bad).
import os as _j67_os
import subprocess as _j67_sp
from pathlib import Path as _J67P

if "ok" not in globals():
    def ok(msg):
        print("PASS " + msg)

    def bad(msg):
        print("FAIL " + msg)


def _j67_src(p):
    q = _J67P(p)
    return q.read_text(encoding="utf-8").replace("\r\n", "\n") if q.is_file() else ""


_VA = _j67_src("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau")
_j = _VA.split("Job67 = {")[1].split("\n\t},")[0] if "Job67 = {" in _VA else ""
(ok if ("Enabled = true," in _j and "OwnerFirst = true, -- NEW-OWNER-FIRST" in _j and "TurretTierAt = { 1, 4, 7, 10 }" in _j) else bad)(
    "CLAUDE-BUD J67: VisualAssetConfig.Job67 is owner-first; turret tiers at Guns L1 / 4 / 7 / 10")
(ok if all(("AutoGunT%d = { ModelAssetId = 0, PendingAssetId = 109072907337393" % i) in _VA for i in range(1, 6)) else bad)(
    "CLAUDE-BUD J67: the 5 turret tiers are PENDING (ModelAssetId 0) until tools/wire-asset-ids.py promotes the WE_CHECK2-passed pack")
_W = _j67_src("tools/wire-asset-ids.py")
(ok if "('MinigunTurretPack', 'GATE DEFENSE', 'PENDING-GET', 109072907337393" in _W else bad)("CLAUDE-BUD J67: the pack has its registry row (promote / reject path)")
_G = _j67_src("src/ServerScriptService/Server/Services/GateDefenseService.luau")
(ok if ("local template = tierTemplate or loadCatalogModel(assetId)" in _G and "catalogRefusal(model)" in _G.split("local function loadCatalogPiece")[1].split("\nend\n")[0]
    and "spawnAutoGun(slot, at, folder, tier)" in _G) else bad)(
    "CLAUDE-BUD J67: the turret tier model replaces today's gun only when promoted, through the same 40-part refusal (else today's gun)")
_l = _j67_os.environ.get("LUAU") or (_j67_os.environ.get("LUAU_COMPILE", "").replace("luau-compile", "luau"))
if _l and _j67_os.path.isfile(_l):
    _r = _j67_sp.run([__import__("sys").executable, "tools/sim/run_turret_tier_test.py"], capture_output=True, text=True, env=dict(_j67_os.environ, LUAU=_l), timeout=120)
    (ok if (_r.returncode == 0 and "TURRET TIER TEST: 0 failed" in _r.stdout) else bad)("CLAUDE-BUD J67: run_turret_tier_test.py (level -> tier 0..10)")
