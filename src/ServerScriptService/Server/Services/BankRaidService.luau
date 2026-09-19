--!strict
--[[
	Empire Bank raid — stand on vault to loot Cash; per-player cooldown.
	Bank guards are living CombatService NPCs (MoveTo + shoot), not static MapSetup props.
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
local guardsSpawned = false

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

local function pushState(player: Player)
	if not RemoteSetup then
		return
	end
	local now = os.time()
	local untilT = cooldownUntil[player.UserId] or 0
	local remaining = math.max(0, untilT - now)
	local remote = RemoteSetup.Get(Constants.RemoteNames.BankRaidStateUpdate) :: RemoteEvent
	remote:FireClient(player, {
		BankId = BankRaidConfig.BankId,
		DisplayName = BankRaidConfig.DisplayName,
		CooldownRemaining = remaining,
		RaidHoldSeconds = BankRaidConfig.RaidHoldSeconds,
		CashHintMin = BankRaidConfig.CashMin,
		CashHintMax = BankRaidConfig.CashMax,
	})
end

local function completeRaid(player: Player)
	local cashMin = BankRaidConfig.CashMin or 15000
	local cashMax = BankRaidConfig.CashMax or 35000
	local cash = math.random(cashMin, cashMax)
	EconomyService.AddCash(player, cash, "bank_raid")
	local cd = BankRaidConfig.CooldownSeconds or 300
	cooldownUntil[player.UserId] = os.time() + cd
	holdProgress[player.UserId] = nil
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
	pushState(player)
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
		findVault()
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
		local radius = BankRaidConfig.VaultRadius or 12
		local need = BankRaidConfig.RaidHoldSeconds or 8
		local nowUnix = os.time()
		local pos = vault.Position
		local nearby: { [number]: boolean } = {}

		for _, player in ipairs(Players:GetPlayers()) do
			local untilT = cooldownUntil[player.UserId] or 0
			if untilT <= nowUnix then
				local char = player.Character
				local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
				local hum = char and char:FindFirstChildOfClass("Humanoid")
				if hrp and hum and hum.Health > 0 then
					if (hrp.Position - pos).Magnitude <= radius then
						nearby[player.UserId] = true
						if not isUnderFire(player) then
							local prog = (holdProgress[player.UserId] or 0) + step
							holdProgress[player.UserId] = prog
							if prog >= need then
								completeRaid(player)
							end
						end
					end
				end
			end
		end

		for uid in pairs(holdProgress) do
			if not nearby[uid] then
				holdProgress[uid] = nil
			end
		end
	end)

	Players.PlayerAdded:Connect(function(player)
		task.defer(function()
			pushState(player)
		end)
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		task.defer(function()
			pushState(player)
		end)
	end

	print("[WAR EMPIRE] BankRaidService ready (live BankGuard combat NPCs)")
end

return BankRaidService
