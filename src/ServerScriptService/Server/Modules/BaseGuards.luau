--!strict
--[[
	claude-bud JOB 20 (2026-09-29): base guards as real defenders (Shared/Configs/GuardConfig). GateDefenseService keeps
	building the guards and runs its 5 Hz loop; this module is the guards' brain, the tower guards, the rewards and the
	balance caps. GateDefenseService passes its own helpers (H) so line of sight, plot bounds, spawn grace and the
	clan check stay exactly its own.
	  * ThinkGuard: hostiles INSIDE the plot (players not owner / clan / friend, enemy army units); the nearest the
	    guard can reach inside its leash; face, walk (a throttled path when it cannot see), shoot with LOS + hit chance;
	    idle at the post, back there ReturnAfterSeconds after the last intruder.
	  * Tower guards: hired per corner tower (Cash, rebirth-scaled price, saved in profile.TowerGuards); anchored on the
	    platform, shoot hostiles OUTSIDE the plot within Tower.Range; respawn after RespawnSeconds.
	  * Damage: players get the server's creator tag for the OWNER only on the killing hit, and only when the pair is
	    under the anti-farm limit and not in a private server (so CombatService credits the owner exactly like his own
	    kill: cash, XP, MOST KILLS, the kill feed). Per-target damage per second capped; at most MaxShootersPerBase.
]]

