# claude-bud JOB 65 (2026-10-01): the NUKE INSTANT RAID (a rebirth-silo nuke on a rival home base = an instant raid of
# the target's FULL ATM through the raid payout path; never multiplied; the shared fairness rules; owner-first).
# Executed inside tools/BuyPathStatic.py (ok / bad).
import os as _j65_os
import re as _j65_re
import subprocess as _j65_sp
import sys as _j65_sys
from pathlib import Path as _J65P

if "ok" not in globals():
    def ok(msg):
        print("PASS " + msg)

    def bad(msg):
        print("FAIL " + msg)


def _j65_src(p):
    q = _J65P(p)
    return q.read_text(encoding="utf-8").replace("\r\n", "\n") if q.is_file() else ""


def _j65_fn(src, head):
    return src.split(head)[1].split("\nend\n")[0] if head in src else ""


_ZC = _j65_src("src/ReplicatedStorage/Shared/Configs/RebirthZonesConfig.luau")
_nr = _ZC.split("NukeRaid = {")[1].split("\n\t},")[0] if "NukeRaid = {" in _ZC else ""
(ok if ("Enabled = true," in _nr and "OwnerFirst = true, -- NEW-OWNER-FIRST" in _nr and "CooldownSeconds = 1800," in _nr and "Vfx = true," in _nr and "Targets = {" in _nr) else bad)(
    "CLAUDE-BUD J65: RebirthZonesConfig.NukeRaid is owner-first: 30 min cooldown, VFX switch, who may be targeted (one config)")
_E = _j65_src("src/ServerScriptService/Server/Services/EconomyService.luau")
_p2c = _j65_fn(_E, "function EconomyService.PendingToCash(")
_tpc = _j65_fn(_E, "function EconomyService.TransferPendingCash(")
(ok if (_p2c and _tpc and not _j65_re.search(r"applyCashMult|cashMultFor|DoubleEvent|AddCash", _p2c + _tpc)) else bad)(
    "CLAUDE-BUD J65: the nuke loot moves 1:1 (TransferPendingCash + PendingToCash never apply a multiplier: no Double Weekend on a transfer)")
_M = _j65_src("src/ServerScriptService/Server/Services/MoneyCollectorService.luau")
_nk = _j65_fn(_M, "function MoneyCollectorService.NukeRaid(")
(ok if ("MoneyCollectorService.CanArmyRaid(attacker, victim)" in _nk and "MoneyCollectorService.GetRaidableBalance(victim)" in _nk and "MoneyCollectorService._MoveLoot(attacker, victim, balance)" in _nk
    and "EconomyService.PendingToCash(attacker, moved)" in _nk and "AddCash" not in _nk and "AccruePendingCash" not in _nk) else bad)(
    "CLAUDE-BUD J65: NukeRaid = the raid checks + the FULL raidable balance + the raid money path (_MoveLoot) into his Cash")
(ok if ('"NUKE_RAID"' in _nk and "notifyRaided(victim)" in _nk and "vRaid.ShieldUntil" in _nk and "NoteRaid(" in _nk) else bad)(
    "CLAUDE-BUD J65: a nuke raid gives the victim shield, the raid report, NUKE_RAID analytics and the BaseRaided notification")
_N = _j65_src("src/ServerScriptService/Server/Services/NukeService.luau")
_v = _j65_fn(_N, "function NukeService.RaidVerdict(")
(ok if all(k in _v for k in ['"Admin"', '"Ally"', '"Protected"', '"CampCooldown"', "mc.CanArmyRaid(player, victim)", '"Cooldown"', '"NotReady"', '"NoSilo"', '"Self"'])
    else bad)("CLAUDE-BUD J65: the verdict refuses admins, allies, protected (the ONE rule), JOB 63 cooldown, raid rules, cooldown, no warhead / silo, self")
_l = _j65_fn(_N, "function NukeService.RaidLaunch(")
(ok if ("NukeService.RaidVerdict(player, plotId)" in _l and "profile.NukeLastLaunch = os.time()" in _l and _l.index("profile.NukeLastLaunch = os.time()") < _l.index("deps.MoneyCollectorService.NukeRaid")
    and "profile.NukeLastLaunch = oldLast" in _l) else bad)(
    "CLAUDE-BUD J65: the launch re-checks on the server, takes the warhead + cooldown before the money moves, gives them back if nothing moved")
(ok if ("Heartbeat" not in _N and "RenderStepped" not in _N) else bad)("CLAUDE-BUD J65: no per-frame loops")
_NC = _j65_src("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/NukeController.luau")
(ok if ('"rlaunch", tostring(d.PlotId)' in _NC and 'cancel.Size = UDim2.fromOffset(170, 64)' in _NC and 'launch.Size = UDim2.fromOffset(190, 64)' in _NC) else bad)(
    "CLAUDE-BUD J65: the preview card has big LAUNCH / CANCEL buttons (64 tall) and sends only the plot id")
_RV = _j65_src("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/RivalController.luau")
(ok if 'NC.PreviewRaid(plotId)' in _RV else bad)("CLAUDE-BUD J65: TARGETS rows get a NUKE button that opens the server preview")
_e = dict(_j65_os.environ)
if "LUAU" not in _e and _e.get("LUAU_COMPILE"):
    _c = _e["LUAU_COMPILE"].replace("luau-compile", "luau")
    if _j65_os.path.isfile(_c):
        _e["LUAU"] = _c
if _e.get("LUAU"):
    _r = _j65_sp.run([_j65_sys.executable, "tools/sim/run_nuke_raid_test.py"], capture_output=True, text=True, env=_e, timeout=150)
    (ok if (_r.returncode == 0 and "NUKE RAID TEST: 0 failed" in _r.stdout) else bad)(
        "CLAUDE-BUD J65: run_nuke_raid_test.py (preview = stolen, target ATM 0, no x2, fairness refusals, cooldown, refund, owner-first)")
