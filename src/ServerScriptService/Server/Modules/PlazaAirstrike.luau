--!strict
--[[
	claude-bud JOB 5c (2026-09-29): the one-shot Plaza Airstrike (DevProducts.PlazaAirstrike, a CounterGrant that banks
	profile.AirstrikeCharges in ProcessReceipt before PurchaseGranted). Balanced for the plaza fight:
	  * used only within UseRangeStuds of the Central Plaza, one per server per ServerCooldownSeconds and per player per
	    PlayerCooldownSeconds (RequestPlazaAirstrike is rate-limited; the server checks every rule and the charge);
	  * WarnSeconds of warning (a toast to everyone in the zone) before it lands, so they can move;
	  * Damage to every OTHER player in the capture zone, NEVER lethal (health stays >= MinHealthLeft), skipping
	    spawn-protected / novice-shielded players; no kill credit, no effect on the capture timer.
	Owner-only first through MonetizationConfig.SkuLiveFor(userId, "PlazaAirstrike").
	Code Bot v221 (Shaun 2026-10-02, MonetizationConfig.PlazaAirstrikeTakeover): the strike ALSO takes the Central Plaza
	for the buyer. FireFromPurchase (MonetizationService OnGranted, after the receipt is SAVED) spends the new charge at
	once, anywhere on the map (no range / cooldown refusal: it was paid for); the AIRSTRIKE button still spends an older
	banked charge. Either way, when the strike lands, TerritoryService.InstantCapture runs the normal awardCapture and
	everyone is told "AIRSTRIKE! <name> took the Plaza" (already the holder: "You still hold the Plaza").
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 60)
local MonetizationConfig = require(Shared.Configs.MonetizationConfig)
local TerritoryConfig = require(Shared.Configs.TerritoryConfig)
local Constants = require(Shared.Constants)

local PlazaAirstrike = {}

local serverReadyAt = 0
local playerReadyAt: { [number]: number } = {}

local function combat(): any?
	local ok, cs = pcall(function(): any
		return require(script.Parent.Parent.Services.CombatService)
	end)
	return if ok then cs else nil
end

local function zone(): (Vector3, number)
	local def: any = (TerritoryConfig.Territories :: any).CentralPlaza
	return (def and def.Position) or Vector3.new(0, 1, 0), (def and def.Radius) or 70
end

local function territory(): any?
	local ok, ts = pcall(function(): any
		return require(script.Parent.Parent.Services.TerritoryService)
	end)
	return if ok then ts else nil
end

-- Code Bot v221: the takeover switch (RetentionConfig.Live: Enabled + OwnerFirst, by the buyer)
function PlazaAirstrike.TakeoverLive(userId: any): boolean
	local block = (MonetizationConfig :: any).PlazaAirstrikeTakeover
	if typeof(block) ~= "table" then
		return false
	end
	local ok, live = pcall(function(): boolean
		return (require(Shared.Configs.RetentionConfig) :: any).Live(block, userId) == true
	end)
	return ok and live == true
end

local function fmt(template: any, fallback: string, name: string): string
	if typeof(template) ~= "string" then
		return fallback
	end
	local ok, msg = pcall(string.format, template, name)
	return if ok and typeof(msg) == "string" then msg else fallback
end

-- set by Start: spend one charge and drop the strike (+ the takeover) for this player; nil until Start ran
local fireStrike: ((Player) -> boolean)? = nil

--[[ Code Bot v221: the receipt path. MonetizationService calls it from OnGranted("PlazaAirstrike"), i.e. only after
	ProcessReceipt banked the charge and the profile was SAVED. No client input at all. ]]
function PlazaAirstrike.FireFromPurchase(player: Player): boolean
	local block = (MonetizationConfig :: any).PlazaAirstrikeTakeover
	if typeof(block) ~= "table" or block.FireOnPurchase ~= true or not PlazaAirstrike.TakeoverLive(player.UserId) then
		return false -- the old behaviour: the charge stays banked for the AIRSTRIKE button
	end
	local f = fireStrike
	if f == nil or player.Parent ~= Players then
		return false
	end
	return f(player)
end

-- deps: { DataService, NotificationService, RateLimitService, RemoteSetup }
function PlazaAirstrike.Start(deps: { [string]: any })
	local T = (MonetizationConfig :: any).PlazaAirstrikeTuning
	local remote = deps.RemoteSetup and deps.RemoteSetup.Get(Constants.RemoteNames.RequestPlazaAirstrike)
	if typeof(T) ~= "table" or remote == nil then
		return
	end
	local function notify(p: Player, msg: string, kind: string)
		if deps.NotificationService then
			deps.NotificationService.Notify(p, msg, kind)
		end
	end
	-- Code Bot v221: after the strike lands, the buyer takes the Plaza through the normal capture (server only)
	local function takeover(player: Player)
		if player.Parent ~= Players or not PlazaAirstrike.TakeoverLive(player.UserId) then
			return
		end
		local block: any = (MonetizationConfig :: any).PlazaAirstrikeTakeover
		local ts = territory()
		if ts == nil or ts.InstantCapture == nil then
			return
		end
		local okC, status = pcall(ts.InstantCapture, player, tostring(block.TerritoryId or "CentralPlaza"))
		local name = player.DisplayName
		if okC and status == "captured" then
			local msg = fmt(block.ToastAll, "AIRSTRIKE! " .. name .. " took the Plaza", name)
			for _, p in ipairs(Players:GetPlayers()) do
				notify(p, msg, if p == player then "Reward" else "Warn")
			end
			print(string.format("[PlazaAirstrike] takeover CentralPlaza -> %s (%d)", player.Name, player.UserId))
		elseif okC and status == "held" then
			notify(player, fmt(block.ToastHeld, "AIRSTRIKE! You still hold the Plaza", name), "Reward")
			local others = fmt(block.ToastHeldOthers, "AIRSTRIKE! " .. name .. " holds the Plaza", name)
			for _, p in ipairs(Players:GetPlayers()) do
				if p ~= player then
					notify(p, others, "Warn")
				end
			end
		else
			warn("[PlazaAirstrike] takeover failed for " .. player.Name .. ": " .. tostring(status))
		end
	end
	-- spend one charge, warn the zone, land the strike WarnSeconds later, then the takeover
	local function land(player: Player, profile: any)
		local center, radius = zone()
		local now = os.clock()
		profile.AirstrikeCharges = math.max(0, (tonumber(profile.AirstrikeCharges) or 1) - 1)
		pcall(function()
			player:SetAttribute("WE_AirstrikeCharges", profile.AirstrikeCharges)
		end)
		if deps.DataService.MarkDirty then
			deps.DataService.MarkDirty(player)
		end
		serverReadyAt = math.max(serverReadyAt, now + T.ServerCooldownSeconds)
		playerReadyAt[player.UserId] = math.max(playerReadyAt[player.UserId] or 0, now + T.PlayerCooldownSeconds)
		for _, p in ipairs(Players:GetPlayers()) do
			local r = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
			if p == player or (r and r:IsA("BasePart") and (r.Position - center).Magnitude <= radius + 20) then
				notify(p, "AIRSTRIKE incoming on the Plaza!", "Warn")
			end
		end
		task.delay(T.WarnSeconds, function()
			local cs = combat()
			for _, p in ipairs(Players:GetPlayers()) do
				if p ~= player then
					local ch = p.Character
					local r = ch and ch:FindFirstChild("HumanoidRootPart")
					local hum = ch and ch:FindFirstChildOfClass("Humanoid")
					if r and hum and r:IsA("BasePart") and hum.Health > 0 and (r.Position - center).Magnitude <= radius then
						local shielded = cs ~= nil
							and ((cs.IsSpawnInvulnerable and cs.IsSpawnInvulnerable(p)) or (cs.IsNoviceShielded and cs.IsNoviceShielded(p)))
						if not shielded then
							local dmg = math.min(T.Damage, math.max(0, hum.Health - T.MinHealthLeft))
							if dmg > 0 then
								hum:TakeDamage(dmg)
							end
						end
					end
				end
			end
			takeover(player)
		end)
	end
	-- Code Bot v221: the paid path (no range / cooldown refusal; needs the saved charge, never trusts the client)
	fireStrike = function(player: Player): boolean
		if not MonetizationConfig.SkuLiveFor(player.UserId, "PlazaAirstrike") then
			return false
		end
		local profile = deps.DataService and deps.DataService.GetProfile(player)
		if profile == nil or (tonumber(profile.AirstrikeCharges) or 0) < 1 then
			return false
		end
		land(player, profile)
		return true
	end
	;(remote :: RemoteEvent).OnServerEvent:Connect(function(player: Player)
		if not require(script.Parent.RemoteGate).Check(player, "RequestPlazaAirstrike") then -- claude-bud JOB 15: rate ceiling + argument schema
			return
		end
		if deps.RateLimitService and not deps.RateLimitService.Allow(player, "plaza_airstrike", 1, 2) then
			return
		end
		if not MonetizationConfig.SkuLiveFor(player.UserId, "PlazaAirstrike") then
			return
		end
		local profile = deps.DataService and deps.DataService.GetProfile(player)
		if profile == nil or (tonumber(profile.AirstrikeCharges) or 0) < 1 then
			return
		end
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		local center = zone()
		if root == nil or not root:IsA("BasePart") or (root.Position - center).Magnitude > T.UseRangeStuds then
			notify(player, "Get closer to the Central Plaza", "Warn")
			return
		end
		local now = os.clock()
		if now < serverReadyAt then
			notify(player, string.format("Airspace busy: %ds", math.ceil(serverReadyAt - now)), "Warn")
			return
		end
		if now < (playerReadyAt[player.UserId] or 0) then
			notify(player, string.format("Airstrike ready in %ds", math.ceil(playerReadyAt[player.UserId] - now)), "Warn")
			return
		end
		-- spend the charge first (saved with the next save; a crash refunds nothing that was not used)
		land(player, profile)
	end)
end

return PlazaAirstrike
