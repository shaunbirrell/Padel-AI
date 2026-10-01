--!strict
--[[
	claude-bud JOB 45 (2026-10-01, Shaun bought the Recruit Pack live ~11:37 and saw NO visual change). ROOT CAUSE
	(traced in docs/proof/recruit-trim/REPORT.md): the entitlement WAS granted (MonetizationService.GrantEntitlement
	"RecruitPack" -> profile.Entitlements + WE_Ent_RecruitPack, set on purchase and again on every join), but no code ever
	built a trim on the base. The JOB 41 "gold trim" was only:
	  * a "RECRUIT · " text prefix and a thicker stroke on the gate sign's BillboardGui (BaseSignService);
	  * a gold stroke on the base owner marker, which hides itself inside 60 studs of your own base (BaseMarker).
	THE FIX (this service): a real GOLD GATE ARCH on the owner's plot, just inside the main gate: two gold-clad pillars
	(plinth, fluted shaft, capital, star finial), a gold crossbeam with an engraved trim band and a "RECRUIT" banner.
	  * Built for an owner with WE_Ent_RecruitPack (the existing entitlement path; no second flag) while
	    MonetizationConfig.RecruitPackLiveFor(owner); OFF = nothing built.
	  * Instant: the attribute's change signal (set in ProcessReceipt) builds it the same frame; a 5 s sweep rebuilds it
	    after a join / plot claim / rebirth / map rebuild, and removes it when the plot is released.
	  * Its own folder Workspace.WE_RecruitTrim (never a building-model part; never inside the base kits), non-colliding
	    decor (it never blocks the gate lane or the army), Parts only (no meshes, no lights).
	[RECRUIT] logs: every grant / build / remove.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MonetizationConfig = require(Shared.Configs.MonetizationConfig)
local BaseConfig = require(Shared.Configs.BaseConfig)
local BaseLayoutConfig = require(Shared.Configs.BaseLayoutConfig)
local PlotFrame = require(Shared.Util.PlotFrame)
local RecruitTrimConfig = require(Shared.Configs.RecruitTrimConfig)

local RecruitTrimService = {}

local MC: any = MonetizationConfig
local ATTR = "WE_Ent_RecruitPack"
local deps: { [string]: any } = {}
local built: { [number]: { Owner: number, Folder: Folder, Key: string }? } = {}

local function T(): any
	return RecruitTrimConfig
end

local function log(fmt: string, ...: any)
	print("[RECRUIT] " .. string.format(fmt, ...))
end

local function root(): Folder
	local f = Workspace:FindFirstChild("WE_RecruitTrim")
	if f == nil then
		local nf = Instance.new("Folder")
		nf.Name = "WE_RecruitTrim"
		nf.Parent = Workspace
		f = nf
	end
	return f :: Folder
end

-- the owner of a plot (a Player in this server) or nil
local function ownerOf(plotId: number): Player?
	local bs = deps.BaseService
	local uid = if bs and bs.GetOwnerUserId then bs.GetOwnerUserId(plotId) else nil
	return if typeof(uid) == "number" then Players:GetPlayerByUserId(uid) else nil
end

-- true when this player's plot should carry the trim
function RecruitTrimService.Wants(player: Player?): boolean
	local t = T()
	return player ~= nil and typeof(t) == "table" and t.Enabled == true and MC.RecruitPackLiveFor(player.UserId) == true
		and player:GetAttribute(ATTR) == true
end

local function part(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material, refl: number?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.Reflectance = refl or 0
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function kid(parent: Instance?, name: string): Instance?
	return if parent then parent:FindFirstChild(name) else nil
end

--[[ Code Bot v172: WHERE the arch stands (was: the plot's front edge minus 4 studs, at a raycast ground height).
	The front wall stands 1.5 studs in from the pad edge and is 3.5-6.3 studs thick (walls Lv 1-5), and its 10-stud gate
	sits between the GatePost parts, so the JOB 45 pillars (plot z 154.9-157.1) were INSIDE the wall body at every
	level, and the raycast from 60 studs up could land on the GateArch / gatehouse lintel and float the arch on top.
	Now the arch reads the REAL gate: the two GatePost parts in the plot's WE_PerimeterWalls (StructureKitBuilder),
	the gate-face wall's thickness and height, and the pad top. It stands GateFurnitureStuds + WallClearStuds behind the
	wall's inner face (clear of the gate posts' roofs, the Tier 3 gatehouse, the Bastion crest, the v171 gold wall
	bands) and in front of the gate guards (10 studs inside), and rises HeightOverWall above the wall so it reads from
	outside at every walls level and the banner hangs above the gate opening's height (whatever fits through the gate
	fits under it). No walls (Lv 0): the old front-edge spot, at the pad top. ]]
function RecruitTrimService.Placement(plotId: number): (CFrame?, number, string)
	local t = T()
	local setup = Workspace:FindFirstChild("WarEmpireSetup")
	local plotFolder = kid(kid(setup, "Bases"), "Plot" .. tostring(plotId))
	local pad = kid(plotFolder, "PlotPad")
	local peri = kid(plotFolder, "WE_PerimeterWalls")
	local posts: { BasePart } = {}
	local wallT, wallH = 0, 0
	if peri then
		for _, d in ipairs(peri:GetDescendants()) do
			if d:IsA("BasePart") then
				if d.Name == "GatePost" then
					table.insert(posts, d :: BasePart)
				elseif d:GetAttribute("WE_WallLevel") ~= nil and string.sub(d.Name, 1, 8) == "WallGate" then
					local s = (d :: BasePart).Size
					wallT = math.max(wallT, math.min(s.X, s.Z))
					wallH = math.max(wallH, s.Y)
				end
			end
		end
	end
	local H = t.Height
	if #posts >= 2 and pad and pad:IsA("BasePart") then
		local a, b = posts[1].Position, posts[2].Position
		local floorY = math.min(a.Y - posts[1].Size.Y * 0.5, b.Y - posts[2].Size.Y * 0.5)
		local mid = Vector3.new((a.X + b.X) * 0.5, floorY, (a.Z + b.Z) * 0.5)
		-- the walls are world-axis aligned: inward = toward the pad centre, across the post line
		local ix, iz = 0, 0
		if math.abs(b.X - a.X) >= math.abs(b.Z - a.Z) then
			iz = if pad.Position.Z >= mid.Z then 1 else -1
		else
			ix = if pad.Position.X >= mid.X then 1 else -1
		end
		if wallT <= 0 then
			wallT = posts[1].Size.X
		end
		if wallH <= 0 then
			wallH = posts[1].Size.Y - 1.5
		end
		-- local -Z = inward (LookVector), the same convention as GateDefenseService's gate frame
		local s, c = -ix, -iz
		local gate = CFrame.new(mid.X, mid.Y, mid.Z, c, 0, s, 0, 1, 0, -s, 0, c)
		local plinthHalf = (t.PillarWidth + 1.2) * 0.5
		-- the gate arch / chevron overhang the wall by 0.6-0.8 a side; the post roofs, gatehouse and crest reach 2.2-2.6
		local inset = math.max(wallT * 0.5 + 0.8, t.GateFurnitureStuds) + t.WallClearStuds + plinthHalf
		H = math.max(H, wallH + t.HeightOverWall)
		local key = string.format("G|%.1f|%.1f|%.1f|%d|%d|%.2f|%.2f", mid.X, mid.Y, mid.Z, ix, iz, wallT, H)
		return gate * CFrame.new(0, 0, -inset), H, key
	end
	local pos = PlotFrame.PlotPosition(plotId)
	if pos == nil then
		return nil, H, ""
	end
	local half = (BaseConfig.PlotSize and BaseConfig.PlotSize.X or 320) * 0.5
	local frame = PlotFrame.PlotCFrame(pos) * CFrame.new(0, 0, half - t.InsetStuds)
	if pad and pad:IsA("BasePart") then
		frame = frame + Vector3.new(0, pad.Position.Y + pad.Size.Y * 0.5 - frame.Position.Y, 0)
	end
	return frame, H, string.format("P|%.1f|%.1f|%.1f|%.2f", frame.Position.X, frame.Position.Y, frame.Position.Z, H)
end

-- the arch for one plot. Frame-local: x across the gate, y up from the plot surface, -z = into the base.
function RecruitTrimService.Build(plotId: number, owner: Player): (Folder?, string)
	local t = T()
	local frame, H, key = RecruitTrimService.Placement(plotId)
	if frame == nil then
		return nil, key
	end
	local gateHalf = (tonumber(BaseLayoutConfig.MainGateWidth) or 14) * 0.5
	local f = Instance.new("Folder")
	f.Name = "Plot" .. tostring(plotId)
	f:SetAttribute("Owner", owner.UserId)
	f:SetAttribute("WE_PlaceKey", key)
	local gold, dark, deep = t.Gold, t.GoldDark, t.Plinth
	local w = t.PillarWidth
	local px = gateHalf + t.PillarGap + w * 0.5
	local shaftH = H - 3.4
	for _, sx in ipairs({ -1, 1 }) do
		local c = frame * CFrame.new(sx * px, 0, 0)
		-- the plinth sinks 0.1 into the pad (no coplanar face with the ground / the road)
		part(f, "Plinth", Vector3.new(w + 1.2, 1.3, w + 1.2), c * CFrame.new(0, 0.55, 0), deep, Enum.Material.Slate)
		part(f, "Base", Vector3.new(w + 0.6, 0.6, w + 0.6), c * CFrame.new(0, 1.5, 0), dark, Enum.Material.Metal, 0.15)
		part(f, "Shaft", Vector3.new(w, shaftH, w), c * CFrame.new(0, 1.8 + shaftH * 0.5, 0), gold, Enum.Material.Metal, t.Reflectance)
		-- fluting: a darker rib proud of each shaft face, stopping short of the base and the capital
		for _, o in ipairs({ Vector3.new(w * 0.5, 0, 0), Vector3.new(-w * 0.5, 0, 0), Vector3.new(0, 0, w * 0.5), Vector3.new(0, 0, -w * 0.5) }) do
			part(f, "Rib", Vector3.new(if o.X ~= 0 then 0.2 else 0.5, shaftH - 1, if o.Z ~= 0 then 0.2 else 0.5), c * CFrame.new(o.X, 1.8 + shaftH * 0.5, o.Z), dark, Enum.Material.Metal, 0.1)
		end
		-- a gold collar a third of the way up
		part(f, "Collar", Vector3.new(w + 0.3, 0.4, w + 0.3), c * CFrame.new(0, 1.8 + shaftH * 0.33, 0), gold, Enum.Material.Metal, t.Reflectance)
		part(f, "Capital", Vector3.new(w + 0.8, 0.8, w + 0.8), c * CFrame.new(0, H - 1.2, 0), dark, Enum.Material.Metal, 0.15)
		part(f, "Cap", Vector3.new(w + 0.4, 0.5, w + 0.4), c * CFrame.new(0, H - 0.55, 0), gold, Enum.Material.Metal, t.Reflectance)
		-- the star finial ON the beam: a stem, then two crossed plates turned 45 degrees
		part(f, "FinialStem", Vector3.new(0.4, 0.8, 0.4), c * CFrame.new(0, H + 1.5, 0), dark, Enum.Material.Metal)
		local top = c * CFrame.new(0, H + 3.0, 0)
		part(f, "Finial", Vector3.new(1.6, 1.6, 0.3), top * CFrame.Angles(0, 0, math.rad(45)), gold, Enum.Material.Metal, t.Reflectance)
		part(f, "Finial", Vector3.new(0.3, 1.6, 1.6), top * CFrame.Angles(math.rad(45), 0, 0), gold, Enum.Material.Metal, t.Reflectance)
	end
	-- the crossbeam (on the caps) with a dark engraved band round its middle
	local span = px * 2 + w
	local beam = frame * CFrame.new(0, H + 0.4, 0)
	part(f, "Beam", Vector3.new(span, 1.4, w * 0.8), beam, gold, Enum.Material.Metal, t.Reflectance)
	part(f, "BeamBand", Vector3.new(span + 0.1, 0.35, w * 0.8 + 0.1), beam, dark, Enum.Material.Metal, 0.1)
	-- the RECRUIT banner, hung from the beam on two gold rods, gold-edged on all four sides
	local bw, bh = t.BannerSize.X, t.BannerSize.Y
	local bTop = H - 1.6
	local banner = part(f, "Banner", Vector3.new(bw, bh, 0.3), frame * CFrame.new(0, bTop - bh * 0.5, 0), t.BannerColor, Enum.Material.Fabric)
	for _, sx in ipairs({ -1, 1 }) do
		part(f, "BannerRod", Vector3.new(0.2, 1.45, 0.2), frame * CFrame.new(sx * (bw * 0.5 - 1), bTop + 0.65, 0), gold, Enum.Material.Metal, t.Reflectance)
		part(f, "BannerSide", Vector3.new(0.3, bh - 0.1, 0.4), banner.CFrame * CFrame.new(sx * bw * 0.5, 0, 0), gold, Enum.Material.Metal, t.Reflectance)
	end
	part(f, "BannerEdge", Vector3.new(bw + 0.4, 0.3, 0.42), banner.CFrame * CFrame.new(0, bh * 0.5, 0), gold, Enum.Material.Metal, t.Reflectance)
	part(f, "BannerEdge", Vector3.new(bw + 0.4, 0.3, 0.42), banner.CFrame * CFrame.new(0, -bh * 0.5, 0), gold, Enum.Material.Metal, t.Reflectance)
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local g = Instance.new("SurfaceGui")
		g.Face = face
		g.MaxDistance = t.TextMaxDistance
		g.LightInfluence = 0
		g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		g.PixelsPerStud = 40
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Size = UDim2.fromScale(1, 1)
		l.Font = Enum.Font.GothamBlack
		l.TextScaled = true
		l.TextColor3 = gold
		l.TextStrokeColor3 = Color3.fromRGB(40, 28, 6)
		l.TextStrokeTransparency = 0.3
		l.Text = "★ " .. t.Text .. " ★"
		l.Parent = g
		g.Parent = banner
	end
	f.Parent = root()
	return f, key
end

-- bring one plot in line with its owner's entitlement (build / keep / move / remove)
function RecruitTrimService.Sync(plotId: number)
	local owner = ownerOf(plotId)
	local want = RecruitTrimService.Wants(owner)
	local cur = built[plotId]
	-- Code Bot v172: a walls upgrade / map rebuild moves the gate face: rebuild the arch at its new spot
	local moved = false
	if cur and want then
		local _, _, key = RecruitTrimService.Placement(plotId)
		moved = key ~= cur.Key
	end
	if cur and (not want or owner == nil or cur.Owner ~= owner.UserId or cur.Folder.Parent == nil or moved) then
		if cur.Folder.Parent then
			cur.Folder:Destroy()
		end
		built[plotId] = nil
		log("removed the trim on plot %d%s", plotId, if moved then " (the gate moved: rebuilding)" else "")
		cur = nil
	end
	if want and owner and cur == nil then
		local f, key = RecruitTrimService.Build(plotId, owner :: Player)
		if f then
			built[plotId] = { Owner = (owner :: Player).UserId, Folder = f, Key = key }
			log("built the gold trim on plot %d for %s (%d parts)", plotId, (owner :: Player).Name, #f:GetChildren())
		end
	end
end

function RecruitTrimService.SyncAll()
	for plotId = 1, BaseConfig.MaxPlots do
		pcall(RecruitTrimService.Sync, plotId)
	end
end

function RecruitTrimService._Built(): { [number]: any }
	return built
end

local function plotOf(player: Player): number?
	local bs = deps.BaseService
	local id = if bs and bs.GetOwnedPlotId then bs.GetOwnedPlotId(player) else nil
	return if typeof(id) == "number" then id else nil
end

local function watch(player: Player)
	player:GetAttributeChangedSignal(ATTR):Connect(function()
		log("%s %s = %s (plot %s)", player.Name, ATTR, tostring(player:GetAttribute(ATTR)), tostring(plotOf(player)))
		local id = plotOf(player)
		if id then
			RecruitTrimService.Sync(id)
		end
	end)
end

function RecruitTrimService.Init(d: { [string]: any })
	deps = d
	local t = T()
	if typeof(t) ~= "table" or t.Enabled ~= true then
		print("[WAR EMPIRE] RecruitTrimService: off (RecruitTrimConfig.Enabled = false)")
		return
	end
	Players.PlayerAdded:Connect(watch)
	for _, p in ipairs(Players:GetPlayers()) do
		watch(p)
	end
	task.spawn(function()
		while true do
			task.wait(t.SweepSeconds)
			RecruitTrimService.SyncAll()
		end
	end)
	print("[WAR EMPIRE] RecruitTrimService Init")
end

return RecruitTrimService
