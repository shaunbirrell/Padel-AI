"""claude-bud JOB 24: build + run the army ATTACK simulation (tools/sim/army_attack_sim.luau) in the Luau CLI, once with
the v116 ATTACK movement ("old") and once with the real FormationController / SoldierController attack mode ("new").
Used by tools/checks/claude_bud_armyattack.py; `python tools/sim/run_attack_sim.py` prints both tables."""
import os
import subprocess
import tempfile
from pathlib import Path

import run_army_sim as _R

SIM = Path(__file__).resolve().parent / "army_attack_sim.luau"


def build(mode="new"):
    sc = _R.SC.read_text(encoding="utf-8")
    code = SIM.read_text(encoding="utf-8")
    code = code.replace("--@@FC@@", _R.FC.read_text(encoding="utf-8"))
    code = code.replace("--@@SC@@", sc[sc.find("local SoldierController = {}"):])
    code = code.replace("--@@CFG@@", _R.follow3_lua()[0])
    code = code.replace('local MODE = "new" --@@MODE@@', f'local MODE = "{mode}"')
    return code


def run(mode="new", timeout=300):
    luau = _R.find_luau()
    if not luau:
        return None
    with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False, encoding="utf-8") as fh:
        fh.write(build(mode))
        tmp = fh.name
    try:
        r = subprocess.run([luau, tmp], capture_output=True, text=True, timeout=timeout, encoding="utf-8", errors="replace")
        return (r.stdout or "") + (r.stderr or "")
    finally:
        os.unlink(tmp)


def metrics(out):
    res = {}
    for line in (out or "").splitlines():
        if line.startswith("ATTACK,"):
            parts = line.split(",")
            res[parts[2]] = {kv.split("=")[0]: float(kv.split("=")[1]) for kv in parts[3:]}
    return res


if __name__ == "__main__":
    for mode in ("old", "new"):
        o = run(mode)
        print(o if o is not None else "no luau CLI")
