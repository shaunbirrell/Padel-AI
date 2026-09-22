--!strict
--[[
	v60: Run BEFORE Bootstrap finishes requiring services.
	1) Create ALL remotes under WE_Remotes (server-only — no Rojo empty folder).
	2) Seed leaderstats + WE_Cash IMMEDIATELY on PlayerAdded (before DataStore).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Destroy legacy empty Rojo Remotes folder so clients never WaitForChild on it
do
	local legacy = ReplicatedStorage:FindFirstChild("Remotes")
	if legacy and legacy:IsA("Folder") and #legacy:GetChildren() == 0 then
		legacy:Destroy()
	end
end

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local EconomyConfig = require(Shared.Configs.EconomyConfig)
local AdminConfig = require(Shared.Configs.AdminConfig)

local Modules = script.Parent:WaitForChild("Modules")
local RemoteSetup = require(Modules:WaitForChild("RemoteSetup"))
RemoteSetup.Init()

local ADMIN_PLAYTEST_USER_ID = 470626172

local function seedCashAmount(userId: number): number
	local startCash = math.floor(tonumber(EconomyConfig.StartingCash) or 10000)
	if userId == ADMIN_PLAYTEST_USER_ID then
		local floor = math.floor(tonumber(AdminConfig.AdminPlaytestCash) or 50_000_000)
		return math.max(startCash, floor)
	end
	return startCash
end

local function ensureLeaderstats(player: Player, cash: number, gold: number)
	local folder = player:FindFirstChild("leaderstats")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "leaderstats"
		folder.Parent = player
	end
	local cashVal = folder:FindFirstChild("Cash")
	if not cashVal then
		cashVal = Instance.new("IntValue")
		cashVal.Name = "Cash"
		cashVal.Parent = folder
	end
	if cashVal:IsA("IntValue") or cashVal:IsA("NumberValue") then
		(cashVal :: any).Value = cash
	end
	local goldVal = folder:FindFirstChild("Gold")
	if not goldVal then
		goldVal = Instance.new("IntValue")
		goldVal.Name = "Gold"
		goldVal.Parent = folder
	end
	if goldVal:IsA("IntValue") or goldVal:IsA("NumberValue") then
		(goldVal :: any).Value = gold
	end
end

local function seedPlayer(player: Player)
	local cash = seedCashAmount(player.UserId)
	local gold = math.floor(tonumber(EconomyConfig.StartingGold) or 0)
	pcall(function()
		player:SetAttribute("WE_Build", 64)
		player:SetAttribute("WE_Cash", cash)
		player:SetAttribute("WE_Gold", gold)
		player:SetAttribute("WE_PendingCash", 0)
	end)
	pcall(ensureLeaderstats, player, cash, gold)
	-- Fire EconomyUpdate if client already listening
	pcall(function()
		local folder = ReplicatedStorage:FindFirstChild(Constants.RemotesFolderName)
		local ev = folder and folder:FindFirstChild(Constants.RemoteNames.EconomyUpdate)
		if ev and ev:IsA("RemoteEvent") then
			(ev :: RemoteEvent):FireClient(player, {
				Cash = cash,
				Gold = gold,
				PendingCash = 0,
			})
		end
	end)
end

Players.PlayerAdded:Connect(seedPlayer)
for _, plr in ipairs(Players:GetPlayers()) do
	task.spawn(seedPlayer, plr)
end

print("[WAR EMPIRE] EarlyRemotes v63: WE_Remotes + leaderstats seed ready")
