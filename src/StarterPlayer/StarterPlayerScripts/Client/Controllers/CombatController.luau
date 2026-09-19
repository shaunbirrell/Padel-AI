--!strict
--[[
	Phase 3/7 — client combat input + HUD (health, ammo, weapon, mobile fire/reload/swap).
	Sends fire/reload/equip requests only — never damage amounts.
	Mobile: large FIRE + RELOAD + weapon swap, center reticle, low-ammo tint,
	hit marker, panels lifted clear of dock / pad BUY.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local Remotes = require(Shared.Remotes)
local UIUtil = require(Shared.Util.UIUtil)
local Types = require(Shared.Types)
local WeaponConfig = require(Shared.Configs.WeaponConfig)

local CombatController = {}

local player = Players.LocalPlayer
local isTouch = UserInputService.TouchEnabled

local healthFill: Frame? = nil
local healthText: TextLabel? = nil
local ammoLabel: TextLabel? = nil
local weaponLabel: TextLabel? = nil
local hitFlash: Frame? = nil
local hitMarker: Frame? = nil
local reticle: Frame? = nil
local lowAmmoHint: TextLabel? = nil

local currentWeaponId: string? = nil
local ammo = 0
local magazineSize = 0
local reloading = false
local alive = true
local firing = false

local requestFire: () -> ()
local requestReload: () -> ()
local cycleWeapon: (delta: number) -> ()

local function addCorner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function addStroke(parent: Instance, color: Color3?, thickness: number?)
	local s = Instance.new("UIStroke")
	s.Color = color or Color3.fromRGB(55, 65, 55)
	s.Thickness = thickness or 1
	s.Parent = parent
	return s
end

local function buildHud()
	local screen = Instance.new("ScreenGui")
	screen.Name = "WarEmpireCombatHUD"
	screen.Parent = player:WaitForChild("PlayerGui")
	screen.ResetOnSpawn = false
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.IgnoreGuiInset = false
	screen.DisplayOrder = 30 -- below HUD dock (55) so dock clicks win
	UIUtil.AttachMobileScale(screen, 800, 0.7, 1.15)

	-- Center reticle (aim assist visual — camera center)
	local ret = Instance.new("Frame")
	ret.Name = "Reticle"
	ret.AnchorPoint = Vector2.new(0.5, 0.5)
	ret.Position = UDim2.fromScale(0.5, 0.48)
	ret.Size = UDim2.fromOffset(if isTouch then 22 else 16, if isTouch then 22 else 16)
	ret.BackgroundTransparency = 1
	ret.ZIndex = 15
	ret.Active = false
	ret.Parent = screen
	reticle = ret
	local function arm(dx: number, dy: number, w: number, h: number)
		local a = Instance.new("Frame")
		a.AnchorPoint = Vector2.new(0.5, 0.5)
		a.Position = UDim2.new(0.5, dx, 0.5, dy)
		a.Size = UDim2.fromOffset(w, h)
		a.BackgroundColor3 = Color3.fromRGB(235, 240, 220)
		a.BackgroundTransparency = 0.15
		a.BorderSizePixel = 0
		a.Active = false
		a.ZIndex = 16
		a.Parent = ret
	end
	local gap = if isTouch then 6 else 4
	local thick = if isTouch then 3 else 2
	local len = if isTouch then 8 else 6
	arm(0, -(gap + len / 2), thick, len)
	arm(0, gap + len / 2, thick, len)
	arm(-(gap + len / 2), 0, len, thick)
	arm(gap + len / 2, 0, len, thick)
	local dot = Instance.new("Frame")
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.fromScale(0.5, 0.5)
	dot.Size = UDim2.fromOffset(3, 3)
	dot.BackgroundColor3 = Constants.Colors.Gold
	dot.BorderSizePixel = 0
	dot.Active = false
	dot.ZIndex = 17
	dot.Parent = ret
	addCorner(dot, 2)

	-- Hit marker (X) at reticle — brief on Hit/Kill
	local marker = Instance.new("Frame")
	marker.Name = "HitMarker"
	marker.AnchorPoint = Vector2.new(0.5, 0.5)
	marker.Position = UDim2.fromScale(0.5, 0.48)
	marker.Size = UDim2.fromOffset(28, 28)
	marker.BackgroundTransparency = 1
	marker.Visible = false
	marker.ZIndex = 18
	marker.Active = false
	marker.Parent = screen
	hitMarker = marker
	for _, rot in ipairs({ 45, -45 }) do
		local bar = Instance.new("Frame")
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Position = UDim2.fromScale(0.5, 0.5)
		bar.Size = UDim2.fromOffset(22, 3)
		bar.BackgroundColor3 = Color3.fromRGB(255, 230, 80)
		bar.BorderSizePixel = 0
		bar.Rotation = rot
		bar.Active = false
		bar.ZIndex = 19
		bar.Parent = marker
	end

	-- Health — lifted on mobile so it clears pad BUY (~-108) and capture bar
	local healthPanel = Instance.new("Frame")
	healthPanel.Name = "HealthPanel"
	healthPanel.AnchorPoint = Vector2.new(0.5, 1)
	healthPanel.Position = UDim2.new(0.5, 0, 1, if isTouch then -188 else -20)
	healthPanel.Size = UDim2.fromOffset(if isTouch then 300 else 280, if isTouch then 40 else 36)
	healthPanel.BackgroundColor3 = Constants.Colors.Panel
	healthPanel.BackgroundTransparency = 0.15
	healthPanel.BorderSizePixel = 0
	healthPanel.Parent = screen
	addCorner(healthPanel, 8)
	addStroke(healthPanel)

	local hpBg = Instance.new("Frame")
	hpBg.Position = UDim2.fromOffset(8, 8)
	hpBg.Size = UDim2.new(1, -16, 0, if isTouch then 24 else 20)
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
	hpText.TextSize = if isTouch then 13 else 12
	hpText.TextColor3 = Constants.Colors.Text
	hpText.Text = "100 / 100"
	hpText.Parent = hpBg
	healthText = hpText

	-- Weapon / ammo (bottom right) — clear of dock (~80) + fire cluster
	local weaponPanel = Instance.new("Frame")
	weaponPanel.Name = "WeaponPanel"
	weaponPanel.AnchorPoint = Vector2.new(1, 1)
	weaponPanel.Position = UDim2.new(1, -16, 1, if isTouch then -280 else -20)
	weaponPanel.Size = UDim2.fromOffset(if isTouch then 210 else 200, if isTouch then 64 else 56)
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
	wName.TextSize = if isTouch then 15 else 14
	wName.TextXAlignment = Enum.TextXAlignment.Right
	wName.TextColor3 = Constants.Colors.Text
	wName.Text = "—"
	wName.Parent = weaponPanel
	weaponLabel = wName

	local ammoLbl = Instance.new("TextLabel")
	ammoLbl.BackgroundTransparency = 1
	ammoLbl.Position = UDim2.fromOffset(10, if isTouch then 30 else 28)
	ammoLbl.Size = UDim2.new(1, -20, 0, 24)
	ammoLbl.Font = Enum.Font.GothamMedium
	ammoLbl.TextSize = if isTouch then 18 else 16
	ammoLbl.TextXAlignment = Enum.TextXAlignment.Right
	ammoLbl.TextColor3 = Constants.Colors.Ammo
	ammoLbl.Text = "0 / 0"
	ammoLbl.Parent = weaponPanel
	ammoLabel = ammoLbl

	local lowHint = Instance.new("TextLabel")
	lowHint.Name = "LowAmmo"
	lowHint.BackgroundTransparency = 1
	lowHint.AnchorPoint = Vector2.new(1, 1)
	lowHint.Position = UDim2.new(1, -16, 1, if isTouch then -348 else -80)
	lowHint.Size = UDim2.fromOffset(160, 18)
	lowHint.Font = Enum.Font.GothamBold
	lowHint.TextSize = 12
	lowHint.TextXAlignment = Enum.TextXAlignment.Right
	lowHint.TextColor3 = Color3.fromRGB(255, 140, 80)
	lowHint.Text = ""
	lowHint.Visible = false
	lowHint.Parent = screen
	lowAmmoHint = lowHint

	-- Hit flash — MUST NOT sink clicks (full-screen overlay)
	local flash = Instance.new("Frame")
	flash.Name = "HitFlash"
	flash.BackgroundColor3 = Constants.Colors.Danger
	flash.BackgroundTransparency = 1
	flash.BorderSizePixel = 0
	flash.Size = UDim2.fromScale(1, 1)
	flash.ZIndex = 20
	flash.Active = false
	flash.Parent = screen
	hitFlash = flash

	-- Mobile combat cluster (right side, above dock)
	if isTouch then
		local fireBtn = Instance.new("TextButton")
		fireBtn.Name = "FireButton"
		fireBtn.AnchorPoint = Vector2.new(1, 1)
		fireBtn.Position = UDim2.new(1, -16, 1, -100)
		fireBtn.Size = UDim2.fromOffset(84, 84)
		fireBtn.BackgroundColor3 = Constants.Colors.Danger
		fireBtn.BackgroundTransparency = 0.15
		fireBtn.Text = "FIRE"
		fireBtn.Font = Enum.Font.GothamBold
		fireBtn.TextSize = 18
		fireBtn.TextColor3 = Constants.Colors.Text
		fireBtn.AutoButtonColor = true
		fireBtn.Active = true
		fireBtn.ZIndex = 25
		fireBtn.Parent = screen
		addCorner(fireBtn, 42)
		addStroke(fireBtn, Color3.fromRGB(255, 200, 200), 2)
		UIUtil.EnsureMinTouch(fireBtn, 72)

		fireBtn.MouseButton1Down:Connect(function()
			firing = true
		end)
		fireBtn.MouseButton1Up:Connect(function()
			firing = false
		end)
		fireBtn.InputEnded:Connect(function()
			firing = false
		end)
		-- Touch leave / cancel
		local reloadBtn = Instance.new("TextButton")
		reloadBtn.Name = "ReloadButton"
		reloadBtn.AnchorPoint = Vector2.new(1, 1)
		reloadBtn.Position = UDim2.new(1, -110, 1, -108)
		reloadBtn.Size = UDim2.fromOffset(64, 64)
		reloadBtn.BackgroundColor3 = Constants.Colors.Gunmetal
		reloadBtn.Text = "R"
		reloadBtn.Font = Enum.Font.GothamBold
		reloadBtn.TextSize = 22
		reloadBtn.TextColor3 = Constants.Colors.Ammo
		reloadBtn.AutoButtonColor = true
		reloadBtn.Active = true
		reloadBtn.ZIndex = 25
		reloadBtn.Parent = screen
		addCorner(reloadBtn, 16)
		addStroke(reloadBtn, Constants.Colors.Gold, 1.5)
		UIUtil.EnsureMinTouch(reloadBtn, 56)
		reloadBtn.Activated:Connect(function()
			requestReload()
		end)

		local prevBtn = Instance.new("TextButton")
		prevBtn.Name = "WeaponPrev"
		prevBtn.AnchorPoint = Vector2.new(1, 1)
		prevBtn.Position = UDim2.new(1, -184, 1, -108)
		prevBtn.Size = UDim2.fromOffset(52, 52)
		prevBtn.BackgroundColor3 = Constants.Colors.GunmetalLight
		prevBtn.Text = "◀"
		prevBtn.Font = Enum.Font.GothamBold
		prevBtn.TextSize = 18
		prevBtn.TextColor3 = Constants.Colors.Text
		prevBtn.AutoButtonColor = true
		prevBtn.ZIndex = 25
		prevBtn.Parent = screen
		addCorner(prevBtn, 12)
		UIUtil.EnsureMinTouch(prevBtn, 48)
		prevBtn.Activated:Connect(function()
			cycleWeapon(-1)
		end)

		local nextBtn = Instance.new("TextButton")
		nextBtn.Name = "WeaponNext"
		nextBtn.AnchorPoint = Vector2.new(1, 1)
		nextBtn.Position = UDim2.new(1, -184, 1, -168)
		nextBtn.Size = UDim2.fromOffset(52, 52)
		nextBtn.BackgroundColor3 = Constants.Colors.GunmetalLight
		nextBtn.Text = "▶"
		nextBtn.Font = Enum.Font.GothamBold
		nextBtn.TextSize = 18
		nextBtn.TextColor3 = Constants.Colors.Text
		nextBtn.AutoButtonColor = true
		nextBtn.ZIndex = 25
		nextBtn.Parent = screen
		addCorner(nextBtn, 12)
		UIUtil.EnsureMinTouch(nextBtn, 48)
		nextBtn.Activated:Connect(function()
			cycleWeapon(1)
		end)
	else
		-- Desktop still gets a small optional fire hint (hidden)
		local fireBtn = Instance.new("TextButton")
		fireBtn.Name = "FireButton"
		fireBtn.Visible = false
		fireBtn.Parent = screen
	end
end

local function refreshAmmoLabel()
	if not ammoLabel then
		return
	end
	if reloading then
		ammoLabel.Text = "RELOADING..."
		ammoLabel.TextColor3 = Color3.fromRGB(255, 200, 100)
		if lowAmmoHint then
			lowAmmoHint.Visible = false
		end
		return
	end
	ammoLabel.Text = string.format("%d / %d", ammo, magazineSize)
	local low = magazineSize > 0 and ammo <= math.max(1, math.floor(magazineSize * 0.25))
	local empty = ammo <= 0
	if empty then
		ammoLabel.TextColor3 = Constants.Colors.Danger
		if lowAmmoHint then
			lowAmmoHint.Text = "EMPTY — tap R / RELOAD"
			lowAmmoHint.Visible = true
		end
	elseif low then
		ammoLabel.TextColor3 = Color3.fromRGB(255, 160, 70)
		if lowAmmoHint then
			lowAmmoHint.Text = "LOW AMMO"
			lowAmmoHint.Visible = true
		end
	else
		ammoLabel.TextColor3 = Constants.Colors.Ammo
		if lowAmmoHint then
			lowAmmoHint.Visible = false
		end
	end
end

local function applyState(payload: Types.CombatStatePayload)
	alive = payload.Alive
	ammo = payload.Ammo
	magazineSize = payload.MagazineSize
	reloading = payload.Reloading
	currentWeaponId = payload.WeaponId

	if healthFill and payload.MaxHealth > 0 then
		local ratio = math.clamp(payload.Health / payload.MaxHealth, 0, 1)
		healthFill.Size = UDim2.fromScale(ratio, 1)
		-- Tint redder when critical
		if ratio <= 0.25 then
			healthFill.BackgroundColor3 = Color3.fromRGB(220, 40, 40)
		elseif ratio <= 0.5 then
			healthFill.BackgroundColor3 = Color3.fromRGB(210, 120, 50)
		else
			healthFill.BackgroundColor3 = Constants.Colors.Health
		end
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
	if reticle then
		reticle.Visible = alive and not reloading
	end
	refreshAmmoLabel()
end

local function flashFeedback(kind: string)
	if hitFlash then
		local isOutgoing = kind == "Hit" or kind == "Kill"
		hitFlash.BackgroundColor3 = if isOutgoing then Color3.fromRGB(220, 210, 100) else Constants.Colors.Danger
		hitFlash.BackgroundTransparency = if isOutgoing then 0.85 else 0.55
		task.delay(0.08, function()
			if hitFlash then
				hitFlash.BackgroundTransparency = 1
			end
		end)
	end
	if hitMarker and (kind == "Hit" or kind == "Kill") then
		hitMarker.Visible = true
		for _, child in ipairs(hitMarker:GetChildren()) do
			if child:IsA("Frame") then
				child.BackgroundColor3 = if kind == "Kill"
					then Color3.fromRGB(255, 90, 70)
					else Color3.fromRGB(255, 230, 80)
			end
		end
		task.delay(0.12, function()
			if hitMarker then
				hitMarker.Visible = false
			end
		end)
	end
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

requestFire = function()
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

requestReload = function()
	Remotes.GetEvent(Constants.RemoteNames.RequestReload):FireServer()
end

local function requestEquip(weaponId: string)
	Remotes.GetEvent(Constants.RemoteNames.RequestEquipWeapon):FireServer(weaponId)
end

cycleWeapon = function(delta: number)
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
			-- E is also used by WorldPrompt for proximity — only cycle when not over Gui
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
