--!strict
--[[
	Empire Bank raid — stand on vault to loot Cash; per-player cooldown.
	Bank guards are living CombatService NPCs (MoveTo + shoot), not static MapSetup props.
	Pushes HoldProgress / UnderFire / InVault to clients for BankRaidController HUD.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local BankRaidConfig = require(Shared.Configs.BankRaidConfig)
local AnalyticsConfig = require(Shared.Configs.AnalyticsConfig)

local BankRaidService = {}

local EconomyService: any = nil
local NotificationService: any = nil
local AnalyticsService: any = nil
local RemoteSetup: any = nil
local CombatService: any = nil

local vaultPart: BasePart? = nil
local holdProgress: { [number]: number } = {}
local cooldownUntil: { [number]: number } = {}
local inVaultNow: { [number]: boolean } = {}
local underFireNow: { [number]: boolean } = {}
local lastPushedProgress: { [number]: number } = {}
local guardsSpawned = false
local billboardLabel: TextLabel? = nil

local function findVault(): BasePart?
	if vaultPart and vaultPart.Parent then
		return vaultPart
	end
	for _, inst in ipairs(CollectionService:GetTagged(Constants.Tags.BankVault)) do
		if inst:IsA("BasePart") then
			vaultPart = inst
			return inst
		end
	end
	return nil
end

local function ensureVaultBillboard(vault: BasePart)
	local existing = vault:FindFirstChild("WE_BankRaidStatus")
	if existing and existing:IsA("BillboardGui") then
		local lbl = existing:FindFirstChild("Status")
		if lbl and lbl:IsA("TextLabel") then
			billboardLabel = lbl
			return
		end
	end
	if existing then
		existing:Destroy()
	end
	local bb = Instance.new("BillboardGui")
	bb.Name = "WE_BankRaidStatus"
	bb.Size = UDim2.fromOffset(300, 48)
	bb.StudsOffset = Vector3.new(0, 10, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 220
	bb.Parent = vault

	local lbl = Instance.new("TextLabel")
	lbl.Name = "Status"
	lbl.BackgroundTransparency = 1
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.Font = Enum.Font.GothamBold
	lbl.TextSize = 18
	lbl.TextColor3 = Color3.fromRGB(255, 220, 120)
	lbl.TextStrokeTransparency = 0.4
	lbl.Text = "EMPIRE BANK — STAND TO LOOT"
	lbl.Parent = bb
	billboardLabel = lbl
end

local function refreshBillboardHint()
	local lbl = billboardLabel
	if not lbl then
		return
	end
	-- Prefer a short public hint; per-player cooldown stays on the ScreenGui.
	local anyRaiding = false
	for uid, inv in pairs(inVaultNow) do
		if inv and (holdProgress[uid] or 0) > 0 then
			anyRaiding = true
			break
		end
	end
	if anyRaiding then
		lbl.Text = "EMPIRE BANK — RAID IN PROGRESS"
		lbl.TextColor3 = Color3.fromRGB(255, 180, 80)
	else
		lbl.Text = "EMPIRE BANK — STAND TO LOOT"
		lbl.TextColor3 = Color3.fromRGB(255, 220, 120)
	end
end

local function spawnBankGuards()
	if guardsSpawned then
		return
	end
	if not CombatService or not CombatService.SpawnNPC then
		warn("[WAR EMPIRE] BankRaidService: CombatService.SpawnNPC missing")
		return
	end
	guardsSpawned = true

	local vault = findVault()
	local origin = if vault then vault.Position else (BankRaidConfig.Position or Vector3.new(220, 1, -220))
	local count = BankRaidConfig.GuardCount or 4
	local ring = BankRaidConfig.GuardRingRadius or 16
	local typeId = BankRaidConfig.GuardNPCType or "BankGuard"
	local spawned = 0
	for i = 1, count do
		local angle = (i / count) * math.pi * 2 + 0.35
		local pos = origin + Vector3.new(math.cos(angle) * ring, 3.2, math.sin(angle) * ring)
		local cf = CFrame.new(pos) * CFrame.Angles(0, -angle + math.pi, 0)
		local rec = CombatService.SpawnNPC(typeId, cf)
		if rec then
			spawned += 1
		end
	end
	print(string.format("[WAR EMPIRE] BankRaidService: spawned %d %s combat NPCs at bank", spawned, typeId))
	if spawned == 0 then
		warn("[WAR EMPIRE] BankRaidService: ZERO BankGuards — will retry once in 3s")
		guardsSpawned = false
		task.delay(3, function()
			if not guardsSpawned then
				spawnBankGuards()
			end
		end)
	end
end

local function pushState(player: Player, opts: { InVault: boolean?, UnderFire: boolean? }?)
	if not RemoteSetup then
		return
	end
	local now = os.time()
	local untilT = cooldownUntil[player.UserId] or 0
	local remaining = math.max(0, untilT - now)
	local need = BankRaidConfig.RaidHoldSeconds or 8
	local prog = holdProgress[player.UserId] or 0
	local inVault = if opts and opts.InVault ~= nil then opts.InVault else (inVaultNow[player.UserId] == true)
	local underFire = if opts and opts.UnderFire ~= nil then opts.UnderFire else (underFireNow[player.UserId] == true)
	local remote = RemoteSetup.Get(Constants.RemoteNames.BankRaidStateUpdate) :: RemoteEvent
	remote:FireClient(player, {
		BankId = BankRaidConfig.BankId,
		DisplayName = BankRaidConfig.DisplayName,
		Enabled = BankRaidConfig.Enabled == true,
		CooldownRemaining = remaining,
		RaidHoldSeconds = need,
		HoldNeed = need,
		HoldProgress = prog,
		InVault = inVault,
		UnderFire = underFire,
		CashHintMin = BankRaidConfig.CashMin,
		CashHintMax = BankRaidConfig.CashMax,
	})
	lastPushedProgress[player.UserId] = prog
end

local function completeRaid(player: Player)
	local cashMin = BankRaidConfig.CashMin or 15000
	local cashMax = BankRaidConfig.CashMax or 35000
	local cash = math.random(cashMin, cashMax)
	EconomyService.AddCash(player, cash, "bank_raid")
	local cd = BankRaidConfig.CooldownSeconds or 300
	cooldownUntil[player.UserId] = os.time() + cd
	holdProgress[player.UserId] = nil
	inVaultNow[player.UserId] = false
	underFireNow[player.UserId] = false
	if BankRaidConfig.NotifyOnRaid and NotificationService then
		NotificationService.Notify(
			player,
			string.format("Bank raid +$%d · cooldown %dm", cash, math.ceil(cd / 60)),
			"Reward"
		)
	end
	if AnalyticsService then
		local ev = (AnalyticsConfig.Events and AnalyticsConfig.Events.BANK_RAID) or "BANK_RAID"
		AnalyticsService.Log(ev, player.UserId, { cash = cash })
	end
	pushState(player, { InVault = false, UnderFire = false })
end

local function isUnderFire(player: Player): boolean
	local char = player.Character
	if not char then
		return true
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then
		return true
	end
	return hum.Health < hum.MaxHealth * 0.95
end

function BankRaidService.Push(player: Player)
	pushState(player)
end

function BankRaidService.Init(deps: { [string]: any })
	EconomyService = deps.EconomyService
	NotificationService = deps.NotificationService
	AnalyticsService = deps.AnalyticsService
	RemoteSetup = deps.RemoteSetup
	CombatService = deps.CombatService

	if not BankRaidConfig.Enabled then
		return
	end

	task.defer(function()
		task.wait(2)
		local vault = findVault()
		if vault then
			ensureVaultBillboard(vault)
		end
		spawnBankGuards()
	end)

	local accum = 0
	RunService.Heartbeat:Connect(function(dt)
		accum += dt
		if accum < 0.25 then
			return
		end
		local step = accum
		accum = 0

		local vault = findVault()
		if not vault then
			return
		end
		if not billboardLabel then
			ensureVaultBillboard(vault)
		end
		local radius = BankRaidConfig.VaultRadius or 12
		local need = BankRaidConfig.RaidHoldSeconds or 8
		local nowUnix = os.time()
		local pos = vault.Position
		local nearby: { [number]: boolean } = {}
		local toPush: { Player } = {}

		for _, player in ipairs(Players:GetPlayers()) do
			local uid = player.UserId
			local untilT = cooldownUntil[uid] or 0
			local onCooldown = untilT > nowUnix
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			local inside = false
			local fired = false

			if hrp and hum and hum.Health > 0 then
				inside = (hrp.Position - pos).Magnitude <= radius
			end

			if inside and not onCooldown then
				nearby[uid] = true
				fired = isUnderFire(player)
				underFireNow[uid] = fired
				inVaultNow[uid] = true
				if not fired then
					local prog = (holdProgress[uid] or 0) + step
					holdProgress[uid] = prog
					if prog >= need then
						completeRaid(player)
						-- completeRaid already pushed
					else
						table.insert(toPush, player)
					end
				else
					-- Under fire: progress frozen but HUD must show the block
					table.insert(toPush, player)
				end
			elseif inside and onCooldown then
				-- Standing on vault while cooling down — still show cooldown HUD
				inVaultNow[uid] = true
				underFireNow[uid] = false
				nearby[uid] = true
				table.insert(toPush, player)
			else
				local wasIn = inVaultNow[uid] == true
				local hadProg = (holdProgress[uid] or 0) > 0
				if wasIn or hadProg then
					-- Left vault / progress reset — push once so client hides bar
					inVaultNow[uid] = false
					underFireNow[uid] = false
					holdProgress[uid] = nil
					table.insert(toPush, player)
				else
					inVaultNow[uid] = false
					underFireNow[uid] = false
				end
			end
		end

		for uid in pairs(holdProgress) do
			if not nearby[uid] then
				holdProgress[uid] = nil
			end
		end

		for _, player in ipairs(toPush) do
			pushState(player)
		end

		refreshBillboardHint()
	end)

	Players.PlayerAdded:Connect(function(player)
		task.defer(function()
			pushState(player)
		end)
	end)
	Players.PlayerRemoving:Connect(function(player)
		local uid = player.UserId
		holdProgress[uid] = nil
		inVaultNow[uid] = nil
		underFireNow[uid] = nil
		lastPushedProgress[uid] = nil
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		task.defer(function()
			pushState(player)
		end)
	end

	print("[WAR EMPIRE] BankRaidService ready (live BankGuard combat NPCs + HoldProgress HUD)")
end

return BankRaidService
