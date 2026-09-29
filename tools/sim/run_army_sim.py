"""v115 (Code Bot Roblox): build + run the army-follow acceptance simulation (tools/sim/army_follow_sim.luau) in the
Luau CLI against the REAL FormationController / SoldierController / ArmyConfig.Follow3. Used by
tools/checks/codebot_v115_army.py (metrics + thresholds) and tools/sim/plot_army_sim.py (PNG plots)."""
import os
import re
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FC = ROOT / "src/ReplicatedStorage/Shared/Util/FormationController.luau"
SC = ROOT / "src/ServerScriptService/Server/Modules/SoldierController.luau"
CFG = ROOT / "src/ReplicatedStorage/Shared/Configs/ArmyConfig.luau"
SIM = ROOT / "tools/sim/army_follow_sim.luau"


def follow3_block():
    t = CFG.read_text(encoding="utf-8")
    i = t.find("\tFollow3 = {")
    return t[i:t.find("\n\t},", i)] if i >= 0 else ""


def follow3_lua():
    vals = {}
    for m in re.finditer(r"\n\t\t(\w+) = (-?[\d.]+|true|false|\"\w+\"),", follow3_block()):
        vals[m.group(1)] = m.group(2)
    return "{ " + ", ".join(f"{k} = {v}" for k, v in vals.items()) + " }", vals


def find_luau():
    c = os.environ.get("LUAU")
    if c and os.path.exists(c):
        return c
    if os.environ.get("LUAU_COMPILE"):
        c = os.path.join(os.path.dirname(os.environ["LUAU_COMPILE"]), "luau")
        if os.path.exists(c):
            return c
    c = os.path.expanduser("~/.local/bin/luau")
    return c if os.path.exists(c) else None


def build(trace=()):
    sc = SC.read_text(encoding="utf-8")
    sc_body = sc[sc.find("local SoldierController = {}"):]
    code = SIM.read_text(encoding="utf-8")
    code = code.replace("--@@FC@@", FC.read_text(encoding="utf-8"))
    code = code.replace("--@@SC@@", sc_body)
    code = code.replace("--@@CFG@@", follow3_lua()[0])
    code = code.replace("--@@TRACE@@", ", ".join(f"{n} = true" for n in trace))
    return code


def run(trace=(), timeout=300):
    luau = find_luau()
    if not luau:
        return None
    with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False) as fh:
        fh.write(build(trace))
        tmp = fh.name
    try:
        r = subprocess.run([luau, tmp], capture_output=True, text=True, timeout=timeout)
        return (r.stdout or "") + (r.stderr or "")
    finally:
        os.unlink(tmp)


def metrics(out):
    res = {}
    for line in out.splitlines():
        if line.startswith("METRIC,"):
            parts = line.split(",")
            d = {}
            for kv in parts[2:]:
                k, v = kv.split("=")
                d[k] = float(v)
            res[parts[1]] = d
    return res


if __name__ == "__main__":
    o = run()
    print(o if o is not None else "no luau CLI")
