"""claude-bud JOB 44: build J44Test.rbxl = the normal game (default.project.json) + the test-only J44Driver Script.
The game source is not changed; the driver never reaches default.project.json or the live place.
Run: python tools/studio/build_j44_place.py [out_dir]   (default: build/j44, gitignored)"""
import json
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
out = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "build" / "j44"
out.mkdir(parents=True, exist_ok=True)
proj = json.loads((ROOT / "default.project.json").read_text(encoding="utf-8"))


def absolute(node):
    if isinstance(node, dict):
        for k, v in list(node.items()):
            if k == "$path" and isinstance(v, str):
                node[k] = (ROOT / v).as_posix()
            else:
                absolute(v)


absolute(proj)
proj["name"] = "WarEmpireJ44Test"
proj["tree"]["ServerScriptService"]["J44Driver"] = {"$path": (ROOT / "tools/studio/J44Driver.server.luau").as_posix()}
pj = out / "j44.project.json"
pj.write_text(json.dumps(proj, indent=1), encoding="utf-8")
rojo = os.environ.get("ROJO", "rojo")
r = subprocess.run([rojo, "build", str(pj), "-o", str(out / "J44Test.rbxl")], capture_output=True, text=True)
print(r.stdout.strip() or r.stderr.strip())
sys.exit(r.returncode)
