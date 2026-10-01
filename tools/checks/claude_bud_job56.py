# claude-bud JOB 56 (2026-10-01): helipad + dock spawn terminals (the Garage filtered to Air / Naval through the one
# RequestSpawn path) + the helicopter rotor spinning about its own disc. Executed inside tools/BuyPathStatic.py.
import os as _j56_os
import re as _j56_re
import subprocess as _j56_sp
import sys as _j56_sys
from pathlib import Path as _J56P

if "ok" not in globals():
    def ok(msg):
        print("PASS " + msg)

    def bad(msg):
        print("FAIL " + msg)


def _j56_src(p):
    q = _J56P(p)
    return q.read_text(encoding="utf-8").replace("\r\n", "\n") if q.is_file() else ""


_SC = _j56_src("src/ReplicatedStorage/Shared/Configs/SpawnTerminalConfig.luau")
(ok if ("Enabled = true," in _SC and "OwnerFirst = true, -- NEW-OWNER-FIRST" in _SC and 'Tab = "Air"' in _SC and 'Tab = "Naval"' in _SC and 'Panel = "Garage"' in _SC) else bad)(
    "CLAUDE-BUD J56: SpawnTerminalConfig is owner-first; helipad -> Garage / Air, dock -> Garage / Naval")
_ST = _j56_src("src/ServerScriptService/Server/Services/SpawnTerminalService.luau")
_STc = "\n".join(l.split("--", 1)[0] for l in _j56_re.sub(r"--\[\[.*?\]\]", "", _ST, flags=_j56_re.S).splitlines())
(ok if (not _j56_re.search(r"RequestSpawn|PivotTo|Teleport|AddCash|GrantVehicle|profile\.Vehicles|Neon|PointLight|SpotLight", _STc)) else bad)(
    "CLAUDE-BUD J56: the terminal only opens the Garage: no spawn, no grant, no move, no Neon / lights")
(ok if ('prompt.Name = "WE_PanelPrompt"' in _ST and 'prompt:SetAttribute("WE_OpenPanel", C.Panel)' in _ST and 'prompt:SetAttribute("WE_OpenTab", t.Tab)' in _ST and "prompt.HoldDuration = 0" in _ST) else bad)(
    "CLAUDE-BUD J56: the terminals use the house prompt contract (UIController routes WE_OpenPanel / WE_OpenTab)")
_UI = _j56_src("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/UIController.luau")
_VC = _j56_src("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/VehicleController.luau")
(ok if ('prompt:GetAttribute("WE_OpenTab")' in _UI and "Garage = VehicleController.Open," in _UI and 'tab == "Air" or tab == "Naval"' in _VC) else bad)(
    "CLAUDE-BUD J56: the client route exists (UIController tab hint -> VehicleController.Open(Air / Naval))")
_VS = _j56_src("src/ServerScriptService/Server/Services/VehicleService.luau")
(ok if ("if not VehicleService._IsPlaytestOwner(player) and not rebirthGranted then" in _VS and "meetsStructureReq(profile, def)" in _VS) else bad)(
    "CLAUDE-BUD J56: a normal account still meets every RequestSpawn gate (level / structure / prestige); only the owner skips (VS ~4867)")
_BS = _j56_src("src/ServerScriptService/Server/Bootstrap.server.luau")
(ok if 'safeInit("SpawnTerminalService", SpawnTerminalService, deps)' in _BS else bad)("CLAUDE-BUD J56: SpawnTerminalService is started")
_VA = _j56_src("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau")
_rd = _VA.split("AirRotorDisc = {")[1].split("\n\t},")[0] if "AirRotorDisc = {" in _VA else ""
(ok if ("Enabled = true," in _rd and "OwnerFirst = true, -- NEW-OWNER-FIRST" in _rd) else bad)("CLAUDE-BUD J56: VisualAssetConfig.AirRotorDisc is owner-first")
_AR = _j56_src("src/ServerScriptService/Server/Modules/AirBodyRig.luau")
_rr = _AR.split("local function rigRotor")[1].split("\nend\n")[0] if "local function rigRotor" in _AR else ""
(ok if ("AirBodyRig._DiscFit(parts, jointRot, centre)" in _rr and "[RotorRig]" in _rr and 'hostModel:GetAttribute("OwnerUserId")' in _rr and "local joint = CFrame.new(centre) * jointRot" in _rr) else bad)(
    "CLAUDE-BUD J56: rigRotor spins about the blades' own disc / centre (owner-first) and logs [RotorRig] tilt / offset")
_e = dict(_j56_os.environ)
if "LUAU" not in _e and _e.get("LUAU_COMPILE"):
    _c = _e["LUAU_COMPILE"].replace("luau-compile", "luau")
    if _j56_os.path.isfile(_c):
        _e["LUAU"] = _c
if _e.get("LUAU"):
    _r = _j56_sp.run([_j56_sys.executable, "tools/sim/run_spawn_terminals_test.py"], capture_output=True, text=True, env=_e)
    (ok if (_r.returncode == 0 and "SPAWN TERMINALS TEST: 0 failed" in _r.stdout) else bad)(
        "CLAUDE-BUD J56: run_spawn_terminals_test.py (wanted / built / owner-first / clear; rotor disc 6 deg, 0.4 studs, kept cases)")
