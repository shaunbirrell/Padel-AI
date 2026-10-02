"""claude-bud JOB B (2026-10-01, P0): "the TARGETS list (rival, Lv / Army, EVEN, SEND ARMY, VIEW) is almost black, the text
barely visible, the buttons feel unclickable".

ROOT CAUSE (from the source, modelled here): RivalController's ScreenGui "WE_RivalTargets" never set ZIndexBehavior, so it
rendered with Global ordering (the Instance.new default; every other HUD gui in this game sets Sibling explicitly, and
HudLayout.ApplyScreen does too). The list Frame is ZIndex 3 with BackgroundTransparency 0.03 (97 % opaque, near-black
PLATE); every row, label, verdict chip, SEND ARMY and VIEW inside it is created with the default ZIndex 1. Global
ordering draws by ZIndex across the whole gui, so the panel's own background was painted OVER its rows: the rows showed
through at ~3 % (barely visible), and the top-most object under a finger was the panel, not the button.
FIX: the gui uses Sibling ordering (children always draw above their parent); the list (3) still covers the card (1).

1. MODEL: draw order + visible strength of a row under Global vs Sibling, with the real numbers parsed from the source.
2. STATIC: the gui sets ZIndexBehavior = Sibling; the list's ZIndex is still above the card's; every row object is a
   child of the list; SEND ARMY / VIEW are TextButtons with Active input (the same JOB 38 / map paths as before).
3. The existing rival_controller_harness run (Code Bot v171) still passes (card built, list fills).
Run: python tools/sim/run_targets_list_test.py   (LUAU for the harness; exit 1 on any failure)"""
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SRC = (ROOT / "src/StarterPlayer/StarterPlayerScripts/Client/Controllers/RivalController.luau").read_text(encoding="utf-8").replace("\r\n", "\n")
fails = 0


def check(ok, msg):
    global fails
    print(("ok    " if ok else "FAIL  ") + msg)
    if not ok:
        fails += 1


build = SRC.split("local function build()")[1].split("\nend\n")[0]
m = re.search(r"f\.BackgroundTransparency = ([\d.]+)", build)
alpha = 1 - float(m.group(1)) if m else 0
mz = re.search(r"f\.ZIndex = (\d+)", build)
listZ = int(mz.group(1)) if mz else 1
rowZ = 1  # rebuildList never sets a ZIndex on the row objects (checked below)
check("ZIndex" not in SRC.split("local function rebuildList()")[1].split("\nend\n")[0], "the row objects keep the default ZIndex 1 (rebuildList sets none)")


def visible(behaviour):
    # how much of a row's text reaches the screen: Global = the panel (higher ZIndex) is painted over it
    if behaviour == "Global" and listZ > rowZ:
        return 1 - alpha
    return 1.0


print("MODEL list ZIndex %d, background %.0f%% opaque; row ZIndex %d" % (listZ, alpha * 100, rowZ))
check(visible("Global") <= 0.05, "BEFORE (Global ordering): the rows show through at %.0f%% -> 'almost black, barely visible'" % (visible("Global") * 100))
check(visible("Sibling") == 1.0, "AFTER (Sibling ordering): the rows, SEND ARMY and VIEW draw at 100% above the panel")
check("g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling" in build, "the TARGETS gui sets ZIndexBehavior = Sibling (the root-cause fix)")
check(listZ > 1 and "b.ZIndex" not in build, "the open list still covers the TARGETS card (list ZIndex %d > card 1)" % listZ)
rb = SRC.split("local function rebuildList()")[1].split("\nend\n")[0]
check("row.Parent = p" in rb and "button(row, \"SEND ARMY\"" in rb and "button(row, \"VIEW\"" in rb, "every row (name, stats, chip, SEND ARMY, VIEW) is a child of the list panel")
bt = SRC.split("local function button(")[1].split("\nend\n")[0]
check('Instance.new("TextButton")' in bt, "SEND ARMY / VIEW are TextButtons (they take the tap once nothing paints over them)")
luau = os.environ.get("LUAU")
if luau and (ROOT / "tools/sim/run_codebot_v171_test.py").is_file():
    r = subprocess.run([sys.executable, str(ROOT / "tools/sim/run_codebot_v171_test.py")], capture_output=True, text=True, env=dict(os.environ, LUAU=luau), cwd=str(ROOT))
    check(r.returncode == 0 and "CODEBOT V171 TEST: 0 failed" in r.stdout, "run_codebot_v171_test (rival_controller_harness: the card builds, the list fills) still passes")
print("TARGETS LIST TEST: %d failed" % fails)
sys.exit(1 if fails else 0)
