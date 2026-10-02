"""claude-bud JOB 70: no walk-through dressing + one wall style on every face, on the REAL Job67DressConfig.

  * Collision: Box hull, visuals CanCollide off, hulls CanCollide + CanQuery on, LIVE FOR EVERYONE (OwnerFirst false);
    EVERY piece key in Pieces belongs to exactly one category, every BaseProps cluster piece and every wall piece the
    service places is registered, and the six named categories (sandbag, Hesco, concrete, crate, pallet, barbed wire)
    each hold at least one piece.
  * Walls: WallStyleFor(1..5) covers front / gate, sides (left + right) and rear with ONE style; the tier tables list
    all three face groups; progressive (each tier more than the one below); HescoPlan fits the real ring (3 x 317 + 2 x
    146 studs at 21.5 high, also with 2 extra gap splits) inside MaxHesco at a stretch <= HescoStretchMax, every run
    >= 1 piece; an impossible cap returns nil (the whole ring takes the fallback style, never a mix).
Run: LUAU=path/to/luau(.exe) python tools/sim/run_job70_test.py   (exit 1 on any failure; VERBOSE=1 prints all)"""
import os
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from run_kit_detail_test import PRELUDE  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
MODS = {"Configs/Job67DressConfig": ROOT / "src/ReplicatedStorage/Shared/Configs/Job67DressConfig.luau"}

