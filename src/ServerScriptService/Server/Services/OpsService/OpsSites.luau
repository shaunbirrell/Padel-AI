--!strict
--[[
	OpsSites — which job sites may run, and their world bits (W3 step 2 Phase B, lane O; contract §2.1, §4.1,
	§4.2, §4.4). SERVER ONLY.

	Liveness (Resolve): a site runs only when ALL hold, else it is Off with one logged reason (never bare sand):
	  1. OpsConfig.SiteSwitchedOn(id) (master, kind and site switches);
	  2. WorldConfig.POIs[site.POI].Enabled;
	  3. coexistence until the cutover: the Vault (Town.Bank) needs BankRaidConfig.Enabled == false, a Camp needs
	     CombatConfig.FieldBootstrap == false;
	  4. a site with NPCs needs lane N's CombatService API, and every garrison NPC type must exist (the camp commander
	     falls back to Npc.CommanderFallback);
	  5. every anchor role resolves (ActivityAnchors records read ONCE by OpsService), Optional roles excepted;
	  6. the streaming host rule (OpsConfig.Streaming) for every prompt and label anchor: the host part is within
	     NearHostStuds, or its Model holds exactly one BasePart (the POI's ActivityHost cluster), which is then set
	     to ModelStreamingMode.Persistent. Otherwise Off. No part is ever added to carry a prompt.

	World bits, all on existing instances: ProximityPrompts and the one world label per site are parented to the anchor
	Attachment (never a new part); the bank's BankGate / the Port's HeistGate (WE_RuntimeDoor parts) toggle CanCollide
	and WE_GateState; the bank's StateBanner takes Ui.BannerColors; at most 3 Smoke emitters (Active big sites), 1
	Sparks (bank crack) and 2 blown-pump Smoke emitters (30 s). 0 lights, 0 glowing material, 0 parts added.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 60)
local OpsConfig = require(Shared.Configs.OpsConfig)
local WorldConfig = require(Shared.Configs.WorldConfig)
local BankRaidConfig = require(Shared.Configs.BankRaidConfig)
local CombatConfig = require(Shared.Configs.CombatConfig)
local WorldLabel = require(Shared.Util.WorldLabel)

local UI = OpsConfig.Ui
local TEXT = OpsConfig.Text

local OpsSites = {}

local ctx: any = nil
local smokeCount = 0
local pumpSmokeCount = 0

function OpsSites.Init(context: any)
	ctx = context
end

local poiOn: { [string]: boolean } = {}
for _, p in ipairs(WorldConfig.POIs) do
	poiOn[p.Id] = p.Enabled == true
end

-- roles whose anchor carries a prompt or the label (the streaming host rule applies to these)
local function uiRoles(def: OpsConfig.SiteDef): { string }
	local out: { string } = {}
	local seen: { [string]: boolean } = {}
	local function add(r: string?)
		if r ~= nil and not seen[r] then
			seen[r] = true
			table.insert(out, r)
		end
	end
	if def.Label then
		add(def.Target)
	end
	for _, st in ipairs(def.Stages) do
		if st.Prompt ~= nil then
			add(st.At)
			for _, r in ipairs(st.AtAny or {}) do
				add(r)
			end
		end
	end
	for _, r in ipairs(def.Rotate or {}) do
		add(r)
	end
	return out
end

local function partsIn(model: Instance): number
	local n = 0
	for _, d in ipairs(model:GetDescendants()) do -- once per site at resolve, never in a loop
		if d:IsA("BasePart") then
			n += 1
		end
	end
	return n
end

--[[ Liveness of one site. anchors = { [anchorId] = ActivityAnchors record } read once. Returns (anchorsByRole,
	persistModels) when live, else (nil, reason). ]]
function OpsSites.Resolve(def: OpsConfig.SiteDef, anchors: { [string]: any }): (any, any)
	if not OpsConfig.SiteSwitchedOn(def.Id) then
		return nil, "switched off"
	end
	if poiOn[def.POI] ~= true then
		return nil, "POI " .. def.POI .. " off"
	end
	if def.Kind == "Vault" and BankRaidConfig.Enabled ~= false then
		return nil, "BankRaidConfig.Enabled (the old bank job still runs)"
	end
	if def.Kind == "Camp" and (CombatConfig :: any).FieldBootstrap ~= false then
		return nil, "CombatConfig.FieldBootstrap (the field NPCs still stand on the camp posts)"
	end
	local needsNpc = #def.Garrison > 0 or (def.Waves ~= nil and #def.Waves > 0)
	if needsNpc and not ctx.Garrison.CoreReady() then
		return nil, "NPC core (lane N CombatService API) missing"
	end
	for _, row in ipairs(def.Garrison) do
		if ctx.Garrison.TypeFor(row.Type) == nil then
			return nil, "NPC type " .. row.Type .. " missing"
		end
	end
	for _, w in ipairs(def.Waves or {}) do
		for _, t in ipairs(w.Types) do
			if ctx.Garrison.TypeFor(t) == nil then
				return nil, "NPC type " .. t .. " missing"
			end
		end
	end
	local optional: { [string]: boolean } = {}
	for _, r in ipairs(def.Optional or {}) do
		optional[r] = true
	end
	local byRole: { [string]: any } = {}
	local missing: { string } = {}
	for role, aid in pairs(def.Anchors) do
		local a = anchors[aid]
		if a ~= nil then
			byRole[role] = a
		elseif not optional[role] then
			table.insert(missing, role)
		end
	end
	if #missing > 0 then
		table.sort(missing)
		return nil, "anchors missing: " .. table.concat(missing, "+")
	end
	local persist: { Model } = {}
	for _, role in ipairs(uiRoles(def)) do
		local a = byRole[role]
		if a ~= nil then
			local host = a.Attachment.Parent
			if host == nil or not host:IsA("BasePart") then
				return nil, "anchor " .. role .. " has no host part"
			end
			local d = ((host :: BasePart).Position - a.Position).Magnitude
			if d > OpsConfig.Streaming.NearHostStuds then
				local model = host.Parent
				if OpsConfig.Streaming.PersistHostModel and model ~= nil and model:IsA("Model") and partsIn(model) == 1 then
					if table.find(persist, model :: Model) == nil then
						table.insert(persist, model :: Model)
					end
				else
					return nil, string.format("anchor %s is %.0f studs from its host (streaming rule)", role, d)
				end
			end
		end
	end
	return byRole, persist
end

function OpsSites.Persist(models: { Model })
	for _, m in ipairs(models) do
		pcall(function()
			(m :: any).ModelStreamingMode = Enum.ModelStreamingMode.Persistent
		end)
	end
end

-- ── prompts ─────────────────────────────────────────────────────────────────────────────────────────────────────
--[[ One ProximityPrompt on an anchor Attachment. key names it in rt.Prompts (created at most once). The prompt
	carries no key hint: PromptController draws key caps only for keyboard / gamepad (PreferredInput). ]]
function OpsSites.Prompt(rt: any, key: string, role: string, stage: OpsConfig.StageDef)
	if rt.Prompts[key] ~= nil then
		return
	end
	local a = rt.Anchors[role]
	if a == nil or a.Attachment.Parent == nil or stage.Prompt == nil then
		return
	end
	local p = Instance.new("ProximityPrompt")
	p.Name = "WE_OpsPrompt"
	p.ActionText = TEXT.Prompts[stage.Prompt] or ""
	p.ObjectText = (rt.Def :: OpsConfig.SiteDef).Name
	p.HoldDuration = stage.Hold or 0
	p.MaxActivationDistance = stage.Dist or 10
	p.RequiresLineOfSight = false
	p:SetAttribute("WE_OpsSite", rt.Id)
	p.Parent = a.Attachment
	rt.Prompts[key] = p
	p.Triggered:Connect(function(player: Player)
		ctx.OnSitePrompt(rt, key, role, stage, player)
	end)
end

function OpsSites.DropPrompt(rt: any, key: string)
	local p = rt.Prompts[key]
	if p ~= nil then
		rt.Prompts[key] = nil
		p:Destroy()
	end
end

function OpsSites.DropPrompts(rt: any)
	for key in pairs(table.clone(rt.Prompts)) do
		OpsSites.DropPrompt(rt, key)
	end
end

-- ── the world label ────────────────────────────────────────────────────────────────────────────────────────────
local function subFor(rt: any): (string, Color3)
	local def: OpsConfig.SiteDef = rt.Def
	local st: string = rt.State
	local colors = UI.BannerColors
	if st == "Dormant" or st == "Open" then
		local kind = OpsConfig.Kinds[def.Kind]
		if kind and kind.Hostile then
			return TEXT.LabelSub.Hostile, Color3.fromRGB(230, 90, 70)
		end
		return TEXT.LabelSub.Open, colors.Open
	end
	if st == "Active" then
		return TEXT.LabelSub.Active, colors.Active
	end
	if st == "Held" then
		return TEXT.LabelSub.Held, rt.HeldColor or colors.Active
	end
	return TEXT.LabelSub[st] or TEXT.LabelSub.Closed, colors.Closed
end

--[[ The site's one stud-scaled label at its Target anchor (MaxDistance Ui.LabelMaxDistance, never on top of walls, no $
	figure: label text replicates to everyone). Text changes only when the state changes. ]]
