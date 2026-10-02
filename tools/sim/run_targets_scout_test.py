"""claude-bud JOB 47 (2026-10-01): TARGETS card gone + scout report did nothing + the ghost label behind INTEL OFFICE.

1. GHOST (the real BaseMarkerConfig): replays Shaun's v170 screenshot geometry (956x440 phone, 1024x471 test window,
   the 58 px Roblox top-bar row). A far base tag at y ~34 px sat inside the top row: the old rule (VisibleSet only)
   showed it; InTopBar hides it, and a tag below the row still shows. The controller applies the rule before VisibleSet.
2. TARGETS card + scout report: fixed by Code Bot v171 (crosshair nil AnchorPoint killed build(); scout result card,
   saved report, charge after build). Re-runs its proofs (run_codebot_v171_test, run_endgame_test) and checks the
   Recruit Pack lead is ruled out (the offer card destroys itself on BUY / later / X, so it cannot keep TARGETS hidden).
Run: LUAU=path/to/luau(.exe) python tools/sim/run_targets_scout_test.py   (exit 1 on any failure)"""
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from run_kit_detail_test import PRELUDE  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
SH = ROOT / "src/ReplicatedStorage/Shared"
CL = ROOT / "src/StarterPlayer/StarterPlayerScripts/Client"
MODS = {
    "Configs/BaseMarkerConfig": SH / "Configs/BaseMarkerConfig.luau",
    "Configs/RetentionConfig": SH / "Configs/RetentionConfig.luau",
    "Configs/AdminConfig": SH / "Configs/AdminConfig.luau",
}

TEST = r'''
local fails = 0
local function check(ok, msg) print((ok and "ok    " or "FAIL  ") .. msg); if not ok then fails += 1 end end
local BM = require(node("Configs/BaseMarkerConfig"))
local TOP = 58 -- the Roblox top-bar row (GetGuiInset().Y) on phones and at 1024x471
for _, vp in ipairs({ { 956, 440, "owner phone 956x440" }, { 1024, 471, "1024x471" }, { 1920, 1080, "desktop 1920x1080" } }) do
  -- the screenshot: the ghost tag (flag + "Mich_72..") centred ~34 px down at the right, under the INTEL OFFICE pill
  local ghost = { Key = "ghost", Dist = 1200, X = vp[1] * 0.80, Y = 34, W = 96, H = BM.PillHeight }
  local before = BM.VisibleSet({ ghost })
  check(before.ghost == true, vp[3] .. ": BEFORE the old rule showed a tag inside the top-bar row (the ghost)")
  check(BM.InTopBar(ghost.Y, ghost.H, TOP), vp[3] .. ": AFTER the tag inside the top-bar row hides")
  check(BM.InTopBar(TOP + 2, BM.PillHeight, TOP), vp[3] .. ": a tag whose top edge still reaches into the row hides")
  check(not BM.InTopBar(TOP + BM.TopBarPadPx + BM.PillHeight / 2 + 1, BM.PillHeight, TOP) and not BM.InTopBar(vp[2] * 0.35, BM.PillHeight * 1.2, TOP),
    vp[3] .. ": a tag below the row (in the sky over the play view) still shows")
end
check(BM.InTopBar(10, 24, 0) and not BM.InTopBar(40, 24, 0), "no inset reported: only the very top edge is kept clear")
print(string.format("GHOST: %d failed", fails))
GHOST_FAILS = fails
'''


def luau_part(luau):
    chunks = [PRELUDE]
    for key, path in MODS.items():
        chunks.append("SOURCES[%r] = function(script)\n%s\nend" % (key, path.read_text(encoding="utf-8")))
    chunks.append(TEST)
    with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False, encoding="utf-8") as f:
        f.write("\n".join(chunks))
        path = f.name
    r = subprocess.run([luau, path], capture_output=True, text=True)
    print(r.stdout.strip())
    if r.returncode != 0:
        print(r.stderr.strip()[-2000:])
    m = re.search(r"GHOST: (\d+) failed", r.stdout)
    return int(m.group(1)) if (m and r.returncode == 0) else 1


def main():
    luau = os.environ.get("LUAU", "luau")
    fails = luau_part(luau)

    def check(ok, msg):
        nonlocal fails
        print(("ok    " if ok else "FAIL  ") + msg)
        if not ok:
            fails += 1

    k = (CL / "Controllers/BaseMarkerController.luau").read_text(encoding="utf-8")
    step = k.split("local function step()")[1].split("\nend\n")[0]
    check("B.InTopBar(v.Y, h, topPx)" in step and step.index("B.InTopBar") < step.index("B.VisibleSet(list)")
          and "GetGuiInset" in step and "TopbarInset" in step,
          "the controller drops top-bar tags BEFORE VisibleSet, with the live inset (viewport px, same space as WorldToViewportPoint)")
    rp = (CL / "Controllers/RecruitPackController.luau").read_text(encoding="utf-8")
    check(re.search(r"buy\.Activated:Connect\(function\(\).*?close\(\)", rp, re.S) is not None and "g:Destroy()" in rp,
          "lead ruled out: the Recruit Pack offer card destroys itself on BUY (it cannot keep TARGETS hidden after a purchase)")
    env = dict(os.environ, LUAU=luau)
    for script, tag in (("run_codebot_v171_test.py", "CODEBOT V171 TEST: 0 failed"),):
        r = subprocess.run([sys.executable, str(ROOT / "tools/sim" / script)], capture_output=True, text=True, env=env, cwd=str(ROOT))
        check(r.returncode == 0 and tag in r.stdout, "%s (TARGETS card builds + shows, scout result card / saved / charge after build)" % script)
    r = subprocess.run([sys.executable, str(ROOT / "tools/sim/run_endgame_test.py")], capture_output=True, text=True, env=env, cwd=str(ROOT))
    check(r.returncode == 0 and "ENDGAME TEST: 0 failed" in r.stdout, "run_endgame_test.py (incl. the v171 scout checks) 0 failed")
    print("TARGETS SCOUT TEST: %d failed" % fails)
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
