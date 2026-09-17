--!strict
--[[
	Phase 3 — client combat input + HUD (health, ammo, weapon, mobile fire).
	Sends fire/reload/equip requests only — never damage amounts.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local Remotes = require(Shared.Remotes)
local Types = require(Shared.Types)
local WeaponConfig = require(Shared.Configs.WeaponConfig)

local CombatController = {}

local player = Players.LocalPlayer

local healthFill: Frame? = nil
local healthText: TextLabel? = nil
local ammoLabel: TextLabel? = nil
local weaponLabel: TextLabel? = nil
local hitFlash: Frame? = nil

local currentWeaponId: string? = nil
local ammo = 0
local magazineSize = 0
local reloading = false
local alive = true
local firing = false

local function addCorner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function addStroke(parent: Instance)
	local s = Instance.new("UIStroke")
	s.Color = Color3.fromRGB(55, 65, 55)
	s.Thickness = 1
	s.Parent = parent
end

local function buildHud()
	local screen = Instance.new("ScreenGui")
	screen.Name = "WarEmpireCombatHUD"
	screen.ResetOnSpawn = false
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.IgnoreGuiInset = false
	screen.Parent = player:WaitForChild("PlayerGui")

	local scale = Instance.new("UIScale")
	scale.Parent = screen
	local function updateScale()
		local cam = Workspace.CurrentCamera
		if not cam then
			return
		end
		local size = cam.ViewportSize
		scale.Scale = math.clamp(math.min(size.X, size.Y) / 800, 0.7, 1.15)
	end
	updateScale()
	if Workspace.CurrentCamera then
		Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
	end

	-- Health (bottom center)
	local healthPanel = Instance.new("Frame")
	healthPanel.Name = "HealthPanel"
	healthPanel.AnchorPoint = Vector2.new(0.5, 1)
	healthPanel.Position = UDim2.new(0.5, 0, 1, -20)
	healthPanel.Size = UDim2.fromOffset(280, 36)
	healthPanel.BackgroundColor3 = Constants.Colors.Panel
	healthPanel.BackgroundTransparency = 0.15
	healthPanel.BorderSizePixel = 0
	healthPanel.Parent = screen
	addCorner(healthPanel, 8)
	addStroke(healthPanel)

	local hpBg = Instance.new("Frame")
	hpBg.Position = UDim2.fromOffset(8, 8)
	hpBg.Size = UDim2.new(1, -16, 0, 20)
	hpBg.BackgroundColor3 = Constants.Colors.Background
	hpBg.BorderSizePixel = 0
	hpBg.Parent = healthPanel
	addCorner(hpBg, 4)

	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Constants.Colors.Health
	fill.BorderSizePixel = 0
	fill.Parent = hpBg
	addCorner(fill, 4)
	healthFill = fill

	local hpText = Instance.new("TextLabel")
	hpText.BackgroundTransparency = 1
	hpText.Size = UDim2.fromScale(1, 1)
	hpText.Font = Enum.Font.GothamBold
	hpText.TextSize = 12
	hpText.TextColor3 = Constants.Colors.Text
	hpText.Text = "100 / 100"
	hpText.Parent = hpBg
	healthText = hpText

	-- Weapon / ammo (bottom right)
	local weaponPanel = Instance.new("Frame")
	weaponPanel.Name = "WeaponPanel"
	weaponPanel.AnchorPoint = Vector2.new(1, 1)
	weaponPanel.Position = UDim2.new(1, -16, 1, -20)
	weaponPanel.Size = UDim2.fromOffset(200, 56)
	weaponPanel.BackgroundColor3 = Constants.Colors.Panel
	weaponPanel.BackgroundTransparency = 0.15
	weaponPanel.BorderSizePixel = 0
	weaponPanel.Parent = screen
	addCorner(weaponPanel, 8)
	addStroke(weaponPanel)

	local wName = Instance.new("TextLabel")
	wName.BackgroundTransparency = 1
	wName.Position = UDim2.fromOffset(10, 6)
	wName.Size = UDim2.new(1, -20, 0, 20)
	wName.Font = Enum.Font.GothamBold
	wName.TextSize = 14
	wName.TextXAlignment = Enum.TextXAlignment.Right
	wName.TextColor3 = Constants.Colors.Text
	wName.Text = "—"
	wName.Parent = weaponPanel
	weaponLabel = wName

	local ammoLbl = Instance.new("TextLabel")
	ammoLbl.BackgroundTransparency = 1
	ammoLbl.Position = UDim2.fromOffset(10, 28)
	ammoLbl.Size = UDim2.new(1, -20, 0, 20)
	ammoLbl.Font = Enum.Font.GothamMedium
	ammoLbl.TextSize = 16
	ammoLbl.TextXAlignment = Enum.TextXAlignment.Right
	ammoLbl.TextColor3 = Constants.Colors.Ammo
	ammoLbl.Text = "0 / 0"
	ammoLbl.Parent = weaponPanel
	ammoLabel = ammoLbl

	-- Hit flash
	local flash = Instance.new("Frame")
	flash.Name = "HitFlash"
	flash.BackgroundColor3 = Constants.Colors.Danger
	flash.BackgroundTransparency = 1
	flash.BorderSizePixel = 0
	flash.Size = UDim2.fromScale(1, 1)
	flash.ZIndex = 20
	flash.Parent = screen
	hitFlash = flash

	-- Mobile fire button
	local fireBtn = Instance.new("TextButton")
	fireBtn.Name = "FireButton"
	fireBtn.AnchorPoint = Vector2.new(1, 1)
	fireBtn.Position = UDim2.new(1, -16, 1, -96)
	fireBtn.Size = UDim2.fromOffset(72, 72)
	fireBtn.BackgroundColor3 = Constants.Colors.Danger
	fireBtn.BackgroundTransparency = 0.2
	fireBtn.Text = "FIRE"
	fireBtn.Font = Enum.Font.GothamBold
	fireBtn.TextSize = 16
	fireBtn.TextColor3 = Constants.Colors.Text
	fireBtn.AutoButtonColor = true
	fireBtn.Visible = UserInputService.TouchEnabled
	fireBtn.Parent = screen
	addCorner(fireBtn, 36)
	addStroke(fireBtn)

	fireBtn.MouseButton1Down:Connect(function()
		firing = true
	end)
	fireBtn.MouseButton1Up:Connect(function()
		firing = false
	end)
	fireBtn.MouseButton1Click:Connect(function()
		-- single tap also fires once
	end)
end

local function refreshAmmoLabel()
	if not ammoLabel then
		return
	end
	if reloading then
		ammoLabel.Text = "RELOADING..."
	else
		ammoLabel.Text = string.format("%d / %d", ammo, magazineSize)
	end
end

local function applyState(payload: Types.CombatStatePayload)
	alive = payload.Alive
	ammo = payload.Ammo
	magazineSize = payload.MagazineSize
	reloading = payload.Reloading
	currentWeaponId = payload.WeaponId

	if healthFill and payload.MaxHealth > 0 then
		healthFill.Size = UDim2.fromScale(math.clamp(payload.Health / payload.MaxHealth, 0, 1), 1)
	end
	if healthText then
		healthText.Text = string.format("%d / %d", math.floor(payload.Health), math.floor(payload.MaxHealth))
	end
	if weaponLabel then
		if payload.WeaponId and WeaponConfig.Weapons[payload.WeaponId] then
			weaponLabel.Text = WeaponConfig.Weapons[payload.WeaponId].DisplayName
		else
			weaponLabel.Text = payload.WeaponId or "—"
		end
	end
	refreshAmmoLabel()
end

local function flashFeedback(kind: string)
	if not hitFlash then
		return
	end
	local isOutgoing = kind == "Hit" or kind == "Kill"
	hitFlash.BackgroundColor3 = if isOutgoing then Color3.fromRGB(220, 210, 100) else Constants.Colors.Danger
	hitFlash.BackgroundTransparency = if isOutgoing then 0.8 else 0.55
	task.delay(0.08, function()
		if hitFlash then
			hitFlash.BackgroundTransparency = 1
		end
	end)
end

local function aimRay(): (Vector3, Vector3)
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
	local fallbackOrigin = if root then root.Position + Vector3.new(0, 1.5, 0) else Vector3.new(0, 5, 0)

	local cam = Workspace.CurrentCamera
	if cam then
		local vp = cam.ViewportSize
		local ray = cam:ViewportPointToRay(vp.X / 2, vp.Y / 2)
		return ray.Origin, ray.Direction.Unit
	end
	return fallbackOrigin, Vector3.new(0, 0, -1)
end

local function requestFire()
	if not alive or reloading or ammo <= 0 then
		return
	end

	local origin, direction = aimRay()
	local payload: Types.FireRequestPayload = {
		Direction = direction,
		Origin = origin,
		TargetUserId = nil,
		TargetNpcId = nil,
		HitPosition = nil,
	}

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local character = player.Character
	if character then
		params.FilterDescendantsInstances = { character }
	end
	local result = Workspace:Raycast(origin, direction * 500, params)
	if result then
		payload.HitPosition = result.Position
		local model = result.Instance:FindFirstAncestorOfClass("Model")
		if model then
			local other = Players:GetPlayerFromCharacter(model)
			if other then
				payload.TargetUserId = other.UserId
			else
				local npcId = model:GetAttribute("NPCId")
				if typeof(npcId) == "string" then
					payload.TargetNpcId = npcId
				end
			end
		end
	end

	Remotes.GetEvent(Constants.RemoteNames.RequestFire):FireServer(payload)
end

local function requestReload()
	Remotes.GetEvent(Constants.RemoteNames.RequestReload):FireServer()
end

local function requestEquip(weaponId: string)
	Remotes.GetEvent(Constants.RemoteNames.RequestEquipWeapon):FireServer(weaponId)
end

local function cycleWeapon(delta: number)
	local ids: { string } = {}
	for id in pairs(WeaponConfig.Weapons) do
		table.insert(ids, id)
	end
	table.sort(ids)
	if #ids == 0 then
		return
	end
	local idx = 1
	for i, id in ipairs(ids) do
		if id == currentWeaponId then
			idx = i
			break
		end
	end
	idx = ((idx - 1 + delta) % #ids) + 1
	requestEquip(ids[idx])
end

function CombatController.Init()
	buildHud()

	Remotes.GetEvent(Constants.RemoteNames.CombatStateUpdate).OnClientEvent:Connect(function(payload: Types.CombatStatePayload)
		applyState(payload)
	end)

	Remotes.GetEvent(Constants.RemoteNames.CombatHitFeedback).OnClientEvent:Connect(function(payload: Types.CombatHitFeedbackPayload)
		flashFeedback(payload.Kind)
	end)

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or GuiService.MenuIsOpen then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			firing = true
			requestFire()
		elseif input.KeyCode == Enum.KeyCode.R then
			requestReload()
		elseif input.KeyCode == Enum.KeyCode.Q then
			cycleWeapon(-1)
		elseif input.KeyCode == Enum.KeyCode.E then
			cycleWeapon(1)
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			firing = false
		end
	end)

	task.spawn(function()
		while true do
			task.wait(0.05)
			if firing then
				requestFire()
			end
		end
	end)
end

return CombatController
