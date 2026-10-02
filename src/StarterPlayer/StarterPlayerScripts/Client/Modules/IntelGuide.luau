--!strict
--[[
	Code Bot v168 (Shaun 2026-10-01): after the toast "Contract done: claim it at the Intel Office" the game guides the
	player there with the EXISTING tracker (Modules/ObjectiveMarker: the yellow compass pill top-right reads
	"INTEL OFFICE 1.4km" with its arrow, the GO line and the one world marker), the same system as BASE / AIRDROP.
	No fast travel: it only points.
	  * the server publishes WE_IntelGuide (Vector3: the Intel Office NPC; EndgameService.SyncIntelGuide) while a done
	    contract (daily row or the weekly HVT) is unclaimed, and clears it after the claim (or a new day);
	  * attribute set -> ShowWith({ Short = LABEL, X, Y, Z }) (a manual map pin still wins: ObjectiveMarker ignores us);
	  * the marker clears itself on arrival (ArriveStuds, inside the NPC's 12-stud prompt). If he walks off without
	    claiming (> ReshowStuds) or another objective (an airdrop, a mission GO) ended, it comes back while the
	    attribute is still set: it never fights a LIVE other target, it only fills a free tracker;
	  * attribute cleared -> our marker (Short == LABEL) is cleared; anybody else's is left alone.
	Cost: one attribute signal + a 1 Hz check while a guide is set (nothing otherwise).
]]

local Players = game:GetService("Players")

local IntelGuide = {}

IntelGuide.LABEL = "INTEL OFFICE"
IntelGuide.ATTR = "WE_IntelGuide"
IntelGuide.ArriveStuds = 10
IntelGuide.ReshowStuds = 40
IntelGuide.TimeoutSeconds = 1800
IntelGuide.CheckSeconds = 1

type Target = { Short: string, X: number, Y: number, Z: number }

--[[ Pure: what to do now. guide = the server's point (nil = nothing to claim), current = ObjectiveMarker.Current(),
	pos = the character's position (nil while respawning), fresh = the attribute just changed (the completion moment).
	"show" = ShowWith the Intel Office; "clear" = Clear our own marker; nil = leave the tracker alone. ]]
function IntelGuide.Decide(guide: Vector3?, current: Target?, pos: Vector3?, fresh: boolean): string?
	if guide == nil then
		if current ~= nil and current.Short == IntelGuide.LABEL then
			return "clear"
		end
		return nil
	end
	if current ~= nil then
		if current.Short == IntelGuide.LABEL then
			local dx, dz = current.X - guide.X, current.Z - guide.Z
			return if dx * dx + dz * dz > 1 then "show" else nil -- the office point moved (a re-publish)
		end
		return if fresh then "show" else nil -- the completion moment wins once; later never over a live target
	end
	if fresh then
		return "show"
	end
	-- the tracker is free (arrived and walked off, timed out, an airdrop ended): back on once he is away from it
	if pos == nil then
		return nil
	end
	local dx, dz = pos.X - guide.X, pos.Z - guide.Z
	return if dx * dx + dz * dz > IntelGuide.ReshowStuds * IntelGuide.ReshowStuds then "show" else nil
end

local started = false

function IntelGuide.Start()
	if started then
		return
	end
	started = true
	local player = Players.LocalPlayer
	local ObjectiveMarker = require(script.Parent.ObjectiveMarker)
	local function guide(): Vector3?
		local v = player:GetAttribute(IntelGuide.ATTR)
		return if typeof(v) == "Vector3" then v else nil
	end
	local function apply(fresh: boolean)
		local g = guide()
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local pos = if hrp and hrp:IsA("BasePart") then hrp.Position else nil
		local what = IntelGuide.Decide(g, ObjectiveMarker.Current(), pos, fresh)
		if what == "show" and g then
			ObjectiveMarker.ShowWith(
				{ Short = IntelGuide.LABEL, X = g.X, Y = g.Y, Z = g.Z },
				{ ArriveStuds = IntelGuide.ArriveStuds, TimeoutSeconds = IntelGuide.TimeoutSeconds }
			)
		elseif what == "clear" then
			ObjectiveMarker.Clear()
		end
	end
	local loopOn = false
	local function loop()
		if loopOn then
			return
		end
		loopOn = true
		task.spawn(function()
			while guide() ~= nil and player.Parent do
				task.wait(IntelGuide.CheckSeconds)
				pcall(apply, false)
			end
			loopOn = false
		end)
	end
	player:GetAttributeChangedSignal(IntelGuide.ATTR):Connect(function()
		pcall(apply, true)
		if guide() ~= nil then
			loop()
		end
	end)
	if guide() ~= nil then
		pcall(apply, true)
		loop()
	end
end

return IntelGuide
