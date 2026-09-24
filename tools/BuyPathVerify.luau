--!strict
--[[
	Command-bar / CI-style static checks for BUY + Army + Garage wiring.
	Paste in Studio Play Solo OR run mentally against repo — does not grant currency.
	Prints PASS/FAIL for remotes, monetization Id=0 stubs, catalog, pad tags, GUIs.

	Live playtest automation notes: docs/LIVE_PLAYTEST_AUTOMATION.md
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local function ok(msg: string)
	print("[BuyPathVerify] PASS", msg)
end
local function bad(msg: string)
	warn("[BuyPathVerify] FAIL", msg)
end
local function soft(msg: string)
	print("[BuyPathVerify] WAIT", msg)
end
local function note(msg: string)
	print("[BuyPathVerify] NOTE", msg)
end

local Shared = ReplicatedStorage:FindFirstChild("Shared")
if not Shared then
	bad("ReplicatedStorage.Shared missing")
	return
end

local Constants = require(Shared.Constants)
local Remotes = require(Shared.Remotes)

-- 1) Core BUY + Army + Garage remotes
local need = {
	Constants.RemoteNames.RequestPurchaseUpgrade,
	Constants.RemoteNames.RequestPurchaseVehicle,
	Constants.RemoteNames.RequestPurchaseWeapon,
	Constants.RemoteNames.RequestSpawnVehicle,
	Constants.RemoteNames.RequestDespawnVehicle,
	Constants.RemoteNames.RequestRecruitSoldiers,
	Constants.RemoteNames.RequestDismissSoldiers,
	Constants.RemoteNames.RequestPurchaseDevProduct,
	Constants.RemoteNames.RequestPurchaseGamePass,
	Constants.RemoteNames.RequestPrestige,
	Constants.RemoteNames.BaseStateUpdate,
	Constants.RemoteNames.VehicleStateUpdate,
	Constants.RemoteNames.SoldierStateUpdate,
	Constants.RemoteNames.EconomyUpdate,
	Constants.RemoteNames.Notification,
	Constants.RemoteNames.StudioSmokeLog,
}
for _, name in ipairs(need) do
	local okEv, ev = pcall(function()
		return Remotes.GetEvent(name)
	end)
	if okEv and ev then
		ok("Remote " .. name)
	else
		bad("Remote missing " .. name)
	end
end

-- No Give* remotes (anti-exploit stub)
do
	local folder = ReplicatedStorage:FindFirstChild(Constants.RemotesFolderName)
	if folder then
		local giveHits = 0
		for _, child in ipairs(folder:GetChildren()) do
			if string.find(string.lower(child.Name), "give", 1, true) then
				giveHits += 1
				bad("Forbidden Give* remote: " .. child.Name)
			end
		end
		if giveHits == 0 then
			ok("No Give* remotes in folder")
		end
	else
		bad("Remotes folder missing")
	end
end

-- 2) Monetization stubs — ALL product Ids MUST stay 0 until Creator Dashboard
do
	local okCfg, MonetizationConfig = pcall(function()
		return require(Shared.Configs.MonetizationConfig)
	end)
	if not okCfg or typeof(MonetizationConfig) ~= "table" then
		bad("MonetizationConfig require failed")
	else
		local nonzero = 0
		local checked = 0
		for key, def in pairs(MonetizationConfig.DevProducts or {}) do
			checked += 1
			local id = tonumber(def.Id) or -1
			if id ~= 0 then
				nonzero += 1
				bad(string.format("DevProduct %s Id=%s (want 0 stub)", key, tostring(id)))
			end
		end
		for key, def in pairs(MonetizationConfig.GamePasses or {}) do
			checked += 1
			local id = tonumber(def.Id) or -1
			if id ~= 0 then
				nonzero += 1
				bad(string.format("GamePass %s Id=%s (want 0 stub)", key, tostring(id)))
			end
		end
		if nonzero == 0 and checked > 0 then
			ok(string.format("Monetization stubs clear — %d product Ids all 0", checked))
		elseif checked == 0 then
			bad("MonetizationConfig empty DevProducts/GamePasses")
		end
		if MonetizationConfig.LootBoxPolicyPending ~= true then
			bad("LootBoxPolicyPending should stay true")
		else
			ok("LootBoxPolicyPending=true (no loot-box grants)")
		end
	end
	local okBp, BattlePassConfig = pcall(function()
		return require(Shared.Configs.BattlePassConfig)
	end)
	if okBp and typeof(BattlePassConfig) == "table" then
		if (tonumber(BattlePassConfig.PremiumProductId) or -1) == 0 then
			ok("BattlePass PremiumProductId=0 stub")
		else
			bad("BattlePass PremiumProductId non-zero")
		end
	end
end

