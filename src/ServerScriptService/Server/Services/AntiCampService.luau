--!strict
--[[ claude-bud JOB 63: anti-spawn-camping (Shared/Configs/RaidConfig.AntiCamp), keyed by the BASE OWNER (owner-first).

	  * Defender shield: a player respawning at his own base gets DefenderShieldSeconds of the ONE spawn protection
	    (CombatService state.InvulnerableUntil, which pvpBlock / hurtPlayer apply to every player gun, army unit, turret,
	    guard and vehicle hit), shown by the existing spawn bubble (WE_ShieldUntil); his first shot ends it.
	    (CombatService.onCharacterAdded / RequestFire call DefenderShieldSeconds / OnFire.)
	  * Raider limit: inside another player's base for RaiderLimitSeconds, or when his raid takes the loot, or after
	    RepeatKills kills of the same defender inside RepeatWindowSeconds, he goes back to his own base through the
	    normal respawn (Player:LoadCharacter: CombatService spawns him at his base), with a short notice.
	  * Same-base cooldown: then for SameBaseCooldownSeconds he cannot stay in that base (sent back again) nor damage it
	    or its owner (CombatService pvpBlock reason "camp_cooldown"; GateDefenseService.applyDamageFrom), shown on the
	    TARGETS card (RivalService rows: Wait) and at the base edge (one throttled toast).
	One 1 Hz loop; server-side only; no teleport / PivotTo. ]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 60)
local RaidConfig = require(Shared.Configs.RaidConfig)
local RetentionConfig = require(Shared.Configs.RetentionConfig)
local BaseConfig = require(Shared.Configs.BaseConfig)
local PlotFrame = require(Shared.Util.PlotFrame)

local AntiCampService = {}

local deps: { [string]: any } = {}
local A: any = (RaidConfig :: any).AntiCamp
local entered: { [number]: { Plot: number, At: number }? } = {}
local cooldown: { [number]: { [number]: number } } = {} -- raider uid -> plotId -> clock until
local kills: { [string]: { number } } = {} -- "killer:victim" -> kill clocks
local edgeToastAt: { [number]: number } = {}

AntiCampService._clock = os.clock

function AntiCampService.Live(ownerUserId: number?): boolean
	return typeof(A) == "table" and ownerUserId ~= nil and RetentionConfig.Live(A, ownerUserId)
end

local function ownerOf(plotId: number): number?
	local bs = deps.BaseService
	return if bs and bs.GetOwnerUserId then bs.GetOwnerUserId(plotId) else nil
end

-- the plot a world position is in (pure on PlotFrame; nil = none), and how far outside its edge (studs)
function AntiCampService.PlotAt(pos: Vector3, margin: number?): number?
	local half = BaseConfig.PlotSize.X / 2 + (margin or 0)
	for plotId = 1, BaseConfig.MaxPlots do
		local p = PlotFrame.PlotPosition(plotId)
		if p then
			local l = PlotFrame.PlotCFrame(p):PointToObjectSpace(pos)
			if math.abs(l.X) <= half and math.abs(l.Z) <= half then
				return plotId
			end
		end
	end
	return nil
end

function AntiCampService.CooldownLeft(uid: number, plotId: number): number
	local t = cooldown[uid] and cooldown[uid][plotId]
	return if t then math.max(0, math.ceil(t - AntiCampService._clock())) else 0
end

-- may attacker damage victim? false while the attacker's cooldown covers the victim's base
function AntiCampService.BlocksHurt(attacker: Player, victim: Player): boolean
	local bs = deps.BaseService
	local pid = if bs and bs.GetOwnedPlotId then bs.GetOwnedPlotId(victim) else nil
	return typeof(pid) == "number" and AntiCampService.Live(victim.UserId) and AntiCampService.CooldownLeft(attacker.UserId, pid) > 0
end

function AntiCampService.BlocksBaseDamage(attacker: Player?, plotId: number?): boolean
	if attacker == nil or plotId == nil then
		return false
	end
	return AntiCampService.Live(ownerOf(plotId)) and AntiCampService.CooldownLeft(attacker.UserId, plotId) > 0
end

-- the defender shield for a respawn at his own base (0 = the normal spawn shield)
function AntiCampService.DefenderShieldSeconds(player: Player): number
	if not AntiCampService.Live(player.UserId) then
		return 0
	end
	return tonumber(A.DefenderShieldSeconds) or 0
end

