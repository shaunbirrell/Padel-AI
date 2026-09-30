--!strict
--[[
	claude-bud JOB 34 (2026-09-30): achievement chat lines, banners and the earner's popup. Client only; it shows what
	AchievementService pushes (the server decides who earned what, once, and rate-limits the lines).
	  * FeaturePush "AchShout" { Name, Text, Big } (everyone): one styled system line in chat,
	    "[WAR EMPIRE] <name> <text>" (AchievementConfig.Chat colours; TextChatService RBXGeneral, or the legacy chat's
	    system message). Big = also a short banner in the top stack for everyone (AchievementConfig.Banner).
	  * FeaturePush "AchUnlocked" { Title, Desc, Cash, Gold, XP } (the earner): a small popup in the top stack + sound
	    (AchievementConfig.Popup), one at a time.
	Real px (no UIScale on these guis): text >= 15, no buttons, nothing covers the screen centre; the banners queue
	(MaxQueued, older ones skipped) so only one message shows at a time.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")
local StarterGui = game:GetService("StarterGui")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared", 60)
if not Shared then
	warn("[WAR EMPIRE] AchievementController: no ReplicatedStorage.Shared after 60 s; not started")
	return {}
end
local Constants = require(Shared.Constants)
local Remotes = require(Shared.Remotes)
local AchievementConfig = require(Shared.Configs.AchievementConfig)

local AchievementController = {}

local player = Players.LocalPlayer
local GOLD = Color3.fromRGB(255, 200, 60)
local PLATE = Color3.fromRGB(24, 22, 16)

-- rich-text safe (the server's text is config copy + a Roblox username, but never trust markup)
function AchievementController.Escape(s: string): string
	return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"))
end

-- the rich-text chat line
function AchievementController.Format(name: string, text: string, big: boolean): string
	local C = AchievementConfig.Chat
	local esc = AchievementController.Escape
	local body = esc(text)
	if big then
		body = "<b>" .. body .. "</b>"
	end
	return string.format(
		'<font color="%s"><b>%s</b></font> <font color="%s"><b>%s</b></font> <font color="%s">%s</font>',
		C.PrefixColor,
		esc(C.Prefix),
		C.NameColor,
		esc(name),
		if big then C.BigColor else C.TextColor,
		body
	)
end

local function chatLine(name: string, text: string, big: boolean)
	local okT = pcall(function()
		if TextChatService.ChatVersion ~= Enum.ChatVersion.TextChatService then
			error("legacy chat")
		end
		local chans = TextChatService:FindFirstChild("TextChannels")
		local ch = chans and (chans:FindFirstChild("RBXGeneral") or chans:FindFirstChild("RBXSystem"))
		if ch == nil or not ch:IsA("TextChannel") then
			error("no channel")
		end
		(ch :: TextChannel):DisplaySystemMessage(AchievementController.Format(name, text, big))
	end)
	if not okT then
		local C = AchievementConfig.Chat
		pcall(function()
			StarterGui:SetCore("ChatMakeSystemMessage", {
				Text = C.Prefix .. " " .. name .. " " .. text,
				Color = Color3.fromHex(if big then C.BigColor else C.PrefixColor),
				Font = Enum.Font.GothamBold,
			})
		end)
	end
end

local function screenGui(name: string): ScreenGui?
	local pg = player:FindFirstChildOfClass("PlayerGui")
	if pg == nil then
		return nil
	end
	local old = pg:FindFirstChild(name)
	if old then
		old:Destroy()
	end
	local g = Instance.new("ScreenGui")
	g.Name = name
	g.ResetOnSpawn = false
	g.IgnoreGuiInset = true
	g.DisplayOrder = 41
	g.Parent = pg
	return g
end

local function hud(): any
	local ok, H = pcall(require, script.Parent.Parent.Modules.HudLayout)
	return if ok and type(H) == "table" then H else nil
end

local function viewW(): number
	local cam = Workspace.CurrentCamera
	return if cam then cam.ViewportSize.X else 800
end

-- one card in the top stack for `seconds`, then gone
local function card(guiName: string, stackName: string, order: number, lines: { { Text: string, Px: number, Color: Color3 } }, seconds: number)
	local g = screenGui(guiName)
	if g == nil then
		return
	end
	local pad = 8
	local h = pad * 2
	for _, l in ipairs(lines) do
		h += l.Px + 4
	end
	local f = Instance.new("Frame")
	f.Name = "Card"
	f.AnchorPoint = Vector2.new(0.5, 0)
	f.Position = UDim2.new(0.5, 0, 0, 80)
	f.Size = UDim2.fromOffset(math.min(420, viewW() - 32), h)
	f.BackgroundColor3 = PLATE
	f.BackgroundTransparency = 0.08
	f.BorderSizePixel = 0
	f.Parent = g
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 10)
	c.Parent = f
	local st = Instance.new("UIStroke")
	st.Color = GOLD
	st.Thickness = 2
	st.Parent = f
	local y = pad
	for _, l in ipairs(lines) do
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Position = UDim2.fromOffset(10, y)
		t.Size = UDim2.new(1, -20, 0, l.Px + 2)
		t.Font = Enum.Font.GothamBlack
		t.TextSize = l.Px
		t.TextColor3 = l.Color
		t.TextTruncate = Enum.TextTruncate.AtEnd
		t.Text = l.Text
		t.Parent = f
		y += l.Px + 4
	end
	local H = hud()
	if H then
		pcall(H.RegisterTopStack, stackName, f, order, { Space = "Screen" })
	end
	task.wait(seconds)
	if H then
		pcall(H.UnregisterTopStack, stackName)
	end
	g:Destroy()
end

-- a queue shown one at a time; past maxQueued the oldest waiting item is skipped
local function makeQueue(maxQueued: number, show: (any) -> ()): (any) -> ()
	local items: { any } = {}
	local running = false
	return function(item: any)
		table.insert(items, item)
		while #items > maxQueued do
			table.remove(items, 1)
		end
		if running then
			return
		end
		running = true
		task.spawn(function()
			while #items > 0 do
				local it = table.remove(items, 1)
				pcall(show, it)
			end
			running = false
		end)
	end
end

local function money(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return "$" .. out:gsub("^,", "")
end

function AchievementController.RewardLine(d: any): string
	local parts: { string } = {}
	local cash, gold, xp = tonumber(d.Cash) or 0, tonumber(d.Gold) or 0, tonumber(d.XP) or 0
	if cash > 0 then
		table.insert(parts, "+" .. money(cash))
	end
	if gold > 0 then
		table.insert(parts, string.format("+%d Gold", gold))
	end
	if xp > 0 then
		table.insert(parts, string.format("+%d XP", xp))
	end
	return table.concat(parts, "  ")
end

function AchievementController.Init()
	local B, P = AchievementConfig.Banner, AchievementConfig.Popup
	local banner = makeQueue(B.MaxQueued, function(d: any)
		card("WE_AchBanner", "AchBanner", 16, {
			{ Text = tostring(d.Name), Px = math.max(15, B.TextPx - 2), Color = Color3.fromHex(AchievementConfig.Chat.NameColor) },
			{ Text = tostring(d.Text), Px = math.max(15, B.TextPx), Color = GOLD },
		}, B.Seconds)
	end)
	local popup = makeQueue(P.MaxQueued, function(d: any)
		local okA, Audio = pcall(require, script.Parent.Parent.Modules.AudioController)
		if okA and type(Audio) == "table" and (Audio :: any).Play then
			pcall((Audio :: any).Play, P.Sound)
		end
		local lines = {
			{ Text = "ACHIEVEMENT UNLOCKED", Px = 15, Color = Color3.fromRGB(200, 200, 200) },
			{ Text = tostring(d.Title), Px = math.max(15, P.TextPx + 3), Color = GOLD },
		}
		local reward = AchievementController.RewardLine(d)
		if reward ~= "" then
			table.insert(lines, { Text = reward, Px = math.max(15, P.TextPx - 1), Color = Color3.fromRGB(140, 230, 140) })
		end
		card("WE_AchPopup", "AchPopup", 17, lines, P.Seconds)
	end)
	Remotes.BindEvent(Constants.RemoteNames.FeaturePush, function(kind: any, data: any)
		if typeof(data) ~= "table" then
			return
		end
		if kind == "AchShout" then
			local name, text = tostring(data.Name or ""), tostring(data.Text or "")
			if name == "" or text == "" then
				return
			end
			chatLine(name, text, data.Big == true)
			if data.Big == true and name ~= player.Name then -- the earner has his own popup (one message at a time)
				banner({ Name = name, Text = text })
			end
		elseif kind == "AchUnlocked" then
			popup(data)
		end
	end)
end

return AchievementController