local CollectionService = game:GetService("CollectionService")
local PathfindingService = game:GetService("PathfindingService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 60)
local GuardConfig = require(Shared.Configs.GuardConfig)

local BaseGuards = {}

local C: any = GuardConfig
local deps: { [string]: any } = {}
local pairLog: { [string]: { number } } = {}
local dmgWindow: { [any]: { At: number, Taken: number } } = {}
local shooters: { [number]: { At: number, N: number } } = {} -- plotId -> this tick's engaged shooters
local pathBudget = { At = 0, N = 0 }
local rng = Random.new()

type Target = { Kind: string, Player: Player?, Humanoid: Humanoid, Root: BasePart, OwnerUserId: number, Key: any }

function BaseGuards.Live(): boolean
	return C.Enabled == true
end

function BaseGuards.Bind(d: { [string]: any })
	deps = d
end

local function combatDamage(): any?
	local ok, m = pcall(function()
		return require(script.Parent.Parent.Services.CombatService.CombatDamage) :: any
	end)
	return if ok then m else nil
end

local function areFriends(a: number, b: number): boolean
	local es = deps.EngagementService
	if es and es.AreFriends then
		local ok, yes = pcall(es.AreFriends, a, b)
		return ok and yes == true
	end
	return false
end

-- a player the base must never shoot: the owner, his clan (H.IsAlly), his friends
local function friendlyPlayer(ownerUserId: number, p: Player, H: any): boolean
	return p.UserId == ownerUserId or H.IsAlly(ownerUserId, p) or areFriends(ownerUserId, p.UserId)
end

local function friendlyUnitOwner(ownerUserId: number, unitOwner: number, H: any): boolean
	if unitOwner == ownerUserId or areFriends(ownerUserId, unitOwner) then
		return true
	end
	local p = Players:GetPlayerByUserId(unitOwner)
	return p ~= nil and H.IsAlly(ownerUserId, p)
end

-- every hostile with inside == true (in the plot) or inside == false (outside it, within range of `from`)
local function hostiles(def: any, H: any, inside: boolean, from: Vector3, range: number): { Target }
	local out: { Target } = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if not friendlyPlayer(def.OwnerUserId, p, H) and not H.InSpawnGrace(p) then
			local char = p.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if hum and root and root:IsA("BasePart") and hum.Health > 0 then
				local isIn = H.InsidePlot(def, root.Position)
				if isIn == inside and (inside or (root.Position - from).Magnitude <= range) then
					table.insert(out, { Kind = "Player", Player = p, Humanoid = hum, Root = root, OwnerUserId = p.UserId, Key = p.UserId })
				end
			end
		end
	end
	if C.UnitTargets then
		for _, m in ipairs(CollectionService:GetTagged(C.UnitTag)) do
			local uo = m:GetAttribute("OwnerUserId")
			if m:IsA("Model") and typeof(uo) == "number" and not friendlyUnitOwner(def.OwnerUserId, uo, H) then
				local hum = m:FindFirstChildOfClass("Humanoid")
				local root = m:FindFirstChild("HumanoidRootPart")
				if hum and root and root:IsA("BasePart") and hum.Health > 0 then
					local isIn = H.InsidePlot(def, root.Position)
					if isIn == inside and (inside or (root.Position - from).Magnitude <= range) then
						table.insert(out, { Kind = "Unit", Player = nil, Humanoid = hum, Root = root, OwnerUserId = uo, Key = m })
					end
				end
			end
		end
	end
	return out
end

local function lowTarget(p: Player): boolean
	local prof = deps.DataService and deps.DataService.GetProfile(p)
	if prof == nil then
		return true
	end
	local lvl = tonumber(prof.Level) or 1
	local first = tonumber(prof.FirstJoinUnix) or 0
	return lvl < C.DpsCap.LowLevel or (first > 0 and os.time() - first < C.DpsCap.NewPlayerSeconds)
end

local function isPrivateServer(): boolean
	return game.PrivateServerId ~= "" and game.PrivateServerOwnerId ~= 0
end

local function reward(p: Player, cash: number, xp: number, why: string)
	if deps.EconomyService and cash > 0 then
		pcall(deps.EconomyService.AddCash, p, cash, why)
	end
	if deps.XPService and xp > 0 then
		pcall(deps.XPService.AddXP, p, xp, why)
	end
end

-- one defender hit on a target (capped); returns the damage dealt
local function hurt(def: any, t: Target, amount: number, sourceId: string, H: any): number
	local now = os.clock()
	local w = dmgWindow[t.Key]
	if w == nil or now - w.At >= 1 then
		w = { At = now, Taken = 0 }
		dmgWindow[t.Key] = w
	end
	local win = w :: { At: number, Taken: number }
	local amt = GuardConfig.CapDamage(win.Taken, amount, t.Player ~= nil and lowTarget(t.Player :: Player))
	if amt <= 0 or t.Humanoid.Health <= 0 then
		return 0
	end
	win.Taken += amt
	local owner = Players:GetPlayerByUserId(def.OwnerUserId)
	if t.Kind == "Player" then
		local victim = t.Player :: Player
		if H.InSpawnGrace(victim) then
			return 0
		end
		local killing = t.Humanoid.Health - amt <= 0
		if killing and owner and not (C.Rewards.NoCreditInPrivateServers and isPrivateServer()) and GuardConfig.AllowPair(pairLog, owner.UserId, victim.UserId, now) then
			local cd = combatDamage()
			if cd and cd.TagCreator then
				pcall(cd.TagCreator, t.Humanoid, owner, false) -- CombatService credits the owner (cash, XP, board, feed)
			end
		end
		t.Humanoid:SetAttribute("WE_LastWeapon", sourceId)
		t.Humanoid:TakeDamage(amt)
		pcall(H.Alert, def.PlotId, def.OwnerUserId, victim)
	else
		t.Humanoid:TakeDamage(amt)
		if t.Humanoid.Health <= 0 and owner and not isPrivateServer() and GuardConfig.AllowPair(pairLog, owner.UserId, t.OwnerUserId, now) then
			reward(owner, C.Rewards.UnitKillCash, C.Rewards.UnitKillXP, "guard_unit_kill")
		end
	end
	return amt
end

local function hitChance(dist: number, far: number): number
	if dist <= C.HitNearStuds then
		return C.HitChanceNear
	end
	local k = math.clamp((dist - C.HitNearStuds) / math.max(far - C.HitNearStuds, 1), 0, 1)
	return C.HitChanceNear + (C.HitChanceFar - C.HitChanceNear) * k
end

-- one engaged shooter for this plot this tick (turrets count too); false = the base already has enough firing
local function claimShooter(def: any, tnow: number): boolean
	local s = shooters[def.PlotId]
	if s == nil or tnow - s.At > 0.15 then
		s = { At = tnow, N = #(def.Turrets or {}) }
		shooters[def.PlotId] = s
	end
	local st = s :: { At: number, N: number }
	if st.N >= C.MaxShootersPerBase then
		return false
	end
	st.N += 1
	return true
end

local function requestPath(g: any, to: Vector3, tnow: number)
	if g._bgPathBusy or tnow < (g._bgPathAt or 0) then
		return
	end
	if tnow - pathBudget.At >= 1 then
		pathBudget.At, pathBudget.N = tnow, 0
	end
	if pathBudget.N >= C.PathBudgetPerSecond then
		return
	end
	pathBudget.N += 1
	g._bgPathBusy = true
	g._bgPathAt = tnow + C.PathEverySeconds
	task.spawn(function()
		local ok, path = pcall(function()
			local p = PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = true, WaypointSpacing = 6 })
			p:ComputeAsync(g.Root.Position, to)
			return p
		end)
		g._bgPathBusy = false
		if ok and path and path.Status == Enum.PathStatus.Success then
			g._bgPath = { Points = path:GetWaypoints(), I = 2 }
		else
			g._bgPath = nil
		end
	end)
