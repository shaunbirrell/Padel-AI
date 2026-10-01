--!strict
--[[ claude-bud JOB 58: real aircraft / boats in the hangar and at the dock (Shared/Configs/HangarDockConfig).

	For an owned plot (owner-first by the plot owner): each Part jet slot in the Airfield hangar (its JetFuselage) gets
	the approved store body of HangarDockConfig.Hangar.Bodies[slot], and the dock's Part patrol boat (its BoatHull)
	the first allowed body of Dock.Bodies, through VisualAssetService.CloneDisplayBody (anchored, no collide / query
	/ touch; BodyAllowed exactly as for a driven vehicle). ONLY when a body is placed do the Part pieces under it go
	(Transparency 1, no collide / query; WE_DisplayHidden, kept hidden if a level look re-shows them). No body = the
	Part build stays. Display models live in Workspace.WE_HangarDock.Plot<N>; rebuilt on plot-ready and on an Airfield /
	Dock upgrade (after the Part build), cleared when the owner leaves. ]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared", 60)
local HangarDockConfig = require(Shared.Configs.HangarDockConfig)
local RetentionConfig = require(Shared.Configs.RetentionConfig)

local HangarDockDisplayService = {}

local deps: { [string]: any } = {}
local C: any = HangarDockConfig
local plotOwner: { [number]: number } = {}

function HangarDockDisplayService.Live(ownerUserId: number): boolean
	return RetentionConfig.Live(C, ownerUserId)
end

local function root(): Folder
	local f = Workspace:FindFirstChild("WE_HangarDock")
	if f == nil then
		local nf = Instance.new("Folder")
		nf.Name = "WE_HangarDock"
		nf.Parent = Workspace
		f = nf
	end
	return f :: Folder
end

local function plotFolder(plotId: number): Instance?
	local setup = Workspace:FindFirstChild("WarEmpireSetup")
	local bases = setup and setup:FindFirstChild("Bases")
	return bases and bases:FindFirstChild("Plot" .. plotId)
end

--[[ the display frame of a slot (pure; the tests). kind "Hangar": the Part jet's fuselage (a cylinder turned 90 deg:
	its frame is the jet's with +Z = the nose); "Dock": the boat hull (+X = the bow). Returns a kit-front frame (its
	-Z / LookVector = the nose / bow) on the floor / waterline, then turned by the body's Yaw like a driven body. ]]
function HangarDockDisplayService.FrameFor(kind: string, anchor: CFrame, anchorSize: Vector3, yawDeg: number): CFrame
	local front: Vector3
	local floorY: number
	if kind == "Hangar" then
		local jet = anchor * CFrame.Angles(0, math.rad(-90), 0) -- the jet's own frame (+Z = nose)
		front = -jet.LookVector
		floorY = anchor.Y - C.Hangar.FloorDrop
	else
		front = anchor.RightVector -- the bow
		floorY = anchor.Y - anchorSize.Y / 2 - 0.9 - C.Dock.Sink -- the boot-top under the hull, then the draft
	end
	local pos = Vector3.new(anchor.X, floorY, anchor.Z)
	return CFrame.lookAt(pos, pos + Vector3.new(front.X, 0, front.Z)) * CFrame.Angles(0, math.rad(yawDeg), 0)
end

local function hidePart(p: BasePart)
	if p:GetAttribute("WE_DisplayHidden") then
		return
	end
	p:SetAttribute("WE_DisplayHidden", true)
	p.Transparency = 1
	p.CanCollide = false
	p.CanQuery = false
	p:GetPropertyChangedSignal("Transparency"):Connect(function()
		if p:GetAttribute("WE_DisplayHidden") and p.Transparency < 1 then
			p.Transparency = 1
		end
	end)
end

-- the Part pieces of one slot near a placed body (by name, within HideRadius of the anchor)
function HangarDockDisplayService.HideNear(scope: Instance, names: { string }, at: Vector3, radius: number): number
	local want: { [string]: boolean } = {}
	for _, n in ipairs(names) do
		want[n] = true
	end
	local n = 0
	for _, d in ipairs(scope:GetDescendants()) do
		if d:IsA("BasePart") and want[d.Name] and (d.Position - at).Magnitude <= radius then
			hidePart(d)
			n += 1
		end
	end
	return n
end

-- place a body on one anchor; true when placed (then its Part pieces go)
local function placeOne(kind: string, anchor: BasePart, vehicleIds: { string }, owner: number, scope: Instance, parent: Instance): string?
	local vas = deps.VisualAssetService
	if vas == nil or vas.CloneDisplayBody == nil then
		return nil
	end
	local cfg = C[kind]
	for _, vid in ipairs(vehicleIds) do
		local ok, model, yaw = pcall(vas.CloneDisplayBody, vid, owner, cfg.FitLength)
		if ok and model then
			local m = model :: Model
			local cf = HangarDockDisplayService.FrameFor(kind, anchor.CFrame, anchor.Size, yaw)
			m:PivotTo(cf) -- a static prop placed once (no player / unit is ever moved)
			local bb, size = m:GetBoundingBox()
			m:PivotTo(m:GetPivot() + Vector3.new(0, cf.Y - (bb.Y - size.Y / 2), 0)) -- its lowest point on the floor / waterline
			m.Parent = parent
			HangarDockDisplayService.HideNear(scope, cfg.Hide, anchor.Position, cfg.HideRadius)
			return vid
		end
	end
	return nil
end

function HangarDockDisplayService.Clear(plotId: number)
	plotOwner[plotId] = nil
	local f = root():FindFirstChild("Plot" .. plotId)
	if f then
		f:Destroy()
	end
end

-- (re)place one owned plot's showpieces (owner-first; nil owner / OFF = cleared). Returns the bodies placed.
function HangarDockDisplayService.Sync(plotId: number, ownerUserId: number?): number
	HangarDockDisplayService.Clear(plotId)
	if ownerUserId == nil or not C.Enabled or not HangarDockDisplayService.Live(ownerUserId) then
		return 0
	end
	local scope = plotFolder(plotId)
	if scope == nil then
		return 0
	end
	local f = Instance.new("Folder")
	f.Name = "Plot" .. plotId
	f.Parent = root()
	plotOwner[plotId] = ownerUserId
	local placed: { string } = {}
	local slot = 0
	for _, d in ipairs(scope:GetDescendants()) do
		if d:IsA("BasePart") and d.Name == C.Hangar.Anchor then -- (a hidden fuselage is still the slot's marker)
			slot += 1
			local vid = C.Hangar.Bodies[math.min(slot, #C.Hangar.Bodies)]
			local got = placeOne("Hangar", d, { vid }, ownerUserId, scope, f)
			if got then
				table.insert(placed, "hangar:" .. got)
			end
		end
	end
	for _, d in ipairs(scope:GetDescendants()) do
		-- the boat is built (L1+: shown, or hidden by an earlier showpiece); a dock below L1 keeps it see-through
		if d:IsA("BasePart") and d.Name == C.Dock.Anchor and (d:GetAttribute("WE_DisplayHidden") == true or d.Transparency < 1) then
			local got = placeOne("Dock", d, C.Dock.Bodies, ownerUserId, scope, f)
			if got then
				table.insert(placed, "dock:" .. got)
			end
			break
		end
	end
	print(string.format("[HangarDock] plot=%d owner=%d placed=[%s]", plotId, ownerUserId, table.concat(placed, ",")))
	return #placed
end

local function syncPlayer(player: Player, plotId: number?)
	local bs = deps.BaseService
	local pid = plotId or (if bs and bs.GetOwnedPlotId then bs.GetOwnedPlotId(player) else nil)
	if typeof(pid) == "number" and player.Parent then
		HangarDockDisplayService.Sync(pid, player.UserId)
	end
end

function HangarDockDisplayService.Init(d: { [string]: any })
	deps = d
	if not C.Enabled then
		return
	end
	local bs = d.BaseService
	if bs and bs.OnPlotReady then
		pcall(bs.OnPlotReady, function(player: Player, plotId: number)
			task.delay(C.ResyncDelay, syncPlayer, player, plotId)
		end)
	end
	if bs and bs.GetUpgradeChangedEvent then
		bs.GetUpgradeChangedEvent().Event:Connect(function(userId: number, plotId: number?, structureId: string?, _level: number?)
			if structureId == "Airfield" or structureId == "Dock" then
				local p = Players:GetPlayerByUserId(userId)
				if p then
					task.delay(C.ResyncDelay, syncPlayer, p, plotId)
				end
			end
		end)
	end
	Players.PlayerRemoving:Connect(function(p: Player)
		for plotId, uid in pairs(plotOwner) do
			if uid == p.UserId then
				HangarDockDisplayService.Clear(plotId)
			end
		end
	end)
	print("[WAR EMPIRE] HangarDockDisplayService Init")
end

return HangarDockDisplayService
