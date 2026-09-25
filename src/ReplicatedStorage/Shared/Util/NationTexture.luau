--!strict
--[[
	NationTexture: pure maths for showing a nation's flag (nations spec, lane A0). Configs only: no services, no
	Instances, never yields, no allocation beyond the returned tables. Headless-tested.

	One source for
	  picker (client)  ImageLabel.Image = Source(id).Image, ImageRectOffset = (Rect.X, Rect.Y), ImageRectSize = (Rect.W, Rect.H)
	  world (server)   one Texture per flag face: Texture = Source(id).Image, then TextureProps(faceW, faceH, Rect)

	Atlas layout (NationConfig.Atlas, drawn by tools/gen_nation_flags.py): 1024 x 512, 9 x 6 cells of 112 x 84, each
	flag 104 x 78 centred in its cell (edge-extended gutter 4 px left/right, 3 px top/bottom).

	Texture crop: a Texture tiles its whole image every StudsPerTileU x StudsPerTileV studs. Scaling the image so the
	flag's W x H pixels span the face exactly, then offsetting by the flag's pixel position, shows only that flag:
	  su = faceW / W, sv = faceH / H (studs per pixel)
	  StudsPerTileU = SheetW * su, StudsPerTileV = SheetH * sv
	  OffsetStudsU  = OffsetSignU * X * su, OffsetStudsV = OffsetSignV * Y' * sv (wrapped into [0, tile))
	  Y' = Y, or SheetH - Y - H when NationConfig.Atlas.VFromBottom
	The default signs assume "a larger offset shows image content further right / lower" (the face's top-left shows
	image pixel (X, Y)). The Studio atlas-crop test confirms or flips them in NationConfig.Atlas; nothing here changes.
	The back face is not mirrored: from behind, the hoist appears at the fly end (accepted, spec section 6).
]]

local Configs = script.Parent.Parent.Configs -- ReplicatedStorage.Shared is replicated before any script runs
local NationConfig = require(Configs.NationConfig)
local NationFlagIds = require(Configs.NationFlagIds)

local A = NationConfig.Atlas

export type Rect = {
	Atlas: string, -- AtlasGroup, or "" for a per-flag image
	X: number, -- flag's top-left pixel in the image
	Y: number,
	W: number, -- flag size in pixels
	H: number,
	SheetW: number, -- whole image size in pixels
	SheetH: number,
}

export type TextureProps = {
	StudsPerTileU: number,
	StudsPerTileV: number,
	OffsetStudsU: number,
	OffsetStudsV: number,
}

export type Source = {
	Image: string, -- "rbxassetid://<id>"
	Rect: Rect,
	PerFlag: boolean, -- true: NationFlagIds.Flags[id] (whole image), false: an atlas cell
}

local NationTexture = {}

local function validId(v: any): boolean
	return typeof(v) == "number" and v > 0 and v % 1 == 0 and v < 2 ^ 53
end

local function finitePositive(v: any): boolean
	return typeof(v) == "number" and v == v and v > 0 and v < math.huge
end

-- Atlas cell of a nation: (atlasKey, px, py, w, h) of the flag's pixels (gutter excluded), or nil, 0, 0, 0, 0 for
-- NEUTRAL, unknown, denied or OwnerReview-off ids.
function NationTexture.CellRect(id: any): (string?, number, number, number, number)
	local n = NationConfig.Get(id)
	if not n then
		return nil, 0, 0, 0, 0
	end
	local cell = n.AtlasCell
	if typeof(cell) ~= "number" or cell % 1 ~= 0 or cell < 0 or cell >= A.Columns * A.Rows then
		return nil, 0, 0, 0, 0
	end
	local col = cell % A.Columns
	local row = math.floor(cell / A.Columns)
	local gutterX = math.floor((A.CellW - A.FlagW) / 2)
	local gutterY = math.floor((A.CellH - A.FlagH) / 2)
	return n.AtlasGroup, col * A.CellW + gutterX, row * A.CellH + gutterY, A.FlagW, A.FlagH
end

-- CellRect as a Rect (with the atlas size), or nil.
function NationTexture.Rect(id: any): Rect?
	local key, x, y, w, h = NationTexture.CellRect(id)
	if key == nil then
		return nil
	end
	return { Atlas = key, X = x, Y = y, W = w, H = h, SheetW = A.Width, SheetH = A.Height }
end

-- The whole-image rect of a per-flag PNG (gen_nation_flags.py --per-flag).
function NationTexture.PerFlagRect(): Rect
	return { Atlas = "", X = 0, Y = 0, W = A.PerFlagW, H = A.PerFlagH, SheetW = A.PerFlagW, SheetH = A.PerFlagH }
end

-- Image + rect to show for a nation, or nil when no art is wired for it (caller shows the banner colour).
-- A per-flag id (NationFlagIds.Flags) wins over the atlas.
function NationTexture.Source(id: any): Source?
	local n = NationConfig.Get(id)
	if not n then
		return nil
	end
	local own = NationFlagIds.Flags[n.Id]
	if validId(own) then
		return { Image = string.format("rbxassetid://%d", own), Rect = NationTexture.PerFlagRect(), PerFlag = true }
	end
	local rect = NationTexture.Rect(n.Id)
	if rect == nil then
		return nil
	end
	local atlasId = NationFlagIds.Atlas[rect.Atlas]
	if not validId(atlasId) then
		return nil
	end
	return { Image = string.format("rbxassetid://%d", atlasId), Rect = rect, PerFlag = false }
end

-- True when every nation the picker may show has art (NationConfig.LiveRequiresArt).
function NationTexture.ArtReady(): boolean
	for _, n in ipairs(NationConfig.Nations) do
		if NationConfig.Get(n.Id) and NationTexture.Source(n.Id) == nil then
			return false
		end
	end
	return true
end

-- Texture properties that show exactly `rect` on a faceW x faceH face (studs), or nil for bad input.
function NationTexture.TextureProps(faceW: number, faceH: number, rect: Rect): TextureProps?
	if not (finitePositive(faceW) and finitePositive(faceH)) then
		return nil
	end
	if not (finitePositive(rect.W) and finitePositive(rect.H) and finitePositive(rect.SheetW) and finitePositive(rect.SheetH)) then
		return nil
	end
	if rect.X < 0 or rect.Y < 0 or rect.X + rect.W > rect.SheetW or rect.Y + rect.H > rect.SheetH then
		return nil
	end
	local su = faceW / rect.W
	local sv = faceH / rect.H
	local tileU = rect.SheetW * su
	local tileV = rect.SheetH * sv
	local y = if A.VFromBottom then rect.SheetH - rect.Y - rect.H else rect.Y
	local offU = (A.OffsetSignU * rect.X * su) % tileU
	local offV = (A.OffsetSignV * y * sv) % tileV
	return { StudsPerTileU = tileU, StudsPerTileV = tileV, OffsetStudsU = offU, OffsetStudsV = offV }
end

-- The two faces of a part's thinnest axis and their (width, height) in studs, as Enum.NormalId names:
-- Z thinnest -> Front/Back (W = X, H = Y); X thinnest -> Left/Right (W = Z, H = Y); Y thinnest -> Top/Bottom (W = X, H = Z).
function NationTexture.ThinFaces(sx: number, sy: number, sz: number): (string, string, number, number)
	if sz <= sx and sz <= sy then
		return "Front", "Back", sx, sy
	elseif sx <= sy then
		return "Left", "Right", sz, sy
	end
	return "Top", "Bottom", sx, sz
end

return NationTexture
