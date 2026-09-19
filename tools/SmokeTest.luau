--[[
	WAR EMPIRE — Studio smoke harness (command-bar pasteable)

	When: Play Solo (or Start Server + Player) AFTER Rojo sync + Bootstrap.
	How:  Copy this entire file → Studio Command Bar → Enter.

	Checks:
	- Remotes folder + Request* remotes present (no Give* remotes)
	- Shared configs require cleanly
	- Key server services ModuleScripts present
	- Optional: GetPlayerState invoke
	- Optional: AdminConfig membership print (NO currency grants / no exploit paths)

	Safe by design — never invents GiveCash remotes or ProcessReceipt fakes.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local PASS, FAIL, INFO = 0, 0, 0

local function ok(msg)
	PASS = PASS + 1
	print("[Smoke] ✓", msg)
end

local function bad(msg)
	FAIL = FAIL + 1
	warn("[Smoke] ✗", msg)
end

local function info(msg)
	INFO = INFO + 1
	print("[Smoke] ·", msg)
end

print("========== WAR EMPIRE SMOKE TEST ==========")
print(string.format("Studio=%s  Server=%s  Client=%s", tostring(RunService:IsStudio()), tostring(RunService:IsServer()), tostring(RunService:IsClient())))

-- 1) Shared tree
local Shared = ReplicatedStorage:FindFirstChild("Shared")
if Shared then
	ok("ReplicatedStorage.Shared present")
else
	bad("ReplicatedStorage.Shared missing — Rojo sync Shared?")
end

-- 2) Config requires
local configNames = {
	"GameConfig",
	"EconomyConfig",
	"CombatConfig",
	"VehicleConfig",
	"TerritoryConfig",
	"MissionConfig",
	"MonetizationConfig",
	"BattlePassConfig",
	"PrestigeConfig",
	"ClanConfig",
	"ClanWarConfig",
	"SoldierConfig",
	"SeasonConfig",
	"AdminConfig",
	"DevConfig",
	"LootBoxConfig",
}
if Shared then
	local configs = Shared:FindFirstChild("Configs")
	if configs then
		ok("Shared.Configs folder present")
		for _, name in ipairs(configNames) do
			local mod = configs:FindFirstChild(name)
			if not mod then
				bad("Config missing: " .. name)
			else
				local reqOk, result = pcall(function()
					return require(mod)
				end)
				if reqOk then
					ok("require Configs." .. name)
					if name == "LootBoxConfig" and typeof(result) == "table" and result.PolicyPending == true then
						info("LootBoxConfig.PolicyPending = true (expected)")
					end
					if name == "MonetizationConfig" and typeof(result) == "table" then
						local zeroIds = true
						if result.DevProducts then
							for _, def in pairs(result.DevProducts) do
								if typeof(def) == "table" and def.Id and def.Id ~= 0 then
									zeroIds = false
								end
							end
						end
						if zeroIds then
							info("Monetization product Ids still 0 (placeholders)")
						end
					end
				else
					bad("require Configs." .. name .. " failed: " .. tostring(result))
				end
			end
		end
	else
		bad("Shared.Configs missing")
	end

	local svcMod = Shared:FindFirstChild("Configs") and Shared.Configs:FindFirstChild("StructureVisualConfig")
	if svcMod then
		local okReq, mod = pcall(require, svcMod)
		if okReq and typeof(mod) == "table" and mod.Palettes then
			local n = 0
			for _ in pairs(mod.Palettes) do
				n += 1
			end
			ok("StructureVisualConfig palettes=" .. tostring(n))
		else
			bad("StructureVisualConfig require failed")
		end
	else
		bad("StructureVisualConfig missing")
	end

	local constantsMod = Shared:FindFirstChild("Constants")
	if constantsMod then
		local cOk, Constants = pcall(require, constantsMod)
		if cOk and typeof(Constants) == "table" then
			ok("require Shared.Constants (DataVersion=" .. tostring(Constants.CURRENT_DATA_VERSION) .. ")")
		else
			bad("Constants require failed")
		end
	end
end

-- 3) Remotes folder
local remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not remotes then
	bad("Remotes folder missing — is server Bootstrap running? (Play Solo first)")
