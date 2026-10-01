--!strict
--[[
	claude-bud JOB 46 (2026-10-01, Shaun: "before you buy them it's not clear what you're buying or what it gives you").
	ROOT CAUSE: the only pre-purchase information was the console prompt's ObjectText ("<Name> $cost"), and the HUD's
	prompt pill shows the ActionText only ("BUILD"); nothing said what a zone gives or what you can do there.
	THE CARD: while a rebirth zone's BUILD / UPGRADE prompt is shown (ProximityPromptService.PromptShown on a
	"WE_ZonePrompt", which carries ZoneId + Level), one card in the HUD's top stack (HudLayout.RegisterTopStack: no overlap
	with the other top-stack items, never under the thumbstick / fire / jump):
	  <BUILDING NAME>   Level 1 -> 2 · $180,000
	  +$70/s income · +10 soldiers ...   (the NEXT level's exact gains: RebirthZonesConfig.CardFor, from the config)
	  Here: <what you can do there>       (RebirthZonesConfig.Info.Do)
	It hides with the prompt. Display only; the server decides every purchase.
	ZoneOpen (FeaturePush from the area's activity): opens the Elite Training list (EndgameController) or the missile
	strike panel (MissileController). No fast travel; nothing moves the player.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")

local Shared = ReplicatedStorage:WaitForChild("Shared", 60)
if not Shared then
	warn("[WAR EMPIRE] RebirthZoneController: no ReplicatedStorage.Shared after 60 s; not started")
	return {}
end
local Constants = require(Shared.Constants)
local Remotes = require(Shared.Remotes)
local RebirthZonesConfig = require(Shared.Configs.RebirthZonesConfig)
local EconomyConfig = require(Shared.Configs.EconomyConfig)

local HudLayout = require(script.Parent.Parent.Modules.HudLayout)

local RebirthZoneController = {}

local ZC: any = RebirthZonesConfig
local player = Players.LocalPlayer
local GOLD = Color3.fromRGB(255, 205, 60)
local PLATE = Color3.fromRGB(22, 24, 20)
local GREEN = Color3.fromRGB(150, 230, 140)
local STACK = "RebirthZoneCard"

local gui: ScreenGui? = nil
local card: Frame? = nil
local lines: { TextLabel } = {}
local current: ProximityPrompt? = nil

local function commas(n: number): string
	local s = tostring(math.floor(n))
	return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

local function build()
	local pg = player:FindFirstChildOfClass("PlayerGui")
	if pg == nil then
		return
	end
	local g = Instance.new("ScreenGui")
	g.Name = "WE_RebirthZoneCard"
	g.ResetOnSpawn = false
	g.DisplayOrder = 34
	g.Enabled = false
	g.Parent = pg
	gui = g
	local f = Instance.new("Frame")
	f.Name = "Card"
	f.AnchorPoint = Vector2.new(0.5, 0)
	f.Position = UDim2.new(0.5, 0, 0, 80)
	f.Size = UDim2.fromOffset(500, 150)
	f.BackgroundColor3 = PLATE
	f.BackgroundTransparency = 0.08
	f.Parent = g
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 14)
	c.Parent = f
	local st = Instance.new("UIStroke")
	st.Color = GOLD
	st.Thickness = 2
	st.Parent = f
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 16)
	pad.PaddingRight = UDim.new(0, 16)
	pad.PaddingTop = UDim.new(0, 10)
	pad.PaddingBottom = UDim.new(0, 10)
	pad.Parent = f
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 4)
	list.Parent = f
	type Spec = { Size: number, Color: Color3, Font: Enum.Font }
	local specs: { Spec } = {
		{ Size = 26, Color = GOLD, Font = Enum.Font.GothamBlack },
		{ Size = 21, Color = Color3.new(1, 1, 1), Font = Enum.Font.GothamBold },
		{ Size = 21, Color = GREEN, Font = Enum.Font.GothamBold },
		{ Size = 20, Color = Color3.fromRGB(215, 205, 170), Font = Enum.Font.GothamMedium },
	}
	for i, sp in ipairs(specs) do
		local l = Instance.new("TextLabel")
		l.Name = "Line" .. i
		l.LayoutOrder = i
		l.BackgroundTransparency = 1
		l.Size = UDim2.new(1, 0, 0, sp.Size + 6)
		l.Font = sp.Font
		l.TextSize = sp.Size -- code px under the HUD UIScale (>= 14 px real on a phone)
		l.TextColor3 = sp.Color
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.TextTruncate = Enum.TextTruncate.AtEnd
		l.Parent = f
		lines[i] = l
	end
	card = f
	pcall(HudLayout.ApplyScreen, g)
end

local function hide()
	current = nil
	local g = gui
	if g then
		g.Enabled = false
	end
	pcall(HudLayout.UnregisterTopStack, STACK)
end

local function show(prompt: ProximityPrompt)
	local zoneId = prompt:GetAttribute("ZoneId")
	local level = tonumber(prompt:GetAttribute("Level")) or 0
	if typeof(zoneId) ~= "string" then
		return
	end
	local data = ZC.CardFor(zoneId, level, tonumber(EconomyConfig.PassiveIncome.TickSeconds) or 5)
	if data == nil then
		return
	end
	if gui == nil then
		build()
	end
	local g, f = gui, card
	if g == nil or f == nil then
		return
	end
	current = prompt
	lines[1].Text = data.Title
	lines[2].Text = if data.Maxed then string.format("Level %d (MAX)", data.Level)
		elseif data.Level == 0 then string.format("BUILD · $%s", commas(data.Cost))
		else string.format("Level %d → %d · $%s", data.Level, data.NextLevel, commas(data.Cost))
	lines[3].Text = (if data.Maxed then "Gives: " else "Gets you: ") .. table.concat(data.Gains, " · ")
	lines[4].Text = "Here: " .. data.Do
	g.Enabled = true
	pcall(HudLayout.RegisterTopStack, STACK, f, 14)
end

function RebirthZoneController.Init()
	ProximityPromptService.PromptShown:Connect(function(prompt: ProximityPrompt)
		if prompt.Name == "WE_ZonePrompt" then
			show(prompt)
		end
	end)
	ProximityPromptService.PromptHidden:Connect(function(prompt: ProximityPrompt)
		if prompt == current then
			hide()
		end
	end)
	Remotes.BindEvent(Constants.RemoteNames.FeaturePush, function(kind: any, data: any)
		if kind ~= "ZoneOpen" or typeof(data) ~= "table" then
			return
		end
		if data.Panel == "Recruits" then
			local ok, EC = pcall(function(): any
				return require(script.Parent.EndgameController)
			end)
			if ok and EC and EC.OpenStation then
				EC.OpenStation("Recruits")
			end
		elseif data.Panel == "Missile" then
			local ok, MC = pcall(function(): any
				return require(script.Parent.MissileController)
			end)
			if ok and MC and MC.Open then
				MC.Open()
			end
		end
	end)
end

return RebirthZoneController
