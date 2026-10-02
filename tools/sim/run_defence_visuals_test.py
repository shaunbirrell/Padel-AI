"""claude-bud JOB 53: the Defence upgrades you can SEE, on the REAL EndgameConfig + Server/Modules/DefenceVisuals
(stand-ins: run_kit_detail_test.PRELUDE).

1. TIERS: DefenceVisualTier maps L0..10 to 0,1,1,1,2,2,2,3,3,3,4 (TierAt 1/4/7/10); GateDamageStage gives 0 / 1 (<= 60 %)
   / 2 (<= 30 %) / 3 (breached).
2. PIECES: every track at every tier builds only plain Parts that are Anchored, CanCollide / CanQuery / CanTouch false
   (never block a shot, a raycast or a walk), no Neon, no lights, within MaxParts, more parts as the tier rises, all
   close to their anchor.
3. APPLY: a full L10 base stays inside the per-base allowance; OFF (another owner while OwnerFirst) builds nothing;
   the gate leaves get the tier look, saved as attributes for setGateBarrierOpen.
4. DAMAGE: 100 % -> 50 % -> 20 % -> 100 % -> breached walks 0 -> 1 -> 2 -> 0 -> 3: dents / smoke / sag appear and go
   away again; only a stage change touches anything.
Run: LUAU=path/to/luau(.exe) python tools/sim/run_defence_visuals_test.py   (exit 1 on any failure; VERBOSE=1 prints all)"""
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
    "Configs/EndgameConfig": SH / "Configs/EndgameConfig.luau",
    "Configs/RetentionConfig": SH / "Configs/RetentionConfig.luau",
    "Configs/AdminConfig": SH / "Configs/AdminConfig.luau",
    "Configs/BaseConfig": SH / "Configs/BaseConfig.luau",
    "Configs/EconomyConfig": SH / "Configs/EconomyConfig.luau",
    "Modules/DefenceVisuals": SV / "Modules/DefenceVisuals.luau",
}