local function notify(player: Player, text: string)
	local ns = deps.NotificationService
	if ns and ns.Notify then
		pcall(ns.Notify, player, text, "Warn", 4)
	end
end

local function clockText(sec: number): string
	return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end

-- back to his own base through the normal respawn, then the same-base cooldown
function AntiCampService.SendBack(player: Player, plotId: number, why: string)
	cooldown[player.UserId] = cooldown[player.UserId] or {}
	cooldown[player.UserId][plotId] = AntiCampService._clock() + A.SameBaseCooldownSeconds
	entered[player.UserId] = nil
	notify(player, A.Text[why] or A.Text.time)
	print(string.format("[AntiCamp] uid=%d plot=%d back to base (%s), cooldown %d s", player.UserId, plotId, why, A.SameBaseCooldownSeconds))
	if player.Parent then
		pcall(function()
			local pa: any = player
			pa:LoadCharacter() -- the same respawn call CombatService uses after a death
		end)
	end
end

-- the raid took the loot: he goes home (a short grace to see the cash land)
function AntiCampService.OnRaidDone(thief: Player, plotId: number?)
	if plotId == nil or not AntiCampService.Live(ownerOf(plotId)) then
		return
	end
	task.delay(A.AfterLootSeconds, function()
		local e = entered[thief.UserId]
		if e and e.Plot == plotId and thief.Parent then
			AntiCampService.SendBack(thief, plotId, "loot")
		end
	end)
end

-- a kill: the same defender killed RepeatKills times in RepeatWindowSeconds by a raider inside his base -> home
function AntiCampService.NoteKill(killer: Player, victim: Player)
	local e = entered[killer.UserId]
	local bs = deps.BaseService
	local vPid = if bs and bs.GetOwnedPlotId then bs.GetOwnedPlotId(victim) else nil
	if e == nil or e.Plot ~= vPid or not AntiCampService.Live(victim.UserId) then
		return
	end
	local key = killer.UserId .. ":" .. victim.UserId
	local now = AntiCampService._clock()
	local list = kills[key] or {}
	local keep = {}
	for _, t in ipairs(list) do
		if now - t <= A.RepeatWindowSeconds then
			table.insert(keep, t)
		end
	end
	table.insert(keep, now)
	kills[key] = keep
	if #keep >= A.RepeatKills then
		kills[key] = nil
		AntiCampService.SendBack(killer, e.Plot, "kills")
	end
end

-- one pass over every player (1 Hz)
function AntiCampService.Step()
	local now = AntiCampService._clock()
	local bs = deps.BaseService
	for _, p in ipairs(Players:GetPlayers()) do
		local char = p.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			local pos = root.Position
			local own = if bs and bs.GetOwnedPlotId then bs.GetOwnedPlotId(p) else nil
			local pid = AntiCampService.PlotAt(pos)
			local owner = if pid then ownerOf(pid) else nil
			if pid and pid ~= own and owner and owner ~= p.UserId and AntiCampService.Live(owner) then
				if AntiCampService.CooldownLeft(p.UserId, pid) > 0 then
					AntiCampService.SendBack(p, pid, "cooldown")
				else
					local e = entered[p.UserId]
					if e == nil or e.Plot ~= pid then
						entered[p.UserId] = { Plot = pid, At = now }
					elseif now - e.At >= A.RaiderLimitSeconds then
						AntiCampService.SendBack(p, pid, "time")
					end
				end
			else
				entered[p.UserId] = nil
				-- the base edge: a cooled base just ahead -> one toast with the time left
				local near = AntiCampService.PlotAt(pos, A.EdgeStuds)
				if near and near ~= own and AntiCampService.CooldownLeft(p.UserId, near) > 0 and now - (edgeToastAt[p.UserId] or -math.huge) >= A.EdgeToastEverySeconds then
					edgeToastAt[p.UserId] = now
					notify(p, string.format(A.Text.edge, clockText(AntiCampService.CooldownLeft(p.UserId, near))))
				end
			end
		end
	end
end

function AntiCampService.Init(d: { [string]: any })
	deps = d
	if typeof(A) ~= "table" or A.Enabled ~= true then
		return
	end
	Players.PlayerRemoving:Connect(function(p: Player)
		entered[p.UserId] = nil
		cooldown[p.UserId] = nil
		edgeToastAt[p.UserId] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(A.TickSeconds)
			pcall(AntiCampService.Step)
		end
	end)
	print("[WAR EMPIRE] AntiCampService Init")
end

return AntiCampService
