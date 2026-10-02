--!strict
--[[
	Code Bot v148: player avatar moods that this place cannot load.

	A player wearing a dynamic head gets its mood animation in Character.Animate.mood (an Animation). Several of
	Roblox's own face bundles point at mood animations uploaded by another user (not Roblox, not this game's owner),
	so every client that plays one logs "Failed to load animation with sanitized ID. Animation failed to load" and the
	server logs it again for the replicated track (live error report 2026-09-30: 1,878 client + 277 server).

	This script swaps such a mood for Roblox's default mood (RigConfig.AvatarMood.FallbackId) the moment it appears on
	the server, before the character reaches a client. An id is judged ONCE per server with
	AnimationClipProvider:GetAnimationClipAsync (the same place permission the Animator uses; a failure logs nothing):
	  - known bad (RigConfig.AvatarMood.KnownBad) or fails the check -> fallback mood stays;
	  - loads -> the player's own mood is put back (an unknown id shows the fallback for the one lookup).
	Only Animate.mood of player characters is touched: soldiers, guards, walk / run / idle and emotes are untouched.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AnimationClipProvider = game:GetService("AnimationClipProvider")

local RigConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Configs"):WaitForChild("RigConfig"))
local cfg = (RigConfig :: any).AvatarMood
if type(cfg) ~= "table" or cfg.Enabled == false then
	return
end

local FALLBACK: string = cfg.FallbackId
local WAS_ATTR = "WE_MoodWas"

local function idOf(s: string): string?
	return string.match(s, "(%d+)%s*$")
end

local FALLBACK_ID = idOf(FALLBACK) or ""
local verdict: { [string]: boolean } = { [FALLBACK_ID] = true }
for _, id in ipairs(cfg.KnownBad or {}) do
	verdict[tostring(id)] = false
end
local waiting: { [string]: { Animation } } = {}

local function check(id: string)
	local ok = pcall(function()
		return AnimationClipProvider:GetAnimationClipAsync("rbxassetid://" .. id)
	end)
	verdict[id] = ok
	local list = waiting[id]
	waiting[id] = nil
	if ok and list then
		for _, a in ipairs(list) do
			-- put the player's own mood back, unless something changed it meanwhile
			if a.Parent ~= nil and a.AnimationId == FALLBACK and a:GetAttribute(WAS_ATTR) == id then
				a:SetAttribute(WAS_ATTR, nil)
				a.AnimationId = "rbxassetid://" .. id
			end
		end
	end
end

local function guard(a: Animation)
	local id = idOf(a.AnimationId)
	if id == nil or id == FALLBACK_ID then
		return
	end
	local v = verdict[id]
	if v == true then
		return
	end
	a:SetAttribute(WAS_ATTR, id)
	a.AnimationId = FALLBACK
	if v == nil then
		local list = waiting[id]
		if list then
			table.insert(list, a)
		else
			waiting[id] = { a }
			task.spawn(check, id)
		end
	end
end

local function isMoodAnim(d: Instance): boolean
	local p = d.Parent
	if p == nil or not d:IsA("Animation") or p.Name ~= "mood" then
		return false
	end
	local a = p.Parent
	return a ~= nil and a.Name == "Animate"
end

local watched: { [Animation]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function watchAnim(a: Animation)
	if watched[a] then
		return
	end
	watched[a] = true
	guard(a)
	a:GetPropertyChangedSignal("AnimationId"):Connect(function()
		if isMoodAnim(a) then
			guard(a)
		end
	end)
end

local function watchCharacter(char: Model)
	-- the Animate script may arrive after CharacterAdded, and the mood inside it may be filled later still
	for _, d in ipairs(char:GetDescendants()) do
		if isMoodAnim(d) then
			watchAnim(d :: Animation)
		end
	end
	char.DescendantAdded:Connect(function(d: Instance)
		if isMoodAnim(d) then -- also fires for each Animation inside a mood value added whole
			watchAnim(d :: Animation)
		end
	end)
end

local function onPlayer(plr: Player)
	plr.CharacterAdded:Connect(watchCharacter)
	if plr.Character then
		watchCharacter(plr.Character)
	end
end

Players.PlayerAdded:Connect(onPlayer)
for _, plr in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayer, plr)
end