TEST = r'''
local fails = 0
local function check(ok, msg) print((ok and "ok    " or "FAIL  ") .. msg); if not ok then fails += 1 end end
local J = require(node("Configs/Job67DressConfig"))
local K = J.PropCollision
check(K and K.Enabled == true and K.OwnerFirst == false, "Collision: Enabled, LIVE FOR EVERYONE (OwnerFirst = false)")
check(K.Hull == "Box" and K.VisualCanCollide == false and K.HullCanCollide == true and K.HullCanQuery == true, "Box hull on (CanCollide + CanQuery), visuals CanCollide off")
-- every piece in exactly one category
local seen = {}
for cat, keys in pairs(K.Categories) do
  for _, k in ipairs(keys) do
    check(seen[k] == nil, "piece " .. k .. " is in one category only (" .. cat .. ")")
    seen[k] = cat
    check(J.Pieces[k] ~= nil, "category " .. cat .. ": " .. k .. " is a real piece")
  end
end
local missing = {}
for k in pairs(J.Pieces) do if seen[k] == nil then table.insert(missing, k) end end
table.sort(missing)
check(#missing == 0, "every piece has a collision category" .. (if #missing > 0 then " (missing " .. table.concat(missing, ", ") .. ")" else ""))
for _, cat in ipairs({ "Sandbag", "Hesco", "Concrete", "Crate", "Pallet", "BarbedWire" }) do
  check(K.Categories[cat] and #K.Categories[cat] > 0, "category " .. cat .. " holds pieces")
end
-- every placement the service makes is registered: base prop clusters + the wall pieces
local placed, unreg = 0, {}
for kind, tiers in pairs(J.BaseProps.Kinds) do
  for t, rows in ipairs(tiers) do
    for _, row in ipairs(rows) do
      placed += 1
      if J.CategoryOf(row[1]) == nil then table.insert(unreg, kind .. "/" .. t .. "/" .. row[1]) end
    end
  end
end
for _, k in ipairs({ "HescoBlock", "SandbagLine", "SandbagStack", "SandbagStackLow", "BarbedWire", "BarbedWireB", "Blockade", "TrenchNest" }) do
  placed += 1
  if J.CategoryOf(k) == nil then table.insert(unreg, "walls/" .. k) end
end
check(#unreg == 0, string.format("all %d placements (prop clusters + wall pieces) have a category%s", placed, if #unreg > 0 then " (" .. table.concat(unreg, ", ") .. ")" else ""))
local pal = false
for _, tiers in pairs(J.BaseProps.Kinds) do for _, rows in ipairs(tiers) do for _, row in ipairs(rows) do if row[1] == "Pallet" then pal = true end end end end
check(pal, "a pallet is placed in the base prop clusters")

-- walls: one style for every face
local prev = -1
for lv = 1, 5 do
  local st = J.WallStyleFor(lv)
  local t = J.WallTier(lv)
  local faces = {}
  for _, f in ipairs(st.Faces) do faces[f] = true end
  check(faces.Gate and faces.Sides and faces.Rear and #st.Faces == 3, "L" .. lv .. " " .. t.Name .. ": style " .. st.Kind .. " on front / gate, both sides and rear")
  local cover = {}
  for _, f in ipairs(t.Hesco) do cover[f] = "Hesco" end
  for _, f in ipairs(t.Lines) do cover[f] = (cover[f] and "BOTH") or "Lines" end
  check(cover.Gate and cover.Sides and cover.Rear and cover.Gate == cover.Sides and cover.Sides == cover.Rear and cover.Gate ~= "BOTH",
    "L" .. lv .. ": the tier table lists every face with the same look (" .. tostring(cover.Gate) .. ")")
  check((st.Hesco and #t.Hesco == 3) or (not st.Hesco and #t.Lines == 3), "L" .. lv .. ": WallStyle matches the face lists")
  local score = #t.Hesco * 100 + #t.Lines * 10 + t.GateStacks + t.Wire + t.Blockades + (t.Trench and 5 or 0) + (t.CornerStacks and 3 or 0) + (st.Rows or 1)
  check(score > prev, "L" .. lv .. " is visibly more than the tier below")
  prev = score
end
check(J.WallStyleFor(0) == nil, "L0: no wall style")
for lv = 3, 5 do
  local cap = J.WallTier(lv).MaxHesco
  for _, runs in ipairs({ { 317, 317, 317, 146, 146 }, { 317, 150, 160, 317, 146, 146 }, { 317, 317, 100, 210, 146, 146 } }) do
    local s, counts = J.HescoPlan(runs, 21.5, cap)
    local total, every = 0, true
    for i in ipairs(runs) do total += (counts and counts[i] or 0); if not counts or counts[i] < 1 then every = false end end
    check(s ~= nil and s <= J.Walls.HescoStretchMax + 1e-9 and total <= cap and every,
      string.format("L%d: Hesco on all %d runs = %d pieces <= %d at stretch %.2f", lv, #runs, total, cap, s or -1))
  end
  check(cap * J.Pieces.HescoBlock.Tris <= 250000, string.format("L%d: Hesco triangle budget %d <= 250k", lv, cap * J.Pieces.HescoBlock.Tris))
end
check(J.HescoPlan({ 317, 317, 317, 146, 146 }, 21.5, 3) == nil, "a cap no ring fits -> nil (every face takes the fallback style)")
check(J.Walls.WallStyle.Hesco.FallbackStyle == "Wall" and J.Walls.WallStyle.Wall.Rows == 2, "the fallback is the 2-row sandbag wall on every face")
print(string.format("JOB70 LUA: %d failed", fails))
if fails > 0 then error("failed") end
'''


def main():
    chunks = [PRELUDE]
    for k, p in MODS.items():
        chunks.append("SOURCES['%s'] = function(script)\n%s\nend" % (k, p.read_text(encoding="utf-8")))
    chunks.append(TEST)
    with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False, encoding="utf-8") as f:
        f.write("\n".join(chunks))
        path = f.name
    r = subprocess.run([os.environ.get("LUAU", "luau"), path], capture_output=True, text=True, timeout=100)
    out = r.stdout.strip().splitlines()
    fails = 0
    if r.returncode != 0 or "JOB70 LUA: 0 failed" not in r.stdout:
        fails = 1
        out.append(r.stderr.strip()[-2000:])
    out.append("JOB70 TEST: %d failed" % fails)
    print("\n".join(out) if os.environ.get("VERBOSE") else "\n".join(l for l in out if l.startswith(("FAIL", "JOB70 TEST"))))
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
