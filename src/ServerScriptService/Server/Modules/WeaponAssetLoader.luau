--!strict
--[[ W2 Combat Core (contracts §3.8, asset shortlist §6.2 C4): optional gun meshes from verified store asset ids.

	CombatService.Init task.spawns WeaponAssetLoader.Start once. For every WeaponConfig weapon with VisualAssetId > 0
	it loads each DISTINCT asset id once (InsertService:LoadAsset, then AssetService:LoadAssetAsync; each pcall'd;
	failures are cached and never retried), takes Tool[VisualToolName] (or the first Tool), then its Model child
	VisualChild (or the Tool's own parts), and publishes a sanitised copy as Model "Weapon_<WeaponId>" in
	ReplicatedStorage.WE_WeaponTemplates (created here). The client (WeaponVisuals) uses that template when present
	and its own Part kit otherwise.

	Sanitising: every Script / LocalScript / ModuleScript and Sound is destroyed (Attachments, Beams, WeldConstraints
	and Motor6Ds stay); every BasePart is unanchored, CanCollide / CanQuery / CanTouch false, Massless, no shadow.
	A template with more than MAX_PARTS BaseParts is refused.

	Today every VisualAssetId is 0 (the owner has not taken the Weapons Kit items and "Allow Loading Third Party
	Assets" stays OFF), so Start does nothing. Dropping verified ids into WeaponConfig later needs no code change. ]]

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
		local named = root:FindFirstChild(toolName, true)
		if named and named:IsA("Tool") then
			return named
		end
	end
	if root:IsA("Tool") then
		return root
	end
	return root:FindFirstChildWhichIsA("Tool", true)
end

-- Strip code and sounds, make every part a massless visual. Returns the BasePart count.
local function sanitise(model: Instance): number
	local parts = 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("LuaSourceContainer") or d:IsA("Sound") then
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

-- Build Weapon_<weaponId> from one loaded asset root. Returns the template, or nil and a reason.
function WeaponAssetLoader.BuildTemplate(weaponId: string, root: Instance, toolName: string?, childName: string?): (Model?, string)
	local tool = findTool(root, toolName)
	if tool == nil then
		return nil, "no Tool"
	end
	local model = Instance.new("Model")
	model.Name = "Weapon_" .. weaponId
	local source: Instance = tool
	if typeof(childName) == "string" and childName ~= "" then
		local child = tool:FindFirstChild(childName)
		if child and child:IsA("Model") then
			source = child
		end
	end
	for _, c in ipairs(source:GetChildren()) do
		if not (c:IsA("LuaSourceContainer") or c:IsA("Sound")) then
			c:Clone().Parent = model
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