function OpsSites.Label(rt: any)
	local def: OpsConfig.SiteDef = rt.Def
	if not def.Label then
		return
	end
	local sub, color = subFor(rt)
	local bb: BillboardGui? = rt.Label
	if bb == nil or bb.Parent == nil then
		local a = rt.Anchors[def.Target]
		if a == nil or a.Attachment.Parent == nil then
			return
		end
		local made = WorldLabel.Create(a.Attachment, def.Name, {
			Name = "WE_OpsLabel",
			Sub = sub,
			SubColor = color,
			MaxDistance = UI.LabelMaxDistance,
			Offset = Vector3.new(0, UI.LabelLift, 0),
		})
		WorldLabel.SetRole(made, nil)
		rt.Label = made
		rt.LabelSub = sub
		return
	end
	if rt.LabelSub ~= sub then
		rt.LabelSub = sub
		WorldLabel.SetText(bb, def.Name, sub, color)
	end
end

function OpsSites.DropLabel(rt: any)
	local bb = rt.Label
	rt.Label = nil
	rt.LabelSub = nil
	if bb ~= nil then
		bb:Destroy()
	end
end

-- ── doors, banner, particles (existing parts only) ─────────────────────────────────────────────────────────────
local function poiFolder(inst: Instance, poi: string): Instance?
	local want = "POI_" .. poi
	local cur = inst.Parent
	while cur ~= nil and not cur:IsA("Workspace") do
		if cur.Name == want then
			return cur
		end
		cur = cur.Parent
	end
	return nil