else
	ok("Remotes folder present (" .. #remotes:GetChildren() .. " children)")
	local required = {
		"RequestPurchaseUpgrade",
		"RequestClaimDailyReward",
		"RequestSpawnVehicle",
		"RequestPurchaseVehicle",
		"RequestDespawnVehicle",
		"RequestEquipWeapon",
		"RequestPurchaseWeapon",
		"RequestFire",
		"RequestReload",
		"RequestStartMission",
		"RequestClaimMission",
		"RequestCaptureTerritory",
		"RequestAdminCommand",
		"RequestPurchaseDevProduct",
		"RequestPurchaseGamePass",
		"RequestSkipTutorial",
		"RequestPrestige",
		"RequestCreateClan",
		"RequestJoinClan",
		"RequestLeaveClan",
		"RequestClaimBattlePassReward",
		"RequestRecruitSoldiers",
		"RequestDismissSoldiers",
		"RequestDeclareClanWar",
		"GetPlayerState",
		"PlayerStateUpdate",
		"EconomyUpdate",
		"Notification",
	}
	for _, name in ipairs(required) do
		local child = remotes:FindFirstChild(name)
		if child then
			ok("Remote: " .. name)
		else
			bad("Remote missing: " .. name)
		end
	end
	-- Forbidden Give* remotes
	local giveFound = false
	for _, child in ipairs(remotes:GetChildren()) do
		if string.sub(child.Name, 1, 4) == "Give" then
			giveFound = true
			bad("FORBIDDEN Give* remote present: " .. child.Name)
		end
	end
	if not giveFound then
		ok("No Give* remotes (good)")
	end
end

-- 4) Server service ModuleScripts present
local server = ServerScriptService:FindFirstChild("Server")
if server then
	ok("ServerScriptService.Server present")
	local services = server:FindFirstChild("Services")
	local modules = server:FindFirstChild("Modules")
	local expectedServices = {
		"DataService",
		"EconomyService",
		"RateLimitService",
		"AntiExploitService",
		"CombatService",
		"VehicleService",
		"TerritoryService",
		"MissionService",
		"MonetizationService",
		"PrestigeService",
		"ClanService",
		"BattlePassService",
		"SoldierService",
		"SeasonService",
		"ClanWarService",
		"AdminService",
		"TutorialService",
	}
	if services then
		for _, name in ipairs(expectedServices) do
			if services:FindFirstChild(name) then
				ok("Service module: " .. name)
			else
				bad("Service module missing: " .. name)
			end
		end
	else
		bad("Server.Services folder missing")
	end
	if modules and modules:FindFirstChild("RemoteSetup") and modules:FindFirstChild("RemoteGuard") then
		ok("Modules: RemoteSetup + RemoteGuard")
	else
		bad("Modules RemoteSetup/RemoteGuard missing")
	end
else
	bad("ServerScriptService.Server missing — Rojo sync?")
end

-- 5) Client LocalPlayer hooks (Play mode)
local lp = Players.LocalPlayer
if lp then
	ok("LocalPlayer = " .. lp.Name .. " (" .. tostring(lp.UserId) .. ")")
	-- GetPlayerState (safe read)
	if remotes and remotes:FindFirstChild("GetPlayerState") then
		local fn = remotes.GetPlayerState
		local invokeOk, stateOrErr = pcall(function()
			return fn:InvokeServer()
		end)
		if invokeOk and typeof(stateOrErr) == "table" then
			ok("GetPlayerState returned profile snapshot (Cash=" .. tostring(stateOrErr.Cash) .. ")")
		elseif invokeOk and stateOrErr == nil then
			info("GetPlayerState returned nil (profile still loading or rate-limited)")
		else
			bad("GetPlayerState invoke failed: " .. tostring(stateOrErr))
		end
	end

	-- Admin membership (read-only). NEVER fire givecash / currency grants from smoke.
	local isAdmin = false
	if Shared and Shared:FindFirstChild("Configs") then
		local adminMod = Shared.Configs:FindFirstChild("AdminConfig")
		if adminMod then
			local aOk, AdminConfig = pcall(require, adminMod)
			if aOk and typeof(AdminConfig) == "table" and typeof(AdminConfig.UserIds) == "table" then
				for _, id in ipairs(AdminConfig.UserIds) do
					if id == lp.UserId then
						isAdmin = true
						break
					end
				end
			end
		end
	end
	if isAdmin then
		info("LocalPlayer IS admin (AdminConfig) — RequestAdminCommand available; smoke will NOT grant currency")
		-- Safe no-op probe: unknown command should be ignored by AdminService (no side effects)
		if remotes and remotes:FindFirstChild("RequestAdminCommand") then
			local fireOk, fireErr = pcall(function()
				remotes.RequestAdminCommand:FireServer("__smoke_ping__", nil, nil)
			end)
			if fireOk then
				ok("Fired safe admin probe __smoke_ping__ (no grant)")
			else
				bad("Admin probe fire failed: " .. tostring(fireErr))
			end
		end
	else
		info("LocalPlayer is not in AdminConfig.UserIds — skipping admin probe")
	end
