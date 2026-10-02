--!strict
--[[
	claude-bud JOB 40 part E (2026-09-30): the base owner markers' DATA (BaseMarkerConfig). Publishes one Configuration
	per plot under ReplicatedStorage.WE_BaseMarkers ("Plot<N>") with attributes:
	  Owner (UserId, nil = open), Name (DisplayName), User (@username), Nation (a NationConfig id the owner shows,
	  from the plot's NationFlag view, nil = none), Prestige, Clan (the clan tag), ClanId, Pos (the plot centre).
	Written only when a value changes. Updated on a plot claim (BaseService.OnPlotReady), a leave, and a slow 5 s sweep
	(rebirths, nation picks, clan changes). Nothing per frame. The client (BaseMarkerController) decides who sees what.
	The data is public (the same the v123 sign shows); it is published for every plot whatever the flag, but no client
	draws a marker unless BaseMarkerConfig is live for that viewer.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BaseMarkerConfig = require(Shared.Configs.BaseMarkerConfig)

local BaseMarkerService = {}

local deps: { [string]: any } = {}
local NationFlagMod: any = nil

local function folder(): Folder
	local f = ReplicatedStorage:FindFirstChild(BaseMarkerConfig.FolderName)
	if f and f:IsA("Folder") then
		return f
	end
	local nf = Instance.new("Folder")
	nf.Name = BaseMarkerConfig.FolderName
	nf.Parent = ReplicatedStorage
	return nf
end

local function setAttr(inst: Instance, k: string, v: any)
	if inst:GetAttribute(k) ~= v then
		inst:SetAttribute(k, v)
	end
end

-- the published record for a plot (pure-ish: reads services; the tests call it with stubs)
function BaseMarkerService.PlotData(plotId: number): { [string]: any }
	local out: { [string]: any } = {}
	local bs = deps.BaseService
	local ownerId = if bs and bs.GetOwnerUserId then bs.GetOwnerUserId(plotId) else nil
	local owner = if ownerId then Players:GetPlayerByUserId(ownerId) else nil
	if owner == nil then
		return out
	end
	out.Owner = owner.UserId
	out.Name = owner.DisplayName
	out.User = owner.Name
	local profile = deps.DataService and deps.DataService.GetProfile(owner)
	out.Prestige = if profile then math.max(0, math.floor(tonumber(profile.Prestige) or 0)) else 0
	-- claude-bud JOB 41 part B: the Recruit Pack's gold trim (an entitlement, no stat; the pack's owner-first flag)
	local okRec, live = pcall(function(): boolean
		local MC: any = require(Shared.Configs.MonetizationConfig)
		return MC.RecruitPackLiveFor(owner.UserId) == true and owner:GetAttribute("WE_Ent_RecruitPack") == true
	end)
	out.Recruit = if okRec and live == true then true else nil
	local view = if NationFlagMod and NationFlagMod.ViewOf then NationFlagMod.ViewOf(plotId) else nil
	if view and view.Show == true and typeof(view.NationId) == "string" then
		local okN, NC = pcall(function(): any
			return require(Shared.Configs.NationConfig)
		end)
		local neutral = if okN and NC then NC.NeutralId else nil
		if view.NationId ~= neutral then
			out.Nation = view.NationId
		end
	end
	local cs = deps.ClanService
	local okC, clanId = pcall(function()
		return cs and cs.GetClanId and cs.GetClanId(owner)
	end)
	if okC and typeof(clanId) == "string" then
		out.ClanId = clanId
		local okR, rec = pcall(function()
			return cs.GetClan(clanId)
		end)
		if okR and typeof(rec) == "table" and typeof(rec.Tag) == "string" then
			out.Clan = rec.Tag
		end
	end
	return out
end

local function plotCentre(plotId: number): Vector3?
	local setup = Workspace:FindFirstChild("WarEmpireSetup")
	local bases = setup and setup:FindFirstChild("Bases")
	local f = bases and bases:FindFirstChild("Plot" .. tostring(plotId))
	local pad = f and f:FindFirstChild("PlotPad")
	if pad and pad:IsA("BasePart") then
		return pad.Position + Vector3.new(0, pad.Size.Y * 0.5, 0)
	end
	return nil
end

function BaseMarkerService.Refresh(plotId: number)
	local root = folder()
	local name = "Plot" .. tostring(plotId)
	local c = root:FindFirstChild(name)
	if c == nil then
		local nc = Instance.new("Configuration")
		nc.Name = name
		nc.Parent = root
		c = nc
	end
	local conf = c :: Instance
	local d = BaseMarkerService.PlotData(plotId)
	setAttr(conf, "PlotId", plotId)
	setAttr(conf, "Pos", plotCentre(plotId) or conf:GetAttribute("Pos"))
	for _, k in ipairs({ "Owner", "Name", "User", "Nation", "Prestige", "Clan", "ClanId", "Recruit" }) do
		setAttr(conf, k, d[k])
	end
end

function BaseMarkerService.RefreshAll()
	local setup = Workspace:FindFirstChild("WarEmpireSetup")
	local bases = setup and setup:FindFirstChild("Bases")
	for _, f in ipairs(if bases then bases:GetChildren() else {}) do
		local id = tonumber(string.match(f.Name, "^Plot(%d+)$"))
		if id then
			pcall(BaseMarkerService.Refresh, id)
		end
	end
end

function BaseMarkerService.Init(d: { [string]: any })
	deps = d
	if BaseMarkerConfig.Live.Enabled ~= true then
		return
	end
	local okNF, nf = pcall(function(): any
		return require(script.Parent.Parent.Modules.NationFlag)
	end)
	NationFlagMod = if okNF then nf else nil
	local bs = d.BaseService
	if bs and bs.OnPlotReady then
		bs.OnPlotReady(function(_player: Player, plotId: number)
			pcall(BaseMarkerService.Refresh, plotId)
		end)
	end
	Players.PlayerRemoving:Connect(function()
		task.delay(1, BaseMarkerService.RefreshAll) -- the plot is released a moment after he leaves
	end)
	task.spawn(function()
		while true do
			pcall(BaseMarkerService.RefreshAll)
			task.wait(BaseMarkerConfig.RefreshSeconds)
		end
	end)
	print("[WAR EMPIRE] BaseMarkerService Init")
end

return BaseMarkerService
