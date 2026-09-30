--!strict
--[[
	claude-bud JOB 39 (2026-09-30): ENDGAME PROGRESSION, the server side (EndgameConfig, owner-first). Phase 1:
	  * the Rebirth price scale: BaseService.PurchaseUpgrade asks EndgameService.ScaledCost for every structure /
	    business buy. WE_BaseCostScale (player attribute, display only) tells the client's price labels; nil = 1.
	  * EMPIRE LEVEL: profile.Endgame.EmpireLevel (0..30), kept through both rebirth paths (PrestigeService never
	    touches profile.Endgame). EconomyService.cashMultFor multiplies by EmpireMultFor (non-exempt reasons only).
	  * the plaza stations: publishes each live station's frame (ReplicatedStorage.WE_PlazaStations) from the
	    Enterables registry; the client builds the interior and the prompt for live players only.
	ONE purchase path (Purchase(player, kind, id)): the flag, the requirement, the price from config (never from
	the client), the station reach, not hurt in the last HurtLockSeconds, then SpendCash("endgame_<kind>"), save, push.
	Remotes: RequestEndgameBuy (kind, id?) and RequestEndgameState () through RemoteGate + RateLimitService; the state
	goes back as FeaturePush "EndgameState".
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local EndgameConfig = require(Shared.Configs.EndgameConfig)
local PlazaServicesConfig = require(Shared.Configs.PlazaServicesConfig)
local PrestigeConfig = require(Shared.Configs.PrestigeConfig)

local EndgameService = {}

local deps: { [string]: any } = {}
local hurtAt: { [number]: number? } = {}
local stationCF: { [string]: any } = {} -- station kind -> the building ground frame (CFrame)
local clock: () -> number = os.clock

local function getProfile(player: Player): any
	local ds = deps.DataService
	return if ds and ds.GetProfile then ds.GetProfile(player) else nil
end

local function notify(player: Player, text: string, kind: string?)
	local ns = deps.NotificationService
	if player.Parent and ns and ns.Notify then
		pcall(ns.Notify, player, text, kind or "Info", 4)
	end
end

local function nonNeg(v: any): number
	local n = tonumber(v) or 0
	if n ~= n then
		return 0
	end
	return math.max(0, math.floor(n))
end

-- profile.Endgame, created on demand (ProfileSchema sanitises it on load)
function EndgameService.Data(profile: any): any
	if typeof(profile.Endgame) ~= "table" then
		profile.Endgame = { EmpireLevel = 0 }
	end
	return profile.Endgame
end

function EndgameService.EmpireLevel(profile: any): number
	local e = if typeof(profile) == "table" then profile.Endgame else nil
	if typeof(e) ~= "table" then
		return 0
	end
	return math.min(nonNeg(e.EmpireLevel), EndgameConfig.Empire.MaxLevel)
end

-- §2.1 the price factor for this player now (1 while the Rebirth part is not live for him)
function EndgameService.CostScale(userId: number, profile: any): number
	if typeof(profile) ~= "table" or not EndgameConfig.LiveFor(userId, "Rebirth") then
		return 1
	end
	return EndgameConfig.RebirthCostScale(nonNeg(profile.Prestige))
end

-- the price BaseService charges for a structure / business level (raw cost when the part is off)
function EndgameService.ScaledCost(player: Player, profile: any, structureId: string, cost: number): number
	return EndgameConfig.ScaleStructureCost(structureId, cost, EndgameService.CostScale(player.UserId, profile))
end

-- the Empire cash factor (EconomyService.cashMultFor, non-exempt reasons); 1 while the part is not live
function EndgameService.EmpireMultFor(player: Player, profile: any): number
	if not EndgameConfig.LiveFor(player.UserId, "EmpireLevel") then
		return 1
	end
	return EndgameConfig.EmpireMult(EndgameService.EmpireLevel(profile))
end

local function setAttr(player: Player, name: string, value: any)
	if player:GetAttribute(name) ~= value then
		player:SetAttribute(name, value)
	end
end

-- display attributes: WE_EndgameLive (the client builds stations / panels), WE_EmpireLevel, WE_BaseCostScale
function EndgameService.SyncAttributes(player: Player)
	local profile = getProfile(player)
	if profile == nil then
		return
	end
	local anyLive = EndgameConfig.AnyLiveFor(player.UserId)
	setAttr(player, "WE_EndgameLive", if anyLive then true else nil)
	local empire = if EndgameConfig.LiveFor(player.UserId, "EmpireLevel") then EndgameService.EmpireLevel(profile) else 0
	setAttr(player, "WE_EmpireLevel", if empire > 0 then empire else nil)
	local scale = EndgameService.CostScale(player.UserId, profile)
	setAttr(player, "WE_BaseCostScale", if scale > 1 then scale else nil)
end

-- the station frame (building ground frame) for a station kind, or nil until the world registered it
function EndgameService.StationFrame(kind: string): CFrame?
	return stationCF[kind]
end

-- the NPC's world position for a station kind
function EndgameService.StationPoint(kind: string): Vector3?
	local cf = stationCF[kind]
	local st = PlazaServicesConfig.Stations[kind]
	if cf == nil or st == nil then
		return nil
	end
	return (cf * CFrame.new(st.NpcAt)).Position
end

-- (true) when the player stands within BuyRange of the station's NPC
function EndgameService.AtStation(player: Player, kind: string): boolean
	local p = EndgameService.StationPoint(kind)
	local c = player.Character
	local r = c and c:FindFirstChild("HumanoidRootPart")
	if p == nil or r == nil or not r:IsA("BasePart") then
		return false
	end
	return (r.Position - p).Magnitude <= EndgameConfig.Station.BuyRange
end

function EndgameService.RecentlyHurt(player: Player): boolean
	local t = hurtAt[player.UserId]
	return t ~= nil and clock() - t < EndgameConfig.Station.HurtLockSeconds
end

-- what the client's panels show (display only; Purchase re-checks everything)
function EndgameService.State(player: Player): { [string]: any }
	local profile = getProfile(player)
	local uid = player.UserId
	local out: { [string]: any } = { Live = EndgameConfig.AnyLiveFor(uid) }
	if profile == nil then
		return out
	end
	if EndgameConfig.LiveFor(uid, "EmpireLevel") then
		local L = EndgameService.EmpireLevel(profile)
		out.Empire = {
			Level = L,
			Max = EndgameConfig.Empire.MaxLevel,
			Pct = math.floor((EndgameConfig.EmpireMult(L) - 1) * 100 + 0.5),
			NextCost = EndgameConfig.EmpireCost(L + 1),
			NextPct = EndgameConfig.Empire.CashPctPerLevel,
			Milestone = EndgameConfig.Empire.Milestones[L + 1],
		}
	end
	if EndgameConfig.LiveFor(uid, "Rebirth") then
		local p = nonNeg(profile.Prestige)
		out.Rebirth = {
			Scale = EndgameConfig.RebirthCostScale(p),
			NextScale = EndgameConfig.RebirthCostScale(p + 1),
			NextBase = EndgameConfig.LifeCost(EndgameConfig.RebirthCostScale(p + 1)),
			Next = PrestigeConfig.NextRebirths(p, 1, nil)[1],
		}
	end
	local points: { [string]: any } = {}
	for kind, st in pairs(PlazaServicesConfig.Stations) do
		local pt = EndgameService.StationPoint(kind)
		if pt and EndgameConfig.LiveFor(uid, st.Part) then
			points[kind] = { X = pt.X, Y = pt.Y, Z = pt.Z }
		end
	end
	out.Stations = points
	return out
end

function EndgameService.Push(player: Player)
	local rs = deps.RemoteSetup
	local ev = rs and rs.Get(Constants.RemoteNames.FeaturePush)
	if ev and ev:IsA("RemoteEvent") then
		(ev :: RemoteEvent):FireClient(player, "EndgameState", EndgameService.State(player))
	end
end

local function short(n: number): string
	if n >= 1e9 then
		return string.format("%.2fB", n / 1e9)
	elseif n >= 1e6 then
		return string.format("%.1fM", n / 1e6)
	elseif n >= 1e3 then
		return string.format("%.0fK", n / 1e3)
	end
	return tostring(math.floor(n))
end

--[[ THE one purchase path. kind: "Empire" (phase 1). The client sends only kind / id; the price is config's.
	Returns (ok, message). ]]
function EndgameService.Purchase(player: Player, kind: string, _id: string?): (boolean, string)
	local T = EndgameConfig.Text
	local profile = getProfile(player)
	if profile == nil then
		return false, "Loading"
	end
	if kind == "Empire" then
		if not EndgameConfig.LiveFor(player.UserId, "EmpireLevel") then
			return false, T.NotLive
		end
		if not EndgameService.AtStation(player, "Command") then
			return false, T.NotHere
		end
		if EndgameService.RecentlyHurt(player) then
			return false, T.Hurt
		end
		local L = EndgameService.EmpireLevel(profile)
		local price = EndgameConfig.EmpireCost(L + 1)
		if price == nil then
			return false, T.Max
		end
		local eco = deps.EconomyService
		if eco == nil or eco.SpendCash == nil then
			return false, "Not ready"
		end
		local cash = nonNeg(profile.Cash)
		if cash < price then
			return false, string.format(T.Short, short(price - cash))
		end
		local ok, err = eco.SpendCash(player, price, "endgame_empire")
		if not ok then
			return false, tostring(err or "SpendFailed")
		end
		profile = getProfile(player) or profile
		local e = EndgameService.Data(profile)
		e.EmpireLevel = L + 1
		if deps.DataService and deps.DataService.MarkDirty then
			deps.DataService.MarkDirty(player)
		end
		print(string.format("[Station] Command empire ok L=%d price=%d mult=%.2f", L + 1, price, EndgameConfig.EmpireMult(L + 1)))
		pcall(EndgameService.SyncAttributes, player)
		local bss = deps.BaseSignService
		if bss and bss.Refresh then
			pcall(bss.Refresh, profile.BasePlotId)
		end
		return true, string.format(T.EmpireBought, L + 1, math.floor((EndgameConfig.EmpireMult(L + 1) - 1) * 100 + 0.5))
	end
	return false, "Unknown"
end

local function watchCharacter(player: Player, char: Model)
	local hum = char:WaitForChild("Humanoid", 10)
	if hum == nil or not hum:IsA("Humanoid") then
		return
	end
	local last = hum.Health
	hum.HealthChanged:Connect(function(h: number)
		if h < last then
			hurtAt[player.UserId] = clock()
		end
		last = h
	end)
end

-- publish the live stations' frames once the plaza houses are registered (the world builds at start)
local function publishStations()
	local folder = ReplicatedStorage:FindFirstChild(PlazaServicesConfig.FolderName)
	if folder == nil then
		local f = Instance.new("Folder")
		f.Name = PlazaServicesConfig.FolderName
		f.Parent = ReplicatedStorage
		folder = f
	end
	local okE, Ent = pcall(function(): any
		return require(script.Parent.Parent.Modules.Enterables)
	end)
	if not okE or Ent == nil then
		return
	end
	for _ = 1, 60 do
		local missing = false
		for kind, st in pairs(PlazaServicesConfig.Stations) do
			if (EndgameConfig.Parts :: any)[st.Part] == true and stationCF[kind] == nil then
				local found = nil
				for _, e in ipairs(Ent.List()) do
					if e.Id == st.Row then
						found = e
					end
				end
				if found then
					stationCF[kind] = found.CF
					local v = Instance.new("CFrameValue")
					v.Name = kind
					v.Value = found.CF
					v.Parent = folder
					print(string.format("[Station] %s published at %s (%s)", kind, tostring(found.CF.Position), st.Row))
				else
					missing = true
				end
			end
		end
		if not missing then
			return
		end
		task.wait(2)
	end
	warn("[Station] some plaza stations never found their building (PlazaBuildingsConfig rows / Enterables)")
end

-- test hooks
function EndgameService._SetStation(kind: string, cf: CFrame?)
	stationCF[kind] = cf
end
function EndgameService._SetClock(fn: () -> number)
	clock = fn
end
function EndgameService._Hurt(uid: number, t: number?)
	hurtAt[uid] = t
end

function EndgameService.Init(d: { [string]: any })
	deps = d
	if EndgameConfig.Live.Enabled ~= true then
		return
	end
	task.spawn(publishStations)
	local function onPlayer(player: Player)
		player.CharacterAdded:Connect(function(c: Model)
			task.spawn(watchCharacter, player, c)
		end)
		if player.Character then
			task.spawn(watchCharacter, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in ipairs(Players:GetPlayers()) do
		onPlayer(p)
	end
	Players.PlayerRemoving:Connect(function(p: Player)
		hurtAt[p.UserId] = nil
	end)
	if d.DataService and d.DataService.OnProfileLoaded then
		d.DataService.OnProfileLoaded(function(player: Player)
			pcall(EndgameService.SyncAttributes, player)
		end)
	end
	-- the rebirth count / live state change rarely: a slow sweep keeps the display attributes right (1 per 5 s)
	task.spawn(function()
		while true do
			task.wait(5)
			for _, p in ipairs(Players:GetPlayers()) do
				pcall(EndgameService.SyncAttributes, p)
			end
		end
	end)
	local rs = d.RemoteSetup
	local buy = rs and rs.Get(Constants.RemoteNames.RequestEndgameBuy)
	if buy and buy:IsA("RemoteEvent") then
		(buy :: RemoteEvent).OnServerEvent:Connect(function(player: Player, kind: any, id: any)
			if not require(script.Parent.Parent.Modules.RemoteGate).Check(player, "RequestEndgameBuy", kind, id) then
				return
			end
			if d.RateLimitService and not d.RateLimitService.Allow(player, "endgame_buy", EndgameConfig.Station.RatePerSec, EndgameConfig.Station.Burst) then
				return
			end
			if typeof(kind) ~= "string" or not EndgameConfig.AnyLiveFor(player.UserId) then
				return
			end
			local ok, msg = EndgameService.Purchase(player, kind, if typeof(id) == "string" then id else nil)
			notify(player, msg, if ok then "Success" else "Warn")
			EndgameService.Push(player)
		end)
	end
	local ask = rs and rs.Get(Constants.RemoteNames.RequestEndgameState)
	if ask and ask:IsA("RemoteEvent") then
		(ask :: RemoteEvent).OnServerEvent:Connect(function(player: Player)
			if not require(script.Parent.Parent.Modules.RemoteGate).Check(player, "RequestEndgameState") then
				return
			end
			if d.RateLimitService and not d.RateLimitService.Allow(player, "endgame_state", 2, 4) then
				return
			end
			if EndgameConfig.AnyLiveFor(player.UserId) then
				EndgameService.Push(player)
			end
		end)
	end
	print("[WAR EMPIRE] EndgameService Init")
end

return EndgameService
