--!strict
--[[
	NationFlag (nations spec section 2 Server, lane B): the owner's chosen flag on their OWN base.

	Two flag parts per plot, both built by other modules and only reshaped + dressed here (MapSetup is never edited;
	spec R7). The work is idempotent, so every OnPlotReady may call ApplyPlot again:
	  ParadeFlag   Bases.PlotN.LayoutGround.ParadeFlag (MapSetup). Turned to 6 x 4.5 x 0.14 so its faces look down
	               the plot's +Z axis (the main gate), hoist next to the FlagPole, fly towards plot +X.
	  HQ flag      Bases.PlotN.CommandCenter (plinth) > WE_Building (HollowBuildingBuilder, StructureId
	               "CommandCenter") > Flag. Trimmed to 0.12 x 3.6 x 4.8 (4:3) with the hoist kept at its pole. The
	               building is rebuilt on every level change, so the plot folder's DescendantAdded re-dresses the new
	               flag (one Name compare per added instance; no scans, no loops).
	Each flag part gets the CollectionService tag WE_NationFlag, the attribute WE_NationShaped and exactly two
	Texture children (WE_NationTexA / WE_NationTexB) on the two faces of its thinnest axis
	(NationTexture.ThinFaces). A Texture shows one atlas cell (NationTexture.Source / TextureProps).
	  * Showing a nation with art: Texture = the atlas image, cropped; the part takes the nation's banner colour
	    (seen on the thin edges).
	  * Showing a nation without art (atlas id 0): Texture blank and Transparency 1; the part takes the banner colour.
	  * Plain (no owner, NationId nil / "NEUTRAL", feature hidden for this owner): the part's original army green,
	    Textures blank and Transparency 1. Parts are never destroyed.
	WE_NationShown on the part is the idempotence key (shown id, face size, image): an unchanged view writes nothing.

	The flagpole prompt (WE_PanelPrompt on FlagBase; WE_OpenPanel "Nation", WE_OpenTab "flagpole", "Change flag",
	hold 0, range 12) exists only while the plot has an owner AND the view says Show (nations art ready, or the
	owner is an admin; lead decision 6). WE_PanelPrompt is in HudConfig.ActionLane.OwnerOnlyPromptNames, so other
	players' clients disable it locally; the server Triggered handler checks the owner again.

	Never here (CLAUDE.md nation rule): GUI text on the flag (flags are Textures only), lights or glowing materials,
	anything at the gate (strike fire spawns there; the flags stand at the parade ground and the HQ roof, 140+ studs
	from the gate), and no effect, text or rule that names a nation.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared -- replicated by Rojo before any server script runs (no unbounded wait)
local NationConfig = require(Shared.Configs.NationConfig)
local NationTexture = require(Shared.Util.NationTexture)

local NationFlag = {}

NationFlag.Tag = "WE_NationFlag"

export type View = {
	OwnerUserId: number?, -- nil: nobody owns the plot (plain flags, no prompt)
	NationId: string?, -- the owner's saved id: a NationConfig id, NationConfig.NeutralId or nil
	Show: boolean, -- the owner may see nations here (NationConfig.Enabled and (art ready or admin))
}

type PlotState = {
	Folder: Instance?,
	AddedConn: RBXScriptConnection?,
	View: View?,
	Prompt: ProximityPrompt?,
	PromptConn: RBXScriptConnection?,
}

local PARADE_SIZE = Vector3.new(6, 4.5, 0.14) -- 4:3, faces along the pole's local Z (plot +Z = main gate)
local HQ_SIZE = Vector3.new(0.12, 3.6, 4.8) -- 4:3, keeps the builder's orientation (thin along X)
local POLE_GAP = 0.05 -- studs between the pole's surface and the hoist edge
local TEXTURE_NAMES = { "WE_NationTexA", "WE_NationTexB" }
local PROMPT_NAME = "WE_PanelPrompt" -- HudConfig.ActionLane.OwnerOnlyPromptNames
local PROMPT_RANGE = 12
local PLAIN_COLOR_ATTR = "WE_NationPlainColor"
local SHOWN_ATTR = "WE_NationShown"

local plots: { [number]: PlotState } = {}
local onPromptTriggered: ((Player, number) -> ())? = nil

---------------------------------------------------------------------------------------------------------------
-- lookups (targeted FindFirstChild only; the plot folder is never scanned)
---------------------------------------------------------------------------------------------------------------

local function findPlotFolder(plotId: number): Instance?
	local setup = Workspace:FindFirstChild("WarEmpireSetup")
	local bases = setup and setup:FindFirstChild("Bases")
	local folder = bases and bases:FindFirstChild("Plot" .. tostring(plotId))
	if folder and folder:IsA("Folder") then
		return folder
	end
	return nil
end

local function childPart(parent: Instance?, name: string): BasePart?
	local p = parent and parent:FindFirstChild(name)
	if p and p:IsA("BasePart") then
		return p
	end
	return nil
end

local function isHqBuilding(inst: Instance): boolean
	return inst.Name == "WE_Building" and inst:IsA("Model") and inst:GetAttribute("StructureId") == "CommandCenter"
end

local function hqFlagOf(folder: Instance): BasePart?
	local building = folder:FindFirstChild("CommandCenter")
	local model = building and building:FindFirstChild("WE_Building")
	if model and isHqBuilding(model) then
		return childPart(model, "Flag")
	end
	return nil
end

---------------------------------------------------------------------------------------------------------------
-- shape (idempotent: the new CFrame is computed from the pole, never from the flag's previous shape)
---------------------------------------------------------------------------------------------------------------

local function markShaped(flag: BasePart)
	if flag:GetAttribute(PLAIN_COLOR_ATTR) == nil then
		flag:SetAttribute(PLAIN_COLOR_ATTR, flag.Color) -- the builder's army green, restored when nothing shows
	end
	if flag:GetAttribute("WE_NationShaped") ~= true then
		flag:SetAttribute("WE_NationShaped", true)
	end
	-- never a target: shots, hit effects and touches pass through the cloth (CLAUDE.md nation rule)
	if flag.CanQuery then
		flag.CanQuery = false
	end
	if flag.CanTouch then
		flag.CanTouch = false
	end
	if not CollectionService:HasTag(flag, NationFlag.Tag) then
		CollectionService:AddTag(flag, NationFlag.Tag)
	end
end

local function sameRotation(a: CFrame, b: CFrame): boolean
	return a.XVector:Dot(b.XVector) > 1 - 1e-6 and a.YVector:Dot(b.YVector) > 1 - 1e-6
end

-- writes only what differs (a re-apply of the same shape changes nothing)
local function setShape(flag: BasePart, size: Vector3, cf: CFrame)
	if (flag.Size - size).Magnitude > 1e-4 then
		flag.Size = size
	end
	if (flag.Position - cf.Position).Magnitude > 1e-3 or not sameRotation(flag.CFrame, cf) then
		flag.CFrame = cf
	end
end

-- Parade flag: 6 x 4.5 x 0.14 on the pole's +X side at its current height, faces along the pole's local Z.
local function shapeParade(flag: BasePart, pole: BasePart)
	local rel = pole.CFrame:PointToObjectSpace(flag.Position)
	local side = pole.Size.X * 0.5 + POLE_GAP + PARADE_SIZE.X * 0.5
	setShape(flag, PARADE_SIZE, pole.CFrame * CFrame.new(side, rel.Y, 0))
	markShaped(flag)
end

-- HQ flag: 0.12 x 3.6 x 4.8, same orientation and height, hoist edge POLE_GAP from its pole.
local function shapeHq(flag: BasePart)
	local model = flag.Parent
	local pole = childPart(model, "FlagPole")
	local cf = flag.CFrame
	if pole then
		local rel = cf:PointToObjectSpace(pole.Position)
		local sign = if rel.Z >= 0 then 1 else -1
		local hoist = rel.Z - sign * (pole.Size.X * 0.5 + POLE_GAP)
		cf = cf * CFrame.new(0, 0, hoist - sign * HQ_SIZE.Z * 0.5)
	end
	setShape(flag, HQ_SIZE, cf)
	markShaped(flag)
end

---------------------------------------------------------------------------------------------------------------
-- dress (two Textures; the part colour)
---------------------------------------------------------------------------------------------------------------

local function ensureTextures(flag: BasePart): { Texture }
	local faceA, faceB = NationTexture.ThinFaces(flag.Size.X, flag.Size.Y, flag.Size.Z)
	local faces = { faceA, faceB }
	local out: { Texture } = {}
	for i, name in ipairs(TEXTURE_NAMES) do
		local t = flag:FindFirstChild(name)
		local tex: Texture
		if t and t:IsA("Texture") then
			tex = t
		else
			tex = Instance.new("Texture")
			tex.Name = name
			tex.Texture = ""
			tex.Transparency = 1
			tex.Parent = flag
		end
		local face = (Enum.NormalId :: any)[faces[i]]
		if tex.Face ~= face then
			tex.Face = face
		end
		out[i] = tex
	end
	return out
end

local function viewNation(view: View?): NationConfig.NationDef?
	if view == nil or view.OwnerUserId == nil or not view.Show then
		return nil
	end
	return NationConfig.Get(view.NationId)
end

local function dress(flag: BasePart, view: View?)
	local textures = ensureTextures(flag)
	local def = viewNation(view)
	local _, _, w, h = NationTexture.ThinFaces(flag.Size.X, flag.Size.Y, flag.Size.Z)
	local src = if def then NationTexture.Source(def.Id) else nil
	local props = if src then NationTexture.TextureProps(w, h, src.Rect) else nil
	local image = if src and props then src.Image else ""
	local key = string.format("%s|%.2fx%.2f|%s", if def then def.Id else "-", w, h, image)
	if flag:GetAttribute(SHOWN_ATTR) == key then
		return -- nothing changed: no writes
	end
	local plain = flag:GetAttribute(PLAIN_COLOR_ATTR)
	local color = if def then def.Color elseif typeof(plain) == "Color3" then plain else flag.Color
	if flag.Color ~= color then
		flag.Color = color
	end
	for _, tex in ipairs(textures) do
		if props and image ~= "" then
			tex.Texture = image
			tex.StudsPerTileU = props.StudsPerTileU
			tex.StudsPerTileV = props.StudsPerTileV
			tex.OffsetStudsU = props.OffsetStudsU
			tex.OffsetStudsV = props.OffsetStudsV
			tex.Transparency = 0
		else
			tex.Texture = ""
			tex.Transparency = 1
		end
	end
	flag:SetAttribute(SHOWN_ATTR, key)
end

---------------------------------------------------------------------------------------------------------------
-- flagpole prompt (owner-only; created only while the view says Show)
---------------------------------------------------------------------------------------------------------------

local function dropPrompt(st: PlotState)
	if st.PromptConn then
		st.PromptConn:Disconnect()
		st.PromptConn = nil
	end
	if st.Prompt then
		st.Prompt:Destroy()
		st.Prompt = nil
	end
end

local function syncPrompt(plotId: number, st: PlotState, base: BasePart?)
	local view = st.View
	local want = base ~= nil and view ~= nil and view.OwnerUserId ~= nil and view.Show
	if not want or base == nil then
		dropPrompt(st)
		return
	end
	if st.Prompt and st.Prompt.Parent == base then
		return
	end
	dropPrompt(st)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = PROMPT_NAME
	prompt.ActionText = "Change flag"
	prompt.ObjectText = "Your flag"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = PROMPT_RANGE
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt:SetAttribute("WE_OpenPanel", "Nation")
	prompt:SetAttribute("WE_OpenTab", "flagpole")
	prompt.Parent = base
	st.Prompt = prompt
	st.PromptConn = prompt.Triggered:Connect(function(who: Player)
		local cur = plots[plotId]
		local owner = cur and cur.View and cur.View.OwnerUserId
		if owner == nil or who.UserId ~= owner then
			return -- owner-only (other clients disable the prompt locally; checked again here)
		end
		if onPromptTriggered then
			onPromptTriggered(who, plotId)
		end
	end)
end

---------------------------------------------------------------------------------------------------------------
-- binding
---------------------------------------------------------------------------------------------------------------

local function applyHq(plotId: number, flag: BasePart)
	local st = plots[plotId]
	shapeHq(flag)
	dress(flag, st and st.View)
end

local function bind(plotId: number): (PlotState?, Instance?)
	local folder = findPlotFolder(plotId)
	local st = plots[plotId]
	if not st then
		st = {}
		plots[plotId] = st
	end
	local state = st :: PlotState
	if folder == nil then
		return state, nil
	end
	if state.Folder ~= folder then
		if state.AddedConn then
			state.AddedConn:Disconnect()
		end
		dropPrompt(state)
		state.Folder = folder
		-- the Command Center is rebuilt on every level change: dress the new flag as soon as its model arrives
		state.AddedConn = folder.DescendantAdded:Connect(function(inst: Instance)
			if inst.Name ~= "WE_Building" or not isHqBuilding(inst) then
				return
			end
			local flag = childPart(inst, "Flag")
			if flag then
				applyHq(plotId, flag)
			end
		end)
	end
	return state, folder
end

--[[ Show `view` on plot `plotId` (idempotent; call it on every OnPlotReady and after every accepted pick).
	Returns the flag parts it dressed (0-2). Never yields. ]]
function NationFlag.ApplyPlot(plotId: number, view: View): { BasePart }
	local st, folder = bind(plotId)
	local done: { BasePart } = {}
	if st == nil then
		return done
	end
	st.View = { OwnerUserId = view.OwnerUserId, NationId = view.NationId, Show = view.Show == true }
	if folder == nil then
		dropPrompt(st)
		return done
	end
	local ground = folder:FindFirstChild("LayoutGround")
	local parade = childPart(ground, "ParadeFlag")
	local pole = childPart(ground, "FlagPole")
	if parade and pole then
		shapeParade(parade, pole)
		dress(parade, st.View)
		table.insert(done, parade)
	end
	local hq = hqFlagOf(folder)
	if hq then
		applyHq(plotId, hq)
		table.insert(done, hq)
	end
	syncPrompt(plotId, st, childPart(ground, "FlagBase"))
	return done
end

--[[ The owner left / the plot was released: plain army green, no prompt. Parts and Textures stay (blank). ]]
function NationFlag.ResetPlot(plotId: number)
	NationFlag.ApplyPlot(plotId, { OwnerUserId = nil, NationId = nil, Show = false })
end

--[[ The owner id the plot's flags were last dressed for (nil = none). ]]
function NationFlag.OwnerOf(plotId: number): number?
	local st = plots[plotId]
	return if st and st.View then st.View.OwnerUserId else nil
end

--[[ cb(owner, plotId) when the plot's owner triggers the flagpole prompt (analytics only; the client opens the
	picker itself through WE_OpenPanel). ]]
function NationFlag.SetPromptHandler(cb: (Player, number) -> ())
	onPromptTriggered = cb
end

return NationFlag
