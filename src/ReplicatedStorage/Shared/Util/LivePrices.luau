--!strict
--[[ Code Bot v156 (2026-10-01, Shaun's phone: the Supply Depot said "Commander Starter Pack  149 R$", the Roblox prompt
	said "Commander Starter Bundle  249"). THE Robux price and name every Shop / Supply Depot row, purchase stand and
	offer card shows.
	Root cause: the UI printed MonetizationConfig RobuxPrice / DisplayName, typed by hand, while Roblox charges the
	product's real price (the owner's v71 decision to reprice the Starter Pack to 149 never reached the Creator Hub).
	  * Server: LivePrices.StartServer() asks MarketplaceService:GetProductInfo once per live Id (pcall'd, spaced out),
	    caches the answer and publishes it on ReplicatedStorage: WE_Px_<GP|DP>_<Key> = PriceInRobux and
	    WE_PxN_<GP|DP>_<Key> = the product Name. Refreshed every RefreshSeconds; a failed lookup keeps the last value.
	  * Everyone (client and server) reads Price / Name: the live Roblox value, else the config value (fallback only).
	  * Display only: grants, receipts and prompts never read these (the prompt always charges the real price).
	Never change a price here: prices live on the Creator Hub. ]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MonetizationConfig = require(script.Parent.Parent.Configs.MonetizationConfig)

local LivePrices = {}
LivePrices.RefreshSeconds = 600 -- one lookup round per server per 10 min
LivePrices.SpacingSeconds = 0.2 -- between two lookups (about 40 products: ~8 s a round)
LivePrices.PricePrefix = "WE_Px_"
LivePrices.NamePrefix = "WE_PxN_"

local function tagOf(kind: string): string
	return if kind == "GamePass" then "GP" else "DP"
end

local function defOf(kind: string, key: string): any
	local section: any = if kind == "GamePass" then MonetizationConfig.GamePasses else MonetizationConfig.DevProducts
	local d = if typeof(section) == "table" then section[key] else nil
	return if typeof(d) == "table" then d else nil
end

local function isKey(key: any): boolean
	return typeof(key) == "string" and #key > 0 and #key <= 48 and string.match(key, "^[%w_]+$") ~= nil
end

-- the real Robux price of a product / pass (Roblox's PriceInRobux once known, else the config RobuxPrice)
function LivePrices.Price(kind: string, key: string): number
	if not isKey(key) then
		return 0
	end
	local live = ReplicatedStorage:GetAttribute(LivePrices.PricePrefix .. tagOf(kind) .. "_" .. key)
	if typeof(live) == "number" and live > 0 and live < 1e7 then
		return math.floor(live)
	end
	local d = defOf(kind, key)
	return math.max(0, math.floor(tonumber(d and d.RobuxPrice) or 0))
end

-- the product's name on Roblox (what the purchase prompt says), else the config DisplayName, else the key
function LivePrices.Name(kind: string, key: string): string
	if not isKey(key) then
		return tostring(key)
	end
	local live = ReplicatedStorage:GetAttribute(LivePrices.NamePrefix .. tagOf(kind) .. "_" .. key)
	if typeof(live) == "string" and #live > 0 and #live <= 60 then
		return live
	end
	local d = defOf(kind, key)
	return if d and typeof(d.DisplayName) == "string" then d.DisplayName else key
end

-- the live Roblox price only (nil until the server's lookup has published it)
function LivePrices.Known(kind: string, key: string): number?
	if not isKey(key) then
		return nil
	end
	local live = ReplicatedStorage:GetAttribute(LivePrices.PricePrefix .. tagOf(kind) .. "_" .. key)
	return if typeof(live) == "number" and live > 0 and live < 1e7 then math.floor(live) else nil
end

-- an offer card's price: the live one, else the server payload's (the server read the same cache), else the config
function LivePrices.ForOffer(kind: string, key: string, payloadPrice: any): number
	local known = LivePrices.Known(kind, key)
	if known then
		return known
	end
	local p = tonumber(payloadPrice)
	if p and p > 0 and p < 1e7 then
		return math.floor(p)
	end
	return LivePrices.Price(kind, key)
end

-- "249 R$" (or "BUY" / fallbackText when there is no price)
function LivePrices.Cta(kind: string, key: string, fallbackText: string?): string
	local p = LivePrices.Price(kind, key)
	return if p > 0 then tostring(p) .. " R$" else (fallbackText or "BUY")
end

-- fn() after any live price / name changes (coalesced to one call per frame)
function LivePrices.Changed(fn: () -> ()): RBXScriptConnection
	local queued = false
	return ReplicatedStorage.AttributeChanged:Connect(function(name: string)
		if string.sub(name, 1, 5) ~= "WE_Px" or queued then
			return
		end
		queued = true
		task.defer(function()
			queued = false
			fn()
		end)
	end)
end

-- the server's cache (key "GP_VIP" -> { Price, Name })
local cache: { [string]: { Price: number, Name: string } } = {}
local started = false

local function lookup(kind: string, key: string, id: number)
	local MarketplaceService = game:GetService("MarketplaceService")
	local infoType = if kind == "GamePass" then Enum.InfoType.GamePass else Enum.InfoType.Product
	local ok, info = pcall(function()
		return MarketplaceService:GetProductInfo(id, infoType)
	end)
	if not ok or typeof(info) ~= "table" then
		return -- keep the last good value (or the config fallback)
	end
	local price = tonumber((info :: any).PriceInRobux)
	local name = (info :: any).Name
	local tag = tagOf(kind) .. "_" .. key
	local entry = cache[tag] or { Price = 0, Name = "" }
	if price and price > 0 and price < 1e7 then
		entry.Price = math.floor(price)
		ReplicatedStorage:SetAttribute(LivePrices.PricePrefix .. tag, entry.Price)
	end
	if typeof(name) == "string" and #name > 0 and #name <= 60 then
		entry.Name = name
		ReplicatedStorage:SetAttribute(LivePrices.NamePrefix .. tag, name)
	end
	cache[tag] = entry
end

local function round()
	for _, kind in ipairs({ "DevProduct", "GamePass" }) do
		local section: any = if kind == "GamePass" then MonetizationConfig.GamePasses else MonetizationConfig.DevProducts
		for key, d in pairs(section) do
			local id = if typeof(d) == "table" then tonumber(d.Id) else nil
			if isKey(key) and id and id > 0 then
				lookup(kind, key, id)
				task.wait(LivePrices.SpacingSeconds)
			end
		end
	end
end

-- server only, once: fill the cache now, then refresh every RefreshSeconds (never yields the caller)
function LivePrices.StartServer()
	if started or not RunService:IsServer() then
		return
	end
	started = true
	task.spawn(function()
		while true do
			local ok, err = pcall(round)
			if not ok then
				warn("[LivePrices] lookup round failed:", err)
			end
			task.wait(LivePrices.RefreshSeconds)
		end
	end)
end

-- test / debug hook: the server's cache
function LivePrices._Cache(): { [string]: { Price: number, Name: string } }
	return cache
end

return LivePrices
