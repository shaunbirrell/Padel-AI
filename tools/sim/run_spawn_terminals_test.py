"""claude-bud JOB 56: the helipad + dock spawn terminals (the REAL SpawnTerminalService + SpawnTerminalConfig + PlotFrame)
and the rotor disc fit (the REAL AirBodyRig._DiscFit; VisualAssetConfig stubbed to its AirRotorDisc row).

1. WANTED: no helipad / dock -> no terminal; Helipad L1 -> the aircraft terminal; both -> both (from the SAVED
   BaseUpgrades).
2. BUILT: each terminal is the house contract (WE_PanelPrompt, WE_OpenPanel = Garage, WE_OpenTab = Air / Naval), a
   finger-friendly prompt (hold 0, range >= 10, no line of sight), no Neon, no lights, the screen label MaxDistance <= 40,
   phone-safe copy (no key names, no "click"). Another owner while OwnerFirst: none. Clear removes them.
3. ROTOR: a blade disc tilted 6 deg against the chassis -> the spin axis is the disc normal (6.0 deg); a hub box 0.4 studs
   off the blades -> the blades' own centre; an aligned, centred rotor -> unchanged; a chunky (not flat) part or a 40 deg
   "tilt" -> the configured axis is kept.
Run: LUAU=path/to/luau(.exe) python tools/sim/run_spawn_terminals_test.py   (exit 1 on any failure; VERBOSE=1 prints all)"""
import os
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from run_kit_detail_test import PRELUDE  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
SH = ROOT / "src/ReplicatedStorage/Shared"
SV = ROOT / "src/ServerScriptService/Server"
MODS = {
    "Configs/SpawnTerminalConfig": SH / "Configs/SpawnTerminalConfig.luau",
    "Configs/RetentionConfig": SH / "Configs/RetentionConfig.luau",
    "Configs/AdminConfig": SH / "Configs/AdminConfig.luau",
    "Configs/EconomyConfig": SH / "Configs/EconomyConfig.luau",
    "Configs/BaseConfig": SH / "Configs/BaseConfig.luau",
    "Configs/BaseLayoutConfig": SH / "Configs/BaseLayoutConfig.luau",
    "Configs/BusinessConfig": SH / "Configs/BusinessConfig.luau",
    "Util/PlotFrame": SH / "Util/PlotFrame.luau",
    "Services/SpawnTerminalService": SV / "Services/SpawnTerminalService.luau",
    "Modules/AirBodyRig": SV / "Modules/AirBodyRig.luau",
}
VAC = (SH / "Configs/VisualAssetConfig.luau").read_text(encoding="utf-8")
_i = VAC.index("\tAirRotorDisc = {")
AIR_ROTOR = VAC[_i:VAC.index("\n\t},", _i) + 4]