TEST = r'''
local fails = 0
local function check(ok, msg) print((ok and "ok    " or "FAIL  ") .. msg); if not ok then fails += 1 end end
local prevG = game
game = { GetService = function(_, n) if n == "RunService" then return { IsStudio = function() return false end } end return prevG:GetService(n) end }
NumberSequenceKeypoint = { new = function() return {} end }
local EG = require(node("Configs/EndgameConfig"))
-- codebot_v220 (Shaun 2026-10-02 07:51: everything public): EG.DefenceVisuals.OwnerFirst = false live; the owner-first paths
-- below are still proved with OwnerFirst = true, and a non-owner is live once it is restored (end of test)
local __V220_LAUNCHED = EG.DefenceVisuals.OwnerFirst
check(__V220_LAUNCHED == false, "codebot_v220: EG.DefenceVisuals.OwnerFirst = false (public for everyone)")
EG.DefenceVisuals.OwnerFirst = true
local DV = require(node("Modules/DefenceVisuals"))
local OWNER, OTHER = 470626172, 9

-- 1. tiers + stages
local want = { [0] = 0, 1, 1, 1, 2, 2, 2, 3, 3, 3, 4 }
local got = {}
for l = 0, 10 do got[l + 1] = EG.DefenceVisualTier(l) end
local okT = true
for l = 0, 10 do if EG.DefenceVisualTier(l) ~= want[l] then okT = false end end
check(okT, "visual tier by level 0..10: " .. table.concat(got, ","))
check(EG.GateDamageStage(1, false) == 0 and EG.GateDamageStage(0.61, false) == 0 and EG.GateDamageStage(0.6, false) == 1
  and EG.GateDamageStage(0.31, false) == 1 and EG.GateDamageStage(0.3, false) == 2 and EG.GateDamageStage(0, false) == 2
  and EG.GateDamageStage(1, true) == 3, "gate damage stage: >60 % clean, <=60 % 1, <=30 % 2, breached 3")
check(EG.DefenceVisuals.OwnerFirst == true and EG.DefenceVisualsLive(OWNER) and not EG.DefenceVisualsLive(OTHER), string.format("owner-first: live for the owner only (owner %s / Defence %s / other %s)", tostring(EG.DefenceVisualsLive(OWNER)), tostring(EG.LiveFor(OWNER, "Defence")), tostring(EG.DefenceVisualsLive(OTHER))))

-- helpers
local function withFind(o)
  o.FindFirstChild = function(s, n) for _, c in ipairs(s:GetChildren()) do if c.Name == n then return c end end return nil end
  return o
end
local function audit(root, anchor, reach)
  local n, bad, far = 0, {}, 0
  for _, d in ipairs(root:GetDescendants()) do
    if d.ClassName == "Part" then
      n += 1
      if not (d.Anchored == true and d.CanCollide == false and d.CanQuery == false and d.CanTouch == false) then table.insert(bad, d.Name .. ":collide/query") end
      if d.Material == "Material.Neon" then table.insert(bad, d.Name .. ":neon") end
      if anchor and (d.CFrame.Position - anchor).Magnitude > reach then far += 1 end
    elseif string.find(d.ClassName, "Light") then
      table.insert(bad, d.Name .. ":light")
    end
  end
  return n, bad, far
end

-- 2. every piece at every tier
local AT = CFrame.new(100, 0, 50) * CFrame.Angles(0, 0.4, 0)
for _, track in ipairs({ "Plating", "Guns" }) do
  local prev = 0
  for tier = 0, 4 do
    local f = Instance.new("Folder")
    local m = if track == "Plating" then DV.TurretPlating(AT, tier, f) else DV.TurretGuns(AT, tier, f)
    local n, bad, far = audit(f, AT.Position, 6)
    local okP = if tier == 0 then m == nil and n == 0 else (m ~= nil and n > prev and n <= EG.DefenceVisuals.MaxParts.Turret and #bad == 0 and far == 0)
    check(okP, string.format("%s T%d: %d parts (<= %d), %s, %d beyond 6 studs", track, tier, n, EG.DefenceVisuals.MaxParts.Turret, if #bad == 0 then "all anchored / no-collide / no-query, no Neon, no lights" else table.concat(bad, " "), far))
    prev = n
  end
end
local function leaves(f)
  local out = {}
  for i, sx in ipairs({ -2.5, 2.5 }) do
    local l = withFind(Instance.new("Part"))
    l.Name = "GateBarrier_" .. i
    l.Size = Vector3.new(4.7, 9, 1.6)
    l.CFrame = CFrame.new(200 + sx, 4, 0)
    l.Parent = f
    table.insert(out, l)
  end
  return out
end
do
  local prev = 0
  for tier = 0, 4 do
    local f = withFind(Instance.new("Folder"))
    local ls = leaves(f)
    local m = DV.Gate(ls, tier, f)
    local n = 0
    local bad = {}
    if m then n, bad = audit(m, Vector3.new(200, 4, 0), 9) end
    local okG = if tier == 0 then m == nil else (n > prev and n <= EG.DefenceVisuals.MaxParts.Gate and #bad == 0 and ls[1]:GetAttribute("WE_DefColor") ~= nil)
    check(okG, string.format("Gate T%d: %d parts (<= %d) incl. hidden dents, %s, leaves keep the tier look as attributes", tier, n, EG.DefenceVisuals.MaxParts.Gate, if #bad == 0 then "clean" else table.concat(bad, " ")))
    prev = n
  end
end
do
  local prev = 0
  for tier = 0, 4 do
    local f = Instance.new("Folder")
    local body = Instance.new("Part")
    body.Size = Vector3.new(4, 5, 3)
    body.CFrame = CFrame.new(50, 2.5, 80)
    local m = DV.Vault(body, tier, f)
    local n, bad, far = audit(f, body.CFrame.Position, 6)
    local okV = if tier == 0 then m == nil else (n > prev and n <= EG.DefenceVisuals.MaxParts.Vault and #bad == 0 and far == 0)
    check(okV, string.format("Vault T%d: %d parts (<= %d) round the money collector, %s", tier, n, EG.DefenceVisuals.MaxParts.Vault, if #bad == 0 then "clean" else table.concat(bad, " ")))
    prev = n
  end
end

-- 3. apply: a full L10 base, and OFF
local bases = { CFrame.new(-7, 0, 0), CFrame.new(7, 0, 0), CFrame.new(-16, 0, 0), CFrame.new(16, 0, 0) }
local function body() local b = Instance.new("Part"); b.Size = Vector3.new(4, 5, 3); b.CFrame = CFrame.new(0, 2.5, -40); return b end
local F = withFind(Instance.new("Folder"))
local L = leaves(F)
local added = DV.Apply(OWNER, { Plating = 10, Guns = 10, Gate = 10, Vault = 10 }, bases, L, body(), F)
check(added > 0 and added <= 140, string.format("a full L10 base (4 nests): +%d instances (<= 140; the base cap is 2,700 parts)", added))
local F2 = withFind(Instance.new("Folder"))
local L2 = leaves(F2)
local added2 = DV.Apply(OTHER, { Plating = 10, Guns = 10, Gate = 10, Vault = 10 }, bases, L2, body(), F2)
check(added2 == 0 and L2[1]:GetAttribute("WE_DefColor") == nil, "OFF (another owner while OwnerFirst): nothing built, the leaves keep the old look")
local F3 = withFind(Instance.new("Folder"))
local added3 = DV.Apply(OWNER, { Plating = 0, Guns = 0, Gate = 0, Vault = 0 }, bases, leaves(F3), body(), F3)
check(added3 == 0, "all levels 0: nothing built (a new player's base looks exactly as before)")

-- 4. the gate's damage stages (on the L10 gate built in 3)
local vis = F:FindFirstChild("DefVis_Gate")
local function partsNamed(prefix) local out = {} for _, p in ipairs(vis:GetChildren()) do if string.sub(p.Name, 1, #prefix) == prefix then table.insert(out, p) end end return out end
local function allT(list, t) for _, p in ipairs(list) do if p.Transparency ~= t then return false end end return #list > 0 end
local band0 = partsNamed("Band")[1].CFrame
local smokeOf = function() return L[1]:FindFirstChild("WE_GateSmoke") end
check(DV.GateDamage(L, 1, false) == 0 and allT(partsNamed("Dent"), 1) and smokeOf() == nil, "100 %: stage 0, dents hidden, no smoke")
check(DV.GateDamage(L, 0.5, false) == 1 and allT(partsNamed("Dent1"), 0) and allT(partsNamed("Dent2"), 1) and smokeOf() == nil, "50 %: stage 1, the first dents show")
check(DV.GateDamage(L, 0.2, false) == 2 and allT(partsNamed("Dent"), 0) and smokeOf() ~= nil and partsNamed("Band")[1].CFrame.Position ~= nil and partsNamed("Band")[1]:GetAttribute("WE_SagFrom") ~= nil, "20 %: stage 2, all dents, bands sag, one smoke emitter")
local nKids = #L[1]:GetChildren()
DV.GateDamage(L, 0.15, false)
check(#L[1]:GetChildren() == nKids, "same stage again: nothing added (only a stage change touches the gate)")
check(DV.GateDamage(L, 1, false) == 0 and allT(partsNamed("Dent"), 1) and smokeOf() == nil and partsNamed("Band")[1]:GetAttribute("WE_SagFrom") == nil and partsNamed("Band")[1].CFrame.Position.Y == band0.Position.Y, "repaired / rebuilt: back to stage 0 (dents hidden, smoke gone, bands straight)")
check(DV.GateDamage(L, 0, true) == 3 and allT(partsNamed("Band"), 1) and allT(partsNamed("Dent"), 1) and smokeOf() ~= nil, "breached: stage 3, the reinforcement is gone, smoke")
check(DV.GateDamage(L, 1, false) == 0 and allT(partsNamed("Band"), 0), "rebuilt after a breach: the tier reinforcement is back")

-- 5. claude-bud JOB 55: a Defence buy mid-raid never heals (EndgameConfig.KeepDamage, used by GateDefenseService.RefreshDefence)
check(EG.KeepDamage(1000, 400, 1120) == 520, "gate 400/1000, Gate +12 %: 520/1120 (the 600 damage stays; was a full 1120 repair)")
check(EG.KeepDamage(1000, 1000, 1120) == 1120, "an undamaged gate: full at the new max")
check(EG.KeepDamage(1000, 0, 1120) == 0, "a breached gate stays breached (its rebuild timer brings it back)")
check(EG.KeepDamage(1000, 50, 900) == 1 and EG.KeepDamage(400, 10, 460) == 70, "never below 1 while standing; a turret 10/400 -> 70/460")
print(string.format("DEFENCE VISUALS LUA: %d failed", fails))
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
    if r.returncode != 0 or "DEFENCE VISUALS LUA: 0 failed" not in r.stdout:
        fails = 1
        out.append(r.stderr.strip()[-2500:])
    out.append("DEFENCE VISUALS TEST: %d failed" % fails)
    print("\n".join(out) if os.environ.get("VERBOSE") else "\n".join(l for l in out if l.startswith(("FAIL", "DEFENCE VISUALS TEST"))))
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
