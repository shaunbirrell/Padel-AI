--!strict
--[[ W2 Combat Core (contracts §3.8, asset shortlist §6.2 C4): optional gun meshes from verified store asset ids.

	CombatService.Init task.spawns WeaponAssetLoader.Start once. For every WeaponConfig weapon with VisualAssetId > 0
	it loads each DISTINCT asset id once (InsertService:LoadAsset, then AssetService:LoadAssetAsync; each pcall'd;
	failures are cached and never retried), takes Tool[VisualToolName] (or the first Tool), then its Model child
	VisualChild (or the Tool's own parts), and publishes a sanitised copy as Model "Weapon_<WeaponId>" in
	ReplicatedStorage.WE_WeaponTemplates (created here). The client (WeaponVisuals) uses that template when present
	and its own Part kit otherwise.

	Sanitising: every Script / LocalScript / ModuleScript and Sound is destroyed, and so is every effect (Beam,
	ParticleEmitter, Trail, Fire, Smoke, Sparkles, lights: the client draws its own muzzle flash, and a kit's
	flash Beam only ever moved with the kit's scripts) together with the Attachments that only such a Beam used.
	Attachments, Welds, WeldConstraints and Motor6Ds stay. Every BasePart is unanchored, CanCollide / CanQuery /
	CanTouch false, Massless, no shadow. A template with more than MAX_PARTS BaseParts is refused.

	VisualChild is copied as ONE clone, so the kit's own joints between its parts (magazine, bolt) keep pointing at
	the copies (cloning part by part left them pointing at the source asset, and the client got loose parts).

	Grip (owner asset list 2026-09-25): a Roblox Weapons Kit Tool holds its gun Model plus an invisible Tool.Handle,
	and the kit welds the two together only at equip time, at the gun's "HandleAttachment". When VisualChild picked
	a Model, the Tool's Handle is copied too (Transparency 1), placed on that attachment (else where it is) and
	welded to the part that carries it. WeaponVisuals grips the part named Handle, so the gun sits in the hand the
	way the kit holds it: barrel along the Handle's -Z, top along its +Y.

	WeaponConfig wires the Roblox-owned Weapons Kit guns (creator Roblox, User 1: they load with "Allow Loading Third
	Party Assets" OFF). Each distinct id loads once per server, outside VisualAssetConfig.MaxLoadAttempts. A failed
	load or a refused template keeps that weapon's Part kit. ]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponAssetLoader = {}

local MAX_PARTS = 16
local FOLDER_NAME = "WE_WeaponTemplates"

local loaded: { [number]: Instance | false } = {} -- asset id -> loaded root (false = failed, cached)
local started = false
local published: { [string]: boolean } = {}

local function loadAsset(assetId: number): Instance?
	local cached = loaded[assetId]
	if cached ~= nil then
		return if cached == false then nil else cached :: Instance
	end
	local root: Instance? = nil
	local okI, resI = pcall(function()
		return game:GetService("InsertService"):LoadAsset(assetId)
	end)
	if okI and typeof(resI) == "Instance" then
		root = resI
	else
		local okA, resA = pcall(function()
			return (game:GetService("AssetService") :: any):LoadAssetAsync(assetId)
		end)
		if okA and typeof(resA) == "Instance" then
			root = resA
		end
	end
	loaded[assetId] = root or false
	if root == nil then
		warn(string.format("[WeaponAssetLoader] asset %d did not load (the Part kit stays)", assetId))
	end
	return root
end

local function findTool(root: Instance, toolName: string?): Instance?
	if typeof(toolName) == "string" and toolName ~= "" then
		if root:IsA("Tool") and root.Name == toolName then
			return root
		end
		-- the Tool with exactly this name (a kit Tool holds a Model of the same name: FindFirstChild could stop there)
		for _, d in ipairs(root:GetDescendants()) do -- once per asset load, never per frame
			if d:IsA("Tool") and d.Name == toolName then
				return d
			end
		end
	end
	if root:IsA("Tool") then
		return root
	end
	return root:FindFirstChildWhichIsA("Tool", true)
end

-- effects a gun template never keeps (the client makes its own flash; lights cost phones)
local function isEffect(d: Instance): boolean
	return d:IsA("Beam")
		or d:IsA("ParticleEmitter")
		or d:IsA("Trail")
		or d:IsA("Fire")
		or d:IsA("Smoke")
		or d:IsA("Sparkles")
		or d:IsA("Light")
end

-- Strip code, sounds and effects, make every part a massless visual. Returns the BasePart count.
local function sanitise(model: Instance): number
	local parts = 0
	local beamEnds: { Instance } = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d.Parent == nil then
			continue -- inside something destroyed above
		end
		if d:IsA("Beam") then
			local b = d :: Beam
			local a0, a1 = b.Attachment0, b.Attachment1
			if a0 and a0:IsDescendantOf(model) then
				table.insert(beamEnds, a0)
			end
			if a1 and a1:IsDescendantOf(model) then
				table.insert(beamEnds, a1)
			end
		end
		if d:IsA("LuaSourceContainer") or d:IsA("Sound") or isEffect(d) then
			d:Destroy()
		elseif d:IsA("BasePart") then
			parts += 1
			d.Anchored = false
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Massless = true
			d.CastShadow = false
		end
	end
	-- a flash Beam's end points (kit "MuzzleFlash0/1", off the barrel axis) go with it, so the client's muzzle
	-- search finds the barrel tip
	for _, a in ipairs(beamEnds) do
		if a.Parent ~= nil and #a:GetChildren() == 0 then
			a:Destroy()
		end
	end
	return parts
end

local function folder(): Folder
	local f = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if f and f:IsA("Folder") then
		return f
	end
	local nf = Instance.new("Folder")
	nf.Name = FOLDER_NAME
	nf.Parent = ReplicatedStorage
	return nf
end

--[[ The kit's invisible Tool.Handle → the template's grip part (see the header). body: the gun's main part (the
	source Model's PrimaryPart) when known; the part that carries "HandleAttachment" wins. Adds 1 part. ]]
function WeaponAssetLoader._AddGripHandle(model: Model, kitHandle: BasePart, body: BasePart?)
	local att: Attachment? = nil
	for _, d in ipairs(model:GetDescendants()) do -- once per template, never per frame
		if d:IsA("Attachment") and d.Name == "HandleAttachment" and d.Parent and d.Parent:IsA("BasePart") then
			att = d
			break
		end
	end
	local anchorPart: BasePart? = if att then att.Parent :: BasePart else body
	if anchorPart == nil then
		local best = 0
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				local v = d.Size.X * d.Size.Y * d.Size.Z
				if v > best then
					best = v
					anchorPart = d
				end
			end
		end
	end
	if anchorPart == nil then
		return
	end
	local h = kitHandle:Clone()
	for _, c in ipairs(h:GetChildren()) do
		c:Destroy()
	end
	h.Name = "Handle"
	h.Transparency = 1
	if att then
		h.CFrame = anchorPart.CFrame * att.CFrame -- where the kit's equip weld puts the Handle
	end
	local w = Instance.new("Weld")
	w.Name = "WE_GripWeld"
	w.Part0 = h
	w.Part1 = anchorPart
	w.C0 = h.CFrame:ToObjectSpace(anchorPart.CFrame)
	w.C1 = CFrame.identity
	w.Parent = h
	h.Parent = model
end

-- Build Weapon_<weaponId> from one loaded asset root. Returns the template, or nil and a reason.
function WeaponAssetLoader.BuildTemplate(weaponId: string, root: Instance, toolName: string?, childName: string?): (Model?, string)
	local tool = findTool(root, toolName)
	if tool == nil then
		return nil, "no Tool"
	end
	local model = Instance.new("Model")
	model.Name = "Weapon_" .. weaponId
	local source: Instance = tool
	local gunModel = false
	if typeof(childName) == "string" and childName ~= "" then
		local child = tool:FindFirstChild(childName)
		if child and child:IsA("Model") then
			source = child
			gunModel = true
		end
	end
	-- ONE clone of the source, so joints between its parts are remapped onto the copies
	local copyOrNil: Instance? = source:Clone() -- nil when the source is not Archivable
	if copyOrNil == nil then
		model:Destroy()
		return nil, "not archivable"
	end
	local copy: Instance = copyOrNil
	local body: BasePart? = if copy:IsA("Model") then (copy :: Model).PrimaryPart else nil
	for _, c in ipairs(copy:GetChildren()) do
		if c:IsA("LuaSourceContainer") or c:IsA("Sound") then
			c:Destroy()
		else
			c.Parent = model
		end
	end
	copy:Destroy()
	if gunModel and model:FindFirstChild("Handle") == nil then
		local kitHandle = tool:FindFirstChild("Handle")
		if kitHandle and kitHandle:IsA("BasePart") then
			WeaponAssetLoader._AddGripHandle(model, kitHandle, body)
		end
	end
	local parts = sanitise(model)
	if parts == 0 then
		model:Destroy()
		return nil, "no parts"
	end
	if parts > MAX_PARTS then
		model:Destroy()
		return nil, string.format("%d parts > %d", parts, MAX_PARTS)
	end
	local handle = model:FindFirstChild("Handle")
	if handle and handle:IsA("BasePart") then
		model.PrimaryPart = handle
	end
	return model, "ok"
end

--[[ Load and publish every weapon with VisualAssetId > 0. Idempotent; call from a spawned thread (it yields). ]]
function WeaponAssetLoader.Start(weapons: { [string]: any })
	if started then
		return
	end
	started = true
	local ids: { string } = {}
	for id, def in pairs(weapons) do
		local aid = tonumber(def.VisualAssetId)
		if aid and aid > 0 and aid % 1 == 0 then
			table.insert(ids, id)
		end
	end
	if #ids == 0 then
		return
	end
	table.sort(ids)
	for _, weaponId in ipairs(ids) do
		local def = weapons[weaponId]
		local assetId = tonumber(def.VisualAssetId) :: number
		local root = loadAsset(assetId)
		if root and not published[weaponId] then
			local ok, template, why = pcall(WeaponAssetLoader.BuildTemplate, weaponId, root, def.VisualToolName, def.VisualChild)
			if ok and template then
				local f = folder()
				local old = f:FindFirstChild(template.Name)
				if old then
					old:Destroy()
				end
				template.Parent = f
				published[weaponId] = true
			else
				warn(string.format("[WeaponAssetLoader] %s (asset %d) refused: %s", weaponId, assetId, tostring(if ok then why else template)))
			end
		end
	end
end

return WeaponAssetLoader
