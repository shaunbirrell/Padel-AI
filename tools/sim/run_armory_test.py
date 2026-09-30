"""claude-bud JOB 35: real-code tests in the Luau CLI for the premium guns armory (stand-ins: run_kit_detail_test.PRELUDE
plus Clone / FindFirstChild / bounds / ScaleTo on the Instance stand-in).

1. GUN MECHANICS (the real Shared/Util/GunMechanics):
   * Burst: 2 shots Gap apart, then the full interval; the counter restarts;
   * SpinUp: refused before 80 % of the spin, accepted after, stays warm while firing, cold again after SpinKeep;
   * ChargeSeconds: refused without a charge / too early / stale, accepted when charged, one charge = one shot;
   * MaxTargets clamp; Dps.
2. THE SERVER SCHEDULE: RequestFire's schedule lines (the v69 GCRA with this job's Interval / Ready / OnShot, copied
   line for line from CombatService) under a 20 Hz held trigger for 6 s: shots per gun match the design, and the
   existing guns are unchanged (their Interval is the old 1 / FireRate).
3. CONFIG (the real WeaponConfig / MonetizationConfig / PremiumGunsConfig): six premium guns with the brief's asset
   ids, Premium + CostCash 0 + a live PG_* pass (Id and price in MonetizationConfig), the Armory Pass covers all six and
   hides once the six are owned; no id clashes with the rebirth guns; the DPS table (printed).
4. SERVICE (the real Services/PremiumGunService on stubs): CaseState Owned / Soon / Buy; OnPassOwned grants one gun /
   the bundle grants six, idempotent; not live = no grant; the prompt text is the stands' "Buy - R$ X".
5. ARMORY PLACEMENT: the 7 cases stay inside the plot, clear of the Supply Depot row, kiosks, structure sites, warzone
   props, the main road, the spawn and the ATM; the sign sits inside the front wall.
6. LOADER (the real Modules/WeaponAssetLoader.BuildTemplate): a plain 6-part model gets a Handle, every part welded,
   a spinning barrel weld, scaled to VisualLength; a kit Tool with VisualChild "*" takes its first Model child; a
   template over 16 parts is refused (the Part kit stays).
Run: LUAU=path/to/luau(.exe) python tools/sim/run_armory_test.py   (exit 1 on any failure)"""
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
SV = ROOT / "src/ServerScriptService/Server"
MODS = {
    "Util/GunMechanics": SH / "Util/GunMechanics.luau",
    "Configs/WeaponConfig": SH / "Configs/WeaponConfig.luau",
    "Configs/MonetizationConfig": SH / "Configs/MonetizationConfig.luau",
    "Configs/PremiumGunsConfig": SH / "Configs/PremiumGunsConfig.luau",
    "Configs/RetentionConfig": SH / "Configs/RetentionConfig.luau",
    "Configs/AdminConfig": SH / "Configs/AdminConfig.luau",
    "Configs/BaseLayoutConfig": SH / "Configs/BaseLayoutConfig.luau",
    "Configs/BaseConfig": SH / "Configs/BaseConfig.luau",
    "Util/PlotFrame": SH / "Util/PlotFrame.luau",
    "Services/PremiumGunService": SV / "Services/PremiumGunService.luau",
    "Modules/WeaponAssetLoader": SV / "Modules/WeaponAssetLoader.luau",
}

# the schedule lines of CombatService.RequestFire, checked below to still be in the source (so this copy cannot drift)
SCHEDULE_LINES = [
    "local minInterval = 1 / math.max(def.FireRate * researchMult(player, \"WeaponFireRate\"), 0.1) -- v69 research",
    "minInterval = GunMechanics.Interval(def, mech, clock(), minInterval) -- claude-bud JOB 35: Burst.Gap inside a burst",
    "if clock() - state.LastFireAt < minInterval * 0.5 or clock() - gunAt < minInterval * 0.5 then -- v69: GCRA",
    "GunMechanics.OnShot(def, mech, clock()) -- claude-bud JOB 35: burst count, keeps the barrel warm, spends the charge",
    "state.LastFireAt = math.max(state.LastFireAt + minInterval, clock()) -- v69 research: was = clock()",
    "if not GunMechanics.Ready(def, mech, clock()) then",
]

