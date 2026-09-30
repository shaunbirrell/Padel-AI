--!strict
--[[
	claude-bud JOB 36 (2026-09-30): the server side of the SHOP OVERHAUL that is not a purchase (ShopOverhaulConfig;
	MonetizationService does the receipts, the War Chest ownership, the VIP +50 %, the death / army offers).
	  * WE_PassivePerMin: every PerMinPublishSeconds, each live player's passive $/min (MonetizationService.PassivePerMin)
	    as a player attribute, so the Shop rows / offers show the live cash-pack amounts. Display only: ProcessReceipt
	    recomputes the grant itself.
	  * The daily VIP supply crate: a live VIP owner gets max(SupplyFloor, SupplyMinutes x $/min) once every
	    SupplyEveryHours (profile.VipSupplyAt), automatically (join + a 10 min check), reason "vip_supply" (exempt from
	    the multipliers: the minutes already include them).
	  * The base Speed stand sells Speed Boost (SpeedStandProduct) while its plot's owner is live; back to the config's
	    first live offer otherwise (PurchaseStands.Retarget).
	  * Perk attributes the combat code reads (server-set, never from the client): WE_PerkDoubleHP (ArmourService doubles
	    the base MaxHealth) and WE_PerkSuperSoldiers (SquadOrdersService: army damage and soldier HP x1.25), from pass
	    ownership while live; ArmourService.Apply / SquadOrdersService.ApplyResearch re-run when they change.
	Kill switch: ShopOverhaulConfig.Live (owner-first).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local ShopOverhaulConfig = require(Shared.Configs.ShopOverhaulConfig)
local MonetizationConfig = require(Shared.Configs.MonetizationConfig)
local PurchaseStands = require(script.Parent.Parent.Modules.PurchaseStands)

local ShopOverhaulService = {}

local deps: { [string]: any } = {}
local PAD_TAG = (Constants.Tags and Constants.Tags.PremiumPad) or "WE_PremiumPad"

local function live(uid: number): boolean
	return ShopOverhaulConfig.LiveFor(uid)
end

local function perMin(player: Player): number
	local ms = deps.MonetizationService
	local profile = deps.DataService and deps.DataService.GetProfile(player)
	if ms == nil or ms.PassivePerMin == nil or profile == nil then
		return 0
	end
	local ok, v = pcall(ms.PassivePerMin, player, profile)
	return if ok and typeof(v) == "number" then v else 0
end

local function ownsPass(player: Player, key: string): boolean
	local ms = deps.MonetizationService
	if ms == nil then
		return false
	end
	local ok, v = pcall(function()
		return ms.PlayerOwnsEntitlement(player, key) or ms.PlayerOwnsGamePass(player, key)
	end)
	return ok and v == true
end

--[[ The VIP crate decision (pure; tests call it): the amount to pay now, or 0. ]]
function ShopOverhaulService.VipSupplyDue(lastUnix: number, now: number, rate: number): number
	local every = math.max(1, ShopOverhaulConfig.Vip.SupplyEveryHours) * 3600
	if now - (tonumber(lastUnix) or 0) < every then
		return 0
	end
	return ShopOverhaulConfig.VipSupplyAmount(rate)
end

function ShopOverhaulService.TryVipSupply(player: Player): number
	if not live(player.UserId) or not ownsPass(player, "VIP") then
		return 0
	end
	local profile = deps.DataService and deps.DataService.GetProfile(player)
	if profile == nil or player.Parent == nil then
		return 0
	end
	local amount = ShopOverhaulService.VipSupplyDue(tonumber(profile.VipSupplyAt) or 0, os.time(), perMin(player))
	if amount <= 0 or deps.DataService.GetProfile(player) ~= profile then
		return 0
	end
	profile.VipSupplyAt = os.time()
	deps.EconomyService.AddCash(player, amount, "vip_supply")
	deps.DataService.MarkDirty(player)
	local s = tostring(amount):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
	if deps.NotificationService then
		pcall(deps.NotificationService.Notify, player, "VIP supply crate: +$" .. s, "Reward", 5)
	end
	if deps.AnalyticsService then
		pcall(deps.AnalyticsService.Log, "VIP_SUPPLY", player.UserId, { cash = amount })
	end
	return amount
end

-- the perk attributes from ownership (server-set; the combat code reads them), then re-apply what they change
function ShopOverhaulService.SyncPerks(player: Player)
	local on = live(player.UserId)
	local hp = on and ownsPass(player, ShopOverhaulConfig.DoubleHP.PassKey)
	local ss = on and ownsPass(player, ShopOverhaulConfig.SuperSoldiers.PassKey)
	local hpChanged = (player:GetAttribute("WE_PerkDoubleHP") == true) ~= hp
	local ssChanged = (player:GetAttribute("WE_PerkSuperSoldiers") == true) ~= ss
	player:SetAttribute("WE_PerkDoubleHP", if hp then true else nil)
	player:SetAttribute("WE_PerkSuperSoldiers", if ss then true else nil)
	if hpChanged then
		local okA, AS = pcall(function(): any
			return require(script.Parent.ArmourService)
		end)
		if okA and AS and AS.Apply then
			pcall(AS.Apply, player)
		end
	end
	if ssChanged and deps.SquadOrdersService and deps.SquadOrdersService.ApplyResearch then
		pcall(deps.SquadOrdersService.ApplyResearch, player)
	end
end

-- the base Speed stand of this plot: Speed Boost while its owner is live, else the config's first live offer
function ShopOverhaulService.SyncSpeedStand(plotId: number, owner: Player?)
	local wantBoost = owner ~= nil and live(owner.UserId)
	local slot: any = nil
	for _, s in ipairs(MonetizationConfig.PremiumPads.Slots) do
		if s.Id == "Speed" then
			slot = s
		end
	end
	if slot == nil then
		return
	end
	local fallback = MonetizationConfig.LivePadOffer(slot)
	local product: any = (MonetizationConfig.DevProducts :: any)[ShopOverhaulConfig.SpeedStandProduct]
	local canBoost = typeof(product) == "table" and (tonumber(product.Id) or 0) ~= 0
	for _, top in ipairs(CollectionService:GetTagged(PAD_TAG)) do -- once per plot ready / leave
		if top:IsA("BasePart") and top:GetAttribute("PlotId") == plotId and top:GetAttribute("PadSlot") == "Speed" then
			if wantBoost and canBoost then
				PurchaseStands.Retarget(top, "DevProduct", ShopOverhaulConfig.SpeedStandProduct)
			elseif fallback then
				PurchaseStands.Retarget(top, fallback.Kind, fallback.Key)
			end
		end
	end
end

function ShopOverhaulService.Init(d: { [string]: any })
	deps = d
	local plotOf: { [number]: number } = {}
	if d.DataService and d.DataService.OnProfileLoaded then
		d.DataService.OnProfileLoaded(function(player: Player)
			task.delay(8, function()
				if player.Parent then
					ShopOverhaulService.SyncPerks(player)
					ShopOverhaulService.TryVipSupply(player)
				end
			end)
		end)
	end
	local ms = d.MonetizationService
	if ms and ms.OnPassOwned then
		ms.OnPassOwned(function(player: Player)
			task.defer(function()
				if player.Parent then
					ShopOverhaulService.SyncPerks(player)
					ShopOverhaulService.TryVipSupply(player)
				end
			end)
		end)
	end
	if d.BaseService and d.BaseService.OnPlotReady then
		d.BaseService.OnPlotReady(function(player: Player, plotId: number)
			plotOf[player.UserId] = plotId
			pcall(ShopOverhaulService.SyncSpeedStand, plotId, player)
		end)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		local plotId = plotOf[player.UserId]
		plotOf[player.UserId] = nil
		if plotId then
			pcall(ShopOverhaulService.SyncSpeedStand, plotId, nil)
		end
	end)
	-- the live $/min for the Shop (a few players, every PerMinPublishSeconds) + the VIP crate check every 10 min
	task.spawn(function()
		local sinceCrate = 0
		while true do
			task.wait(ShopOverhaulConfig.PerMinPublishSeconds)
			sinceCrate += ShopOverhaulConfig.PerMinPublishSeconds
			for _, p in ipairs(Players:GetPlayers()) do
				if live(p.UserId) then
					local v = math.floor(perMin(p))
					if p:GetAttribute(ShopOverhaulConfig.PerMinAttribute) ~= v then
						p:SetAttribute(ShopOverhaulConfig.PerMinAttribute, v)
					end
					if sinceCrate >= 600 then
						pcall(ShopOverhaulService.TryVipSupply, p)
					end
				end
			end
			if sinceCrate >= 600 then
				sinceCrate = 0
			end
		end
	end)
	print("[WAR EMPIRE] ShopOverhaulService Init")
end

return ShopOverhaulService