-- 2b) Studio BUY smoke remote (Play Solo client Output mirror)
do
	local name = Constants.RemoteNames.StudioSmokeLog
	local okEv, ev = pcall(function()
		return Remotes.GetEvent(name)
	end)
	if okEv and ev then
		ok("StudioSmokeLog remote present (StudioBuySmoke → FireAllClients)")
	else
		bad("StudioSmokeLog remote missing")
	end
	note("Play Solo: expect [SMOKE] BUY START/OK in server AND client Output ~4s after plot")
end

-- 3) PERF flag — keep StudioSkipWorldDressing
do
	local okDev, DevConfig = pcall(function()
		return require(Shared.Configs.DevConfig)
	end)
	if okDev and typeof(DevConfig) == "table" then
		if DevConfig.StudioSkipWorldDressing == true then
			ok("DevConfig.StudioSkipWorldDressing=true (8GB PERF)")
		else
			bad("StudioSkipWorldDressing should stay true for laptop PERF")
		end
	else
		bad("DevConfig require failed")
	end
end

-- 4) VisualAssetConfig free-ID sanity (config only — does not InsertService)
do
	local okCfg, VisualAssetConfig = pcall(function()
		return require(Shared.Configs.VisualAssetConfig)
	end)
	if not okCfg or typeof(VisualAssetConfig) ~= "table" then
		bad("VisualAssetConfig require failed")
	else
		ok("VisualAssetConfig loaded Enabled=" .. tostring(VisualAssetConfig.Enabled))
		local function countPositive(map: any): number
			local n = 0
			if typeof(map) ~= "table" then
				return 0
			end
			for _, ref in pairs(map) do
				if typeof(ref) == "table" and typeof(ref.ModelAssetId) == "number" and ref.ModelAssetId > 0 then
					n += 1
				end
			end
			return n
		end
		local v = countPositive(VisualAssetConfig.Vehicles)
		local b = countPositive(VisualAssetConfig.Buildings)
		local d = countPositive(VisualAssetConfig.DesertProps)
		local c = countPositive(VisualAssetConfig.Characters)
		if v >= 60 then
			ok(string.format("Vehicles free IDs mapped=%d (full roster aliases)", v))
		elseif v >= 20 then
			ok(string.format("Vehicles free IDs mapped=%d", v))
		else
			bad(string.format("Vehicles free IDs thin=%d (want ≥20)", v))
		end
		if b >= 5 then
			ok(string.format("Buildings free IDs mapped=%d", b))
		else
			bad(string.format("Buildings free IDs thin=%d (want ≥5)", b))
		end
		if d >= 2 then
			ok(string.format("DesertProps free IDs mapped=%d", d))
		else
			bad(string.format("DesertProps free IDs thin=%d (want ≥2)", d))
		end
		if c >= 1 then
			ok(string.format("Characters free IDs mapped=%d", c))
		else
			bad("Characters free IDs missing")
		end
		local fb = VisualAssetConfig.KitFamilyFallback
		if typeof(fb) == "table" and fb.JetFighter and fb.NavalPatrol then
			ok("KitFamilyFallback has JetFighter + NavalPatrol")
		else
			bad("KitFamilyFallback missing Jet/Naval keys")
		end
	end
end

-- 5) World tags — garage / army pads (spawn reliability)
do
	local function countTag(tag: string): number
		local n = 0
		for _, inst in ipairs(CollectionService:GetTagged(tag)) do
			if inst:IsA("BasePart") then
				n += 1
			end
		end
		return n
	end
	local vehiclePads = countTag(Constants.Tags.VehicleSpawn)
	local navalPads = countTag(Constants.Tags.NavalSpawn)
	local upgradePads = countTag(Constants.Tags.UpgradeSlot)
	local plots = countTag(Constants.Tags.BasePlot)
	if vehiclePads >= 4 then
		ok(string.format("WE_VehicleSpawn pads=%d", vehiclePads))
	elseif vehiclePads > 0 then
		soft(string.format("WE_VehicleSpawn pads=%d (thin — MapSetup done?)", vehiclePads))
	else
		soft("WE_VehicleSpawn pads=0 (ok if MapSetup not finished yet)")
	end
	if navalPads >= 1 then
		ok(string.format("WE_NavalSpawn pads=%d", navalPads))
	else
		soft("WE_NavalSpawn pads=0")
	end
	if upgradePads >= 6 then
		ok(string.format("WE_UpgradeSlot pads=%d", upgradePads))
	else
		soft(string.format("WE_UpgradeSlot pads=%d", upgradePads))
	end
	if plots >= 1 then
		ok(string.format("WE_BasePlot pads=%d", plots))
	else
		soft("WE_BasePlot pads=0")
	end
end