EXTRA = r'''
task = { spawn = function() end, wait = function() end, delay = function() end, defer = function() end }
local function signal() local s = { fns = {} }; s.Connect = function(self, fn) table.insert(self.fns, fn); return { Disconnect = function() end } end; return s end
local Players = { PlayerAdded = signal(), PlayerRemoving = signal(), GetPlayers = function() return {} end }
local RunService = { IsStudio = function() return false end }
local prevGame = game
game = { GetService = function(_, n)
  if n == "Players" then return Players elseif n == "RunService" then return RunService end
  return prevGame:GetService(n) end }
utf8 = { char = function() return "R$" end }

-- Instance stand-in extras for the loader: names, classes, Clone, bounds, ScaleTo
local baseIndex = INST.__index
local CLASSES = { Part = { "BasePart" }, MeshPart = { "BasePart" }, TrussPart = { "BasePart" }, Model = { "PVInstance" }, Tool = { "Model" }, Script = { "LuaSourceContainer" } }
INST.__index = function(t, k)
  if k == "IsA" then return function(s, c)
    if s.ClassName == c or c == "Instance" then return true end
    for _, p in ipairs(CLASSES[s.ClassName] or {}) do if p == c then return true end end
    return false end end
  if k == "FindFirstChild" then return function(s, n) for _, c in ipairs(rawget(s, "__kids") or {}) do if c.Name == n then return c end end return nil end end
  if k == "FindFirstChildWhichIsA" then return function(s, cls, deep)
    local list = if deep then s:GetDescendants() else s:GetChildren()
    for _, c in ipairs(list) do if c:IsA(cls) then return c end end return nil end end
  if k == "FindFirstChildOfClass" then return function(s, cls) for _, c in ipairs(rawget(s, "__kids") or {}) do if c.ClassName == cls then return c end end return nil end end
  if k == "Clone" then return function(s)
    local function copy(o)
      local n = Instance.new(o.ClassName)
      for pk, pv in pairs(rawget(o, "__props")) do if pk ~= "Parent" then rawget(n, "__props")[pk] = pv end end
      for ak, av in pairs(o.__attr) do n.__attr[ak] = av end
      for _, c in ipairs(rawget(o, "__kids") or {}) do copy(c).Parent = n end
      return n
    end
    return copy(s) end end
  if k == "GetBoundingBox" or k == "GetExtentsSize" then return function(s)
    local lo, hi = nil, nil
    for _, d in ipairs(s:GetDescendants()) do
      if d:IsA("BasePart") and d.CFrame then
        local p, sz = d.CFrame.Position, d.Size
        local a = Vector3.new(p.X - sz.X / 2, p.Y - sz.Y / 2, p.Z - sz.Z / 2)
        local b = Vector3.new(p.X + sz.X / 2, p.Y + sz.Y / 2, p.Z + sz.Z / 2)
        lo = if lo then Vector3.new(math.min(lo.X, a.X), math.min(lo.Y, a.Y), math.min(lo.Z, a.Z)) else a
        hi = if hi then Vector3.new(math.max(hi.X, b.X), math.max(hi.Y, b.Y), math.max(hi.Z, b.Z)) else b
      end
    end
    local size = hi - lo
    if k == "GetExtentsSize" then return size end
    return CFrame.new((lo + hi) * 0.5), size end end
  if k == "IsDescendantOf" then return function(s, a) local q = s.Parent; while type(q) == "table" do if q == a then return true end; q = q.Parent end; return false end end
  if k == "GetScale" then return function(s) return rawget(s, "__props").__scale or 1 end end
  if k == "ScaleTo" then return function(s, sc)
    local f = sc / (rawget(s, "__props").__scale or 1)
    for _, d in ipairs(s:GetDescendants()) do
      if d:IsA("BasePart") and d.Size then d.Size = d.Size * f; d.CFrame = CFrame.new(d.CFrame.Position * f) end
    end
    rawget(s, "__props").__scale = sc end end
  return baseIndex(t, k)
end
'''