end

-- the leash: a goal never more than LeashStuds from the post and always inside the plot
local function leashed(def: any, g: any, goal: Vector3, H: any): Vector3
	local post = g.PostCf.Position
	local off = goal - post
	local flat = Vector3.new(off.X, 0, off.Z)
	if flat.Magnitude > C.LeashStuds then
		goal = post + flat.Unit * C.LeashStuds + Vector3.new(0, off.Y, 0)
	end
	return H.ClampInside(def, goal)
end

--[[ One gate / extra guard, one think. Returns true (GateDefenseService's old think is skipped). ]]
function BaseGuards.ThinkGuard(def: any, g: any, stats: any, tnow: number, H: any): boolean
	if not g.Alive or g.Humanoid.Health <= 0 or not g.Root.Parent then
		return true
	end
	local pos = g.Root.Position
	local list = hostiles(def, H, true, pos, math.huge)
	local best: Target? = nil
	local bestD = math.huge
	for _, t in ipairs(list) do
		-- only intruders within the leash (+ the shoot range) of this guard's post
		local fromPost = (t.Root.Position - g.PostCf.Position).Magnitude
		local d = (t.Root.Position - pos).Magnitude
		if fromPost <= C.LeashStuds + (stats.ShootRange or 70) and d < bestD then
			best, bestD = t, d
		end
	end
	if best then
		local t = best :: Target
		g._bgLastIntruder = tnow
		H.FaceYaw(g.Root, t.Root.Position)
		local range = stats.ShootRange or 70
		local ignore: { Instance } = { g.Model, def.Folder, t.Root.Parent :: Instance }
		local sees = H.HasLos(pos, t.Root.Position, ignore)
		if bestD > range * 0.85 or not sees then
			if sees then
				g._bgPath = nil
				g.Humanoid:MoveTo(leashed(def, g, t.Root.Position, H))
			else
				local path = g._bgPath
				if path and path.I <= #path.Points then
					local wp = path.Points[path.I]
					if (pos - wp.Position).Magnitude < 3 then
						path.I += 1
					end
					g.Humanoid:MoveTo(leashed(def, g, wp.Position, H))
				else
					requestPath(g, leashed(def, g, t.Root.Position, H), tnow)
				end
			end
		else
			g.Humanoid:MoveTo(pos)
		end
		local interval = 1 / math.max(stats.GuardFireRate or 1.4, 0.1)
		if sees and bestD <= range and tnow - g.LastFireAt >= interval and claimShooter(def, tnow) then
			g.LastFireAt = tnow
			if rng:NextNumber() <= hitChance(bestD, range) then
				hurt(def, t, (stats.GuardDamage or 14) * H.ResearchMult(def.OwnerUserId), "BaseGuard", H)
			end
			pcall(H.ShotFx, def, g, pos, t.Root.Position)
		end
		return true
	end
	-- no intruder: hold, then walk back to the post and stand there (idle)
	local post = g.PostCf.Position
	if tnow - (g._bgLastIntruder or -math.huge) >= C.ReturnAfterSeconds and (Vector3.new(pos.X - post.X, 0, pos.Z - post.Z)).Magnitude > 2 then
		g.Humanoid:MoveTo(post)
	elseif (Vector3.new(pos.X - post.X, 0, pos.Z - post.Z)).Magnitude <= 2 then
		g.Humanoid:MoveTo(pos)
		H.FaceYaw(g.Root, post + g.PostCf.LookVector * 10)
	end
	g._bgPath = nil
	return true
end

-- the extra guards' posts (Defenses research GuardRoster), world CFrames facing the gate
function BaseGuards.ExtraPosts(plotId: number, ownerUserId: number, gateCf: CFrame): { CFrame }
	local out: { CFrame } = {}
	local owner = Players:GetPlayerByUserId(ownerUserId)
	local rs = deps.ResearchService
	local n = 0
	if owner and rs and rs.GetAdd then
		local ok, v = pcall(rs.GetAdd, owner, C.CountStat)
		n = if ok then math.clamp(math.floor(tonumber(v) or 0), 0, C.MaxExtraGuards) else 0
	end
	local okPF, PlotFrame = pcall(function()
		return require(Shared.Util.PlotFrame) :: any
	end)
	for i = 1, n do
		local p = C.ExtraPosts[i]
		if p and okPF then
			local at = PlotFrame.LocalToWorld(plotId, p.X, p.Z)
			local gate = gateCf.Position
			out[i] = CFrame.lookAt(Vector3.new(at.X, gate.Y, at.Z), Vector3.new(gate.X, gate.Y, gate.Z))
		end
	end
	return out
end

-- after a guard spawns: the Defenses research HP multiplier
function BaseGuards.AfterSpawn(g: any, ownerUserId: number)
	local owner = Players:GetPlayerByUserId(ownerUserId)
	local rs = deps.ResearchService
	if owner and rs and rs.GetBonus then
		local ok, m = pcall(rs.GetBonus, owner, C.HealthStat)
		if ok and typeof(m) == "number" and m > 1 then
			g.Humanoid.MaxHealth = math.floor(g.Humanoid.MaxHealth * math.min(m, 3))
			g.Humanoid.Health = g.Humanoid.MaxHealth
		end
	end
end

function BaseGuards.RespawnSeconds(): number
	return C.RespawnSeconds
end

-- a player killed an enemy base guard / tower guard: the smaller reward (not on MOST KILLS), pair-limited
function BaseGuards.OnGuardKilledBy(attacker: Player, ownerUserId: number)
	if isPrivateServer() or attacker.UserId == ownerUserId then
		return
	end
	if GuardConfig.AllowPair(pairLog, attacker.UserId, ownerUserId, os.clock()) then
		reward(attacker, C.Rewards.GuardKillCash, C.Rewards.GuardKillXP, "guard_kill")
	end
end

-- ── tower guards ────────────────────────────────────────────────────────────────────────────────────────────────
type TowerSlot = { Unit: any?, DeadAt: number? }
local towerState: { [number]: { Def: any, Slots: { [number]: TowerSlot }, CheckAt: number, Prompts: { [number]: Instance } } } = {}

local function platforms(def: any): { [number]: BasePart }
	local out: { [number]: BasePart } = {}
	local plotFolder = def.Folder and def.Folder.Parent
	local tf = plotFolder and plotFolder:FindFirstChild(C.Tower.Folder, true)
	if tf then
		for i = 1, C.Tower.Slots do
			local p = tf:FindFirstChild(C.Tower.PlatformPrefix .. i, true)
			if p and p:IsA("BasePart") then
				out[i] = p
			end
		end
	end
	return out
end

-- tower slots 1..n are hired, n = the owner's Tower Guards research level (bought through ResearchService.Purchase)
local function hiredCount(ownerUserId: number): number
	local owner = Players:GetPlayerByUserId(ownerUserId)
	local rs = deps.ResearchService
	if owner and rs and rs.GetAdd then
		local ok, v = pcall(rs.GetAdd, owner, "TowerGuards")
		return if ok then math.clamp(math.floor(tonumber(v) or 0), 0, C.Tower.Slots) else 0
	end
	return 0
end

local function badge(model: Model)
	local head = model:FindFirstChild("Head", true) or model:FindFirstChild("HumanoidRootPart")
	if head and head:IsA("BasePart") and head:FindFirstChild("WE_TowerBadge") == nil then
		local bb = Instance.new("BillboardGui")
		bb.Name = "WE_TowerBadge"
		bb.Size = UDim2.fromScale(1.6, 1.6)
		bb.StudsOffset = Vector3.new(0, 2.4, 0)
		bb.MaxDistance = 40
		bb.LightInfluence = 0
		local t = Instance.new("TextLabel")
		t.Size = UDim2.fromScale(1, 1)
		t.BackgroundTransparency = 1
		t.TextScaled = true
		t.Font = Enum.Font.GothamBlack
		t.TextColor3 = C.Tower.BadgeColor
		t.TextStrokeTransparency = 0.3
		t.Text = "★"
		t.Parent = bb
		bb.Parent = head
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and string.find(string.lower(d.Name), "helmet") then
			d.Color = C.Tower.BadgeColor -- a gold helmet
		end
	end
end

local function spawnTower(def: any, i: number, plat: BasePart, H: any): any?
	local top = plat.Position + Vector3.new(0, plat.Size.Y / 2 + 3, 0)
	local centre: Vector3 = def.PadCenter or def.GateCf.Position
	local out = Vector3.new(top.X - centre.X, 0, top.Z - centre.Z)
	local cf = CFrame.lookAt(top, top + (if out.Magnitude > 0.1 then out.Unit else Vector3.new(0, 0, -1))) -- facing out of the base
	local stats = { GuardHealth = C.Tower.Health, GuardDamage = C.Tower.Damage }
	local ok, g = pcall(H.SpawnGuardModel, def.OwnerUserId, 100 + i, cf, stats, def.Folder, def.PlotId)
	if not ok or g == nil then
		return nil
	end
	g.Root.Anchored = true -- stands on the platform
	g.Model:SetAttribute("TowerGuard", true)
	g.Model:SetAttribute("OwnerUserId", def.OwnerUserId)
	g.Humanoid.MaxHealth = C.Tower.Health
	g.Humanoid.Health = C.Tower.Health
	badge(g.Model)
	return g
end

local function ensurePrompt(def: any, st: any, i: number, plat: BasePart, hired: boolean)
	local existing = st.Prompts[i]
	if hired then
		if existing then
			existing:Destroy()
			st.Prompts[i] = nil
		end
		return
	end
	if existing and existing.Parent then
		return
	end
	local owner = Players:GetPlayerByUserId(def.OwnerUserId)
	local prof = owner and deps.DataService and deps.DataService.GetProfile(owner)
	local cost = GuardConfig.TowerCost(if prof then tonumber(prof.Prestige) or 0 else 0) -- = ResearchService's scaled price
	local base = Vector3.new(plat.Position.X, def.GateCf.Position.Y + 2, plat.Position.Z)
	local host = Instance.new("Part")
	host.Name = "TowerGuardPrompt" .. i
	host.Anchored = true
	host.CanCollide = false
	host.CanQuery = false
	host.CanTouch = false
	host.Transparency = 1
	host.Size = Vector3.new(1, 1, 1)
	host.CFrame = CFrame.new(base)
	host:SetAttribute("OwnerUserId", def.OwnerUserId)
	host:SetAttribute("TowerSlot", i)
	local pp = Instance.new("ProximityPrompt")
	pp.Name = "WE_TowerGuardPrompt"
	pp.ActionText = "Hire guard - $" .. tostring(cost)
	pp.ObjectText = "Tower Guard"
	pp.HoldDuration = 0.4
	pp.MaxActivationDistance = C.Tower.PromptDistance
	pp.RequiresLineOfSight = false
	pp:SetAttribute("OwnerUserId", def.OwnerUserId)
	pp.Parent = host
	pp.Triggered:Connect(function(player: Player)
		BaseGuards.Hire(player, def.PlotId, i)
	end)
	CollectionService:AddTag(pp, "WE_TowerGuardPrompt") -- the client shows it to the owner only
	host.Parent = def.Folder
	st.Prompts[i] = host
end

-- the owner hires the next tower guard: the Defenses research "Tower Guards" (ResearchService.Purchase pays through the
-- existing research_ purchase path, rebirth-scaled price); only the next free tower's prompt is shown
function BaseGuards.Hire(player: Player, plotId: number, i: number)
	local rl = deps.RateLimitService
	if rl and not rl.Allow(player, "hire_tower_guard", 1, 2) then
		return
	end
	local st = towerState[plotId]
	local def = st and st.Def
	if def == nil or def.OwnerUserId ~= player.UserId or typeof(i) ~= "number" or i ~= hiredCount(player.UserId) + 1 then
		return
	end
	if (platforms(def) :: any)[i] == nil or deps.ResearchService == nil then
		return
	end
	local ok, err = deps.ResearchService.Purchase(player, "TowerGuards")
	if deps.NotificationService then
		if ok then
			pcall(deps.NotificationService.Notify, player, "Tower guard hired!", "Success")
		else
			pcall(deps.NotificationService.Notify, player, if err == "InsufficientCash" then "Not enough Cash" else "Can't hire yet", "Warn")
		end
	end
	st.CheckAt = 0 -- spawn / next prompt on the next think
end

--[[ The plot's tower guards, one think (inside GateDefenseService's 5 Hz loop). ]]
function BaseGuards.ThinkTowers(def: any, tnow: number, H: any)
	if not C.Tower.Enabled then
		return
	end
	local st = towerState[def.PlotId]
	if st == nil or st.Def ~= def then
		st = { Def = def, Slots = {}, CheckAt = 0, Prompts = {} }
		towerState[def.PlotId] = st
	end
	local state = st :: any
	if tnow >= state.CheckAt then
		state.CheckAt = tnow + 3
		local plats = platforms(def)
		local n = hiredCount(def.OwnerUserId)
		for i = 1, C.Tower.Slots do
			local plat = plats[i]
			if plat then
				-- a prompt only on the next free tower (hired ones and later ones show none)
				ensurePrompt(def, state, i, plat, i ~= n + 1)
				local slot = state.Slots[i] or {}
				state.Slots[i] = slot
				if i <= n then
					local u = slot.Unit
					local dead = u == nil or not u.Alive or u.Humanoid.Health <= 0 or u.Model.Parent == nil
					if dead then
						slot.DeadAt = slot.DeadAt or tnow
						if u == nil or tnow - (slot.DeadAt :: number) >= C.RespawnSeconds then
							slot.Unit = spawnTower(def, i, plat, H)
							slot.DeadAt = nil
						end
					end
				end
			end
		end
	end
	for _, slot in pairs(state.Slots) do
		local g = slot.Unit
		if g and g.Alive and g.Humanoid.Health > 0 and g.Root.Parent then
			local pos = g.Root.Position
			local best: Target? = nil
			local bestD = C.Tower.Range
			for _, t in ipairs(hostiles(def, H, false, pos, C.Tower.Range)) do
				local d = (t.Root.Position - pos).Magnitude
				if d < bestD then
					best, bestD = t, d
				end
			end
			if best then
				local t = best :: Target
				local look = Vector3.new(t.Root.Position.X, pos.Y, t.Root.Position.Z)
				if (look - pos).Magnitude > 0.5 then
					g.Root.CFrame = CFrame.lookAt(pos, look)
				end
				local interval = 1 / math.max(C.Tower.FireRate, 0.05)
				if tnow - g.LastFireAt >= interval and H.HasLos(pos, t.Root.Position, { g.Model, def.Folder, t.Root.Parent :: Instance }) and claimShooter(def, tnow) then
					g.LastFireAt = tnow
					if rng:NextNumber() <= C.Tower.HitChance then
						hurt(def, t, C.Tower.Damage * H.ResearchMult(def.OwnerUserId), "TowerGuard", H)
					end
					pcall(H.ShotFx, def, g, pos, t.Root.Position)
				end
			end
		end
	end
end

-- a player's hit on a tower guard part (GateDefenseService.ApplyDamage): true when it landed
function BaseGuards.DamageTower(def: any, hitPart: BasePart, amount: number, attacker: Player): boolean
	local st = towerState[def.PlotId]
	if st == nil then
		return false
	end
	for _, slot in pairs(st.Slots) do
		local g = slot.Unit
		if g and (hitPart == g.Root or hitPart:IsDescendantOf(g.Model)) then
			if g.Alive and g.Humanoid.Health > 0 then
				g.Humanoid:TakeDamage(amount)
				if g.Humanoid.Health <= 0 then
					BaseGuards.OnGuardKilledBy(attacker, def.OwnerUserId)
				end
				return true
			end
			return false
		end
	end
	return false
end

return BaseGuards
