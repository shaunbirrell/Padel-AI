--!strict
--[[
	StreamPrefetch (streaming2 lane S1, spec F1): the one way the server moves a character far across the map.

	Under instance streaming a phone only holds the world round its character. A PivotTo to a far spot lands the
	player where nothing has streamed in yet: a pause screen, or a fall through missing ground. The server asks the
	engine to stream the destination first with Player:RequestStreamAroundAsync (Player.yaml; techniques.md
	"Proactive streaming"), then moves the character.

	OFF SWITCH. Everything here is a no-op while Workspace.StreamingEnabled is false (default.project.json is the
	flag): no RequestStreamAroundAsync / AddReplicationFocus call is made, and PivotTo moves at once, inside the call.

	API
	  Enabled(): boolean                         Workspace.StreamingEnabled
	  Place(character, cf): boolean              PivotTo + zero root velocity, now, no pre-fetch
	  IsNear(player, pos): boolean               the character is within StreamingConfig.NearStuds of pos
	  Request(player, pos, timeout?): boolean    YIELDS while streaming is on: pcall'd RequestStreamAroundAsync
	                                             (false only when the request threw); true at once when off
	  PivotTo(player, cf, opts?): boolean        pre-fetch (only when the move is longer than NearStuds), then Place,
	                                             in its own thread. At most one move in flight per player: a call
	                                             while one is pre-fetching re-targets it (the newest target wins and
	                                             is pre-fetched too when far from the fetched one). opts.OnDone(moved)
	                                             runs once, after the move. No stacked retries: one settle check
	                                             (StreamingConfig.SettleCheckSeconds) moves the character again only
	                                             when it snapped back to where it started.
	  IsMoving(player): boolean                  a pre-fetched move is still on its way (FallSafety waits for it)
	  HoldFocus(player, part, maxSeconds?)       AddReplicationFocus(part) until the returned release() runs, or
	                                             maxSeconds (default StreamingConfig.JoinFocusMaxSeconds) pass
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared", 60)
local StreamingConfig = require(Shared.Configs.StreamingConfig)

local StreamPrefetch = {}

export type Opts = {
	Timeout: number?, -- RequestStreamAroundAsync timeout (default StreamingConfig.PrefetchTimeout)
	OnDone: ((moved: boolean) -> ())?, -- runs once, after the move (moved = false: no character / player left)
}

type Flight = {
	Target: CFrame,
	Timeout: number,
	Done: { (boolean) -> () },
	Deadline: number, -- os.clock(): past it the flight is stale (see STALE_SLACK)
	Abandoned: boolean,
}

-- A re-targeted flight pre-fetches again; after this many rounds it moves to the newest target as it is.
local MAX_ROUNDS = 3
-- RequestStreamAroundAsync gives up after its timeout (Player.yaml), so a flight lasts at most MAX_ROUNDS timeouts.
-- Should one ever hang, it goes stale this many seconds later: the next move starts afresh (and takes over its
-- callbacks), and FallSafety stops waiting for it. The hung worker, if it ever wakes, moves nothing.
local STALE_SLACK = 5

local flights: { [Player]: Flight } = {} -- the move in flight per player
local moveGen: { [Player]: number } = {} -- bumped by every PivotTo: a newer move cancels an older settle check

Players.PlayerRemoving:Connect(function(player: Player)
	flights[player] = nil -- its worker sees player.Parent == nil and drops the move
	moveGen[player] = nil
end)

-- Read on every call (never cached): the engine fixes it for the server's life, the headless stand-in toggles it.
-- Workspace.yaml: read security None; pcall'd anyway because the join path runs through here.
function StreamPrefetch.Enabled(): boolean
	local ok, on = pcall(function()
		return Workspace.StreamingEnabled
	end)
	return ok and on == true
end

local function rootOf(character: Model?): BasePart?
	if character == nil then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return character.PrimaryPart
end

-- PivotTo + zero velocity: exactly the move BaseService.TeleportToPlot made before streaming2.
function StreamPrefetch.Place(character: Model?, cf: CFrame): boolean
	if character == nil or character.Parent == nil then
		return false
	end
	character:PivotTo(cf)
	local hrp = character:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		hrp.AssemblyLinearVelocity = Vector3.zero
		hrp.AssemblyAngularVelocity = Vector3.zero
	end
	return true
end

function StreamPrefetch.IsNear(player: Player, pos: Vector3): boolean
	local root = rootOf(player.Character)
	return root ~= nil and (root.Position - pos).Magnitude <= StreamingConfig.NearStuds
end

function StreamPrefetch.Request(player: Player, pos: Vector3, timeout: number?): boolean
	if not StreamPrefetch.Enabled() then
		return true
	end
	local ok, err = pcall(player.RequestStreamAroundAsync, player, pos, timeout or StreamingConfig.PrefetchTimeout)
	if not ok then
		warn("[StreamPrefetch] RequestStreamAroundAsync failed for", player.Name, err)
	end
	return ok
end

-- The player's flight unless it is stale. A stale flight stays in the table, marked Abandoned, so the next PivotTo
-- takes over its callbacks.
local function liveFlight(player: Player): Flight?
	local flight = flights[player]
	if flight == nil or flight.Abandoned then
		return nil
	end
	if os.clock() > flight.Deadline then
		flight.Abandoned = true
		warn("[StreamPrefetch] a pre-fetched move went stale for", player.Name)
		return nil
	end
	return flight
end

function StreamPrefetch.IsMoving(player: Player): boolean
	return liveFlight(player) ~= nil
end

-- Pre-fetch until the (maybe re-targeted) destination is covered. Yields; the caller clears the flight right after,
-- with no yield in between, so a re-target can never slip in after the last check.
local function prefetchRounds(player: Player, flight: Flight)
	local fetched: Vector3? = nil
	for _ = 1, MAX_ROUNDS do
		if player.Parent == nil then
			return
		end
		local pos = flight.Target.Position
		local covered = if fetched ~= nil
			then (fetched - pos).Magnitude <= StreamingConfig.NearStuds
			else StreamPrefetch.IsNear(player, pos)
		if covered then
			return
		end
		fetched = pos
		StreamPrefetch.Request(player, pos, flight.Timeout)
	end
end

local function placeAndWatch(player: Player, target: CFrame): boolean
	local character = player.Character
	local root = rootOf(character)
	local from = if root then root.Position else nil
	if not StreamPrefetch.Place(character, target) then
		return false
	end
	-- One settle check (no stacked retries): spawn / physics can undo a pivot made right after a spawn. Only a far
	-- move can visibly be undone, and "undone" means back where it started, never "walked a few studs".
	local near = StreamingConfig.NearStuds
	if from ~= nil and character ~= nil and (from - target.Position).Magnitude > near then
		local gen = moveGen[player]
		task.delay(StreamingConfig.SettleCheckSeconds, function()
			if moveGen[player] ~= gen or liveFlight(player) ~= nil or player.Character ~= character then
				return -- a newer move (or a new life) owns the character
			end
			local r = rootOf(character)
			if r ~= nil and (r.Position - target.Position).Magnitude > near and (r.Position - from).Magnitude <= near then
				StreamPrefetch.Place(character, target)
			end
		end)
	end
	return true
end

local function runFlight(player: Player, flight: Flight)
	xpcall(prefetchRounds, function(err: any)
		warn("[StreamPrefetch] pre-fetch failed for", player.Name, err)
	end, player, flight)
	if flight.Abandoned then
		return -- went stale while it hung; a newer flight owns the move and these callbacks
	end
	if flights[player] == flight then
		flights[player] = nil
	end
	local moved = false
	if player.Parent ~= nil then
		local okMove, res = pcall(placeAndWatch, player, flight.Target)
		if not okMove then
			warn("[StreamPrefetch] move failed for", player.Name, res)
		end
		moved = okMove and res == true
	end
	for _, cb in ipairs(flight.Done) do
		task.spawn(cb, moved)
	end
end

function StreamPrefetch.PivotTo(player: Player, cf: CFrame, opts: Opts?): boolean
	local onDone = if opts then opts.OnDone else nil
	if not StreamPrefetch.Enabled() then
		-- streaming off: the plain move, at once (no RequestStreamAroundAsync call)
		local moved = StreamPrefetch.Place(player.Character, cf)
		if onDone then
			task.spawn(onDone, moved)
		end
		return moved
	end
	moveGen[player] = (moveGen[player] or 0) + 1
	local timeout = if opts and opts.Timeout then opts.Timeout else StreamingConfig.PrefetchTimeout
	local prev = flights[player] -- when liveFlight calls it stale, its callbacks move to the new flight
	local flight = liveFlight(player)
	if flight then
		-- one move in flight per player: re-target it; its worker pre-fetches the new spot when it is far
		flight.Target = cf
		flight.Timeout = timeout
		flight.Deadline = math.max(flight.Deadline, os.clock() + MAX_ROUNDS * timeout + STALE_SLACK)
		if onDone then
			table.insert(flight.Done, onDone)
		end
		return true
	end
	local newFlight: Flight = {
		Target = cf,
		Timeout = timeout,
		Done = if prev then prev.Done else {}, -- a stale flight's callbacks ride on this one
		Deadline = os.clock() + MAX_ROUNDS * timeout + STALE_SLACK,
		Abandoned = false,
	}
	if onDone then
		table.insert(newFlight.Done, onDone)
	end
	flights[player] = newFlight
	task.spawn(runFlight, player, newFlight)
	return true
end

function StreamPrefetch.HoldFocus(player: Player, part: BasePart?, maxSeconds: number?): () -> ()
	if part == nil or not StreamPrefetch.Enabled() then
		return function() end
	end
	local held = pcall(player.AddReplicationFocus, player, part)
	if not held then
		return function() end
	end
	local released = false
	local function release()
		if released then
			return
		end
		released = true
		pcall(player.RemoveReplicationFocus, player, part)
	end
	task.delay(maxSeconds or StreamingConfig.JoinFocusMaxSeconds, release)
	return release
end

return StreamPrefetch
