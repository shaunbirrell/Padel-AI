"""claude-bud JOB 54: the night lighting per base, on the REAL LightingConfig + Server/Modules/NightLights (+ PlotFrame,
BaseLayoutConfig, BaseConfig) and the client NightExposureController's pure maths (stand-ins: run_kit_detail_test.PRELUDE;
the ground raycast always hits y = 0).

1. The town + the old 3 lights per plot are built at start (NightLights.Build) inside MaxLights.
2. Every OWNED plot (the owner, owner-first) gets exactly Night2.PerBaseLights more: helipad flood, dock flood, the lit
   gate sign, the beacon. Per base <= 7 night lights (<= 40, the CLAUDE.md cap); 10 owned plots + the town <= 120.
3. Every light: Shadows off, Enabled off until the night flip, tagged WE_NightLight; every second one WE_LowOff (the
   low-quality halving).
4. Another owner while OwnerFirst: nothing. The same plot again: no rebuild (no churn on a walls / Defence purchase).
   ClearPlot gives the lights back. A rebuild (NightLights.Build) brings the owned plots back.
5. Glow-only extras per plot: 4 helipad corners, 4 dock bollard lamps, 10 runway threshold lights.
6. Exposure: 0 by day (today's look), Night2.Exposure.Night at night, eased through dusk.
Run: LUAU=path/to/luau(.exe) python tools/sim/run_night_lights_test.py   (exit 1 on any failure; VERBOSE=1 prints all)"""
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
CL = ROOT / "src/StarterPlayer/StarterPlayerScripts/Client"
MODS = {
    "Configs/LightingConfig": SH / "Configs/LightingConfig.luau",
    "Configs/WorldConfig": SH / "Configs/WorldConfig.luau",
    "Configs/BaseConfig": SH / "Configs/BaseConfig.luau",
    "Configs/BaseLayoutConfig": SH / "Configs/BaseLayoutConfig.luau",
    "Configs/BusinessConfig": SH / "Configs/BusinessConfig.luau",
    "Configs/RetentionConfig": SH / "Configs/RetentionConfig.luau",
    "Configs/AdminConfig": SH / "Configs/AdminConfig.luau",
    "Configs/EconomyConfig": SH / "Configs/EconomyConfig.luau",
    "Util/PlotFrame": SH / "Util/PlotFrame.luau",
    "Modules/NightLights": SV / "Modules/NightLights.luau",
    "Controllers/NightExposureController": CL / "Controllers/NightExposureController.luau",
}

