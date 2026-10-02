"""claude-bud JOB 50 part D (2026-10-01): hotbar weapon captions overlapped on the phone ("HAVOC" "LONGSHOT" "LONGSHOT"
"QUAKE" running into each other).

ROOT CAUSE (from the source + the real HudConfig numbers): each slot's WeaponName box was slot + Gap + 4 wide (80 v in a
64 v slot, so 8 v into each 12 v gap: two neighbours' boxes overlapped by 4 v), with TextScaled stretching an 8-letter
name across the whole box; and two pairs of weapons shared a caption (LongshotDMR / LongshotSniper "LONGSHOT",
HavocLauncher / HavocRotary "HAVOC").
NOW: the caption box is slot - 4 (inside its own slot: a positive gap to the neighbour's box), sized by fitCaption
(NameSize down to CaptionMinTextPx real px, then "…"), and every weapon has a distinct ShortName.
Run: python tools/sim/run_hotbar_caption_test.py   (exit 1 on any failure)"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HUD = (ROOT / "src/ReplicatedStorage/Shared/Configs/HudConfig.luau").read_text(encoding="utf-8")
CC = (ROOT / "src/StarterPlayer/StarterPlayerScripts/Client/Controllers/CombatController.luau").read_text(encoding="utf-8").replace("\r\n", "\n")
WC = (ROOT / "src/ReplicatedStorage/Shared/Configs/WeaponConfig.luau").read_text(encoding="utf-8")
fails = 0


def check(ok, msg):
    global fails
    print(("ok    " if ok else "FAIL  ") + msg)
    if not ok:
        fails += 1


hb = HUD.split("HudConfig.Hotbar = {")[1]
slot = int(re.search(r"\n\tSlot = (\d+)", hb).group(1))
gap = int(re.search(r"\n\tGap = (\d+)", hb).group(1))
old_w = slot + gap + 4
old_overlap = 2 * (old_w - slot) / 2 - gap
check(old_overlap > 0, "BEFORE: a %d v caption box in a %d v slot with a %d v gap: neighbouring boxes overlapped by %d v" % (old_w, slot, gap, old_overlap))
ms = CC.split("local function makeSlot")[1].split("\nend\n")[0]
check('name.Size = UDim2.new(1, -4, 0, nameSize + 4)' in ms and "name.TextScaled = false" in ms and "Enum.TextTruncate.AtEnd" in ms,
      "AFTER: the caption box is slot - 4 (%d v: %d v clear of the neighbour's box), no TextScaled stretch, truncates cleanly" % (slot - 4, gap + 4))
check("fitCaption(sl.Name, shortName(id))" in CC and "CaptionMinTextPx" in CC.split("local function fitCaption")[1].split("\nend\n")[0],
      "fitCaption sizes each name to fit its slot, floor = CaptionMinTextPx real px (the documented caption exception)")
names = {}
for m in re.finditer(r'Id = "(\w+)",[^\n]*?ShortName = "([^"]+)"', WC):
    names[m.group(1)] = m.group(2)
for m in re.finditer(r'rebirthGun\("\w+", "(\w+)", "[^"]+", "([^"]+)"', WC):
    names[m.group(1)] = m.group(2)
seen = {}
dups = []
for wid, sn in names.items():
    if sn in seen:
        dups.append("%s=%s=%s" % (seen[sn], wid, sn))
    seen[sn] = wid
check(not dups and names.get("LongshotDMR") == "DMR" and names.get("HavocLauncher") == "HAVOC RL",
      "every named weapon has a distinct ShortName (DMR vs LONGSHOT, HAVOC RL vs HAVOC) %s" % (dups or ""))
print("HOTBAR CAPTION TEST: %d failed" % fails)
sys.exit(1 if fails else 0)
