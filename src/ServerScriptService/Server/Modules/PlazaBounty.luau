--!strict
--[[
	claude-bud JOB 4.3 (2026-09-29): the plaza bounty (Shared/Configs/PlazaBountyConfig). Server only. TerritoryService
	calls PlazaBounty.OnCaptured(player, zoneId, position) right after a capture completes. Nothing the client sends
	is read: the capture itself is TerritoryService's server-side capture.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 60)
local PlazaBountyConfig = require(Shared.Configs.PlazaBountyConfig)
local Constants = require(Shared.Constants)
local Remotes = require(Shared.Remotes)

local PlazaBounty = {}

local deps: { [string]: any } = {}
local bounty: { Holder: number, EndsAt: number, Serial: number, Pos: Vector3 }? = nil
local serial = 0
local lastEarned: { [number]: number } = {} -- userId -> os.clock() of the last bounty paid

function PlazaBounty.Bind(d: { [string]: any })
	deps = d
end

local function push(player: Player, data: { [string]: any })
	local ev = Remotes.TryGetEvent(Constants.RemoteNames.FeaturePush)
	if ev then
		ev:FireClient(player, "Bounty", data)
	end
end

local function notify(player: Player, msg: string, kind: string)
	local ns = deps.NotificationService
	if ns and ns.Notify then
		ns.Notify(player, msg, kind, 5)
	end
end

local function fmt(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

local function endBounty()
	if bounty == nil then
		return
	end
	local holder = bounty.Holder
	bounty = nil
	for _, p in ipairs(Players:GetPlayers()) do
		if p.UserId ~= holder and PlazaBountyConfig.LiveFor(p.UserId) then
			push(p, { Show = false })
		end
	end
end

function PlazaBounty.OnCaptured(player: Player, zoneId: string, position: Vector3)
	if zoneId ~= PlazaBountyConfig.ZoneId then
		return
	end
	local now = os.clock()
	local b = bounty
	-- 1) a live bounty retaken by someone else: pay once (per-player cooldown), then it ends
	if b and now < b.EndsAt and player.UserId ~= b.Holder and PlazaBountyConfig.LiveFor(player.UserId) then
		local last = lastEarned[player.UserId]
		if last == nil or now - last >= PlazaBountyConfig.EarnCooldownSeconds then
			lastEarned[player.UserId] = now
			-- claude-bud JOB 13: Plaza War Week doubles the bounty (EngagementService.PlazaBountyMult)
			local mult = 1
			pcall(function()
				mult = (require(script.Parent.Parent.Services.EngagementService) :: any).PlazaBountyMult(player)
			end)
			pcall(function() -- claude-bud JOB 39 phase 5: the bounty scales to 3 min of income (x1 while not live)
				mult *= (require(script.Parent.Parent.Services.EndgameService) :: any).BountyScale(player, PlazaBountyConfig.Cash)
			end)
			local econ = deps.EconomyService
			if econ and econ.AddCash then
				econ.AddCash(player, math.floor(PlazaBountyConfig.Cash * mult), "plaza_bounty")
			end
			notify(player, "Bounty claimed! +$" .. fmt(PlazaBountyConfig.Cash * mult), "Reward")
		end
		endBounty()
	elseif b and now >= b.EndsAt then
		endBounty()
	end
	-- 2) this capture starts a new bounty on the capturer (only once the last one is over)
	if bounty ~= nil then
		return
	end
	serial += 1
	local mine = serial
	bounty = { Holder = player.UserId, EndsAt = now + PlazaBountyConfig.WindowSeconds, Serial = mine, Pos = position }
	local mins = math.floor(PlazaBountyConfig.WindowSeconds / 60)
	local secs = PlazaBountyConfig.WindowSeconds % 60
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= player and PlazaBountyConfig.LiveFor(p.UserId) then
			push(p, { Show = true, X = position.X, Y = position.Y, Z = position.Z, Cash = PlazaBountyConfig.Cash })
			notify(p, string.format("BOUNTY: retake the Central Plaza in %d:%02d for +$%s", mins, secs, fmt(PlazaBountyConfig.Cash)), "Info")
		end
	end
	task.delay(PlazaBountyConfig.WindowSeconds, function()
		if bounty and bounty.Serial == mine then
			endBounty()
		end
	end)
end

-- lastEarned is kept for the server's life (a rejoin never resets the earn cooldown); one number per player

return PlazaBounty
