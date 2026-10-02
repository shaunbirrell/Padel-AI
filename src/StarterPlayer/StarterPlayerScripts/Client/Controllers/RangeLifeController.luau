--!strict
--[[ claude-bud JOB 68: SHOOTING RANGE LIFE (client-side cosmetic only; RangeLifeConfig, owner-first).

	The Training Yard's firing-line soldiers (hosts "YardShooter<lane>", R-RIG statues tagged "WE_Rig") fire at their
	lane's bullseye board on a loop: muzzle flash, short 3D shot sound, dust puff + bullet hole on the board, and a reload
	(the rifle arm dips, the magazine sound) every ShotsPerMag shots.
	  * Registry from the "WE_Rig" tag (added / removed signals); never scans the workspace.
	  * ONE task.wait loop at TickHz for every range; the active set (<= MaxPerYard per range, MaxYards ranges, MaxActive)
	    is re-picked every ScanSeconds from the shooters within NearStuds of the player. Nothing runs far away.
	  * Local instances only (a Terrain attachment per active shooter for the flash / puff, pooled hole parts in one
	    local folder); a shooter leaving the set gets its arm back and its effects removed. No lights, no glowing parts. ]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared", 60)

local RangeLifeController = {}

local TEX_FLASH = "rbxasset://textures/particles/sparkles_main.dds" -- engine files in every client
local TEX_DUST = "rbxasset://textures/particles/smoke_main.dds"

export type ShotState = { NextAt: number, Shots: number, ReloadUntil: number }

-- ── pure (the tests) ────────────────────────────────────────────────────────────────────────────────────────────

-- the active shooters: within near of me, the nearest yards first, <= maxPerYard each, <= maxYards yards, <= maxTotal
function RangeLifeController.Pick(list: { { Pos: Vector3, Yard: any } }, me: Vector3, cfg: any): { number }
	local near = tonumber(cfg.NearStuds) or 80
	local yardBest: { [any]: number } = {}
	local cand: { { I: number, D: number } } = {}
	for i, s in ipairs(list) do
		local d = (s.Pos - me).Magnitude
		if d <= near then
			table.insert(cand, { I = i, D = d })
			if yardBest[s.Yard] == nil or d < yardBest[s.Yard] then
				yardBest[s.Yard] = d
			end
		end
	end
	local yards: { any } = {}
	for y in pairs(yardBest) do
		table.insert(yards, y)
	end
	table.sort(yards, function(a, b)
		return yardBest[a] < yardBest[b]
	end)
	local allowed: { [any]: boolean } = {}
	for k = 1, math.min(#yards, tonumber(cfg.MaxYards) or 2) do
		allowed[yards[k]] = true
	end
	table.sort(cand, function(a, b)
		return a.D < b.D
	end)
	local out: { number } = {}
	local per: { [any]: number } = {}
	for _, c in ipairs(cand) do
		local y = list[c.I].Yard
		if allowed[y] and (per[y] or 0) < (tonumber(cfg.MaxPerYard) or 4) and #out < (tonumber(cfg.MaxActive) or 8) then
			per[y] = (per[y] or 0) + 1
			table.insert(out, c.I)
		end
	end
	return out
end

-- one soldier's next step at time now ("wait" | "fire" | "reload" | "reloaded"); u in [0, 1) spaces the shots
function RangeLifeController.Step(s: ShotState, now: number, cfg: any, u: number): string
	if s.ReloadUntil > 0 then
		if now < s.ReloadUntil then
			return "wait"
		end
		s.ReloadUntil = 0
		s.Shots = 0
		s.NextAt = now + (tonumber(cfg.ShotGapMin) or 1) * 0.5
		return "reloaded"
	end
	if now < s.NextAt then
		return "wait"
	end
	if s.Shots >= (tonumber(cfg.ShotsPerMag) or 6) then
		s.ReloadUntil = now + (tonumber(cfg.ReloadSeconds) or 2)
		return "reload"
	end
	s.Shots += 1
	local lo, hi = tonumber(cfg.ShotGapMin) or 1, tonumber(cfg.ShotGapMax) or 2
	s.NextAt = now + lo + (hi - lo) * math.clamp(u, 0, 1)
	return "fire"
end

-- where a shot lands: on the board face toward the shooter, (u, v) in [-1, 1] x spread from the board's centre
function RangeLifeController.HitPoint(board: CFrame, size: Vector3, from: Vector3, u: number, v: number, spread: number): (Vector3, Vector3)
	-- the board is thin along its local X (TrainingYardConfig: Size (0.3, H, 3.2)); its face normal is +/-RightVector
	local n = board.RightVector
	if (from - board.Position):Dot(n) < 0 then
		n = -n
	end
	local p = board.Position + n * (size.X * 0.5 + 0.02) + board.UpVector * (v * spread) + board.LookVector * (u * spread)
	return p, n
end

-- ── runtime ─────────────────────────────────────────────────────────────────────────────────────────────────────

type Entry = {
	Rig: Model,
	Lane: number,
	Active: boolean,
	State: ShotState,
	Rifle: BasePart?,
	Target: BasePart?,
	Shoulder: Motor6D?,
	BaseC0: CFrame?,
	Att: Attachment?,
	Flash: ParticleEmitter?,
	Puff: ParticleEmitter?,
	Holes: { BasePart },
	HoleNext: number,
}

local cfg: any = nil
local Audio: any = nil
local entries: { [Model]: Entry } = {}
local localFolder: Folder? = nil
local rng = Random.new()

local function hostOf(rig: Model): (Model?, number?)
	local host = rig.Parent
	if host and host:IsA("Model") then
		local lane = string.match(host.Name, cfg.ShooterPattern)
		if lane then
			return host, tonumber(lane)
		end
	end
	return nil, nil
end

local function track(rig: Instance)
	if not rig:IsA("Model") or entries[rig] then
		return
	end
	local _, lane = hostOf(rig)
	if lane == nil then
		return
	end
	entries[rig] = { Rig = rig, Lane = lane :: number, Active = false, State = { NextAt = 0, Shots = 0, ReloadUntil = 0 }, Holes = {}, HoleNext = 1 }
end

local function deactivate(e: Entry)
	e.Active = false
	if e.Shoulder and e.BaseC0 then
		e.Shoulder.C0 = e.BaseC0 -- the arm back where the server baked it
	end
	if e.Att then
		e.Att:Destroy()
	end
	for _, h in ipairs(e.Holes) do
		h:Destroy()
	end
	e.Att, e.Flash, e.Puff = nil, nil, nil
	table.clear(e.Holes)
	e.State.ReloadUntil = 0
end

local function untrack(rig: Instance)
	local e = entries[rig :: Model]
	if e then
		if e.Active then
			deactivate(e)
		end
		entries[rig :: Model] = nil
	end
end

local function emitter(parent: Attachment, name: string, tex: string, size: number, life: number, speed: number): ParticleEmitter
	local p = Instance.new("ParticleEmitter")
	p.Name = name
	p.Texture = tex
	p.Rate = 0
	p.Lifetime = NumberRange.new(life)
	p.Speed = NumberRange.new(speed)
	p.SpreadAngle = Vector2.new(30, 30)
	p.Size = NumberSequence.new(size, size * 0.3)
	p.Rotation = NumberRange.new(0, 360)
	p.Parent = parent
	return p
end

local function activate(e: Entry): boolean
	local host = e.Rig.Parent
	local yard = host and host.Parent
	if yard == nil then
		return false
	end
	local rifle = e.Rig:FindFirstChild("Rifle", true)
	local target = yard:FindFirstChild(cfg.TargetPrefix .. tostring(e.Lane), true)
	if not (rifle and rifle:IsA("BasePart")) or not (target and target:IsA("BasePart")) then
		return false
	end
	e.Rifle, e.Target = rifle, target
	local rs = e.Rig:FindFirstChild("Right Shoulder", true)
	if rs and rs:IsA("Motor6D") then
		e.Shoulder = rs
		e.BaseC0 = rs.C0
	end
	local att = Instance.new("Attachment")
	att.Name = "WE_RangeLife"
	att.Parent = Workspace.Terrain
	local fl = emitter(att, "Flash", TEX_FLASH, tonumber(cfg.FlashSize) or 1, tonumber(cfg.FlashSeconds) or 0.06, 0)
	fl.LightEmission = 1
	fl.LightInfluence = 0
	fl.Color = ColorSequence.new(Color3.fromRGB(255, 226, 150), Color3.fromRGB(255, 150, 60))
	local pf = emitter(att, "Puff", TEX_DUST, 0.7, 0.5, 4)
	pf.Color = ColorSequence.new(Color3.fromRGB(196, 178, 140))
	pf.Transparency = NumberSequence.new(0.3, 1)
	e.Att, e.Flash, e.Puff = att, fl, pf
	e.State = { NextAt = os.clock() + rng:NextNumber(0, tonumber(cfg.ShotGapMax) or 2), Shots = rng:NextInteger(0, 3), ReloadUntil = 0 }
	e.Active = true
	return true
end

local function hole(e: Entry, at: Vector3, n: Vector3)
	local folder = localFolder
	if folder == nil then
		return
	end
	local h: BasePart? = e.Holes[e.HoleNext]
	if h == nil then
		local p = Instance.new("Part")
		p.Name = "Hole"
		local s = tonumber(cfg.HoleSize) or 0.2
		p.Size = Vector3.new(s, s, 0.02)
		p.Color = Color3.fromRGB(30, 26, 22)
		p.Material = Enum.Material.SmoothPlastic
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Parent = folder
		e.Holes[e.HoleNext] = p
		h = p
	end
	local hp: BasePart = h :: BasePart
	hp.CFrame = CFrame.lookAt(at, at + n)
	e.HoleNext = (e.HoleNext % math.max(1, tonumber(cfg.HolesPerShooter) or 4)) + 1
end

local function fire(e: Entry)
	local rifle, target, att = e.Rifle, e.Target, e.Att
	if rifle == nil or target == nil or att == nil or rifle.Parent == nil or target.Parent == nil then
		return
	end
	local dir = target.Position - rifle.Position
	if dir.Magnitude < 1 then
		return
	end
	local muzzle = rifle.Position + dir.Unit * (tonumber(cfg.MuzzleForward) or 1.7)
	att.WorldPosition = muzzle
	if e.Flash then
		e.Flash:Emit(1)
	end
	local spread = tonumber(cfg.HitSpread) or 0.9
	local hit, n = RangeLifeController.HitPoint(target.CFrame, target.Size, rifle.Position, rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), spread)
	hole(e, hit, n)
	if Audio then
		pcall(Audio.Play, cfg.Sounds.Fire, muzzle)
		pcall(Audio.Play, cfg.Sounds.Hit, hit)
	end
	-- the puff at the board: the same attachment, moved after the flash particle (LockedToPart off: it stays put)
	task.delay(0.05, function()
		if e.Active and e.Att == att and e.Puff then
			att.WorldPosition = hit
			e.Puff:Emit(math.max(0, math.floor(tonumber(cfg.PuffCount) or 4)))
		end
	end)
end

local function reload(e: Entry, down: boolean)
	if e.Shoulder and e.BaseC0 then
		e.Shoulder.C0 = if down then e.BaseC0 * CFrame.Angles(0, 0, math.rad(tonumber(cfg.ReloadDeg) or 0)) else e.BaseC0
	end
	if down and Audio and e.Rifle then
		pcall(Audio.Play, cfg.Sounds.Reload, e.Rifle.Position)
	end
end

local function myPos(): Vector3?
	local ch = Players.LocalPlayer.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	local cam = Workspace.CurrentCamera
	return if cam then cam.Focus.Position else nil
end

local function live(R: any): boolean
	local ok, v = pcall(R.Live, cfg, Players.LocalPlayer.UserId)
	return ok and v == true
end

local function rescan()
	local me = myPos()
	local list: { { Pos: Vector3, Yard: any } } = {}
	local ents: { Entry } = {}
	if me then
		for rig, e in pairs(entries) do
			local host = rig.Parent
			if host and host:IsA("Model") and host.Parent then
				table.insert(list, { Pos = host:GetPivot().Position, Yard = host.Parent })
				table.insert(ents, e)
			end
		end
	end
	local want: { [Entry]: boolean } = {}
	for _, i in ipairs(if me then RangeLifeController.Pick(list, me :: Vector3, cfg) else {}) do
		want[ents[i]] = true
	end
	for _, e in pairs(entries) do
		if e.Active and not want[e] then
			deactivate(e)
		elseif want[e] and not e.Active then
			activate(e)
		end
	end
end

function RangeLifeController.Init()
	if Shared == nil then
		return
	end
	local okC, C = pcall(function(): any
		return (require :: any)((Shared :: any).Configs.RangeLifeConfig)
	end)
	local okR, R = pcall(function(): any
		return (require :: any)((Shared :: any).Configs.RetentionConfig)
	end)
	if not okC or not okR or type(C) ~= "table" or C.Enabled ~= true then
		return
	end
	cfg = C
	local okA, A = pcall(function(): any
		return require(script.Parent.Parent.Modules.AudioController)
	end)
	Audio = if okA then A else nil
	local f = Instance.new("Folder")
	f.Name = "WE_RangeLifeLocal"
	f.Parent = Workspace
	localFolder = f
	CollectionService:GetInstanceAddedSignal("WE_Rig"):Connect(track)
	CollectionService:GetInstanceRemovedSignal("WE_Rig"):Connect(untrack)
	for _, rig in ipairs(CollectionService:GetTagged("WE_Rig")) do
		track(rig)
	end
	task.spawn(function()
		local period = 1 / math.max(1, tonumber(cfg.TickHz) or 4)
		local nextScan = 0
		local wasLive = false
		while true do
			task.wait(period)
			local on = live(R)
			if not on then
				if wasLive then
					for _, e in pairs(entries) do
						if e.Active then
							deactivate(e)
						end
					end
				end
				wasLive = false
				continue
			end
			wasLive = true
			local now = os.clock()
			if now >= nextScan then
				nextScan = now + (tonumber(cfg.ScanSeconds) or 1.5)
				rescan()
			end
			for _, e in pairs(entries) do
				if e.Active then
					local step = RangeLifeController.Step(e.State, now, cfg, rng:NextNumber())
					if step == "fire" then
						fire(e)
					elseif step == "reload" then
						reload(e, true)
					elseif step == "reloaded" then
						reload(e, false)
					end
				end
			end
		end
	end)
end

return RangeLifeController