end

--[[ The runtime door part a door anchor names (WE_Part: BankGate, HeistGate), found ONCE at site init: the host's
	own folder first (the bank plaza), else the nearest part of that name in the POI folder (within 24 studs). ]]
function OpsSites.FindDoor(rt: any): BasePart?
	for _, a in pairs(rt.Anchors) do
		local name = a.Part
		if typeof(name) == "string" and a.Kind == "door" then
			local host = a.Attachment.Parent
			if host and host.Name ~= "ActivityHost" and host.Parent then
				local d = host.Parent:FindFirstChild(name, true)
				if d and d:IsA("BasePart") then
					return d
				end
			end
			local folder = host and poiFolder(host, (rt.Def :: OpsConfig.SiteDef).POI)
			if folder then
				local best: BasePart? = nil
				local bestD = 24
				for _, d in ipairs(folder:GetDescendants()) do -- once per site at init
					if d.Name == name and d:IsA("BasePart") then
						local dist = (d.Position - a.Position).Magnitude
						if dist < bestD then
							best, bestD = d, dist
						end
					end
				end
				return best
			end
		end
	end
	return nil
end

function OpsSites.SetDoor(rt: any, open: boolean)
	local door: BasePart? = rt.Door
	if door == nil or door.Parent == nil then
		return
	end
	local want = if open then "open" else "closed"
	if door:GetAttribute("WE_GateState") ~= want then
		door:SetAttribute("WE_GateState", want)
	end
	if door.CanCollide == open then
		door.CanCollide = not open
	end
	-- the bank gate slides (MapSetup stores both positions); a HeistGate without the attributes only toggles
	local cf = door:GetAttribute(if open then "WE_OpenCFrame" else "WE_ClosedCFrame")
	if typeof(cf) == "CFrame" and door.CFrame ~= cf then
		door.CFrame = cf
	end
	if door.CanQuery == open then
		door.CanQuery = not open -- a closed gate stops shots; a raised one never blocks a raycast
	end
end

-- the bank's StateBanner (lane BK), found once from the Door anchor's host folder; nil until BK lands
function OpsSites.FindBanner(rt: any): BasePart?
	local a = rt.Anchors[(rt.Def :: OpsConfig.SiteDef).Target]
	local host = a and a.Attachment.Parent
	local folder = host and host.Parent
	if folder == nil then
		return nil
	end
	local b = folder:FindFirstChild("StateBanner", true)
	return if b and b:IsA("BasePart") then b else nil
