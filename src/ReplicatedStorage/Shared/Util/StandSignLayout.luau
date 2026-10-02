--!strict
--[[ Code Bot board-text (Shaun, phone: "the writing on the upgrade / pass boards is far too small"): THE big phone
	layout of a Supply Depot stand sign (PurchaseStands.BuildSign's SurfaceGui), in canvas pixels of a W x H stud panel at
	PixelsPerStud (MonetizationConfig.PremiumPads.BigSign). Pure (no requires, no Instances): the client module
	StandSignBig applies it and tools/checks/codebot_vNNN.py runs it in Luau to prove minimum text sizes, that no text
	overflows its box and that no two boxes overlap.
	Rows (top -> bottom), every box inside the gold edge (Inset), a Gap between rows:
	  Icon    the round disc, top-left
	  Title   the item name beside it, GothamBlack (bold), left
	  Effect  ONE short effect line (MonetizationConfig.EffectFor), GothamBold, centred, full width
	  Chip    the price / OWNED pill (Price inside it), GothamBlack, centred
	Text sizes are UITextSizeConstraint Min / Max on TextScaled labels (Min = the readable floor the check asserts). ]]

export type Box = { X: number, Y: number, W: number, H: number }
export type TextBox = { X: number, Y: number, W: number, H: number, Max: number, Min: number, Font: string, Align: string }
export type Layout = {
	CanvasW: number,
	CanvasH: number,
	Inset: number,
	Icon: Box,
	IconGlyph: TextBox,
	Title: TextBox,
	Effect: TextBox,
	Chip: Box,
	Price: TextBox, -- relative to Chip
	Corner: number,
	EdgeThickness: number,
}

local StandSignLayout = {}

StandSignLayout.Inset = 12 -- px inside the 6 px gold edge
StandSignLayout.Gap = 6

function StandSignLayout.Big(wStuds: number, hStuds: number, px: number): Layout
	local CW, CH = math.floor(wStuds * px + 0.5), math.floor(hStuds * px + 0.5)
	local I, G = StandSignLayout.Inset, StandSignLayout.Gap
	local iconS = math.floor(CH * 0.27) -- 68 on a 252 canvas
	local titleH = iconS + 4
	local icon = { X = I, Y = I - 2, W = iconS, H = iconS }
	local title = {
		X = I + iconS + 10,
		Y = I - 4,
		W = CW - (I + iconS + 10) - I,
		H = titleH,
		Max = 66,
		Min = 34,
		Font = "GothamBlack",
		Align = "Left",
	}
	local effY = title.Y + titleH + G
	local chipH = math.floor(CH * 0.34) -- 85
	local chipY = CH - I - chipH
	local effect = { X = I, Y = effY, W = CW - 2 * I, H = chipY - G - effY, Max = 54, Min = 34, Font = "GothamBold", Align = "Center" }
	local chipW = math.floor(CW * 0.72)
	local chip = { X = math.floor((CW - chipW) / 2), Y = chipY, W = chipW, H = chipH }
	local price = { X = 14, Y = 6, W = chipW - 28, H = chipH - 12, Max = 64, Min = 38, Font = "GothamBlack", Align = "Center" }
	local glyph = { X = 6, Y = 6, W = iconS - 12, H = iconS - 12, Max = 52, Min = 20, Font = "GothamBlack", Align = "Center" }
	return {
		CanvasW = CW,
		CanvasH = CH,
		Inset = I,
		Icon = icon,
		IconGlyph = glyph,
		Title = title,
		Effect = effect,
		Chip = chip,
		Price = price,
		Corner = 16,
		EdgeThickness = 6,
	}
end

return StandSignLayout
