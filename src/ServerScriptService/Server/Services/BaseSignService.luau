--!strict
--[[
	claude-bud JOB 25: the "<Name>'s Empire" sign above every base plot (Shared/Configs/BaseSignConfig; read its header).
	One Model per plot (Workspace.WE_BaseSigns.Sign<plotId>): an invisible anchor part HeightStuds above the plot's main
	gate carrying a BillboardGui (headshot, name, stats line) and a flag plate part beside it dressed by NationFlag
	(Textures, the owner's chosen national flag; plain green without one). Rebuilt text only when the shown key changes
	(checked every UpdateSeconds for the 10 plots: no per-frame work, a handful of property writes per change).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BaseConfig = require(Shared.Configs.BaseConfig)
local BaseSignConfig = require(Shared.Configs.BaseSignConfig)

local BaseSignService = {}

local deps: { [string]: any } = {}
local NationFlagMod: any = nil
local shownKey: { [number]: string } = {}
type Sign = { Model: Model, Anchor: BasePart, Plate: BasePart, Head: ImageLabel, Title: TextLabel, Line: TextLabel }
local signs: { [number]: Sign } = {}

local function folder(): Folder
	local f = Workspace:FindFirstChild("WE_BaseSigns")
	if f == nil then
		local nf = Instance.new("Folder")
		nf.Name = "WE_BaseSigns"
		nf.Parent = Workspace
		f = nf
	end
	return f :: Folder
end

local function label(parent: Instance, pos: UDim2, size: UDim2, font: Enum.Font, color: Color3): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Position = pos
	t.Size = size
	t.Font = font
	t.TextColor3 = color
	t.TextScaled = true
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextTruncate = Enum.TextTruncate.AtEnd
	local c = Instance.new("UITextSizeConstraint")
	c.MinTextSize = 14
	c.MaxTextSize = 26
	c.Parent = t
	t.Parent = parent
	return t
end

-- the sign's world spot: HeightStuds above the plot's gate (GateDefenseService), else above the plot centre
local function spotFor(plotId: number): CFrame?
	local gd = deps.GateDefenseService
	if gd and gd.GetGateCFrame then
		local ok, cf = pcall(gd.GetGateCFrame, plotId)
		if ok and typeof(cf) == "CFrame" then
			return cf + Vector3.new(0, BaseSignConfig.HeightStuds, 0)
		end
	end
	local pos = (BaseConfig :: any).PlotPositions and (BaseConfig :: any).PlotPositions[plotId]
	if typeof(pos) == "Vector3" then
		return CFrame.new(pos + Vector3.new(0, BaseSignConfig.HeightStuds + 20, 0))
	end
	return nil
end

local function ensureSign(plotId: number): Sign?
	local s = signs[plotId]
	if s and s.Model.Parent then
		return s
	end
	local cf = spotFor(plotId)
	if cf == nil then
		return nil
	end
	local C = BaseSignConfig
	local model = Instance.new("Model")
	model.Name = "Sign" .. plotId
	local anchor = Instance.new("Part")
	anchor.Name = "SignAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.CFrame = cf
	anchor.Parent = model
	local plate = Instance.new("Part")
	plate.Name = "SignFlag"
	plate.Anchored = true
	plate.CanCollide = false
	plate.CastShadow = false
	plate.Material = Enum.Material.Fabric
	plate.Color = Color3.fromRGB(74, 86, 58) -- army green (NationFlag restores it when nothing shows)
	plate.Size = C.FlagPlateSize
	plate.CFrame = cf * CFrame.new(0, C.FlagPlateSize.Y * 0.5 + 3.2, 0)
	plate.Parent = model
	local gui = Instance.new("BillboardGui")
	gui.Name = "WE_EmpireSign"
	gui.Size = UDim2.fromOffset(C.SizePx.X, C.SizePx.Y)
	gui.MaxDistance = C.MaxDistanceStuds
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = C.Plate
	bg.BackgroundTransparency = 0.12
	bg.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = bg
	local stroke = Instance.new("UIStroke")
	stroke.Color = C.Gold
	stroke.Thickness = 1.5
	stroke.Parent = bg
	local head = Instance.new("ImageLabel")
	head.Name = "Headshot"
	head.BackgroundColor3 = Color3.fromRGB(45, 48, 40)
	head.Position = UDim2.fromOffset(7, 7)
	head.Size = UDim2.fromOffset(C.SizePx.Y - 14, C.SizePx.Y - 14)
	head.Parent = bg
	local hc = Instance.new("UICorner")
	hc.CornerRadius = UDim.new(0, 6)
	hc.Parent = head
	local x = C.SizePx.Y
	local title = label(bg, UDim2.fromOffset(x, 6), UDim2.new(1, -x - 8, 0.55, -6), Enum.Font.GothamBlack, C.Gold)
	local line = label(bg, UDim2.new(0, x, 0.55, 2), UDim2.new(1, -x - 8, 0.4, -6), Enum.Font.GothamBold, C.Khaki)
	gui.Parent = anchor
	model.Parent = folder()
	local made: Sign = { Model = model, Anchor = anchor, Plate = plate, Head = head, Title = title, Line = line }
	signs[plotId] = made
	return made
end

-- claude-bud JOB 30: the ONE "<Name>'s Empire" string (the sign and the world map both use it)
local function titleOf(owner: Player): string
	local name = if owner.DisplayName ~= "" then owner.DisplayName else owner.Name -- (Roblox-filtered; CustomEmpireNames off)
	return name .. "'s Empire"
end

local function refresh(plotId: number)
	if BaseSignConfig.Enabled ~= true then
		return
	end
	local s = ensureSign(plotId)
	if s == nil then
		return
	end
	local bs = deps.BaseService
	local ownerId = if bs and bs.GetOwnerUserId then bs.GetOwnerUserId(plotId) else nil
	local owner = if ownerId then Players:GetPlayerByUserId(ownerId) else nil
	local key: string
	local recruit = false -- claude-bud JOB 41 B
	local title, line, image = BaseSignConfig.UnclaimedTitle, BaseSignConfig.UnclaimedLine, ""
	if owner then
		local profile = deps.DataService and deps.DataService.GetProfile(owner)
		local level = if profile then math.floor(tonumber(profile.Level) or 1) else 1
		local rebirth = if profile then math.floor(tonumber(profile.Prestige) or 0) else 0
		local army = if profile then math.floor(tonumber(profile.Soldiers) or 0) else 0
		title = titleOf(owner)
		line = string.format("LV %d · REBIRTH %d · ARMY %d", level, rebirth, army)
		-- claude-bud JOB 33: the rebirth title leads the line once earned ("COMMANDER R3 · LV 12 · ARMY 20")
		local okRC, RC = pcall(function(): any
			return require(game:GetService("ReplicatedStorage").Shared.Configs.RebirthConfig)
		end)
		local rankTitle = if okRC and RC.LiveFor(owner.UserId, "Trims") then RC.TitleFor(rebirth) else nil
		if rankTitle then
			line = string.format("%s R%d · LV %d · ARMY %d", string.upper(rankTitle), rebirth, level, army)
		end
		-- claude-bud JOB 39: "EMPIRE 12" after the rank (a gold star from Empire 5, the Marshal title at 30); owner-first
		local okEG, EG = pcall(function(): any
			return require(game:GetService("ReplicatedStorage").Shared.Configs.EndgameConfig)
		end)
		local empire = if okEG and EG.LiveFor(owner.UserId, "EmpireLevel") and profile and typeof(profile.Endgame) == "table"
			then math.floor(tonumber(profile.Endgame.EmpireLevel) or 0)
			else 0
		if empire > 0 then
			line ..= string.format(" · %sEMPIRE %d", if empire >= EG.Empire.StarLevel then "★ " else "", empire)
			if empire >= EG.Empire.MarshalLevel then
				title ..= " · " .. string.upper(EG.Empire.MarshalTitle)
			end
		end
		image = string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", owner.UserId)
		-- claude-bud JOB 41 part B: the Recruit Pack's gold "RECRUIT" trim (an entitlement, no stat; owner-first flag)
		local MC: any = require(game:GetService("ReplicatedStorage").Shared.Configs.MonetizationConfig)
		if MC.RecruitPackLiveFor(owner.UserId) and owner:GetAttribute("WE_Ent_RecruitPack") == true then
			line = "RECRUIT · " .. line
			recruit = true
		end
	end
	-- the flag plate shows what the plot's own flags show (NationFlag's view: the owner's pick, art permitting)
	local nf = NationFlagMod
	local view = if nf and nf.ViewOf then nf.ViewOf(plotId) else nil
	if owner == nil then
		view = nil
	end
	local flagKey = if view then tostring(view.NationId) .. tostring(view.Show) else "-"
	key = title .. "|" .. line .. "|" .. image .. "|" .. flagKey .. (if recruit then "|R" else "")
	if shownKey[plotId] == key then
		return
	end
	shownKey[plotId] = key
	s.Title.Text = title
	s.Line.Text = line
	local trim = s.Title.Parent and s.Title.Parent:FindFirstChildOfClass("UIStroke")
	if trim then
		trim.Thickness = if recruit then 3 else 1.5 -- claude-bud JOB 41 B: the gold Recruit trim (existing Part / stroke colour)
	end
	s.Head.Image = image
	s.Head.Visible = image ~= ""
	if nf and nf.DressPart then
		pcall(nf.DressPart, s.Plate, view)
	end
	s.Plate.Transparency = if owner then 0 else 1
end

-- claude-bud JOB 30: "<Name>'s Empire" for an owned plot (the sign's title), nil for an unclaimed one
function BaseSignService.TitleFor(plotId: number): string?
	local bs = deps and deps.BaseService
	local ownerId = if bs and bs.GetOwnerUserId then bs.GetOwnerUserId(plotId) else nil
	local owner = if ownerId then Players:GetPlayerByUserId(ownerId) else nil
	return if owner then titleOf(owner) else nil
end

function BaseSignService.Refresh(plotId: number?)
	if plotId then
		pcall(refresh, plotId)
		return
	end
	for id = 1, math.max(1, tonumber((BaseConfig :: any).MaxPlots) or 6) do
		pcall(refresh, id)
	end
end

function BaseSignService.Init(d: { [string]: any })
	deps = d
	if BaseSignConfig.Enabled ~= true then
		return
	end
	local okNF, nf = pcall(function()
		return require(script.Parent.Parent.Modules.NationFlag) :: any
	end)
	NationFlagMod = if okNF then nf else nil
	local bs = deps.BaseService
	if bs and bs.OnPlotReady then
		bs.OnPlotReady(function(_player: Player, plotId: number)
			BaseSignService.Refresh(plotId)
		end)
	end
	task.spawn(function()
		task.wait(3)
		while true do
			BaseSignService.Refresh(nil)
			task.wait(BaseSignConfig.UpdateSeconds)
		end
	end)
end

return BaseSignService
