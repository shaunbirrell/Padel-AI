--!strict
--[[
	claude-bud JOB 4/5 (2026-09-29): client side of the server's FeaturePush cues (Constants.RemoteNames.FeaturePush,
	server -> this client only; the server fires it only to players a feature is live for, so nothing here gates).
	Display only: every reward is decided on the server.
	  "Airdrop"  { Show = true, X, Y, Z, Cash } -> the one objective marker ("AIRDROP") to the landing spot
	             { Show = false }               -> clears it if it is still the airdrop
	  "Bounty"   { Show = true, X, Y, Z }       -> the objective marker ("BOUNTY") on the Central Plaza
	             { Show = false }               -> clears it if it is still the bounty
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ObjectiveMarker = require(script.Parent.Parent.Modules.ObjectiveMarker)
local Shared = ReplicatedStorage:WaitForChild("Shared", 60) -- ships with the place (Rojo); bounded wait anyway
local Remotes = require(Shared.Remotes)
local Constants = require(Shared.Constants)

local FeatureController = {}

-- claude-bud JOB 4.4: the local "Army Upgrades" prompt at the own Barracks (opens the Research Soldiers track)
local upgradeAnchor: Attachment? = nil
local function armyUpgrades(data: any)
	if typeof(data) ~= "table" then
		return
	end
	local x, y, z = tonumber(data.X), tonumber(data.Y), tonumber(data.Z)
	if not (x and y and z) then
		return
	end
	if upgradeAnchor then
		upgradeAnchor:Destroy()
	end
	local a = Instance.new("Attachment")
	a.Name = "WE_ArmyUpgradesPrompt"
	a.WorldPosition = Vector3.new(x, y, z)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Army Upgrades"
	prompt.ObjectText = "Barracks"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = a
	local track = if typeof(data.Track) == "string" then data.Track else "Soldiers"
	prompt.Triggered:Connect(function()
		local rc = script.Parent:FindFirstChild("ResearchController")
		if rc and rc:IsA("ModuleScript") then
			local ok, mod = pcall(require, rc)
			if ok and type(mod) == "table" and type((mod :: any).Open) == "function" then
				(mod :: any).Open(track)
			end
		end
	end)
	a.Parent = workspace.Terrain
	upgradeAnchor = a
end

local LABELS = { Airdrop = "AIRDROP", Bounty = "BOUNTY" }

local function marker(kind: string, data: any)
	local label = LABELS[kind]
	if label == nil or typeof(data) ~= "table" then
		return
	end
	if data.Show == true then
		local x, y, z = tonumber(data.X), tonumber(data.Y), tonumber(data.Z)
		if x and y and z then
			ObjectiveMarker.ShowWith({ Short = label, X = x, Y = y, Z = z }, { TimeoutSeconds = 300 })
		end
	else
		local cur = ObjectiveMarker.Current()
		if cur and cur.Short == label then
			ObjectiveMarker.Clear()
		end
	end
end

-- claude-bud JOB 7: the first-ATTACK hint: open the Army popover and outline its ATTACK button (a pulsing gold stroke)
-- with one short hint; gone on the first ATTACK (server "HintDone") or after data.Seconds. No per-frame work.
local hintStroke: UIStroke? = nil
local function hintDone()
	if hintStroke then
		hintStroke:Destroy()
		hintStroke = nil
	end
end
local function attackHint(data: any)
	if typeof(data) ~= "table" or data.Kind ~= "Attack" then
		return
	end
	local okO, Orders = pcall(require, script.Parent.OrdersController)
	if okO and type(Orders) == "table" and (Orders :: any).Open then
		pcall((Orders :: any).Open)
	end
	task.delay(0.3, function()
		local pg = game:GetService("Players").LocalPlayer:FindFirstChildOfClass("PlayerGui")
		local btn = pg and pg:FindFirstChild("Order_Attack", true)
		if btn and btn:IsA("GuiObject") and hintStroke == nil then
			local st = Instance.new("UIStroke")
			st.Name = "WE_HintStroke"
			st.Color = Color3.fromRGB(255, 205, 60)
			st.Thickness = 3
			st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			st.Parent = btn
			hintStroke = st
			local tw = game:GetService("TweenService"):Create(st, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Thickness = 6 })
			tw:Play()
		end
		local okN, NC = pcall(require, script.Parent.NotificationController)
		if okN and type(NC) == "table" and (NC :: any).Show and typeof(data.Text) == "string" then
			pcall((NC :: any).Show, data.Text, "Info", 5)
		end
		task.delay(tonumber(data.Seconds) or 20, hintDone)
	end)
end