end

function OpsSites.Banner(rt: any)
	local banner: BasePart? = rt.Banner
	if banner == nil or banner.Parent == nil then
		return
	end
	local st: string = rt.State
	local c = UI.BannerColors
	local want = if st == "Active" then c.Active elseif st == "Open" or st == "Dormant" then c.Open else c.Closed
	if banner.Color ~= want then
		banner.Color = want
	end
end

local function emitter(parent: Instance, name: string, sparks: boolean): ParticleEmitter
	local s = UI.Smoke
	local e = Instance.new("ParticleEmitter")
	e.Name = name
	if sparks then
		e.Rate = 12
		e.Lifetime = NumberRange.new(0.3, 0.6)
		e.Speed = NumberRange.new(8, 14)
		e.SpreadAngle = Vector2.new(40, 40)
		e.Size = NumberSequence.new(0.2, 0.05)
		e.Color = ColorSequence.new(Color3.fromRGB(255, 200, 90))
		e.LightEmission = 0.4
	else
		e.Rate = s.Rate
		e.Lifetime = NumberRange.new(s.Lifetime)
		e.Speed = NumberRange.new(s.RiseVelocity)
		e.EmissionDirection = Enum.NormalId.Top
		e.Size = NumberSequence.new(s.SizeFrom, s.SizeTo)
		e.Color = ColorSequence.new(Color3.fromRGB(70, 70, 70))
		e.Transparency = NumberSequence.new(0.35, 1)
		e.LightEmission = 0
	end
	e.Parent = parent
	return e
end

-- one Smoke while an Active big site runs (the bank's on its StateBanner), at most 3 in the world
function OpsSites.Smoke(rt: any, on: boolean)
	local def: OpsConfig.SiteDef = rt.Def
	if on then
		if rt.SmokeFx ~= nil or not def.Big or smokeCount >= 3 then
			return
		end
		local parent: Instance? = rt.Banner
		if parent == nil or parent.Parent == nil then
			local a = rt.Anchors[def.Target]
			parent = a and a.Attachment
		end
		if parent ~= nil then
			rt.SmokeFx = emitter(parent, "WE_OpsSmoke", false)
			smokeCount += 1
		end
	elseif rt.SmokeFx ~= nil then
		rt.SmokeFx:Destroy()
		rt.SmokeFx = nil
		smokeCount = math.max(0, smokeCount - 1)
	end
end

-- the bank vault door's Sparks during the crack (the only Sparks emitter)
function OpsSites.Sparks(rt: any, on: boolean, role: string?)
	if on then
		if rt.SparksFx ~= nil or (rt.Def :: OpsConfig.SiteDef).Kind ~= "Vault" then
			return
		end
		local a = role and rt.Anchors[role]
		if a then
			rt.SparksFx = emitter(a.Attachment, "WE_OpsSparks", true)
		end
	elseif rt.SparksFx ~= nil then
		rt.SparksFx:Destroy()
		rt.SparksFx = nil
	end
end

-- a blown pump smokes for 30 s (at most 2 at once)
function OpsSites.PumpSmoke(rt: any, role: string)
	if pumpSmokeCount >= 2 then
		return
	end
	local a = rt.Anchors[role]
	if a == nil then
		return
	end
	local e = emitter(a.Attachment, "WE_OpsPumpSmoke", false)
	pumpSmokeCount += 1
	task.delay(30, function()
		e:Destroy()
		pumpSmokeCount = math.max(0, pumpSmokeCount - 1)
	end)
end

-- a Held checkpoint's sign takes the taker's colour (NationColorService, the capture-ring rule; never a flag / name)
function OpsSites.HeldSign(rt: any, color: Color3?)
	local a = rt.Anchors[(rt.Def :: OpsConfig.SiteDef).Target]
	local host = a and a.Attachment.Parent
	local sign = host and host.Parent and host.Parent:FindFirstChild("CheckpointSign")
	if not (sign and sign:IsA("BasePart")) then
		return
	end
	if color ~= nil then
		if rt.SignOrig == nil then
			rt.SignOrig = sign.Color
		end
		sign.Color = color
	elseif rt.SignOrig ~= nil then
		sign.Color = rt.SignOrig
		rt.SignOrig = nil
	end
end

function OpsSites.Counts(): (number, number)
	return smokeCount, pumpSmokeCount
end

return OpsSites