TEST = r'''
local fails = 0
local function check(ok, msg) print((ok and "ok    " or "FAIL  ") .. msg); if not ok then fails += 1 end end
local GM = require(node("Util/GunMechanics"))
local WC = require(node("Configs/WeaponConfig"))
local MC = require(node("Configs/MonetizationConfig"))
local PG = require(node("Configs/PremiumGunsConfig"))
local W = WC.Weapons

-- ── 1. mechanics ──
local sov, havoc, rail = W.SovereignPistol, W.HavocRotary, W.TempestRailgun
local st = GM.New()
check(GM.Interval(sov, st, 0, 0.5) == 0.5, "burst: the first shot waits the full interval")
GM.OnShot(sov, st, 0)
check(GM.Interval(sov, st, 0.1, 0.5) == 0.1, "burst: the 2nd shot follows at Gap 0.1")
GM.OnShot(sov, st, 0.1)
check(GM.Interval(sov, st, 0.2, 0.5) == 0.5 and st.BurstShots == 2, "burst: after 2 shots the full interval again")
GM.OnShot(sov, st, 0.7)
check(st.BurstShots == 1, "burst: the next burst restarts the count")
st = GM.New()
check(not GM.Ready(havoc, st, 0), "spin: no shot without a spin prime")
GM.Prime(havoc, st, 0, "Spin")
check(not GM.Ready(havoc, st, 0.4), "spin: refused at 0.40 s (needs 0.48)")
check(GM.Ready(havoc, st, 0.5), "spin: accepted at 0.50 s")
GM.OnShot(havoc, st, 0.5)
check(GM.Ready(havoc, st, 0.8), "spin: stays warm while firing")
check(not GM.Ready(havoc, st, 0.5 + 3.5), "spin: cold again after the barrel stopped (and the prime went stale)")
st = GM.New()
check(not GM.Ready(rail, st, 1), "charge: no shot without a charge")
GM.Prime(rail, st, 1, "Charge")
check(not GM.Ready(rail, st, 1.5), "charge: refused at 0.5 s (needs 0.64)")
check(GM.Ready(rail, st, 1.7), "charge: accepted at 0.7 s")
GM.OnShot(rail, st, 1.7)
check(not GM.Ready(rail, st, 1.8), "charge: one charge = one shot")
GM.Prime(rail, st, 2, "Charge")
check(not GM.Ready(rail, st, 2 + 0.8 + 6.5), "charge: a stale charge (held > 6.8 s) is dropped")
check(GM.MaxTargets(rail) == 3 and GM.MaxTargets(W.Sniper) == 1, "pierce: Tempest hits up to 3, others 1")
check(GM.Prime(W.AssaultRifle, GM.New(), 0, "Spin") == false and GM.PrimeKind(W.AssaultRifle) == nil, "an old gun takes no prime")

-- ── 2. server schedule (a 20 Hz held trigger for 6 s) ──
local function hold(def, seconds)
  local state = { LastFireAt = -math.huge }
  local gunAt = -math.huge
  local mech = GM.New()
  local shots, t = 0, 0
  local kind = GM.PrimeKind(def)
  if kind == "Spin" then GM.Prime(def, mech, 0, "Spin") end
  while t <= seconds do
    if kind == "Charge" and not mech.ChargeAt then GM.Prime(def, mech, t, "Charge") end
    local clock = t
    local ok = GM.Ready(def, mech, clock)
    if ok then
      local minInterval = 1 / math.max(def.FireRate, 0.1)
      minInterval = GM.Interval(def, mech, clock, minInterval)
      if not (clock - state.LastFireAt < minInterval * 0.5 or clock - gunAt < minInterval * 0.5) then
        GM.OnShot(def, mech, clock)
        state.LastFireAt = math.max(state.LastFireAt + minInterval, clock)
        gunAt = math.max(gunAt + minInterval, clock)
        shots += 1
      end
    end
    t += 0.05
  end
  return shots
end
local ar = hold(W.AssaultRifle, 6)
check(ar >= 53 and ar <= 56, "unchanged: the Assault Rifle fires 9/s (" .. ar .. " in 6 s)")
local sv = hold(sov, 6)
check(sv >= 18 and sv <= 22, "Sovereign: ~10 bursts of 2 in 6 s (" .. sv .. " shots)")
local hv = hold(havoc, 6)
check(hv >= 105 and hv <= 111, "Havoc: 0.6 s spin-up then 20/s (" .. hv .. " shots)")
local th = hold(W.ThunderheadLauncher, 6)
check(th >= 4 and th <= 6, "Thunderhead: 2-rocket salvos (" .. th .. " rockets; ammo not modelled)")
local tr = hold(rail, 6)
check(tr >= 5 and tr <= 8, "Tempest: one charged shot per ~0.8-1 s (" .. tr .. ")")

-- ── 3. config ──
local want = { SovereignPistol = 720567240, QuakeLauncher = 4842201032, LongshotSniper = 14498314181, HavocRotary = 590594953, ThunderheadLauncher = 12458308179, TempestRailgun = 4842190633 }
local passIds = { PG_Sovereign = 2002154652, PG_Quake = 2003492417, PG_Longshot = 2003180431, PG_Havoc = 2002250646, PG_Thunderhead = 1999305818, PG_Tempest = 2002682646, PG_ArmoryPass = 2002868467 }
local prices = { PG_Sovereign = 99, PG_Quake = 249, PG_Longshot = 299, PG_Havoc = 349, PG_Thunderhead = 399, PG_Tempest = 499, PG_ArmoryPass = 1299 }
for id, aid in pairs(want) do
  local d = W[id]
  check(d ~= nil and d.Premium == true and d.CostCash == 0 and d.VisualAssetId == aid, id .. ": premium, not sold for Cash, asset " .. aid)
  local p = d and MC.GamePasses[d.PassKey]
  check(p ~= nil and p.Id == passIds[d.PassKey] and p.RobuxPrice == prices[d.PassKey] and table.find(p.WeaponIds, id) ~= nil, id .. ": pass " .. tostring(d and d.PassKey) .. " live Id at R$ " .. tostring(p and p.RobuxPrice))
end
local bundle = MC.GamePasses.PG_ArmoryPass
check(bundle.Id == passIds.PG_ArmoryPass and bundle.RobuxPrice == 1299 and #bundle.WeaponIds == 6 and #bundle.BundlePassKeys == 6, "Armory Pass: live Id, R$ 1299, all six")
check(#PG.UnlockedBy({ PG_ArmoryPass = true }) == 6 and #PG.UnlockedBy({ PG_Quake = true }) == 1 and PG.UnlockedBy({ PG_Quake = true })[1] == "QuakeLauncher", "UnlockedBy: bundle = 6, a single = its gun")
local six = {}
for k in pairs(prices) do if k ~= "PG_ArmoryPass" then six[k] = true end end
check(PG.BundleHidden(six) and not PG.BundleHidden({ PG_Quake = true }), "the Armory Pass hides once all six are owned")
for _, id in ipairs({ "VanguardCarbine", "TempestSMG", "WardenShotgun", "LongshotDMR", "TalonSniper", "HavocLauncher", "SovereignRifle" }) do
  check(W[id] ~= nil and W[id].Premium == nil, "rebirth gun " .. id .. " kept, not premium")
end
check(W.LongshotSniper.Scope == true and W.LongshotSniper.Range == 600 and W.LongshotSniper.HeadshotMult == 1.5 and W.LongshotSniper.Damage == 110, "Longshot: scope, range 600, 110 dmg, headshot x1.5")
check(W.QuakeLauncher.MagazineSize == 6 and W.QuakeLauncher.Projectile.Splash == 11 and W.QuakeLauncher.Projectile.GravityFactor > 0, "Quake: 6-round drum, lobbed, splash 11")
check(W.HavocRotary.SpinUp == 0.6 and W.HavocRotary.FireRate == 20 and W.HavocRotary.Damage == 9 and W.HavocRotary.MagazineSize == 150, "Havoc: 0.6 s spin, 20 rps, 9 dmg, 150")
check(W.ThunderheadLauncher.Burst.Count == 2 and W.ThunderheadLauncher.Damage == 170 and W.ThunderheadLauncher.Projectile.Splash == 12, "Thunderhead: 2-rocket salvo, 170, splash 12")
check(W.TempestRailgun.ChargeSeconds == 0.8 and W.TempestRailgun.Damage == 140 and W.TempestRailgun.Pierce == 3, "Tempest: 0.8 s charge, 140, pierces 3")
check(W.SovereignPistol.Damage == 30 and W.SovereignPistol.Burst.Count == 2 and W.SovereignPistol.MagazineSize == 12, "Sovereign: 30 dmg, 2-shot burst, mag 12")
print("DPS table (damage per second at full rate, before reloads):")
for _, id in ipairs({ "StarterRifle", "AssaultRifle", "SMG", "Pistol", "Shotgun", "Sniper", "RocketLauncher", "SovereignRifle", "SovereignPistol", "QuakeLauncher", "LongshotSniper", "HavocRotary", "ThunderheadLauncher", "TempestRailgun" }) do
  print(string.format("  %-20s %6.1f", id, GM.Dps(W[id])))
end
local best = math.max(GM.Dps(W.AssaultRifle), GM.Dps(W.SovereignRifle))
for id in pairs(want) do check(GM.Dps(W[id]) <= best, id .. " DPS " .. string.format("%.0f", GM.Dps(W[id])) .. " <= the best existing automatic (" .. string.format("%.0f", best) .. ")") end

-- ── 4. service ──
local PS = require(node("Services/PremiumGunService"))
local prof = { Weapons = { StarterRifle = true } }
local s1, sub1, act1 = PS.CaseState(prof, PG.Guns[1])
check(s1 == "Buy" and act1 == PS.BuyText(99) and act1 == "Buy - R$ 99", "case: live pass -> " .. act1)
local s2, _, act2 = PS.CaseState(prof, PG.Guns[1])
check(s2 == "Buy" and act2 == "Buy - R$ 99", "case: non-owner sees price -> " .. act2)
prof.Weapons.SovereignPistol = true
local s3, sub3, act3 = PS.CaseState(prof, PG.Guns[1])
check(s3 == "Owned" and act3 == "Equip" and sub3 == "OWNED", "case: owned -> Equip")
local grants, dirty, synced = {}, 0, 0
local profiles = { [470626172] = { Weapons = { StarterRifle = true } }, [5] = { Weapons = { StarterRifle = true } } }
local passCb
PS.Init({
  DataService = { GetProfile = function(p) return profiles[p.UserId] end, MarkDirty = function() dirty += 1 end, OnProfileLoaded = function() end },
  CombatService = { SyncWeapons = function() synced += 1 end },
  NotificationService = { Notify = function() end },
  MonetizationService = { OnPassOwned = function(cb) passCb = cb end },
})
local owner = { UserId = 470626172, Name = "shaunie6" }
local other = { UserId = 5, Name = "rookie" }
passCb(owner, "PG_Quake", "purchase")
check(profiles[470626172].Weapons.QuakeLauncher == true and synced == 1, "OnPassOwned PG_Quake grants the Quake (and syncs the hotbar)")
passCb(owner, "PG_Quake", "join")
check(synced == 1, "idempotent: a second grant changes nothing")
passCb(owner, "PG_ArmoryPass", "join")
local n = 0
for id in pairs(want) do if profiles[470626172].Weapons[id] then n += 1 end end
check(n == 6, "the Armory Pass grants all six (" .. n .. ")")
-- v137 (Code Bot Roblox): the shipped config is OwnerFirst = false (everyone); the owner-first rule is still tested
local launched = PG.Live.OwnerFirst
check(launched == false, "v137 live: PremiumGunsConfig.Live.OwnerFirst = false (everyone)")
PG.Live.OwnerFirst = true
passCb(other, "PG_Havoc", "purchase")
check(profiles[5].Weapons.HavocRotary == nil, "not live for another player (owner-first): no grant")
passCb(owner, "VIP", "join")
check(synced == 2, "an unrelated pass grants nothing")
PG.Live.OwnerFirst = launched
passCb(other, "PG_Havoc", "purchase")
check(profiles[5].Weapons.HavocRotary == true and synced == 3, "v137 live: live for another player: a bought pass grants his gun")
local otherState, _, otherAction = PS.CaseState(profiles[5], PG.Guns[2])
check(otherState == "Buy" and otherAction == "Buy - R$ 249", "v137 live: another player sees a price, not SOON")

-- ── 5. placement ──
local BL = require(node("Configs/BaseLayoutConfig"))
local D = { X0 = -78, Step = 12, Z = 146 }
local obstacles = {}
for i = 0, 3 do table.insert(obstacles, { "depot slot", D.X0 + i * D.Step, D.Z, 5 }) end
for _, s in pairs(BL.Structures) do
  if s.Kiosk then table.insert(obstacles, { "kiosk", s.Kiosk.X, s.Kiosk.Z, 5 }) end
  table.insert(obstacles, { "structure site", s.Site.X, s.Site.Z, if s.WalkIn then 30 else 16 })
end
for _, w in ipairs(BL.WarzoneSpots) do table.insert(obstacles, { "warzone prop", w.X, w.Z, 5 }) end
table.insert(obstacles, { "spawn", 0, 136, 8 }); table.insert(obstacles, { "ATM", -42, 118, 8 })
local A = PG.Armory
local hits = {}
for i = 1, 7 do
  local o = PS.CaseOffset(i)
  if math.abs(o.X) > 150 or o.Z > 155 then table.insert(hits, "case " .. i .. " outside the plot") end
  if math.abs(o.X) < 7 + 3 then table.insert(hits, "case " .. i .. " on the main road") end
  for _, ob in ipairs(obstacles) do
    local d = math.sqrt((o.X - ob[2]) ^ 2 + (o.Z - ob[3]) ^ 2)
    if d < ob[4] + 2.5 then table.insert(hits, string.format("case %d %.1f from %s (%d,%d)", i, d, ob[1], ob[2], ob[3])) end
  end
end
check(#hits == 0, "7 cases clear of the layout: " .. table.concat(hits, "; "))
check(A.SignZ < 158 and A.SignZ > A.Z, "sign behind the row, inside the front wall")
check(PS.CaseOffset(1).X < D.X0 - 10 and PS.CaseOffset(7).X > -150, "the row runs west from the Supply Depot")

-- ── 6. loader ──
local L = require(node("Modules/WeaponAssetLoader"))
local function mk(cls, name, size, pos, parent)
  local p = Instance.new(cls); p.Name = name; p.Size = size; p.CFrame = CFrame.new(pos.X, pos.Y, pos.Z); p.Parent = parent; return p
end
local root = Instance.new("Model"); root.Name = "Model"
local gun = Instance.new("Model"); gun.Name = "gunmodel"; gun.Parent = root
mk("MeshPart", "Body", Vector3.new(1, 1.2, 8), Vector3.new(0, 0, 0), gun)
mk("MeshPart", "Grip", Vector3.new(0.6, 1.4, 0.8), Vector3.new(0, -1, 2), gun)
mk("MeshPart", "Ammo", Vector3.new(1.4, 1.4, 1.4), Vector3.new(0.8, -0.6, 0), gun)
local barrel = Instance.new("Model"); barrel.Name = "Barrel"; barrel.Parent = root
mk("MeshPart", "B1", Vector3.new(0.3, 0.3, 5), Vector3.new(0, 0.2, -5), barrel)
mk("MeshPart", "B2", Vector3.new(0.3, 0.3, 5), Vector3.new(0, -0.2, -5), barrel)
local s = Instance.new("Script"); s.Parent = gun
local t, why = L.BuildTemplate("HavocRotary", root, nil, nil, W.HavocRotary)
check(t ~= nil, "plain model -> template (" .. tostring(why) .. ")")
if t then
  local h = t:FindFirstChild("Handle")
  check(h ~= nil and h.Transparency == 1 and t.PrimaryPart == h, "an invisible Handle is the PrimaryPart")
  local welds, spin, scripts, parts = 0, nil, 0, 0
  for _, d in ipairs(t:GetDescendants()) do
    if d.ClassName == "WeldConstraint" then welds += 1 end
    if d.Name == "WE_SpinWeld" then spin = d end
    if d.ClassName == "Script" then scripts += 1 end
    if d:IsA("BasePart") then parts += 1; if d.Anchored ~= false or d.CanCollide ~= false then print("  loose part " .. d.Name) end end
  end
  check(welds == 3, "every part welded (3 to the body, the 2nd barrel part to its root): " .. welds)
  check(spin ~= nil and spin.Part0 == h, "the barrel model spins on WE_SpinWeld under the Handle")
  check(scripts == 0, "scripts stripped")
  local size = t:GetExtentsSize()
  local longest = math.max(size.X, size.Y, size.Z)
  check(math.abs(longest - 4.2) < 0.05, string.format("scaled to VisualLength 4.2 (%.2f)", longest))
end
local tool = Instance.new("Tool"); tool.Name = "Grenade Launcher"
local tm = Instance.new("Model"); tm.Name = "GL"; tm.Parent = tool
mk("Part", "Body", Vector3.new(1, 1, 3), Vector3.new(0, 0, 0), tm)
mk("Part", "Handle", Vector3.new(0.5, 0.5, 0.5), Vector3.new(0, -0.5, 0.5), tool)
local troot = Instance.new("Model"); tool.Parent = troot
local t2, why2 = L.BuildTemplate("QuakeLauncher", troot, nil, "*", W.QuakeLauncher)
check(t2 ~= nil and t2:FindFirstChild("Body") ~= nil and t2:FindFirstChild("Handle") ~= nil, "kit Tool, VisualChild \"*\" -> its first Model child + the grip Handle (" .. tostring(why2) .. ")")
local big = Instance.new("Model")
for i = 1, 20 do mk("MeshPart", "P" .. i, Vector3.new(1, 1, 1), Vector3.new(i, 0, 0), big) end
local t3, why3 = L.BuildTemplate("LongshotSniper", big, nil, nil, W.LongshotSniper)
check(t3 == nil and string.find(why3, "> 16") ~= nil, "over 16 parts refused (" .. tostring(why3) .. ")")

print(string.format("ARMORY TEST: %d failed", fails))
if fails > 0 then error("failed") end
'''

src = (SV / "Services/CombatService/init.luau").read_text(encoding="utf-8")
missing = [l for l in SCHEDULE_LINES if l not in src]
if missing:
    print("FAIL  CombatService schedule lines changed (update this test's copy):", missing)
    sys.exit(1)
chunks = [PRELUDE, EXTRA]
for key, path in MODS.items():
    chunks.append("SOURCES[%r] = function(script)\n%s\nend" % (key, path.read_text(encoding="utf-8")))
chunks.append(TEST)
with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False, encoding="utf-8") as f:
    f.write("\n".join(chunks))
    path = f.name
luau = os.environ.get("LUAU", "luau")
r = subprocess.run([luau, path], capture_output=True, text=True)
out = r.stdout.strip()
print(out if os.environ.get("VERBOSE") else ("\n".join(l for l in out.splitlines() if l.startswith("FAIL") or l.startswith("ARMORY TEST")) or out))
if r.returncode != 0:
    print(r.stderr.strip()[-2500:])
    sys.exit(1)
