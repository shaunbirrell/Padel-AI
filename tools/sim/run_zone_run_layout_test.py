"""claude-bud JOB 69 B: the zone-run how-to card layout on phones, on the REAL ZoneRunController.CardLayout (+ PillText).

At 1024x471 (the brief), 956x440 (Shaun), 844x390, 800x360 and 1180x820, full and compact: START / CANCEL are >= 44 real px
tall, never in the thumbstick zone (left 40 % x lower 2/3), never near the jump / fire corner (the bottom-right 130 x 130: the Roblox jump button + 16 px clear + the fire button),
inside the screen, below the top bar (58 px), and START / CANCEL never overlap each other.
Run: LUAU=path/to/luau(.exe) python tools/sim/run_zone_run_layout_test.py   (exit 1 on any failure; VERBOSE=1 prints all)"""
import os
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from run_kit_detail_test import PRELUDE  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
CL = ROOT / "src/StarterPlayer/StarterPlayerScripts/Client"

TEST = r'''
local fails = 0
local function check(ok, msg) print((ok and "ok    " or "FAIL  ") .. msg); if not ok then fails += 1 end end
local Z = require(node("Controllers/ZoneRunController"))
local function ov(a, b) return a[1] < b[3] and b[1] < a[3] and a[2] < b[4] and b[2] < a[4] end
for _, vp in ipairs({ { 1024, 471 }, { 956, 440 }, { 844, 390 }, { 800, 360 }, { 1180, 820 } }) do
  for _, compact in ipairs({ false, true }) do
    local W, H = vp[1], vp[2]
    local scale, cx, cy, start, cancel = Z.CardLayout(W, H, compact)
    local ch = (if compact then 210 else 330) * scale
    local thumb = { 0, H / 3, W * 0.4, H }
    local jump = { W - 130, H - 130, W, H }
    local bad = {}
    for name, b in pairs({ START = start, CANCEL = cancel }) do
      if b[4] - b[2] < 44 then table.insert(bad, name .. " < 44 px") end
      if ov(b, thumb) then table.insert(bad, name .. " in the thumbstick zone") end
      if ov(b, jump) then table.insert(bad, name .. " by the jump / fire corner") end
      if b[1] < 0 or b[3] > W or b[4] > H then table.insert(bad, name .. " off screen") end
    end
    if cy - ch / 2 < 58 then table.insert(bad, "card under the top bar") end
    if ov(start, cancel) then table.insert(bad, "START overlaps CANCEL") end
    check(#bad == 0, string.format("%dx%d %s: scale %.2f, buttons %.0f px tall%s", W, H, if compact then "compact" else "full", scale, start[4] - start[2], if #bad == 0 then "" else " -> " .. table.concat(bad, ", ")))
  end
end
check(Z.PillText("Drill Course", 2, 4, 23) == "DRILL COURSE 2/4 · 0:23", "the progress pill: " .. Z.PillText("Drill Course", 2, 4, 23))
print(string.format("ZONE RUN LAYOUT LUA: %d failed", fails))
if fails > 0 then error("failed") end
'''


def main():
    chunks = [PRELUDE, "SOURCES['Controllers/ZoneRunController'] = function(script)\n%s\nend" % (CL / "Controllers/ZoneRunController.luau").read_text(encoding="utf-8"), TEST]
    with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False, encoding="utf-8") as f:
        f.write("\n".join(chunks))
        path = f.name
    r = subprocess.run([os.environ.get("LUAU", "luau"), path], capture_output=True, text=True, timeout=100)
    out = r.stdout.strip().splitlines()
    fails = 0
    if r.returncode != 0 or "ZONE RUN LAYOUT LUA: 0 failed" not in r.stdout:
        fails = 1
        out.append(r.stderr.strip()[-2000:])
    out.append("ZONE RUN LAYOUT TEST: %d failed" % fails)
    print("\n".join(out) if os.environ.get("VERBOSE") else "\n".join(l for l in out if l.startswith(("FAIL", "ZONE RUN LAYOUT TEST"))))
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
