-- v151 Code Bot: JOB 40C candidate load + detail + origin-id probe (read-only; loads, measures, destroys)
local IS = game:GetService("InsertService")
local ids = {856258654,91764409,124247102466690,110033425601385,37473580,12972439539,10140810871,10480494876,1660469777,5437548774,9230948087,12735882090,11921729320,11921736228,8887518461,86311252190175,388036950,2033520495,740042082}
local STRIP = { "LuaSourceContainer","Humanoid","Sound","ProximityPrompt","ClickDetector","Dialog","BodyMover","Constraint",
 "JointInstance","WeldConstraint","NoCollisionConstraint","ParticleEmitter","Fire","Smoke","Sparkles","Beam","Trail","Explosion",
 "ForceField","Tool","BillboardGui","ScreenGui","RemoteEvent","RemoteFunction","BindableEvent","BindableFunction","AnimationController","Animator" }
local out = {}
local function p(...) table.insert(out, string.format(...)) end
for _, id in ipairs(ids) do
  local ok, m = pcall(function() return IS:LoadAsset(id) end)
  if not ok or m == nil then
    p("FAIL %d load %s", id, tostring(m):sub(1,160))
    continue
  end
  local scripts, hum = 0, 0
  for _, d in ipairs(m:GetDescendants()) do
    if d:IsA("LuaSourceContainer") then scripts += 1 elseif d:IsA("Humanoid") then hum += 1 end
  end
  local kill = {}
  for _, d in ipairs(m:GetDescendants()) do
    for _, c in ipairs(STRIP) do if d:IsA(c) then table.insert(kill, d) break end end
  end
  for _, d in ipairs(kill) do pcall(function() d:Destroy() end) end
  local parts, meshp, unions, spm, blocks, other, decals, sa = 0,0,0,0,0,0,0,0
  local assets, names = {}, {}
  local mats = {}
  local function add(v) local s = tostring(v or ""); local n = s:match("(%d%d%d+)"); if n then assets[n] = true end end
  local mn, mx
  for _, d in ipairs(m:GetDescendants()) do
    names[d.Name] = true
    if d:IsA("BasePart") then
      if d.Transparency >= 0.95 and not d.CanCollide then continue end
      parts += 1
      mats[d.Material.Name] = true
      if d:IsA("MeshPart") then meshp += 1; add(d.MeshId); add(d.TextureID)
      elseif d:IsA("UnionOperation") then unions += 1
      else
        local sm = d:FindFirstChildWhichIsA("SpecialMesh") or d:FindFirstChildWhichIsA("FileMesh")
        if sm then spm += 1; add((sm :: any).MeshId); add((sm :: any).TextureId)
        elseif d:IsA("Part") and d.Shape == Enum.PartType.Block then blocks += 1 else other += 1 end
      end
      local h = d.Size*0.5; local a, b = d.Position - h, d.Position + h
      mn = if mn then mn:Min(a) else a; mx = if mx then mx:Max(b) else b
    elseif d:IsA("Decal") or d:IsA("Texture") then decals += 1; add(d.Texture)
    elseif d:IsA("SurfaceAppearance") then sa += 1; add(d.ColorMap); add(d.NormalMap); add(d.RoughnessMap); add(d.MetalnessMap)
    end
  end
  local al = {}; for a in pairs(assets) do table.insert(al, a) end
  local nl = {}; for n in pairs(names) do table.insert(nl, n) end
  local ml = {}; for n in pairs(mats) do table.insert(ml, n) end
  local sz = if mn then mx - mn else Vector3.zero
  p("OK %d parts=%d mesh=%d union=%d spm=%d block=%d other=%d decal=%d sa=%d scripts=%d hum=%d size=%.1fx%.1fx%.1f mats=%s", id, parts, meshp, unions, spm, blocks, other, decals, sa, scripts, hum, sz.X, sz.Y, sz.Z, table.concat(ml, ","))
  p("ASSETS %d %s", id, table.concat(al, ","))
  p("NAMES %d %s", id, table.concat(nl, "|"):sub(1, 600))
  m:Destroy()
end
return table.concat(out, "\n")
