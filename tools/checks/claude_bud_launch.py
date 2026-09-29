# claude-bud JOB 12 (2026-09-29): launch readiness. MonetizationConfig.LaunchAll (one switch, ships false), the owner's
# shortcuts off at launch, every live product prompted + granted + kept (tools/launch_audit.py), and the gates executed
# with the Luau CLI for an owner and a NON-owner, LaunchAll off / on (tools/launch_gate_test.py; skipped without luau).
# Runs inside tools/BuyPathStatic.py (its globals). Helpers start with _cbl_.
import importlib.util as _cbl_il
import os as _cbl_os
import subprocess as _cbl_sp
import sys as _cbl_sys
_cbl_mc = "src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau"
must_contain(_cbl_mc, "\tLaunchAll = false,\n", "CLAUDE-BUD J12: LaunchAll ships false")
must_contain(_cbl_mc, "\treturn (MonetizationConfig :: any).LaunchAll == true and (MonetizationConfig :: any).LaunchSafe[gate] == true", "CLAUDE-BUD J12: Launched = LaunchAll AND the gate is in LaunchSafe")
_cbl_ls = re.search(r"\tLaunchSafe = \{(.*?)\n\t\}", read(_cbl_mc) or "", re.S)
_cbl_safe = set(re.findall(r"\t\t(\w+) = true", _cbl_ls.group(1))) if _cbl_ls else set()
(ok if {"Sales", "VIPPerks", "Placement", "Retention"} <= _cbl_safe and not ({"Balance", "Army", "BodyRollout", "AircraftWeapons"} & _cbl_safe) else bad)(
    f"CLAUDE-BUD J12: LaunchSafe holds the safe gates only (not the balance curve / army / bodies / aircraft weapons) {sorted(_cbl_safe)}")
must_contain("src/ServerScriptService/Server/Services/VehicleService.luau", "local isOwner = VehicleService._IsPlaytestOwner(player) and MonetizationConfig.LaunchAll ~= true", "CLAUDE-BUD J12: no owner shortcut for premium vehicles at launch")
must_contain("src/ServerScriptService/Server/Services/VehicleService.luau", "MC.GarageSlot.OwnerTest == true and MC.LaunchAll ~= true", "CLAUDE-BUD J12: no Extra Garage Slot owner test at launch")
must_contain("src/ServerScriptService/Server/Services/PremiumWeaponService.luau", "local ownerTest = AdminConfig.IsPlaytestOwner(player.UserId) and (MonetizationConfig :: any).LaunchAll ~= true", "CLAUDE-BUD J12: no premium weapons owner shortcut at launch")
_cbl_spec = _cbl_il.spec_from_file_location("cbl_launch_audit", "tools/launch_audit.py")
_cbl_la = _cbl_il.module_from_spec(_cbl_spec)
_cbl_spec.loader.exec_module(_cbl_la)
_cbl_rows = _cbl_la.audit()
_cbl_bad = [r[0] for r in _cbl_rows if not r[6]]
(ok if not _cbl_bad else bad)(f"CLAUDE-BUD J12: every live, sold product has a prompt and a server grant ({len(_cbl_rows)} items; bad {_cbl_bad})")
(ok if all(_cbl_la.RECEIPT.values()) else bad)(f"CLAUDE-BUD J12: receipts idempotent, saved before the ack, passes re-checked ({_cbl_la.RECEIPT})")
_cbl_luau = _cbl_os.environ.get("LUAU")
if not _cbl_luau and _cbl_os.environ.get("LUAU_COMPILE"):
    _cbl_d = _cbl_os.path.dirname(_cbl_os.environ["LUAU_COMPILE"])
    for _n in ("luau.exe", "luau"):
        if _cbl_os.path.exists(_cbl_os.path.join(_cbl_d, _n)):
            _cbl_luau = _cbl_os.path.join(_cbl_d, _n)
if _cbl_luau:
    _cbl_r = _cbl_sp.run([_cbl_sys.executable, "tools/launch_gate_test.py"], capture_output=True, text=True, env=dict(_cbl_os.environ, LUAU=_cbl_luau), timeout=180)
    _cbl_n = _cbl_r.stdout.count("\nPASS ") + _cbl_r.stdout.startswith("PASS ")
    (ok if _cbl_r.returncode == 0 and _cbl_n >= 80 else bad)(f"CLAUDE-BUD J12: launch gates executed (Luau): owner / non-owner x LaunchAll off / on, {_cbl_n} checks, exit {_cbl_r.returncode}")
else:
    ok("CLAUDE-BUD J12: launch gate execution skipped (no luau CLI next to LUAU_COMPILE)")
