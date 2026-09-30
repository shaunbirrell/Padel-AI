-- v152 Code Bot dry run of StorePropsService.PlaceReplaceRows (same steps: LoadAsset, clean, pivot, ScaleTo, PivotTo,
-- prune, snap bottom to the kit base, hide kit) for the market stall rows, on the real Town built by WorldPOI.Build.
local SSS = game:GetService("ServerScriptService")
local IS = game:GetService("InsertService")
local out = {}
local function p(...) table.insert(out, string.format(...)) end
local wf = Instance.new("Folder"); wf.Name = "WorldFill"; wf.Parent = workspace
require(SSS.Server.Modules.WorldPOI).Build(wf, "High")
local Cfg = require(game.ReplicatedStorage.Shared.Configs.StorePropsConfig)
local P = Cfg.Place
local STRIP = { "LuaSourceContainer","Humanoid","Sound","ProximityPrompt","ClickDetector","Dialog","BodyMover","Constraint",
 "JointInstance","WeldConstraint","NoCollisionConstraint","ParticleEmitter","Fire","Smoke","Sparkles","Beam","Trail","Explosion",
 "ForceField","Tool","BillboardGui","ScreenGui","RemoteEvent","RemoteFunction","BindableEvent","BindableFunction","AnimationController","Animator","Attachment" }
local tpl = IS:LoadAsset(86311252190175)
local kill = {}
for _, d in ipairs(tpl:GetDescendants()) do for _, c in ipairs(STRIP) do if d:IsA(c) and not (c == "Attachment" and #d:GetChildren() > 0) then table.insert(kill, d) break end end end
for _, d in ipairs(kill) do d:Destroy() end
local scripts = 0
for _, d in ipairs(tpl:GetDescendants()) do if d:IsA("LuaSourceContainer") then scripts += 1 end; if d:IsA("BasePart") then d.Anchored = true; d.CanTouch = false end end
local cfB, szB = tpl:GetBoundingBox()
tpl.WorldPivot = CFrame.new(cfB.Position.X, cfB.Position.Y - szB.Y / 2, cfB.Position.Z)
p("template scripts after trim=%d parts=%d size=%.2fx%.2fx%.2f", scripts, #tpl:GetDescendants(), szB.X, szB.Y, szB.Z)
local ROWS = {
  { KitPart = "StallCounter", At = Vector3.new(-81, 0, -166.4), Radius = 6, Scale = 5, Yaw = 0 },
  { KitPart = "StallCounter", At = Vector3.new(-80, 0, -182.6), Radius = 6, Scale = 5, Yaw = 180 },
}
for i, row in ipairs(ROWS) do
  local kp
  for _, d in ipairs(wf:GetDescendants()) do
    if d:IsA("BasePart") and d.Name == row.KitPart and Vector3.new(d.Position.X - row.At.X, 0, d.Position.Z - row.At.Z).Magnitude <= row.Radius then kp = d break end
  end
  if not kp then p("row %d: NO KIT", i) continue end
  local cluster = kp:FindFirstAncestorWhichIsA("Model") or kp.Parent
  local parts, lowY = {}, math.huge
  local kmn, kmx
  for _, d in ipairs(cluster:GetDescendants()) do
    if d:IsA("BasePart") and Vector3.new(d.Position.X - kp.Position.X, 0, d.Position.Z - kp.Position.Z).Magnitude <= 9 then
      table.insert(parts, d); lowY = math.min(lowY, d.Position.Y - d.Size.Y * 0.5)
    end
  end
  local kcf, ksz = cluster:GetBoundingBox()
  local cf = CFrame.new(kp.Position.X, lowY, kp.Position.Z) * CFrame.Angles(0, math.rad(row.Yaw), 0)
  local m = tpl:Clone()
  m:ScaleTo(row.Scale)
  m:PivotTo(cf)
  local n = 0
  for _, d in ipairs(m:GetDescendants()) do if d:IsA("BasePart") then n += 1 end end
  m.Parent = wf
  local ccf, csz = m:GetBoundingBox()
  m:PivotTo(m:GetPivot() + Vector3.new(0, lowY - (ccf.Position.Y - csz.Y * 0.5), 0))
  ccf, csz = m:GetBoundingBox()
  for _, q in ipairs(parts) do q.Transparency = 1; q.CanCollide = false; q.CanQuery = false end
  -- overlaps: anything else (not the hidden kit, not the copy) inside the copy's box
  local op = OverlapParams.new(); op.FilterType = Enum.RaycastFilterType.Exclude; op.FilterDescendantsInstances = { m, cluster }
  local inBox = workspace:GetPartBoundsInBox(ccf, csz * 0.98, op)
  local names = {}
  for _, q in ipairs(inBox) do if q.Transparency < 0.95 and #names < 8 then table.insert(names, q.Name .. "@" .. q.Parent.Name) end end
  -- floating: the kit base is the ground the kit stood on; the ground under the copy centre
  local rp = RaycastParams.new(); rp.FilterType = Enum.RaycastFilterType.Exclude; rp.FilterDescendantsInstances = { m, cluster }
  local hit = workspace:Raycast(Vector3.new(ccf.Position.X, lowY + 5, ccf.Position.Z), Vector3.new(0, -50, 0), rp)
  local look = m:GetPivot().LookVector
  p("row %d kit=%s kitParts=%d kitBox=%.1fx%.1fx%.1f copyParts=%d copyBox=%.1fx%.1fx%.1f bottom=%.2f kitBase=%.2f groundHit=%s groundY=%s look=%.2f,%.2f kitLook=%.2f,%.2f overlaps=%d %s",
    i, cluster.Name, #parts, ksz.X, ksz.Y, ksz.Z, n, csz.X, csz.Y, csz.Z, ccf.Position.Y - csz.Y / 2, lowY, hit and hit.Instance.Name or "none", hit and string.format("%.2f", hit.Position.Y) or "-",
    look.X, look.Z, kp.CFrame.LookVector.X, kp.CFrame.LookVector.Z, #names, table.concat(names, ","))
end
return table.concat(out, "\n")
-- output 2026-09-30 ~23:25 Dublin, Open Cloud Luau on place 97112936860418:
-- COMPLETE
-- None
-- template scripts after trim=0 parts=4 size=1.64x2.00x1.03
-- row 1 kit=NW_Stall_1 kitParts=7 kitBox=10.6x7.5x9.0 copyParts=1 copyBox=8.2x10.0x5.1 bottom=0.50 kitBase=0.50 groundHit=none groundY=- look=-0.00,-1.00 kitLook=-0.00,-1.00 overlaps=0 
-- row 2 kit=NW_Stall_2 kitParts=7 kitBox=10.6x7.5x9.0 copyParts=1 copyBox=8.2x10.0x5.1 bottom=0.50 kitBase=0.50 groundHit=none groundY=- look=0.00,1.00 kitLook=0.00,1.00 overlaps=0 