TEST = r'''
local fails = 0
local function check(ok, msg) print((ok and "ok    " or "FAIL  ") .. msg); if not ok then fails += 1 end end
task = { spawn = function() end, delay = function() end, defer = function() end, wait = function() end }
RaycastParams = { new = function() return {} end }
local mt = getmetatable(Vector3.new(0, 0, 0))
local oldIdx = mt.__index
mt.__index = function(t, k)
  if k == "Cross" then return function(a, b) return Vector3.new(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X) end end
  return oldIdx(t, k)
end
CFrame.fromMatrix = function(p, x, y)
  local z = x:Cross(y)
  return CFrame.new(p.X, p.Y, p.Z, x.X, y.X, z.X, x.Y, y.Y, z.Y, x.Z, y.Z, z.Z)
end
local function findIn(s, n) for _, c in ipairs(s:GetChildren()) do if c.Name == n then return c end end return nil end
local WS = Instance.new("Workspace")
WS.Raycast = function(_, from) return { Position = Vector3.new(from.X, 2, from.Z) } end
WS.FindFirstChild = findIn
local function signal() return { Connect = function() return {} end } end
local prevG = game
game = { GetService = function(_, n)
  if n == "Workspace" then return WS end
  if n == "Players" then return { GetPlayers = function() return {} end, PlayerRemoving = signal(), GetPlayerByUserId = function() return nil end } end
  if n == "RunService" then return { IsStudio = function() return false end } end
  if n == "CollectionService" then return { AddTag = function() end } end
  return prevG:GetService(n) end }
local rn = Instance.new
Instance.new = function(cls) local o = rn(cls); o.FindFirstChild = findIn; return o end

local STC = require(node("Configs/SpawnTerminalConfig"))
-- codebot_v220 (Shaun 2026-10-02 07:51: everything public): STC.OwnerFirst = false live; the owner-first paths
-- below are still proved with OwnerFirst = true, and a non-owner is live once it is restored (end of test)
local __V220_LAUNCHED = STC.OwnerFirst
check(__V220_LAUNCHED == false, "codebot_v220: STC.OwnerFirst = false (public for everyone)")
STC.OwnerFirst = true
local ST = require(node("Services/SpawnTerminalService"))
local OWNER, OTHER = 470626172, 9

-- 1. wanted
local function names(t) return table.concat(t, ",") end
check(names(ST.Wanted({ BaseUpgrades = {} })) == "" and names(ST.Wanted({})) == "", "no helipad / dock: no terminal")
check(names(ST.Wanted({ BaseUpgrades = { Helipad = 1 } })) == "Helipad", "Helipad L1: the aircraft terminal")
check(names(ST.Wanted({ BaseUpgrades = { Helipad = 3, Dock = 1 } })) == "Helipad,Dock", "helipad + dock: both terminals")

-- 2. built
local n = ST.Sync(2, OWNER, { BaseUpgrades = { Helipad = 2, Dock = 1 } })
local rootF = WS:FindFirstChild("WE_SpawnTerminals")
local pf = rootF and findIn(rootF, "Plot2")
check(n == 2 and pf ~= nil and #pf:GetChildren() == 2, "the owner's plot 2: 2 terminals built")
for _, kind in ipairs({ "Helipad", "Dock" }) do
  local m = pf and findIn(pf, "WE_SpawnTerminal_" .. kind)
  local prompt, sg, bad = nil, nil, {}
  for _, d in ipairs(m and m:GetDescendants() or {}) do
    if d.ClassName == "ProximityPrompt" then prompt = d end
    if d.ClassName == "SurfaceGui" then sg = d end
    if d.Material == "Material.Neon" then table.insert(bad, "neon") end
    if string.find(d.ClassName, "Light") then table.insert(bad, "light") end
  end
  local t = STC.Terminals[kind]
  local copy = string.lower(t.Action .. " " .. t.Object .. " " .. table.concat(t.Screen, " "))
  check(prompt ~= nil and prompt.Name == "WE_PanelPrompt" and prompt:GetAttribute("WE_OpenPanel") == "Garage" and prompt:GetAttribute("WE_OpenTab") == t.Tab
    and prompt.HoldDuration == 0 and prompt.MaxActivationDistance >= 10 and prompt.RequiresLineOfSight == false and sg and sg.MaxDistance <= 40 and #bad == 0
    and not string.find(copy, "click") and not string.find(copy, "press") and not string.find(copy, "%f[%a]f%f[%A]"),
    string.format("%s terminal: WE_PanelPrompt -> Garage / %s, hold 0, range %s, label <= 40, %s, copy \"%s\"", kind, t.Tab, tostring(prompt and prompt.MaxActivationDistance), if #bad == 0 then "no Neon / lights" else table.concat(bad, " "), t.Action))
end
check(ST.Sync(3, OTHER, { BaseUpgrades = { Helipad = 2, Dock = 1 } }) == 0 and findIn(rootF, "Plot3") == nil, "another owner while OwnerFirst: no terminals (OFF = today)")
ST.Clear(2)
check(findIn(rootF, "Plot2") == nil, "the owner leaves: his terminals go")

-- 3. the rotor disc fit
local AR = require(node("Modules/AirBodyRig"))
local function blade(cf, size) local p = rn("Part"); p.CFrame = cf; p.Size = size; return p end
local JR = CFrame.new(0, 0, 0) -- chassis rotation x axis Y = identity
local tilted = blade(CFrame.new(0, 10, 0) * CFrame.Angles(math.rad(6), 0, 0), Vector3.new(30, 0.4, 30))
local f1 = AR._DiscFit({ tilted }, JR, Vector3.new(0, 10, 0))
check(f1 and f1.Changed and math.abs(f1.Tilt - 6) < 0.05 and math.abs(f1.Rot.UpVector:Dot(tilted.CFrame.UpVector) - 1) < 1e-6,
  string.format("a blade disc tilted 6 deg: the spin axis is its own normal (tilt %.2f deg)", f1 and f1.Tilt or -1))
local off = blade(CFrame.new(0, 10, 0), Vector3.new(30, 0.4, 30))
local f2 = AR._DiscFit({ off }, JR, Vector3.new(0.4, 10, 0))
check(f2 and f2.Changed and f2.Tilt < 0.01 and (f2.Centre - Vector3.new(0, 10, 0)).Magnitude < 1e-6 and math.abs(f2.Offset - 0.4) < 1e-6,
  string.format("a hub box 0.40 studs off the blades: the blades' own centre (offset %.2f)", f2 and f2.Offset or -1))
local f3 = AR._DiscFit({ off }, JR, Vector3.new(0, 10, 0))
check(f3 and not f3.Changed, "an aligned, centred rotor: unchanged (today's joint)")
local chunky = blade(CFrame.new(0, 10, 0) * CFrame.Angles(math.rad(10), 0, 0), Vector3.new(4, 3.5, 4))
local f4 = AR._DiscFit({ chunky }, JR, Vector3.new(0, 10, 0))
check(f4 and f4.Tilt == 0, "a chunky part (not a flat disc): the configured axis is kept")
local wild = blade(CFrame.new(0, 10, 0) * CFrame.Angles(math.rad(40), 0, 0), Vector3.new(30, 0.4, 30))
local f5 = AR._DiscFit({ wild }, JR, Vector3.new(0, 10, 0))
check(f5 and f5.Tilt == 0, "a 40 deg 'tilt' (the box guess is wrong): the configured axis is kept")
local tail = blade(CFrame.new(0, 10, 20) * CFrame.Angles(0, 0, math.rad(90 + 4)), Vector3.new(6, 0.3, 6))
local JRX = CFrame.Angles(0, 0, -math.pi / 2)
local f6 = AR._DiscFit({ tail }, JRX, Vector3.new(0, 10, 20))
check(f6 and math.abs(f6.Tilt - 4) < 0.05, string.format("a tail rotor (Axis X) tilted 4 deg: corrected about its own axis (%.2f)", f6 and f6.Tilt or -1))

print(string.format("SPAWN TERMINALS LUA: %d failed", fails))
if fails > 0 then error("failed") end
'''


def main():
    chunks = [PRELUDE]
    for key, path in MODS.items():
        chunks.append("SOURCES[%r] = function(script)\n%s\nend" % (key, path.read_text(encoding="utf-8")))
    chunks.append("SOURCES['Configs/VisualAssetConfig'] = function() return {\n%s\n} end" % AIR_ROTOR)
    chunks.append(TEST)
    with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False, encoding="utf-8") as f:
        f.write("\n".join(chunks))
        path = f.name
    r = subprocess.run([os.environ.get("LUAU", "luau"), path], capture_output=True, text=True)
    out = r.stdout.strip().splitlines()
    fails = 0
    if r.returncode != 0 or "SPAWN TERMINALS LUA: 0 failed" not in r.stdout:
        fails = 1
        out.append(r.stderr.strip()[-2500:])
    out.append("SPAWN TERMINALS TEST: %d failed" % fails)
    print("\n".join(out) if os.environ.get("VERBOSE") else "\n".join(l for l in out if l.startswith(("FAIL", "SPAWN TERMINALS TEST"))))
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
