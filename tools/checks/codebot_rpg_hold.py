# Code Bot Roblox RPG fix (2026-09-30): the launcher hold must be a real idle loop, never the Weapons Kit's
# pitch-scrub aim sheets (3972164452 NewRifleAim / 3972157449 NewRifleADS). WeaponVisuals.playHold plays the Hold id
# Looped at normal speed, so a pitch sheet swept the Waist + the launcher from 80 deg down to near vertical every 2 s.
import re as _reRPG
from pathlib import Path as _PRPG


def _cbRPG(cond, label):
    if "ok" in globals() and "bad" in globals():
        (ok if cond else bad)(label)
    else:
        print(("PASS " if cond else "FAIL ") + label)
        if not cond:
            raise SystemExit(1)


def _rdRPG(p):
    q = _PRPG(p)
    return q.read_text(encoding="utf-8") if q.is_file() else ""


_HRPG = _rdRPG("src/ReplicatedStorage/Shared/Configs/HudConfig.luau")
_mRPG = _reRPG.search(r"\n\tAnims = \{ Hold = \{([^}]*)\}", _HRPG)
_holdRPG = _mRPG.group(1) if _mRPG else ""
_cbRPG(_mRPG is not None, "CODEBOT RPG: HudConfig.CombatFx.Anims.Hold found")
_cbRPG("Launcher = 3972151362" in _holdRPG, "CODEBOT RPG: launcher hold = RifleHold 3972151362 (arms only, seamless loop)")
for _bad in ("3972164452", "3972157449"):
    _cbRPG(_bad not in _holdRPG, "CODEBOT RPG: no pitch-scrub aim sheet %s as a looped Hold" % _bad)
_WRPG = _rdRPG("src/StarterPlayer/StarterPlayerScripts/Client/Modules/WeaponVisuals.luau")
_cbRPG("tr.Looped = true\n\t\t\ttr:Play(0.15)" in _WRPG, "CODEBOT RPG: playHold still plays the Hold looped (so the id must be a loop)")
