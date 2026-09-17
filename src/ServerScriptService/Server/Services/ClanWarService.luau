--!strict
--[[
	Clan war / global war scaffolding — war state, scores, reward hooks.
	Declare war is server-validated; scores only mutate on server events.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local ClanWarConfig = require(Shared.Configs.ClanWarConfig)

local ClanWarService = {}

export type WarRecord = {
	Id: string,
	AttackerClanId: string,
	DefenderClanId: string,
	StartUnix: number,
	EndUnix: number,
	AttackerScore: number,
	DefenderScore: number,
	Active: boolean,
	Settled: boolean,
}

local DataService: any = nil
local EconomyService: any = nil
local NotificationService: any = nil
local RateLimitService: any = nil
local RemoteSetup: any = nil
local AnalyticsService: any = nil
local ClanService: any = nil

local wars: { [string]: WarRecord } = {}
local clanActiveWar: { [string]: string } = {}
local globalScores: { [string]: number } = {}
local nextWarSerial = 1

local function memberCount(clan: any): number
	local n = 0
	if typeof(clan) == "table" and typeof(clan.Members) == "table" then
		for _ in pairs(clan.Members) do
			n += 1
		end
	end
	return n
end

local function leaderUserId(clan: any): number?
	if typeof(clan) ~= "table" then
		return nil
	end
	return clan.LeaderUserId or clan.OwnerUserId
end

local function pushWar(player: Player, war: WarRecord?)
	local remote = RemoteSetup.Get(Constants.RemoteNames.ClanWarStateUpdate) :: RemoteEvent
	local clanId = if ClanService and ClanService.GetClanId then ClanService.GetClanId(player) else nil
	remote:FireClient(player, {
		War = war,
		MyClanId = clanId,
		GlobalScores = globalScores,
		GlobalWarEnabled = ClanWarConfig.GlobalWarEnabled == true,
		GlobalWarSeasonKey = ClanWarConfig.GlobalWarSeasonKey,
	})
end

local function broadcastWar(war: WarRecord)
	for _, player in ipairs(Players:GetPlayers()) do
		local cid = if ClanService and ClanService.GetClanId then ClanService.GetClanId(player) else nil
		if cid == war.AttackerClanId or cid == war.DefenderClanId then
			pushWar(player, war)
		end
	end
end

local function settleWar(war: WarRecord)
	if war.Settled then
		return
	end
	war.Settled = true
	war.Active = false
	clanActiveWar[war.AttackerClanId] = nil
	clanActiveWar[war.DefenderClanId] = nil

	local winner: string? = nil
	if war.AttackerScore > war.DefenderScore then
		winner = war.AttackerClanId
	elseif war.DefenderScore > war.AttackerScore then
		winner = war.DefenderClanId
	end

	local winCash = ClanWarConfig.WinningClanCashReward or 0
	local winGold = ClanWarConfig.WinningClanGoldReward or 0
	local partCash = ClanWarConfig.ParticipationCashReward or 0

	for _, player in ipairs(Players:GetPlayers()) do
		local cid = if ClanService and ClanService.GetClanId then ClanService.GetClanId(player) else nil
		if cid == winner then
			if winCash > 0 then
				EconomyService.AddCash(player, winCash, "clan_war_win")
			end
			if winGold > 0 then
				EconomyService.AddGold(player, winGold, "clan_war_win")
			end
			if NotificationService then
				NotificationService.Notify(player, "Clan war victory rewards granted!", "Reward")
			end
		elseif cid == war.AttackerClanId or cid == war.DefenderClanId then
			if partCash > 0 then
				EconomyService.AddCash(player, partCash, "clan_war_participate")
			end
			if NotificationService then
				NotificationService.Notify(player, "Clan war ended — participation reward.", "Info")
			end
		end
		pushWar(player, war)
	end

	if AnalyticsService and AnalyticsService.Log then
		AnalyticsService.Log("CLAN_WAR_SETTLE", 0, {
			warId = war.Id,
			winner = winner,
			attackerScore = war.AttackerScore,
			defenderScore = war.DefenderScore,
		})
	end
end

function ClanWarService.AddScore(clanId: string, points: number, _reason: string?)
	if typeof(clanId) ~= "string" or clanId == "" then
		return
	end
	points = math.floor(tonumber(points) or 0)
	if points == 0 then
		return
	end
	if ClanWarConfig.GlobalWarEnabled then
		globalScores[clanId] = (globalScores[clanId] or 0) + points
	end
	local warId = clanActiveWar[clanId]
	if warId then
		local war = wars[warId]
		if war and war.Active then
			if clanId == war.AttackerClanId then
				war.AttackerScore += points
			elseif clanId == war.DefenderClanId then
				war.DefenderScore += points
			end
			if os.time() >= war.EndUnix then
				settleWar(war)
			else
				broadcastWar(war)
			end
		end
	end
end

function ClanWarService.OnTerritoryCaptured(player: Player)
	local clanId = if ClanService and ClanService.GetClanId then ClanService.GetClanId(player) else nil
	if clanId then
		ClanWarService.AddScore(clanId, ClanWarConfig.ScorePerTerritoryCapture or 10, "territory")
	end
end

function ClanWarService.OnEnemyKill(player: Player)
	local clanId = if ClanService and ClanService.GetClanId then ClanService.GetClanId(player) else nil
	if clanId then
		ClanWarService.AddScore(clanId, ClanWarConfig.ScorePerEnemyKill or 1, "kill")
	end
end

function ClanWarService.DeclareWar(player: Player, defenderClanId: any): (boolean, string?)
	if typeof(defenderClanId) ~= "string" or defenderClanId == "" then
		return false, "InvalidDefender"
	end
	if not ClanService then
		return false, "ClanServiceMissing"
	end
	local attackerClanId = ClanService.GetClanId(player)
	if not attackerClanId then
		return false, "NotInClan"
	end
	if attackerClanId == defenderClanId then
		return false, "CannotWarSelf"
	end
	local attackerClan = ClanService.GetClan(attackerClanId)
	local defenderClan = ClanService.GetClan(defenderClanId)
	if not attackerClan or not defenderClan then
		return false, "ClanNotFound"
	end
	if leaderUserId(attackerClan) ~= player.UserId then
		return false, "LeaderOnly"
	end
	local minMembers = ClanWarConfig.MinClanMembersToDeclare or 2
	if memberCount(attackerClan) < minMembers or memberCount(defenderClan) < minMembers then
		return false, "NotEnoughMembers"
	end
	if clanActiveWar[attackerClanId] or clanActiveWar[defenderClanId] then
		return false, "AlreadyAtWar"
	end

	local warId = string.format("war_%d_%d", os.time(), nextWarSerial)
	nextWarSerial += 1
	local now = os.time()
	local war: WarRecord = {
		Id = warId,
		AttackerClanId = attackerClanId,
		DefenderClanId = defenderClanId,
		StartUnix = now,
		EndUnix = now + (ClanWarConfig.WarDurationSeconds or 3600),
		AttackerScore = 0,
		DefenderScore = 0,
		Active = true,
		Settled = false,
	}
	wars[warId] = war
	clanActiveWar[attackerClanId] = warId
	clanActiveWar[defenderClanId] = warId
	broadcastWar(war)

	if NotificationService then
		NotificationService.Notify(player, "Clan war declared!", "Success")
	end
	if AnalyticsService and AnalyticsService.Log then
		AnalyticsService.Log("CLAN_WAR_DECLARE", player.UserId, {
			warId = warId,
			attacker = attackerClanId,
			defender = defenderClanId,
		})
	end
	return true, nil
end

function ClanWarService.Push(player: Player)
	local clanId = if ClanService and ClanService.GetClanId then ClanService.GetClanId(player) else nil
	local war: WarRecord? = nil
	if clanId and clanActiveWar[clanId] then
		war = wars[clanActiveWar[clanId]]
	end
	pushWar(player, war)
end

function ClanWarService.Init(deps: { [string]: any })
	DataService = deps.DataService
	EconomyService = deps.EconomyService
	NotificationService = deps.NotificationService
	RateLimitService = deps.RateLimitService
	RemoteSetup = deps.RemoteSetup
	AnalyticsService = deps.AnalyticsService
	ClanService = deps.ClanService

	local declareRemote = RemoteSetup.Get(Constants.RemoteNames.RequestDeclareClanWar) :: RemoteEvent
	declareRemote.OnServerEvent:Connect(function(player: Player, defenderClanId: any)
		if not RateLimitService.Allow(player, "clan_war_declare", 1, 1) then
			return
		end
		local ok, err = ClanWarService.DeclareWar(player, defenderClanId)
		if not ok and NotificationService then
			NotificationService.Notify(player, "Cannot declare war: " .. tostring(err), "Warn")
		end
	end)

	DataService.OnProfileLoaded(function(player: Player, _profile: any)
		ClanWarService.Push(player)
	end)

	task.spawn(function()
		while true do
			task.wait(15)
			local now = os.time()
			for _, war in pairs(wars) do
				if war.Active and not war.Settled and now >= war.EndUnix then
					settleWar(war)
				end
			end
		end
	end)
end

return ClanWarService