TEST = r'''
local fails = 0
local function check(ok, msg) print((ok and "ok    " or "FAIL  ") .. msg); if not ok then fails += 1 end end
task = { spawn = function() end, delay = function() end, defer = function() end, wait = function() end }
RaycastParams = { new = function() return {} end }
CFrame.lookAt = function(at) return CFrame.new(at.X, at.Y, at.Z) end
local TAGS = {}
local WS = Instance.new("Workspace")
WS.Raycast = function(_, from) return { Position = Vector3.new(from.X, 0, from.Z) } end
local function findIn(s, n) for _, c in ipairs(s:GetChildren()) do if c.Name == n then return c end end return nil end
WS.FindFirstChild = findIn
WS.GetDescendants = function() return {} end
local prevG = game
game = { GetService = function(_, n)
  if n == "Workspace" then return WS end
  if n == "CollectionService" then return { AddTag = function(_, o, t) TAGS[o] = t end } end
  if n == "RunService" then return { IsStudio = function() return false end } end
  return prevG:GetService(n) end }
-- folders created by NightLights find their children by name (ClearPlot / SyncPlot look them up)
local rn = Instance.new
Instance.new = function(cls) local o = rn(cls); if cls == "Folder" or cls == "Model" then o.FindFirstChild = findIn end; return o end

local LC = require(node("Configs/LightingConfig"))
local BC = require(node("Configs/BaseConfig"))
local PF = require(node("Util/PlotFrame"))
local NL = require(node("Modules/NightLights"))
local OWNER, OTHER = 470626172, 9

local function lightsUnder(root)
  local out = {}
  if root == nil then return out end
  for _, d in ipairs(root:GetDescendants()) do if d.ClassName == "PointLight" or d.ClassName == "SpotLight" then table.insert(out, d) end end
  return out
end
local function glowNamed(root, name)
  local n = 0
  if root == nil then return 0 end
  for _, d in ipairs(root:GetDescendants()) do if d.Name == name then n += 1 end end
  return n
end

-- 1. the start build
NL.Build()
local NLF = WS:FindFirstChild("WE_NightLights")
local static = NL.Count()
check(NLF ~= nil and static > 0 and static <= LC.MaxLights, string.format("start: the town + 3 per plot = %d night lights (<= %d)", static, LC.MaxLights))

-- 2. every owned plot
local function gateOf(plotId) local p = PF.LocalToWorld(plotId, 0, BC.PlotSize.X / 2); return CFrame.new(p.X, 0, p.Z) end
local perOk, perMax = true, 0
for plotId = 1, BC.MaxPlots do
  if PF.PlotPosition(plotId) ~= nil then
    local n = NL.SyncPlot(plotId, OWNER, gateOf(plotId))
    local base = #lightsUnder(findIn(NLF, "Plot" .. plotId .. "_Night")) + #lightsUnder(findIn(NLF, "Plot" .. plotId .. "_Night2"))
    perMax = math.max(perMax, base)
    if n ~= LC.Night2.PerBaseLights or base > 40 then perOk = false; print("  plot " .. plotId .. ": +" .. n .. ", base " .. base) end
  end
end
check(perOk and perMax <= 7, string.format("every owned plot: +%d lights (helipad, dock, gate sign, beacon); per base %d night lights (<= 7, cap 40)", LC.Night2.PerBaseLights, perMax))
check(NL.Count() <= LC.MaxLights, string.format("10 owned plots + the town: %d night lights (<= MaxLights %d)", NL.Count(), LC.MaxLights))

-- 3. every light
local all = lightsUnder(NLF)
local bad, low = 0, 0
for _, l in ipairs(all) do
  if l.Shadows ~= false or l.Enabled ~= false or TAGS[l] ~= LC.LightTag then bad += 1 end
  if l:GetAttribute(LC.LowOffAttribute) == true then low += 1 end
end
check(bad == 0 and #all == NL.Count(), string.format("all %d lights: Shadows off, off until the night flip, tagged %s", #all, LC.LightTag))
check(math.abs(low - #all / 2) <= 1, string.format("low-quality halving: %d of %d carry %s", low, #all, LC.LowOffAttribute))

-- 4. owner-first, no churn, clear, rebuild
local before = NL.Count()
NL.ClearPlot(3)
check(NL.Count() == before - LC.Night2.PerBaseLights and findIn(NLF, "Plot3_Night2") == nil, "the owner leaves: his plot's extras go and the lights are given back")
check(NL.SyncPlot(3, OTHER, gateOf(3)) == 0 and findIn(NLF, "Plot3_Night2") == nil, "another owner while OwnerFirst: nothing (OFF = the old 3 lights)")
local G3 = gateOf(3) -- one CFrame (Roblox compares CFrames by value; the stand-in by reference)
NL.SyncPlot(3, OWNER, G3)
local f3 = findIn(NLF, "Plot3_Night2")
check(NL.SyncPlot(3, OWNER, G3) == 0 and findIn(NLF, "Plot3_Night2") == f3, "the same plot again (a walls / Defence purchase): no rebuild, no churn")
local total = NL.Count()
NL.Build()
NLF = WS:FindFirstChild("WE_NightLights")
check(NL.Count() == total and findIn(NLF, "Plot3_Night2") ~= nil, string.format("a rebuild (NightLights.Build) brings the owned plots back: %d = %d", NL.Count(), total))

-- 5. glow-only extras
local f1 = findIn(NLF, "Plot1_Night2")
check(glowNamed(f1, "PadCorner") == 4 and glowNamed(f1, "BollardLamp") == 4 and glowNamed(f1, "Threshold") == 10 and glowNamed(f1, "BeaconHead") == 1 and glowNamed(f1, "SignLamp") == 1,
  string.format("plot 1 glow: %d pad corners, %d bollard lamps, %d thresholds, a beacon head, a sign lamp", glowNamed(f1, "PadCorner"), glowNamed(f1, "BollardLamp"), glowNamed(f1, "Threshold")))
local neon = 0
for _, d in ipairs(NLF:GetDescendants()) do if d.Material == "Material.Neon" then neon += 1 end end
check(neon == 0, "nothing is Neon by day (glow parts flip only at night: WE_NightGlow)")

-- 6. exposure
local NE = require(node("Controllers/NightExposureController"))
local E = LC.Night2.Exposure
check(NE.ExposureAt(12, LC) == E.Day and E.Day == 0, "noon: exposure 0 (today's look)")
check(NE.ExposureAt(23, LC) == E.Night and NE.ExposureAt(2, LC) == E.Night, string.format("night: exposure %.2f", E.Night))
local mid = NE.ExposureAt((LC.Cycle.DuskStart + LC.Cycle.NightStart) / 2, LC)
check(mid > E.Day and mid < E.Night, string.format("dusk: eased (%.2f)", mid))
check(E.Night <= 0.5, "the night lift stays gentle (<= 0.5 EV)")

print(string.format("NIGHT LIGHTS LUA: %d failed", fails))
if fails > 0 then error("failed") end
'''


def main():
    chunks = [PRELUDE]
    for key, path in MODS.items():
        chunks.append("SOURCES[%r] = function(script)\n%s\nend" % (key, path.read_text(encoding="utf-8")))
    chunks.append(TEST)
    with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False, encoding="utf-8") as f:
        f.write("\n".join(chunks))
        path = f.name
    r = subprocess.run([os.environ.get("LUAU", "luau"), path], capture_output=True, text=True)
    out = r.stdout.strip().splitlines()
    fails = 0
    if r.returncode != 0 or "NIGHT LIGHTS LUA: 0 failed" not in r.stdout:
        fails = 1
        out.append(r.stderr.strip()[-2500:])
    out.append("NIGHT LIGHTS TEST: %d failed" % fails)
    print("\n".join(out) if os.environ.get("VERBOSE") else "\n".join(l for l in out if l.startswith(("FAIL", "NIGHT LIGHTS TEST"))))
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
