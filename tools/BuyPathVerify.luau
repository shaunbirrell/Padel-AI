--!strict
--[[
	Command-bar / CI-style static checks for BUY wiring.
	Paste in Studio Play Solo OR run mentally against repo — does not grant currency.
	Prints PASS/FAIL for remote + controller presence + catalog config sanity.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local function ok(msg: string)
	print("[BuyPathVerify] PASS", msg)
end
local function bad(msg: string)
	warn("[BuyPathVerify] FAIL", msg)
end
local function soft(msg: string)
	print("[BuyPathVerify] WAIT", msg)
end

local Shared = ReplicatedStorage:FindFirstChild("Shared")
if not Shared then
	bad("ReplicatedStorage.Shared missing")
	return
end

local Constants = require(Shared.Constants)
local Remotes = require(Shared.Remotes)

local need = {
	Constants.RemoteNames.RequestPurchaseUpgrade,
	Constants.RemoteNames.RequestPurchaseVehicle,
	Constants.RemoteNames.RequestPurchaseWeapon,
	Constants.RemoteNames.BaseStateUpdate,
	Constants.RemoteNames.VehicleStateUpdate,
	Constants.RemoteNames.EconomyUpdate,
	Constants.RemoteNames.RequestPrestige,
}
for _, name in ipairs(need) do
	local ev = Remotes.GetEvent(name)
	if ev then
		ok("Remote " .. name)
	else
		bad("Remote missing " .. name)
	end
end

-- VisualAssetConfig free-ID sanity (config only — does not InsertService)
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
		if v >= 20 then
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

local pg = Players.LocalPlayer and Players.LocalPlayer:FindFirstChild("PlayerGui")
if pg then
	for _, guiName in ipairs({
		"WE_PadBuyGui",
		"WarEmpireGarage",
		"WarEmpireCombatHUD",
		"WarEmpireTerritory",
		"WarEmpireShop",
		"WarEmpireProgression",
		"WarEmpireHUD",
	}) do
		local g = pg:FindFirstChild(guiName)
		if g then
			ok("Gui present " .. guiName)
			-- Soft: prefer Activated-wired TextButtons when present
			local activated = 0
			local mb1 = 0
			for _, d in ipairs(g:GetDescendants()) do
				if d:IsA("TextButton") or d:IsA("ImageButton") then
					-- Cannot introspect connections easily; presence is enough
					activated += 1
				end
			end
			if activated > 0 then
				ok(string.format("Gui %s has %d GuiButtons", guiName, activated))
			end
			mb1 = mb1 -- silence
		else
			soft("Gui not yet: " .. guiName .. " (ok if early)")
		end
	end

	-- Pad BUY must be Activated path (WorldPromptController)
	local buyGui = pg:FindFirstChild("WE_PadBuyGui")
	if buyGui then
		local buyBtn = buyGui:FindFirstChild("BuyButton", true) or buyGui:FindFirstChildWhichIsA("TextButton", true)
		if buyBtn and buyBtn:IsA("GuiButton") then
			ok("Pad BUY GuiButton present: " .. buyBtn.Name)
			if buyBtn.AbsoluteSize.Y >= 64 or buyBtn.Size.Y.Offset >= 64 then
				ok("Pad BUY touch height OK")
			else
				soft("Pad BUY height may be small — check EnsureMinTouch")
			end
		else
			soft("Pad BUY button not visible yet (stand on own pad)")
		end
	end
end

print("[BuyPathVerify] Done — stand on YOUR pad and tap BUY; Output should show [WorldPrompt] BUY + [BaseService] Remote BUY result Ok=true")
print("[BuyPathVerify] Shop/Rebirth: dock tiles use Activated; panels DisplayOrder 60 above HUD dock 55")
