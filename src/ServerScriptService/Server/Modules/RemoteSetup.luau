--!strict
--[[
	Creates remotes under ReplicatedStorage.WE_Remotes (server-only).
	v62: RequestPurchaseUpgrade OnServerEvent is hooked HERE at create-time so the
	exact same instance client FireServer hits is always listened — BaseService
	registers the handler via SetPurchaseUpgradeHandler (never a second remote).
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
	Constants.RemoteNames.PurchaseResult,
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
local _purchaseHandler: ((Player, any) -> ())? = nil
local _purchaseHooked = false
local _purchaseHookedInstance: RemoteEvent? = nil

function RemoteSetup.SetPurchaseUpgradeHandler(handler: (Player, any) -> ())
	_purchaseHandler = handler
	print("[RemoteSetup] PurchaseUpgrade handler registered")
end

local function ensurePurchaseHook(folder: Folder)
	local name = Constants.RemoteNames.RequestPurchaseUpgrade
	local ev = folder:FindFirstChild(name)
	if not ev then
		ev = Instance.new("RemoteEvent")
		ev.Name = name
		ev.Parent = folder
	end
	-- v63: re-hook if prior RemoteEvent was destroyed / replaced (never sticky forever)
	if _purchaseHooked then
		local hooked = _purchaseHookedInstance
		if hooked and hooked.Parent and hooked == ev then
			return
		end
		warn("[RemoteSetup] RequestPurchaseUpgrade instance changed — re-hooking OnServerEvent")
		_purchaseHooked = false
		_purchaseHookedInstance = nil
	end
	if not ev:IsA("RemoteEvent") then
		warn("[RemoteSetup] RequestPurchaseUpgrade is not RemoteEvent:", ev.ClassName)
		return
	end
	_purchaseHooked = true
	_purchaseHookedInstance = ev :: RemoteEvent
	local hookedEv = ev :: RemoteEvent
	hookedEv.OnServerEvent:Connect(function(player: Player, payload: any)
		-- Ignore events from a destroyed/replaced remote
		if _purchaseHookedInstance ~= hookedEv then
			return
		end
		local sid = if typeof(payload) == "table" then tostring((payload :: any).StructureId) else tostring(payload)
		print(string.format("[RemoteSetup] OnServerEvent RequestPurchaseUpgrade %s → %s handler=%s", player.Name, sid, tostring(_purchaseHandler ~= nil)))
		if _purchaseHandler then
			_purchaseHandler(player, payload)
		else
			warn("[RemoteSetup] RequestPurchaseUpgrade fired but handler not registered yet — BaseService.Init pending")
		end
	end)
	hookedEv.AncestryChanged:Connect(function(_, parent)
		if parent == nil and _purchaseHookedInstance == hookedEv then
			_purchaseHooked = false
			_purchaseHookedInstance = nil
			warn("[RemoteSetup] RequestPurchaseUpgrade destroyed — will re-hook on next Get/Init")
		end
	end)
	print("[RemoteSetup] RequestPurchaseUpgrade OnServerEvent hooked on WE_Remotes." .. name)
end

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

	-- v62: hook purchase OnServerEvent on the SAME instance clients FireServer
	ensurePurchaseHook(folder :: Folder)

	if not _initialized then
		_initialized = true
		print(string.format("[RemoteSetup] Remotes ready: %d events + %d functions (folder=%s)", #EVENTS, #FUNCTIONS, folder.Name))
	end

	return folder :: Folder
end


function RemoteSetup.Get(name: string): Instance
	-- v61: never hang Init/handlers — ensure folder+remote exist immediately
	local folder = ReplicatedStorage:FindFirstChild(Constants.RemotesFolderName)
	if not (folder and folder:IsA("Folder")) then
		folder = RemoteSetup.Init()
	end
	local remote = folder:FindFirstChild(name)
	if remote then
		if name == Constants.RemoteNames.RequestPurchaseUpgrade then
			ensurePurchaseHook(folder :: Folder)
		end
		return remote
	end
	-- Create missing event/function rather than WaitForChild forever
	if name == Constants.RemoteNames.GetPlayerState then
		local fn = Instance.new("RemoteFunction")
		fn.Name = name
		fn.Parent = folder
		warn("[RemoteSetup] Get created missing RemoteFunction:", name)
		return fn
	end
	local ev = Instance.new("RemoteEvent")
	ev.Name = name
	ev.Parent = folder
	warn("[RemoteSetup] Get created missing RemoteEvent:", name)
	if name == Constants.RemoteNames.RequestPurchaseUpgrade then
		ensurePurchaseHook(folder :: Folder)
	end
	return ev
end

return RemoteSetup
