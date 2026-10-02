"""v124 (Code Bot Roblox): runs the REAL FormationController.PickTarget / PickTargetTiered under the luau CLI (a tiny
Vector3 shim) on the phone-bug geometry: the ATTACK army deployed at AttackStandoff 36 from a sticky bank-guard target,
an enemy player at d studs from the army centre. Returns the rows [(d, v123 pick, v124 pick)] + regression results."""
import os, shutil, subprocess, tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SHIM = """local V = {}
V.__index = V
local function new(x, y, z) return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0, Magnitude = math.sqrt((x or 0) ^ 2 + (y or 0) ^ 2 + (z or 0) ^ 2) }, V) end
V.__sub = function(a, b) return new(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
V.__add = function(a, b) return new(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
local Vector3 = { new = new, zero = new(0, 0, 0), xAxis = new(1, 0, 0), yAxis = new(0, 1, 0), zAxis = new(0, 0, 1) }
local CFrame = setmetatable({}, { __index = function() return function() return {} end end })
"""
SIM = """local FC = require("./FC")
local function v(x, z) return { X = x, Y = 0, Z = z } end
local cfg = { AttackAggroStuds = 120, AttackKeepExtraStuds = 20, AttackRetargetStuds = 15 }
local c0 = v(0, 0)
for _, d in ipairs({ 5, 15, 20, 25, 30, 45, 60, 100 }) do
	local cands = { { Key = "Guard", Pos = v(0, 36), Pri = 0 }, { Key = "Guard2", Pos = v(8, 40), Pri = 0 }, { Key = "Stevie", Pos = v(d, 0), Pri = 1 } }
	print(("ROW %d %s %s"):format(d, tostring(FC.PickTarget("Guard", cands, c0, cfg)), tostring((FC.PickTargetTiered("Guard", cands, c0, cfg)))))
end
local A, B, C = { Key = "A", Pos = v(0, 36) }, { Key = "B", Pos = v(0, 30) }, { Key = "C", Pos = v(0, 10) }
print("REG npc_sticky " .. tostring(FC.PickTargetTiered("A", { A, B }, c0, cfg) == FC.PickTarget("A", { A, B }, c0, cfg)))
print("REG npc_retarget " .. tostring(FC.PickTargetTiered("A", { A, B, C }, c0, cfg) == "C"))
print("REG far_player_ignored " .. tostring(FC.PickTargetTiered("A", { A, { Key = "P", Pos = v(130, 0), Pri = 1 } }, c0, cfg) == "A"))
print("REG cur_player_kept_in_keep_band " .. tostring(FC.PickTargetTiered("P", { A, { Key = "P", Pos = v(135, 0), Pri = 1 } }, c0, cfg) == "P"))
print("REG players_sticky " .. tostring(FC.PickTargetTiered("P1", { { Key = "P1", Pos = v(0, 30), Pri = 1 }, { Key = "P2", Pos = v(0, 20), Pri = 1 } }, c0, cfg) == "P1"))
print("REG aggressor_first " .. tostring(FC.PickTargetTiered("P1", { { Key = "P1", Pos = v(0, 10), Pri = 1 }, { Key = "P2", Pos = v(0, 90), Pri = 2 } }, c0, cfg) == "P2"))
print("REG empty " .. tostring(FC.PickTargetTiered(nil, {}, c0, cfg) == nil))
"""


def luau_bin():
    for c in (os.environ.get("LUAU_BIN"), str(Path.home() / ".local/bin/luau"), shutil.which("luau")):
        if c and Path(c).is_file():
            return c
    return None


def run():
    lb = luau_bin()
    if lb is None:
        return None
    src = (ROOT / "src/ReplicatedStorage/Shared/Util/FormationController.luau").read_text(encoding="utf-8")
    with tempfile.TemporaryDirectory() as d:
        (Path(d) / "FC.luau").write_text(SHIM + src, encoding="utf-8")
        (Path(d) / "sim.luau").write_text(SIM, encoding="utf-8")
        out = subprocess.run([lb, "sim.luau"], cwd=d, capture_output=True, text=True, timeout=60)
    rows, regs = [], {}
    for line in out.stdout.splitlines():
        p = line.split()
        if p and p[0] == "ROW":
            rows.append((int(p[1]), p[2], p[3]))
        elif p and p[0] == "REG":
            regs[p[1]] = p[2] == "true"
    return rows, regs, out.stderr


if __name__ == "__main__":
    print(run())
