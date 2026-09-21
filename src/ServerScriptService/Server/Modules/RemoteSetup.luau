--!strict
--[[
	Creates remotes under ReplicatedStorage.Remotes.
	Request/action pattern ONLY — no GiveCash / GiveXP / GiveWeapon remotes.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants"))

local RemoteSetup = {}

local EVENTS = {
	-- Server pushes
	Constants.RemoteNames.PlayerStateUpdate,
	Constants.RemoteNames.BaseStateUpdate,
	Constants.RemoteNames.Notification,
	Constants.RemoteNames.EconomyUpdate,
	Constants.RemoteNames.XPUpdate,
	Constants.RemoteNames.CombatStateUpdate,
	Constants.RemoteNames.CombatHitFeedback,
	Constants.RemoteNames.VehicleStateUpdate,
	Constants.RemoteNames.TerritoryStateUpdate,
	Constants.RemoteNames.MissionStateUpdate,
	-- Client requests
	Constants.RemoteNames.RequestPurchaseUpgrade,
	Constants.RemoteNames.RequestClaimDailyReward,
	Constants.RemoteNames.RequestSpawnVehicle,
	Constants.RemoteNames.RequestPurchaseVehicle,
	Constants.RemoteNames.RequestDespawnVehicle,
	Constants.RemoteNames.RequestEquipWeapon,
	Constants.RemoteNames.RequestPurchaseWeapon,
	Constants.RemoteNames.RequestFire,
	Constants.RemoteNames.RequestReload,
	Constants.RemoteNames.RequestStartMission,
	Constants.RemoteNames.RequestClaimMission,
	Constants.RemoteNames.RequestCaptureTerritory,
	Constants.RemoteNames.RequestAdminCommand,
	Constants.RemoteNames.RequestPurchaseDevProduct,
	Constants.RemoteNames.RequestPurchaseGamePass,
	Constants.RemoteNames.RequestSkipTutorial,
	Constants.RemoteNames.TutorialStateUpdate,
	Constants.RemoteNames.RequestPrestige,
	Constants.RemoteNames.PrestigeStateUpdate,
	Constants.RemoteNames.RequestCreateClan,
	Constants.RemoteNames.RequestJoinClan,
	Constants.RemoteNames.RequestLeaveClan,
	Constants.RemoteNames.ClanStateUpdate,
	Constants.RemoteNames.RequestClaimBattlePassReward,
	Constants.RemoteNames.BattlePassStateUpdate,
	Constants.RemoteNames.RequestRecruitSoldiers,
	Constants.RemoteNames.RequestDismissSoldiers,
	Constants.RemoteNames.SoldierStateUpdate,
	Constants.RemoteNames.RequestSquadOrder,
	Constants.RemoteNames.SquadOrderStateUpdate,
	Constants.RemoteNames.SeasonStateUpdate,
	Constants.RemoteNames.RequestDeclareClanWar,
	Constants.RemoteNames.ClanWarStateUpdate,
	Constants.RemoteNames.RequestRedeemCode,
	Constants.RemoteNames.CodeStateUpdate,
	Constants.RemoteNames.NationColorUpdate,
	Constants.RemoteNames.RequestClaimSpinner,
	Constants.RemoteNames.SpinnerStateUpdate,
	Constants.RemoteNames.BankRaidStateUpdate,
	Constants.RemoteNames.StudioSmokeLog,
	Constants.RemoteNames.DeathShopOffer,
	Constants.RemoteNames.StarterBundleOffer,
	Constants.RemoteNames.AutoCollectOffer,
	Constants.RemoteNames.DoubleCashOffer,
	Constants.RemoteNames.VIPOffer,
	Constants.RemoteNames.SpeedBoostOffer,
	Constants.RemoteNames.CashMegaOffer,
	Constants.RemoteNames.AtmRaidStateUpdate,
	Constants.RemoteNames.PromptPremiumPad,
}

local FUNCTIONS = {
	Constants.RemoteNames.GetPlayerState,
}

local _initialized = false

function RemoteSetup.Init(): Folder
	-- v60: scrub legacy Rojo empty Remotes so clients never latch onto it
	local legacy = ReplicatedStorage:FindFirstChild("Remotes")
	if legacy and legacy:IsA("Folder") and legacy.Name ~= Constants.RemotesFolderName then
		if #legacy:GetChildren() == 0 then
			legacy:Destroy()
		end
	end

	local folder = ReplicatedStorage:FindFirstChild(Constants.RemotesFolderName)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = Constants.RemotesFolderName
		folder.Parent = ReplicatedStorage
	end

	-- Always ensure every remote exists (idempotent; cheap if already present)
	for _, name in ipairs(EVENTS) do
		if not folder:FindFirstChild(name) then
			local ev = Instance.new("RemoteEvent")
			ev.Name = name
			ev.Parent = folder
		end
	end

	for _, name in ipairs(FUNCTIONS) do
		if not folder:FindFirstChild(name) then
			local fn = Instance.new("RemoteFunction")
			fn.Name = name
			fn.Parent = folder
		end
	end

	-- Guard: never create Give* remotes
	for _, child in ipairs(folder:GetChildren()) do
		if string.sub(child.Name, 1, 4) == "Give" then
			warn("[RemoteSetup] Removing forbidden remote:", child.Name)
			child:Destroy()
		end
	end

	if not _initialized then
		_initialized = true
		print(string.format("[RemoteSetup] Remotes ready: %d events + %d functions", #EVENTS, #FUNCTIONS))
	end

	return folder :: Folder
end


function RemoteSetup.Get(name: string): Instance
	local folder = ReplicatedStorage:FindFirstChild(Constants.RemotesFolderName)
	if not folder then
		folder = ReplicatedStorage:WaitForChild(Constants.RemotesFolderName, 30)
	end
	assert(folder, "WE_Remotes missing")
	local remote = folder:FindFirstChild(name)
	if remote then
		return remote
	end
	remote = folder:WaitForChild(name, 30)
	assert(remote, "remote missing: " .. name)
	return remote
end

return RemoteSetup