else
	info("No LocalPlayer (Edit mode?) — remotes/config checks still valid; re-run in Play Solo for GetPlayerState")
end

-- 6) Walk-over buy / world tags (StudioSetup) — always run
do
	local CS = game:GetService("CollectionService")
	local slots = CS:GetTagged("WE_UpgradeSlot")
	if #slots == 0 then
		bad("No WE_UpgradeSlot tags — run tools/StudioSetup.luau in Command Bar")
	else
		ok("WE_UpgradeSlot count=" .. tostring(#slots))
		local withBillboard, withStruct, withPlot, withBuyPrompt, withKitBody = 0, 0, 0, 0, 0
		for _, inst in ipairs(slots) do
			if inst:IsA("BasePart") then
				if inst:FindFirstChild("WE_PriceBillboard") or inst:FindFirstChild("Label") then
					withBillboard += 1
				end
				if typeof(inst:GetAttribute("StructureId")) == "string" then
					withStruct += 1
				end
				if typeof(inst:GetAttribute("PlotId")) == "number" then
					withPlot += 1
				end
				local prompt = inst:FindFirstChild("WE_WorldPrompt")
				if prompt and prompt:IsA("ProximityPrompt") then
					-- Buy prompts must NOT live on upgrade pads (walk-over only)
					withBuyPrompt += 1
				end
				for _, ch in ipairs(inst:GetChildren()) do
					if ch:IsA("BasePart") and ch:GetAttribute("WE_KitRole") == "Body" then
						withKitBody += 1
						break
					end
				end
			end
		end
		ok("Upgrade slots with StructureId=" .. tostring(withStruct))
		ok("Upgrade slots with PlotId=" .. tostring(withPlot))
		ok("Upgrade slots with price billboard=" .. tostring(withBillboard))
		ok("Upgrade slots with kit Body part=" .. tostring(withKitBody))
		if withBuyPrompt > 0 then
			bad("Upgrade pads still have WE_WorldPrompt buy prompts count=" .. tostring(withBuyPrompt) .. " (walk-over should remove them)")
		else
			ok("Walk-over buy: no buy ProximityPrompt on upgrade slots")
		end
	end
	ok("WE_VehicleSpawn count=" .. tostring(#CS:GetTagged("WE_VehicleSpawn")))
	ok("WE_BasePlot count=" .. tostring(#CS:GetTagged("WE_BasePlot")))
	-- Client controller present after Rojo sync
	local sps = game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts")
	local client = sps and sps:FindFirstChild("Client")
	local controllers = client and client:FindFirstChild("Controllers")
	local wpc = controllers and controllers:FindFirstChild("WorldPromptController")
	if wpc then
		ok("WorldPromptController ModuleScript present")
	else
		info("WorldPromptController not under StarterPlayer yet (Rojo / Play sync)")
	end
end

-- 7) Checklist summary for humans
print("---------- PLAYTEST CHECKLIST ----------")
print("1. Rojo sync + tools/StudioSetup.luau (Edit) once")
print("2. Play Solo — HUD Cash/Level; plot assigned")
print("3. WALK onto Command Center pad to buy; or B / BASE UPGRADES menu")
print("4. Combat LMB + R; G spawn Jeep (seat/drive); heli/jet placeholder air OK")
print("5. M missions; P shop (Id 0 warns only); K BP/clan; A army")
print("6. O settings — music/SFX mute; G garage empty-state; mobile BASE button visible")
print("7. Persistence: leave/rejoin with API Services on")
print("8. Admin only if your UserId is in AdminConfig")
print("========================================")
print(string.format("[Smoke] DONE  pass=%d  fail=%d  info=%d", PASS, FAIL, INFO))
if FAIL > 0 then
	warn("[Smoke] FAILURES detected — fix before shipping playtest")
else
	print("[Smoke] All automated checks passed")
end