-- claude-bud JOB 5d: a server "Offer" (a purchase prompt at a moment) as the standard offer toast; tapping it runs the
-- Shop's own guarded prompt (nothing is granted here: ProcessReceipt / pass ownership decide)
local function offerToast(data: any)
	if typeof(data) ~= "table" or typeof(data.Key) ~= "string" or typeof(data.Title) ~= "string" then
		return
	end
	local okN, NotificationController = pcall(require, script.Parent.NotificationController)
	local okS, ShopController = pcall(require, script.Parent.ShopController)
	if not (okN and okS) then
		return
	end
	local key = data.Key :: string
	local src = if typeof(data.Source) == "string" then data.Source else "offer"
	;(NotificationController :: any).ShowOffer({
		Key = "fp_" .. key,
		Title = data.Title,
		Sub = if typeof(data.Sub) == "string" then data.Sub else nil,
		Cta = if typeof(data.Cta) == "string" then data.Cta else "GET",
		OnGet = function()
			if data.Kind == "GamePass" then
				(ShopController :: any).PromptGamePass(key, src)
			else
				(ShopController :: any).PromptDevProduct(key, src)
			end
		end,
	})
end

-- claude-bud JOB 5b: VIP perks on this client (display / own movement only; the server decides every payout)
local function vipPerks()
	local Players = game:GetService("Players")
	local TextChatService = game:GetService("TextChatService")
	local MonetizationConfig = require(Shared.Configs.MonetizationConfig)
	local tag = tostring(((MonetizationConfig :: any).VIPPerks or {}).ChatTag or "[VIP]")
	-- the [VIP] chat tag of any sender the server marked (WE_VIPTag), seen by everyone
	pcall(function()
		TextChatService.OnIncomingMessage = function(message: TextChatMessage)
			local props = Instance.new("TextChatMessageProperties")
			local src = message.TextSource
			local sender = if src then Players:GetPlayerByUserId(src.UserId) else nil
			if sender and sender:GetAttribute("WE_VIPTag") == true then
				props.PrefixText = "<font color='#D4AF37'>" .. tag .. "</font> " .. message.PrefixText
			end
			return props
		end
	end)
	-- the lounge door: open (non-colliding) on a VIP's own client only; 3 s poll (streaming-safe, no tree scans)
	task.spawn(function()
		local lp = Players.LocalPlayer
		while lp.Parent do
			local lounge = workspace:FindFirstChild("WE_VIPLounge")
			local door = lounge and lounge:FindFirstChild("VIPDoor")
			if door and door:IsA("BasePart") then
				local vip = lp:GetAttribute("WE_VIPTag") == true
				door.CanCollide = not vip
				door.LocalTransparencyModifier = if vip then 0.5 else 0
			end
			task.wait(3)
		end
	end)
end
-- claude-bud JOB 5c: the AIRSTRIKE button (only with a charge, only near the Central Plaza; 2 Hz check). Right edge,
-- mid-height: clear of the thumbstick (left), jump (bottom-right) and top-bar pills; 64 code px tall (>= 44 real).
local function airstrikeButton()
	local Players = game:GetService("Players")
	local MonetizationConfig = require(Shared.Configs.MonetizationConfig)
	local lp = Players.LocalPlayer
	if not MonetizationConfig.SkuLiveFor(lp.UserId, "PlazaAirstrike") then
		return
	end
	local range = tonumber(((MonetizationConfig :: any).PlazaAirstrikeTuning or {}).UseRangeStuds) or 220
	local gui = Instance.new("ScreenGui")
	gui.Name = "WE_Airstrike"
	gui.ResetOnSpawn = false
	gui.Enabled = false
	local btn = Instance.new("TextButton")
	btn.AnchorPoint = Vector2.new(1, 0.5)
	btn.Position = UDim2.new(1, -16, 0.42, 0)
	btn.Size = UDim2.fromOffset(170, 64)
	btn.BackgroundColor3 = Color3.fromRGB(170, 40, 30)
	btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	btn.Font = Enum.Font.GothamBlack
	btn.TextSize = 20
	btn.Text = "AIRSTRIKE"
	btn.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = btn
	btn.Activated:Connect(function()
		task.spawn(Remotes.FireServer, Constants.RemoteNames.RequestPlazaAirstrike)
	end)
	gui.Parent = lp:WaitForChild("PlayerGui", 30)
	task.spawn(function()
		while lp.Parent do
			local n = tonumber(lp:GetAttribute("WE_AirstrikeCharges")) or 0
			local root = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
			local near = root ~= nil and root:IsA("BasePart") and Vector3.new(root.Position.X, 0, root.Position.Z).Magnitude <= range
			gui.Enabled = n > 0 and near
			btn.Text = string.format("AIRSTRIKE (%d)", n)
			task.wait(0.5)
		end
	end)
end
function FeatureController.Init()
	task.spawn(airstrikeButton)
	vipPerks()
	Remotes.BindEvent(Constants.RemoteNames.FeaturePush, function(kind: any, data: any)
		if typeof(kind) ~= "string" then
			return
		end
		if LABELS[kind] then
			marker(kind, data)
		elseif kind == "ArmyUpgrades" then
			armyUpgrades(data)
		elseif kind == "Offer" then
			offerToast(data)
		elseif kind == "Hint" then
			attackHint(data)
		elseif kind == "HintDone" then
			hintDone()
		end
	end)
end

return FeatureController
