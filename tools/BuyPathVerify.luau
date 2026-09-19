--!strict
--[[
	Command-bar / CI-style static checks for BUY wiring.
	Paste in Studio Play Solo OR run mentally against repo — does not grant currency.
	Prints PASS/FAIL for remote + controller presence.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local function ok(msg: string)
	print("[BuyPathVerify] PASS", msg)
end
local function bad(msg: string)
	warn("[BuyPathVerify] FAIL", msg)
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
}
for _, name in ipairs(need) do
	local ev = Remotes.GetEvent(name)
	if ev then
		ok("Remote " .. name)
	else
		bad("Remote missing " .. name)
	end
end

local pg = Players.LocalPlayer and Players.LocalPlayer:FindFirstChild("PlayerGui")
if pg then
	for _, guiName in ipairs({ "WE_PadBuyGui", "WarEmpireGarage", "WarEmpireCombatHUD", "WarEmpireTerritory" }) do
		-- Guis may appear after Init — soft check
		local g = pg:FindFirstChild(guiName)
		if g then
			ok("Gui present " .. guiName)
		else
			print("[BuyPathVerify] WAIT Gui not yet: " .. guiName .. " (ok if early)")
		end
	end
end

print("[BuyPathVerify] Done — stand on YOUR pad and tap BUY; Output should show [WorldPrompt] BUY + [BaseService] Remote BUY result Ok=true")