-- 6) Client GUIs + Activated path notes
local pg = Players.LocalPlayer and Players.LocalPlayer:FindFirstChild("PlayerGui")
if pg then
	for _, guiName in ipairs({
		"WE_PadBuyGui",
		"WarEmpireGarage",
		"WarEmpireArmy",
		"WarEmpireCombatHUD",
		"WarEmpireTerritory",
		"WarEmpireShop",
		"WarEmpireProgression",
		"WarEmpireHUD",
	}) do
		local g = pg:FindFirstChild(guiName)
		if g then
			ok("Gui present " .. guiName)
			local buttons = 0
			for _, d in ipairs(g:GetDescendants()) do
				if d:IsA("TextButton") or d:IsA("ImageButton") then
					buttons += 1
					if d.Active ~= true then
						soft(string.format("GuiButton %s.%s Active=false", guiName, d.Name))
					end
				end
			end
			if buttons > 0 then
				ok(string.format("Gui %s has %d GuiButtons", guiName, buttons))
			end
		else
			soft("Gui not yet: " .. guiName .. " (ok if early)")
		end
	end

	local buyGui = pg:FindFirstChild("WE_PadBuyGui")
	if buyGui then
		local buyBtn = buyGui:FindFirstChild("BuyButton", true) or buyGui:FindFirstChildWhichIsA("TextButton", true)
		if buyBtn and buyBtn:IsA("GuiButton") then
			ok("Pad BUY GuiButton present: " .. buyBtn.Name)
			-- v70: the BUY button lives in the HUD action lane; the rule is >= 44 px REAL (after the HUD UIScale)
			if buyBtn.AbsoluteSize.Y >= 44 then
				ok(string.format("Pad BUY touch height OK (%d px real)", math.floor(buyBtn.AbsoluteSize.Y)))
			else
				soft(string.format("Pad BUY height %d px real < 44 — check HudConfig.ActionLane", math.floor(buyBtn.AbsoluteSize.Y)))
			end
		else
			soft("Pad BUY button not visible yet (stand on own pad)")
		end
	end

	local garage = pg:FindFirstChild("WarEmpireGarage")
	if garage then
		local spawnish = 0
		for _, d in ipairs(garage:GetDescendants()) do
			if d:IsA("TextButton") and (d.Text == "SPAWN" or d.Text == "BUY" or string.find(d.Text, "BUY", 1, true) or d.Text == "DESPAWN" or d.Name == "GarageToggle") then
				spawnish += 1
			end
		end
		if spawnish > 0 then
			ok(string.format("Garage action buttons visible≈%d (open panel / OWNED filter)", spawnish))
		else
			soft("Garage SPAWN/BUY not visible yet — open the Garage (rail tile / G) after VehicleStateUpdate")
		end
	end

	-- v70 HUD: the new top-level guis, and ONE HUD scale on every gui that carries a MobileScale
	for _, guiName in ipairs({ "WE_TopStrip", "WE_Reticle", "WE_PromptLane", "WarEmpireNotifications" }) do
		if pg:FindFirstChild(guiName) then
			ok("Gui present " .. guiName)
		else
			soft("Gui not yet: " .. guiName .. " (ok if early)")
		end
	end
	local scales: { [string]: number } = {}
	local first: number? = nil
	local same = true
	for _, g in ipairs(pg:GetChildren()) do
		local s = if g:IsA("ScreenGui") then g:FindFirstChild("MobileScale") else nil
		if s and s:IsA("UIScale") then
			scales[g.Name] = s.Scale
			if first == nil then
				first = s.Scale
			elseif math.abs(s.Scale - (first :: number)) > 0.001 then
				same = false
			end
		end
	end
	if first == nil then
		soft("no MobileScale UIScale found yet (ok if early)")
	elseif same then
		ok(string.format("one HUD scale %.2f on every MobileScale gui", first :: number))
	else
		local parts = {}
		for name, v in pairs(scales) do
			table.insert(parts, string.format("%s=%.2f", name, v))
		end
		table.sort(parts)
		bad("MobileScale differs between HUD guis: " .. table.concat(parts, " "))
	end
else
	soft("LocalPlayer.PlayerGui missing (run on client / Play Solo)")
end

note(string.format("Studio=%s Server=%s Client=%s", tostring(RunService:IsStudio()), tostring(RunService:IsServer()), tostring(RunService:IsClient())))
print("[BuyPathVerify] Done — stand on YOUR pad and tap BUY; Output should show [WorldPrompt] BUY + [BaseService] Remote BUY result Ok=true")
print("[BuyPathVerify] Army: rail Army tile / key Y → popover → MANAGE ARMY → RECRUIT; expect SoldierStateUpdate + Success toast")
print("[BuyPathVerify] Garage: rail Garage tile / G → OWNED Jeep SPAWN; expect Deployed toast + DriverSeat model")
print("[BuyPathVerify] Shop/Rebirth: rail tiles use Activated; panels DisplayOrder 60 above the HUD rail 55")
print("[BuyPathVerify] Automation: docs/LIVE_PLAYTEST_AUTOMATION.md + tools/SmokeTest.luau")
