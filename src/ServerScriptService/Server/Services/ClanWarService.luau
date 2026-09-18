--!strict
--[[
	Clan war — declare, score, settle with rewards + scoreboard.
	Declare is server-validated; scores only mutate on server events.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local ClanWarConfig = require(Shared.Configs.ClanWarConfig)
local AnalyticsConfig = require(Shared.Configs.AnalyticsConfig)

local RemoteGuard = require(script.Parent.Parent.Modules.RemoteGuard)

local ClanWarService = {}

export type WarRecord = {
	Id: string,
	AttackerClanId: string,
	DefenderClanId: string,
	AttackerName: string?,
	DefenderName: string?,
	StartUnix: number,
	EndUnix: number,
	AttackerScore: number,
	DefenderScore: number,
	Active: boolean,
	Settled: boolean,
	WinnerClanId: string?,
}

local DataService: any = nil
local EconomyService: any = nil
local NotificationService: any = nil
local RateLimitService: any = nil
local RemoteSetup: any = nil
local AnalyticsService: any = nil
local ClanService: any = nil
local AntiExploitService: any = nil

local wars: { [string]: WarRecord } = {}
local clanActiveWar: { [string]: string } = {}
local globalScores: { [string]: number } = {}
local declareCooldownUntil: { [string]: number } = {} -- clanId -> unix
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

local function clanDisplayName(clanId: string): string
	if ClanService and ClanService.GetClan then
		local clan = ClanService.GetClan(clanId)
		if clan and typeof(clan.Name) == "string" then
			local tag = if typeof(clan.Tag) == "string" then clan.Tag else "?"
			return string.format("[%s] %s", tag, clan.Name)
		end
	end
	return clanId
end

local function topScoreboard(): { { ClanId: string, Score: number, Name: string } }
	local list: { { ClanId: string, Score: number, Name: string } } = {}
	for clanId, score in pairs(globalScores) do
		table.insert(list, {
			ClanId = clanId,
			Score = score,
			Name = clanDisplayName(clanId),
		})
	end
	table.sort(list, function(a, b)
		if a.Score == b.Score then
			return a.ClanId < b.ClanId
		end
		return a.Score > b.Score
	end)
	local topN = ClanWarConfig.ScoreboardTopN or 8
	local out = {}
	for i = 1, math.min(topN, #list) do
		table.insert(out, list[i])
	end
	return out
end

local function notifyClan(clanId: string, message: string, kind: string)
	if not NotificationService then
		return
	end
	for _, player in ipairs(Players:GetPlayers()) do
		local cid = if ClanService and ClanService.GetClanId then ClanService.GetClanId(player) else nil
		if cid == clanId then
			NotificationService.Notify(player, message, kind)
		end
	end
end

local function pushWar(player: Player, war: WarRecord?)
	local remote = RemoteSetup.Get(Constants.RemoteNames.ClanWarStateUpdate) :: RemoteEvent
	local clanId = if ClanService and ClanService.GetClanId then ClanService.GetClanId(player) else nil
	local cooldownLeft = 0
	if clanId and declareCooldownUntil[clanId] then
		cooldownLeft = math.max(0, declareCooldownUntil[clanId] - os.time())
	end
	remote:FireClient(player, {
		War = war,
		MyClanId = clanId,
		GlobalScores = globalScores,
		Scoreboard = topScoreboard(),
		GlobalWarEnabled = ClanWarConfig.GlobalWarEnabled == true,
		GlobalWarSeasonKey = ClanWarConfig.GlobalWarSeasonKey,
		DeclareCooldownLeft = cooldownLeft,
		MinMembers = ClanWarConfig.MinClanMembersToDeclare or 2,
		WarDurationSeconds = ClanWarConfig.WarDurationSeconds or 3600,
		Rewards = {
			WinCash = ClanWarConfig.WinningClanCashReward or 0,
			WinGold = ClanWarConfig.WinningClanGoldReward or 0,
			PartCash = ClanWarConfig.ParticipationCashReward or 0,
			PartGold = ClanWarConfig.ParticipationGoldReward or 0,
			ScoreBonusCashPerPoint = ClanWarConfig.ScoreBonusCashPerPoint or 0,
		},
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

local function broadcastAll()
	for _, player in ipairs(Players:GetPlayers()) do
		local clanId = if ClanService and ClanService.GetClanId then ClanService.GetClanId(player) else nil
		local war: WarRecord? = nil
		if clanId and clanActiveWar[clanId] then
			war = wars[clanActiveWar[clanId]]
		end
		pushWar(player, war)
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

	local cooldown = ClanWarConfig.DeclareCooldownSeconds or 300
	local untilUnix = os.time() + cooldown
	declareCooldownUntil[war.AttackerClanId] = untilUnix
	declareCooldownUntil[war.DefenderClanId] = untilUnix

	local winner: string? = nil
	if war.AttackerScore > war.DefenderScore then
		winner = war.AttackerClanId
	elseif war.DefenderScore > war.AttackerScore then
		winner = war.DefenderClanId
	end
	war.WinnerClanId = winner

	local winCash = ClanWarConfig.WinningClanCashReward or 0
	local winGold = ClanWarConfig.WinningClanGoldReward or 0
	local partCash = ClanWarConfig.ParticipationCashReward or 0
	local partGold = ClanWarConfig.ParticipationGoldReward or 0
	local scoreBonus = ClanWarConfig.ScoreBonusCashPerPoint or 0

	local attackerName = war.AttackerName or clanDisplayName(war.AttackerClanId)
	local defenderName = war.DefenderName or clanDisplayName(war.DefenderClanId)
	local scoreLine = string.format("%s %d – %d %s", attackerName, war.AttackerScore, war.DefenderScore, defenderName)

	for _, player in ipairs(Players:GetPlayers()) do
		local cid = if ClanService and ClanService.GetClanId then ClanService.GetClanId(player) else nil
		if cid == winner then
			local bonus = 0
			if scoreBonus > 0 then
				local myScore = if cid == war.AttackerClanId then war.AttackerScore else war.DefenderScore
				bonus = math.floor(myScore * scoreBonus)
			end
			if winCash + bonus > 0 then
				EconomyService.AddCash(player, winCash + bonus, "clan_war_win")
			end
			if winGold > 0 then
				EconomyService.AddGold(player, winGold, "clan_war_win")
			end
			if NotificationService then
				NotificationService.Notify(
					player,
					string.format("Clan war VICTORY! %s  (+$%d%s)", scoreLine, winCash + bonus, if winGold > 0 then string.format(" +%dG", winGold) else ""),
					"Reward"
				)
			end
		elseif cid == war.AttackerClanId or cid == war.DefenderClanId then
			if partCash > 0 then
				EconomyService.AddCash(player, partCash, "clan_war_participate")
			end
			if partGold > 0 then
				EconomyService.AddGold(player, partGold, "clan_war_participate")
			end
			local resultWord = if winner then "defeat" else "draw"
			if NotificationService then
				NotificationService.Notify(
					player,
					string.format("Clan war %s — %s  (+$%d participation)", resultWord, scoreLine, partCash),
					"Info"
				)
			end
		end
		pushWar(player, war)
	end

	local eventName = if AnalyticsConfig.Events.CLAN_WAR_SETTLE then AnalyticsConfig.Events.CLAN_WAR_SETTLE else "CLAN_WAR_SETTLE"
	if AnalyticsService and AnalyticsService.Log then
		AnalyticsService.Log(eventName, 0, {
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
	if not RemoteGuard.IsIdString(defenderClanId) then
		return false, "InvalidDefender"
	end
	if not RemoteGuard.RequireProfile(DataService, player) then
		return false, "NoProfile"
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
	local now = os.time()
	if declareCooldownUntil[attackerClanId] and now < declareCooldownUntil[attackerClanId] then
		return false, "DeclareCooldown"
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

	local warId = string.format("war_%d_%d", now, nextWarSerial)
	nextWarSerial += 1
	local war: WarRecord = {
		Id = warId,
		AttackerClanId = attackerClanId,
		DefenderClanId = defenderClanId,
		AttackerName = clanDisplayName(attackerClanId),
		DefenderName = clanDisplayName(defenderClanId),
		StartUnix = now,
		EndUnix = now + (ClanWarConfig.WarDurationSeconds or 3600),
		AttackerScore = 0,
		DefenderScore = 0,
		Active = true,
		Settled = false,
		WinnerClanId = nil,
	}
	wars[warId] = war
	clanActiveWar[attackerClanId] = warId
	clanActiveWar[defenderClanId] = warId
	broadcastWar(war)
	-- Also refresh scoreboard for everyone
	broadcastAll()

	local declareMsg = string.format(
		"WAR DECLARED: %s vs %s (%dm)",
		war.AttackerName or attackerClanId,
		war.DefenderName or defenderClanId,
		math.floor((ClanWarConfig.WarDurationSeconds or 3600) / 60)
	)
	notifyClan(attackerClanId, declareMsg, "Success")
	notifyClan(defenderClanId, declareMsg .. " — DEFEND!", "Warn")

	local eventName = if AnalyticsConfig.Events.CLAN_WAR_DECLARE then AnalyticsConfig.Events.CLAN_WAR_DECLARE else "CLAN_WAR_DECLARE"
	if AnalyticsService and AnalyticsService.Log then
		AnalyticsService.Log(eventName, player.UserId, {
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
	AntiExploitService = deps.AntiExploitService

	local declareRemote = RemoteSetup.Get(Constants.RemoteNames.RequestDeclareClanWar) :: RemoteEvent
	declareRemote.OnServerEvent:Connect(function(player: Player, defenderClanId: any)
		if not RateLimitService.Allow(player, "clan_war_declare", 1, 1) then
			if AntiExploitService and AntiExploitService.Strike then
				AntiExploitService.Strike(player, "clan_war_declare_rate")
			end
			return
		end
		local ok, err = ClanWarService.DeclareWar(player, defenderClanId)
		if not ok and NotificationService then
			local msg = "Cannot declare war: " .. tostring(err)
			if err == "DeclareCooldown" then
				local cid = if ClanService then ClanService.GetClanId(player) else nil
				local left = if cid and declareCooldownUntil[cid] then math.max(0, declareCooldownUntil[cid] - os.time()) else 0
				msg = string.format("War declare cooldown: %ds remaining", left)
			elseif err == "NotEnoughMembers" then
				msg = string.format("Both clans need ≥%d members to war", ClanWarConfig.MinClanMembersToDeclare or 2)
			elseif err == "LeaderOnly" then
				msg = "Only the clan leader can declare war"
			end
			NotificationService.Notify(player, msg, "Warn")
		end
	end)

	DataService.OnProfileLoaded(function(player: Player, _profile: any)
		ClanWarService.Push(player)
	end)

	task.spawn(function()
		while true do
			task.wait(15)
			if next(wars) ~= nil then
				local now = os.time()
				for _, war in pairs(wars) do
					if war.Active and not war.Settled and now >= war.EndUnix then
						settleWar(war)
					end
				end
			end
		end
	end)
end

return ClanWarService
