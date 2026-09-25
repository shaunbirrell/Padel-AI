--!strict
--[[
	NationConfig: the country a player chooses (cosmetic only: a flag on their own base, a code in the player list).
	Nations spec (fb2/spec_nations.md, lane A0). Pure data + pure helpers: no services, no Instances, never yields.

	Roster (200): the 193 UN members + Holy See (VA) + Palestine (PS) + Taiwan (TW) + Kosovo (XK) + England,
	Scotland and Wales (GB-ENG / GB-SCT / GB-WLS). Ids are ISO 3166-1 alpha-2 (the GB-* ids are ISO 3166-2).
	"No flag" is stored as the value NeutralId ("NEUTRAL"), never as nil (nil = never picked).
	Rules (CLAUDE.md): current national flags only. Never historical, regime, separatist, extremist or party flags,
	military insignia or dependent territories. tools/BuyPathStatic.py checks every Id against the allowlist
	(UN members + the 7 above + NEUTRAL) and the Denied list below.

	Flag art: lipis/flag-icons (MIT, pinned in tools/gen_nation_flags.py), rendered 4:3 into 7 atlases of 1024x512
	(assets/flags/atlas_<AtlasGroup>.png). Each nation has one cell (AtlasGroup, AtlasCell); Shared/Util/NationTexture
	turns a cell into the picker's ImageRect and the world Texture's StudsPerTile / OffsetStuds. Uploaded image ids live
	in NationFlagIds.luau (written by tools/wire-nation-flag-ids.py). Changing a nation's AtlasGroup / AtlasCell means
	re-running the generator and re-uploading that atlas.
	"Review" holds the flags with script or weapons in the official design (moderation false-positive risk), so a
	rejected Review upload never blanks a whole region.

	Color = banner colour (main flag colour): territory rings, contested pulse, capture HUD, and the flag part's colour
	while no art is uploaded.
]]

export type Region = "Europe" | "Americas" | "Asia" | "Africa" | "MiddleEast" | "Oceania"
export type AtlasGroup = Region | "Review"
export type NationDef = {
	Id: string,
	Name: string,
	Short: string, -- utf8.len <= 14 (picker tile, Settings row, "Flag raised: <Short>")
	Region: Region, -- picker tab
	Color: Color3,
	AtlasGroup: AtlasGroup, -- which atlas image holds the flag
	AtlasCell: number, -- 0-based cell in that atlas (row-major, Atlas.Columns per row)
	Aliases: { string }?, -- extra search words (Turkey, Ivory Coast ...)
	Cutout: boolean?, -- the flag is not a rectangle (Nepal): transparent pixels outside its shape
}

local NationConfig = {
	Enabled = true,
	NeutralId = "NEUTRAL",
	NeutralLabel = "No flag",

	-- Owner decisions: on by default. false hides the nation from the picker and makes Get return nil, so the
	-- ProfileSchema sanitiser clears it and those players get a free re-pick at their next join.
	OwnerReview = {
		TW = true,
		XK = true,
		PS = true,
		["GB-ENG"] = true,
		["GB-SCT"] = true,
		["GB-WLS"] = true,
	} :: { [string]: boolean },

	-- Changing nation (server-enforced, no cost)
	FreeRepickSeconds = 600, -- free window after the first real pick (starts only while NationFreeUntil == 0)
	FreeRepickMax = 5, -- at most this many changes inside the free window
	ChangeCooldownSeconds = 86400, -- then one change per 24 h
	MaxJoinPrompts = 3, -- LATER re-offers the picker at the next join, at most this many times
	RequestRate = 0.5, -- RateLimitService tokens / s for RequestSetNation
	RequestBurst = 3,

	-- Toggles
	SuggestPreselect = false, -- the IP-based suggestion is a badged tile only, never selected (privacy, spec R3)
	LiveRequiresArt = true, -- the picker opens by itself for non-admins only once every atlas id is wired
	OutpostFlags = false, -- outposts keep banner colour only at launch (policy caution around territory, spec R6)
	PlayerListColumn = true, -- leaderstats "Nation" column (added after Cash and Gold)
	PlayerListColumnName = "Nation",
	PlayerListEmoji = false, -- flip only after the emoji device test; the column shows Code(id) until then
	NeutralCode = "-", -- player-list text for "No flag"
	ContestMinColorDistance = 0.25, -- RGB distance (0..1.73) below which the contested pulse uses amber

	-- Picker
	Featured = { "US", "GB", "BR", "PH", "ID", "MX", "CA", "AU", "DE", "FR", "IE" }, -- "For you" tab after the suggestion
	RegionOrder = { "Europe", "Americas", "Asia", "Africa", "MiddleEast", "Oceania" } :: { Region },
	RegionLabel = {
		Europe = "Europe",
		Americas = "Americas",
		Asia = "Asia",
		Africa = "Africa",
		MiddleEast = "Mid East",
		Oceania = "Oceania",
	} :: { [string]: string },

	-- Atlas layout (tools/gen_nation_flags.py draws exactly this; NationTexture reads it). 9 x 6 cells of 112 x 84 px
	-- in a 1024 x 512 image. Each flag is 104 x 78 (4:3), centred in its cell with an edge-extended gutter of 4 px
	-- left/right and 3 px top/bottom (84 - 78 = 6), so filtering at the flag's edge never samples a neighbour.
	Atlas = {
		Groups = { "Europe", "Americas", "Asia", "Africa", "MiddleEast", "Oceania", "Review" } :: { AtlasGroup },
		Width = 1024,
		Height = 512,
		Columns = 9,
		Rows = 6,
		CellW = 112,
		CellH = 84,
		FlagW = 104,
		FlagH = 78,
		PerFlagW = 256, -- per-flag fallback PNGs (gen_nation_flags.py --per-flag): the whole image is the flag
		PerFlagH = 192,
		-- World Texture crop convention. Set by the 5-minute Studio atlas-crop test (spec section 3): if the flag shows
		-- the wrong cell, flip OffsetSignU / OffsetSignV to -1 and/or VFromBottom to true (see NationTexture.TextureProps).
		OffsetSignU = 1,
		OffsetSignV = 1,
		VFromBottom = false,
	},

	-- Never add these (historical / regime / war flags, military insignia, extremist or party flags, separatist or
	-- unrecognised entities, dependent territories). Get never returns them; BuyPathStatic fails the build if any appears.
	Denied = { "GB-NIR", "EH", "ES-CT", "ES-PV", "ARAB", "EU", "UN", "XX", "HK", "MO", "CEFTA" },

	Nations = {
		{ Id = "AD", Name = "Andorra", Short = "Andorra", Region = "Europe", Color = Color3.fromRGB(16, 16, 176), AtlasGroup = "Europe", AtlasCell = 0 },
		{ Id = "AE", Name = "United Arab Emirates", Short = "UAE", Region = "MiddleEast", Color = Color3.fromRGB(240, 16, 16), AtlasGroup = "MiddleEast", AtlasCell = 0, Aliases = { "Emirates" } },
		{ Id = "AF", Name = "Afghanistan", Short = "Afghanistan", Region = "Asia", Color = Color3.fromRGB(16, 144, 16), AtlasGroup = "Review", AtlasCell = 0 },
		{ Id = "AG", Name = "Antigua and Barbuda", Short = "Antigua", Region = "Americas", Color = Color3.fromRGB(208, 16, 48), AtlasGroup = "Americas", AtlasCell = 0 },
		{ Id = "AL", Name = "Albania", Short = "Albania", Region = "Europe", Color = Color3.fromRGB(240, 16, 16), AtlasGroup = "Europe", AtlasCell = 1 },
		{ Id = "AM", Name = "Armenia", Short = "Armenia", Region = "Asia", Color = Color3.fromRGB(16, 48, 176), AtlasGroup = "Asia", AtlasCell = 0 },
		{ Id = "AO", Name = "Angola", Short = "Angola", Region = "Africa", Color = Color3.fromRGB(240, 16, 16), AtlasGroup = "Review", AtlasCell = 1 },
		{ Id = "AR", Name = "Argentina", Short = "Argentina", Region = "Americas", Color = Color3.fromRGB(112, 176, 208), AtlasGroup = "Americas", AtlasCell = 1 },
		{ Id = "AT", Name = "Austria", Short = "Austria", Region = "Europe", Color = Color3.fromRGB(208, 16, 48), AtlasGroup = "Europe", AtlasCell = 2 },
		{ Id = "AU", Name = "Australia", Short = "Australia", Region = "Oceania", Color = Color3.fromRGB(16, 16, 144), AtlasGroup = "Oceania", AtlasCell = 0 },
		{ Id = "AZ", Name = "Azerbaijan", Short = "Azerbaijan", Region = "Asia", Color = Color3.fromRGB(16, 176, 240), AtlasGroup = "Asia", AtlasCell = 1 },
		{ Id = "BA", Name = "Bosnia and Herzegovina", Short = "Bosnia", Region = "Europe", Color = Color3.fromRGB(16, 16, 144), AtlasGroup = "Europe", AtlasCell = 3 },
		{ Id = "BB", Name = "Barbados", Short = "Barbados", Region = "Americas", Color = Color3.fromRGB(16, 48, 112), AtlasGroup = "Review", AtlasCell = 2 },
		{ Id = "BD", Name = "Bangladesh", Short = "Bangladesh", Region = "Asia", Color = Color3.fromRGB(16, 112, 80), AtlasGroup = "Asia", AtlasCell = 2 },
		{ Id = "BE", Name = "Belgium", Short = "Belgium", Region = "Europe", Color = Color3.fromRGB(240, 16, 48), AtlasGroup = "Europe", AtlasCell = 4 },
		{ Id = "BF", Name = "Burkina Faso", Short = "Burkina Faso", Region = "Africa", Color = Color3.fromRGB(208, 16, 16), AtlasGroup = "Africa", AtlasCell = 0 },
		{ Id = "BG", Name = "Bulgaria", Short = "Bulgaria", Region = "Europe", Color = Color3.fromRGB(16, 144, 112), AtlasGroup = "Europe", AtlasCell = 5 },
		{ Id = "BH", Name = "Bahrain", Short = "Bahrain", Region = "MiddleEast", Color = Color3.fromRGB(208, 16, 48), AtlasGroup = "MiddleEast", AtlasCell = 1 },
		{ Id = "BI", Name = "Burundi", Short = "Burundi", Region = "Africa", Color = Color3.fromRGB(208, 16, 48), AtlasGroup = "Africa", AtlasCell = 1 },
		{ Id = "BJ", Name = "Benin", Short = "Benin", Region = "Africa", Color = Color3.fromRGB(48, 144, 16), AtlasGroup = "Africa", AtlasCell = 2 },
		{ Id = "BN", Name = "Brunei", Short = "Brunei", Region = "Asia", Color = Color3.fromRGB(240, 240, 16), AtlasGroup = "Review", AtlasCell = 3 },
		{ Id = "BO", Name = "Bolivia", Short = "Bolivia", Region = "Americas", Color = Color3.fromRGB(208, 48, 16), AtlasGroup = "Americas", AtlasCell = 2 },
		{ Id = "BR", Name = "Brazil", Short = "Brazil", Region = "Americas", Color = Color3.fromRGB(48, 144, 80), AtlasGroup = "Americas", AtlasCell = 3 },
		{ Id = "BS", Name = "Bahamas", Short = "Bahamas", Region = "Americas", Color = Color3.fromRGB(16, 208, 208), AtlasGroup = "Americas", AtlasCell = 4 },
		{ Id = "BT", Name = "Bhutan", Short = "Bhutan", Region = "Asia", Color = Color3.fromRGB(240, 208, 48), AtlasGroup = "Asia", AtlasCell = 3 },
		{ Id = "BW", Name = "Botswana", Short = "Botswana", Region = "Africa", Color = Color3.fromRGB(16, 208, 240), AtlasGroup = "Africa", AtlasCell = 3 },
		{ Id = "BY", Name = "Belarus", Short = "Belarus", Region = "Europe", Color = Color3.fromRGB(208, 16, 48), AtlasGroup = "Europe", AtlasCell = 6 },
		{ Id = "BZ", Name = "Belize", Short = "Belize", Region = "Americas", Color = Color3.fromRGB(16, 48, 144), AtlasGroup = "Americas", AtlasCell = 5 },
		{ Id = "CA", Name = "Canada", Short = "Canada", Region = "Americas", Color = Color3.fromRGB(208, 48, 16), AtlasGroup = "Americas", AtlasCell = 6 },
		{ Id = "CD", Name = "DR Congo", Short = "DR Congo", Region = "Africa", Color = Color3.fromRGB(16, 112, 240), AtlasGroup = "Africa", AtlasCell = 4, Aliases = { "Congo", "DRC" } },
		{ Id = "CF", Name = "Central African Republic", Short = "C. African Rep", Region = "Africa", Color = Color3.fromRGB(240, 240, 16), AtlasGroup = "Africa", AtlasCell = 5 },
		{ Id = "CG", Name = "Congo", Short = "Congo", Region = "Africa", Color = Color3.fromRGB(240, 240, 16), AtlasGroup = "Africa", AtlasCell = 6 },
		{ Id = "CH", Name = "Switzerland", Short = "Switzerland", Region = "Europe", Color = Color3.fromRGB(240, 16, 16), AtlasGroup = "Europe", AtlasCell = 7 },
		{ Id = "CI", Name = "Côte d'Ivoire", Short = "Côte d'Ivoire", Region = "Africa", Color = Color3.fromRGB(16, 208, 16), AtlasGroup = "Africa", AtlasCell = 7, Aliases = { "Ivory Coast" } },
		{ Id = "CL", Name = "Chile", Short = "Chile", Region = "Americas", Color = Color3.fromRGB(208, 48, 16), AtlasGroup = "Americas", AtlasCell = 7 },
		{ Id = "CM", Name = "Cameroon", Short = "Cameroon", Region = "Africa", Color = Color3.fromRGB(240, 208, 16), AtlasGroup = "Africa", AtlasCell = 8 },
		{ Id = "CN", Name = "China", Short = "China", Region = "Asia", Color = Color3.fromRGB(240, 16, 48), AtlasGroup = "Asia", AtlasCell = 4 },
		{ Id = "CO", Name = "Colombia", Short = "Colombia", Region = "Americas", Color = Color3.fromRGB(240, 240, 16), AtlasGroup = "Americas", AtlasCell = 8 },
		{ Id = "CR", Name = "Costa Rica", Short = "Costa Rica", Region = "Americas", Color = Color3.fromRGB(16, 16, 176), AtlasGroup = "Americas", AtlasCell = 9 },
		{ Id = "CU", Name = "Cuba", Short = "Cuba", Region = "Americas", Color = Color3.fromRGB(16, 48, 144), AtlasGroup = "Americas", AtlasCell = 10 },
		{ Id = "CV", Name = "Cape Verde", Short = "Cape Verde", Region = "Africa", Color = Color3.fromRGB(16, 16, 112), AtlasGroup = "Africa", AtlasCell = 9, Aliases = { "Cabo Verde" } },
		{ Id = "CY", Name = "Cyprus", Short = "Cyprus", Region = "Europe", Color = Color3.fromRGB(208, 112, 16), AtlasGroup = "Europe", AtlasCell = 8 },
		{ Id = "CZ", Name = "Czechia", Short = "Czechia", Region = "Europe", Color = Color3.fromRGB(208, 16, 16), AtlasGroup = "Europe", AtlasCell = 9, Aliases = { "Czech Republic" } },
		{ Id = "DE", Name = "Germany", Short = "Germany", Region = "Europe", Color = Color3.fromRGB(240, 16, 16), AtlasGroup = "Europe", AtlasCell = 10 },
		{ Id = "DJ", Name = "Djibouti", Short = "Djibouti", Region = "Africa", Color = Color3.fromRGB(16, 208, 16), AtlasGroup = "Africa", AtlasCell = 10 },
		{ Id = "DK", Name = "Denmark", Short = "Denmark", Region = "Europe", Color = Color3.fromRGB(208, 16, 48), AtlasGroup = "Europe", AtlasCell = 11 },
		{ Id = "DM", Name = "Dominica", Short = "Dominica", Region = "Americas", Color = Color3.fromRGB(16, 144, 16), AtlasGroup = "Americas", AtlasCell = 11 },
		{ Id = "DO", Name = "Dominican Republic", Short = "Dominican Rep", Region = "Americas", Color = Color3.fromRGB(16, 48, 112), AtlasGroup = "Americas", AtlasCell = 12 },
		{ Id = "DZ", Name = "Algeria", Short = "Algeria", Region = "Africa", Color = Color3.fromRGB(16, 112, 48), AtlasGroup = "Africa", AtlasCell = 11 },
		{ Id = "EC", Name = "Ecuador", Short = "Ecuador", Region = "Americas", Color = Color3.fromRGB(240, 240, 16), AtlasGroup = "Americas", AtlasCell = 13 },
		{ Id = "EE", Name = "Estonia", Short = "Estonia", Region = "Europe", Color = Color3.fromRGB(16, 144, 240), AtlasGroup = "Europe", AtlasCell = 12 },
		{ Id = "EG", Name = "Egypt", Short = "Egypt", Region = "Africa", Color = Color3.fromRGB(208, 16, 48), AtlasGroup = "Africa", AtlasCell = 12 },
		{ Id = "ER", Name = "Eritrea", Short = "Eritrea", Region = "Africa", Color = Color3.fromRGB(176, 16, 48), AtlasGroup = "Africa", AtlasCell = 13 },
		{ Id = "ES", Name = "Spain", Short = "Spain", Region = "Europe", Color = Color3.fromRGB(176, 16, 16), AtlasGroup = "Europe", AtlasCell = 13 },
		{ Id = "ET", Name = "Ethiopia", Short = "Ethiopia", Region = "Africa", Color = Color3.fromRGB(48, 144, 16), AtlasGroup = "Africa", AtlasCell = 14 },
		{ Id = "FI", Name = "Finland", Short = "Finland", Region = "Europe", Color = Color3.fromRGB(16, 48, 112), AtlasGroup = "Europe", AtlasCell = 14 },
		{ Id = "FJ", Name = "Fiji", Short = "Fiji", Region = "Oceania", Color = Color3.fromRGB(112, 176, 240), AtlasGroup = "Oceania", AtlasCell = 1 },
		{ Id = "FM", Name = "Micronesia", Short = "Micronesia", Region = "Oceania", Color = Color3.fromRGB(112, 144, 208), AtlasGroup = "Oceania", AtlasCell = 2 },
		{ Id = "FR", Name = "France", Short = "France", Region = "Europe", Color = Color3.fromRGB(16, 16, 144), AtlasGroup = "Europe", AtlasCell = 15 },
		{ Id = "GA", Name = "Gabon", Short = "Gabon", Region = "Africa", Color = Color3.fromRGB(16, 112, 176), AtlasGroup = "Africa", AtlasCell = 15 },
		{ Id = "GB", Name = "United Kingdom", Short = "UK", Region = "Europe", Color = Color3.fromRGB(208, 16, 48), AtlasGroup = "Europe", AtlasCell = 16, Aliases = { "Britain", "Great Britain" } },
		{ Id = "GB-ENG", Name = "England", Short = "England", Region = "Europe", Color = Color3.fromRGB(208, 16, 48), AtlasGroup = "Europe", AtlasCell = 17 },
		{ Id = "GB-SCT", Name = "Scotland", Short = "Scotland", Region = "Europe", Color = Color3.fromRGB(16, 112, 176), AtlasGroup = "Europe", AtlasCell = 18 },
		{ Id = "GB-WLS", Name = "Wales", Short = "Wales", Region = "Europe", Color = Color3.fromRGB(16, 176, 48), AtlasGroup = "Europe", AtlasCell = 19 },
		{ Id = "GD", Name = "Grenada", Short = "Grenada", Region = "Americas", Color = Color3.fromRGB(208, 16, 48), AtlasGroup = "Americas", AtlasCell = 14 },
		{ Id = "GE", Name = "Georgia", Short = "Georgia", Region = "Asia", Color = Color3.fromRGB(240, 16, 16), AtlasGroup = "Asia", AtlasCell = 5 },
		{ Id = "GH", Name = "Ghana", Short = "Ghana", Region = "Africa", Color = Color3.fromRGB(16, 112, 48), AtlasGroup = "Africa", AtlasCell = 16 },
		{ Id = "GM", Name = "Gambia", Short = "Gambia", Region = "Africa", Color = Color3.fromRGB(16, 16, 144), AtlasGroup = "Africa", AtlasCell = 17 },
		{ Id = "GN", Name = "Guinea", Short = "Guinea", Region = "Africa", Color = Color3.fromRGB(16, 144, 16), AtlasGroup = "Africa", AtlasCell = 18 },
		{ Id = "GQ", Name = "Equatorial Guinea", Short = "Eq. Guinea", Region = "Africa", Color = Color3.fromRGB(48, 144, 16), AtlasGroup = "Africa", AtlasCell = 19 },
		{ Id = "GR", Name = "Greece", Short = "Greece", Region = "Europe", Color = Color3.fromRGB(16, 80, 176), AtlasGroup = "Europe", AtlasCell = 20 },
		{ Id = "GT", Name = "Guatemala", Short = "Guatemala", Region = "Americas", Color = Color3.fromRGB(80, 144, 208), AtlasGroup = "Review", AtlasCell = 4 },
		{ Id = "GW", Name = "Guinea-Bissau", Short = "Guinea-Bissau", Region = "Africa", Color = Color3.fromRGB(16, 144, 80), AtlasGroup = "Africa", AtlasCell = 20 },
		{ Id = "GY", Name = "Guyana", Short = "Guyana", Region = "Americas", Color = Color3.fromRGB(48, 144, 16), AtlasGroup = "Americas", AtlasCell = 15 },
		{ Id = "HN", Name = "Honduras", Short = "Honduras", Region = "Americas", Color = Color3.fromRGB(16, 208, 208), AtlasGroup = "Americas", AtlasCell = 16 },
		{ Id = "HR", Name = "Croatia", Short = "Croatia", Region = "Europe", Color = Color3.fromRGB(240, 16, 16), AtlasGroup = "Europe", AtlasCell = 21 },
		{ Id = "HT", Name = "Haiti", Short = "Haiti", Region = "Americas", Color = Color3.fromRGB(208, 16, 48), AtlasGroup = "Review", AtlasCell = 5 },
		{ Id = "HU", Name = "Hungary", Short = "Hungary", Region = "Europe", Color = Color3.fromRGB(48, 144, 16), AtlasGroup = "Europe", AtlasCell = 22 },
		{ Id = "ID", Name = "Indonesia", Short = "Indonesia", Region = "Asia", Color = Color3.fromRGB(240, 16, 16), AtlasGroup = "Asia", AtlasCell = 6 },
		{ Id = "IE", Name = "Ireland", Short = "Ireland", Region = "Europe", Color = Color3.fromRGB(16, 144, 80), AtlasGroup = "Europe", AtlasCell = 23 },
		{ Id = "IL", Name = "Israel", Short = "Israel", Region = "MiddleEast", Color = Color3.fromRGB(16, 48, 176), AtlasGroup = "MiddleEast", AtlasCell = 2 },
		{ Id = "IN", Name = "India", Short = "India", Region = "Asia", Color = Color3.fromRGB(16, 144, 16), AtlasGroup = "Asia", AtlasCell = 7 },
		{ Id = "IQ", Name = "Iraq", Short = "Iraq", Region = "MiddleEast", Color = Color3.fromRGB(208, 16, 48), AtlasGroup = "Review", AtlasCell = 6 },
		{ Id = "IR", Name = "Iran", Short = "Iran", Region = "Asia", Color = Color3.fromRGB(208, 16, 16), AtlasGroup = "Review", AtlasCell = 7 },
		{ Id = "IS", Name = "Iceland", Short = "Iceland", Region = "Europe", Color = Color3.fromRGB(16, 48, 144), AtlasGroup = "Europe", AtlasCell = 24 },
		{ Id = "IT", Name = "Italy", Short = "Italy", Region = "Europe", Color = Color3.fromRGB(16, 144, 80), AtlasGroup = "Europe", AtlasCell = 25 },
		{ Id = "JM", Name = "Jamaica", Short = "Jamaica", Region = "Americas", Color = Color3.fromRGB(16, 144, 16), AtlasGroup = "Americas", AtlasCell = 17 },
		{ Id = "JO", Name = "Jordan", Short = "Jordan", Region = "MiddleEast", Color = Color3.fromRGB(240, 16, 16), AtlasGroup = "MiddleEast", AtlasCell = 3 },
		{ Id = "JP", Name = "Japan", Short = "Japan", Region = "Asia", Color = Color3.fromRGB(176, 16, 48), AtlasGroup = "Asia", AtlasCell = 8 },
		{ Id = "KE", Name = "Kenya", Short = "Kenya", Region = "Africa", Color = Color3.fromRGB(16, 112, 16), AtlasGroup = "Review", AtlasCell = 8 },
		{ Id = "KG", Name = "Kyrgyzstan", Short = "Kyrgyzstan", Region = "Asia", Color = Color3.fromRGB(240, 16, 16), AtlasGroup = "Asia", AtlasCell = 9 },
		{ Id = "KH", Name = "Cambodia", Short = "Cambodia", Region = "Asia", Color = Color3.fromRGB(16, 48, 176), AtlasGroup = "Asia", AtlasCell = 10 },
		{ Id = "KI", Name = "Kiribati", Short = "Kiribati", Region = "Oceania", Color = Color3.fromRGB(240, 48, 48), AtlasGroup = "Oceania", AtlasCell = 3 },
		{ Id = "KM", Name = "Comoros", Short = "Comoros", Region = "Africa", Color = Color3.fromRGB(48, 144, 80), AtlasGroup = "Africa", AtlasCell = 21 },
		{ Id = "KN", Name = "Saint Kitts and Nevis", Short = "St Kitts", Region = "Americas", Color = Color3.fromRGB(208, 16, 16), AtlasGroup = "Americas", AtlasCell = 18 },
		{ Id = "KP", Name = "North Korea", Short = "North Korea", Region = "Asia", Color = Color3.fromRGB(208, 16, 16), AtlasGroup = "Asia", AtlasCell = 11 },
		{ Id = "KR", Name = "South Korea", Short = "South Korea", Region = "Asia", Color = Color3.fromRGB(16, 80, 176), AtlasGroup = "Asia", AtlasCell = 12, Aliases = { "Korea" } },
		{ Id = "KW", Name = "Kuwait", Short = "Kuwait", Region = "MiddleEast", Color = Color3.fromRGB(240, 16, 48), AtlasGroup = "MiddleEast", AtlasCell = 4 },
		{ Id = "KZ", Name = "Kazakhstan", Short = "Kazakhstan", Region = "Asia", Color = Color3.fromRGB(16, 176, 208), AtlasGroup = "Asia", AtlasCell = 13 },
		{ Id = "LA", Name = "Laos", Short = "Laos", Region = "Asia", Color = Color3.fromRGB(208, 16, 48), AtlasGroup = "Asia", AtlasCell = 14 },
		{ Id = "LB", Name = "Lebanon", Short = "Lebanon", Region = "MiddleEast", Color = Color3.fromRGB(240, 16, 16), AtlasGroup = "MiddleEast", AtlasCell = 5 },
		{ Id = "LC", Name = "Saint Lucia", Short = "Saint Lucia", Region = "Americas", Color = Color3.fromRGB(112, 208, 240), AtlasGroup = "Americas", AtlasCell = 19, Aliases = { "St Lucia" } },
		{ Id = "LI", Name = "Liechtenstein", Short = "Liechtenstein", Region = "Europe", Color = Color3.fromRGB(208, 16, 48), AtlasGroup = "Europe", AtlasCell = 26 },
		{ Id = "LK", Name = "Sri Lanka", Short = "Sri Lanka", Region = "Asia", Color = Color3.fromRGB(144, 48, 48), AtlasGroup = "Review", AtlasCell = 9 },
		{ Id = "LR", Name = "Liberia", Short = "Liberia", Region = "Africa", Color = Color3.fromRGB(208, 16, 16), AtlasGroup = "Africa", AtlasCell = 22 },
		{ Id = "LS", Name = "Lesotho", Short = "Lesotho", Region = "Africa", Color = Color3.fromRGB(16, 48, 144), AtlasGroup = "Africa", AtlasCell = 23 },
		{ Id = "LT", Name = "Lithuania", Short = "Lithuania", Region = "Europe", Color = Color3.fromRGB(16, 112, 80), AtlasGroup = "Europe", AtlasCell = 27 },
		{ Id = "LU", Name = "Luxembourg", Short = "Luxembourg", Region = "Europe", Color = Color3.fromRGB(16, 176, 208), AtlasGroup = "Europe", AtlasCell = 28 },
		{ Id = "LV", Name = "Latvia", Short = "Latvia", Region = "Europe", Color = Color3.fromRGB(144, 16, 48), AtlasGroup = "Europe", AtlasCell = 29 },
		{ Id = "LY", Name = "Libya", Short = "Libya", Region = "Africa", Color = Color3.fromRGB(48, 144, 80), AtlasGroup = "Africa", AtlasCell = 24 },
		{ Id = "MA", Name = "Morocco", Short = "Morocco", Region = "Africa", Color = Color3.fromRGB(208, 48, 48), AtlasGroup = "Africa", AtlasCell = 25 },
		{ Id = "MC", Name = "Monaco", Short = "Monaco", Region = "Europe", Color = Color3.fromRGB(240, 16, 48), AtlasGroup = "Europe", AtlasCell = 30 },
		{ Id = "MD", Name = "Moldova", Short = "Moldova", Region = "Europe", Color = Color3.fromRGB(208, 48, 16), AtlasGroup = "Europe", AtlasCell = 31 },
		{ Id = "ME", Name = "Montenegro", Short = "Montenegro", Region = "Europe", Color = Color3.fromRGB(208, 16, 16), AtlasGroup = "Europe", AtlasCell = 32 },
		{ Id = "MG", Name = "Madagascar", Short = "Madagascar", Region = "Africa", Color = Color3.fromRGB(16, 112, 48), AtlasGroup = "Africa", AtlasCell = 26 },
		{ Id = "MH", Name = "Marshall Islands", Short = "Marshall Is.", Region = "Oceania", Color = Color3.fromRGB(48, 80, 176), AtlasGroup = "Oceania", AtlasCell = 4 },
		{ Id = "MK", Name = "North Macedonia", Short = "N. Macedonia", Region = "Europe", Color = Color3.fromRGB(208, 16, 16), AtlasGroup = "Europe", AtlasCell = 33 },
		{ Id = "ML", Name = "Mali", Short = "Mali", Region = "Africa", Color = Color3.fromRGB(240, 240, 16), AtlasGroup = "Africa", AtlasCell = 27 },
		{ Id = "MM", Name = "Myanmar", Short = "Myanmar", Region = "Asia", Color = Color3.fromRGB(240, 208, 16), AtlasGroup = "Asia", AtlasCell = 15, Aliases = { "Burma" } },
		{ Id = "MN", Name = "Mongolia", Short = "Mongolia", Region = "Asia", Color = Color3.fromRGB(208, 48, 48), AtlasGroup = "Asia", AtlasCell = 16 },
		{ Id = "MR", Name = "Mauritania", Short = "Mauritania", Region = "Africa", Color = Color3.fromRGB(16, 112, 48), AtlasGroup = "Africa", AtlasCell = 28 },
		{ Id = "MT", Name = "Malta", Short = "Malta", Region = "Europe", Color = Color3.fromRGB(208, 16, 48), AtlasGroup = "Europe", AtlasCell = 34 },
		{ Id = "MU", Name = "Mauritius", Short = "Mauritius", Region = "Africa", Color = Color3.fromRGB(16, 16, 112), AtlasGroup = "Africa", AtlasCell = 29 },
		{ Id = "MV", Name = "Maldives", Short = "Maldives", Region = "Asia", Color = Color3.fromRGB(208, 16, 48), AtlasGroup = "Asia", AtlasCell = 17 },
		{ Id = "MW", Name = "Malawi", Short = "Malawi", Region = "Africa", Color = Color3.fromRGB(240, 16, 16), AtlasGroup = "Africa", AtlasCell = 30 },
		{ Id = "MX", Name = "Mexico", Short = "Mexico", Region = "Americas", Color = Color3.fromRGB(16, 112, 80), AtlasGroup = "Americas", AtlasCell = 20 },
		{ Id = "MY", Name = "Malaysia", Short = "Malaysia", Region = "Asia", Color = Color3.fromRGB(208, 16, 16), AtlasGroup = "Asia", AtlasCell = 18 },
		{ Id = "MZ", Name = "Mozambique", Short = "Mozambique", Region = "Africa", Color = Color3.fromRGB(240, 208, 16), AtlasGroup = "Review", AtlasCell = 10 },
		{ Id = "NA", Name = "Namibia", Short = "Namibia", Region = "Africa", Color = Color3.fromRGB(208, 16, 16), AtlasGroup = "Africa", AtlasCell = 31 },
		{ Id = "NE", Name = "Niger", Short = "Niger", Region = "Africa", Color = Color3.fromRGB(240, 80, 16), AtlasGroup = "Africa", AtlasCell = 32 },
		{ Id = "NG", Name = "Nigeria", Short = "Nigeria", Region = "Africa", Color = Color3.fromRGB(16, 144, 80), AtlasGroup = "Africa", AtlasCell = 33 },
		{ Id = "NI", Name = "Nicaragua", Short = "Nicaragua", Region = "Americas", Color = Color3.fromRGB(16, 112, 208), AtlasGroup = "Americas", AtlasCell = 21 },
		{ Id = "NL", Name = "Netherlands", Short = "Netherlands", Region = "Europe", Color = Color3.fromRGB(48, 80, 144), AtlasGroup = "Europe", AtlasCell = 35, Aliases = { "Holland" } },
		{ Id = "NO", Name = "Norway", Short = "Norway", Region = "Europe", Color = Color3.fromRGB(240, 48, 48), AtlasGroup = "Europe", AtlasCell = 36 },
		{ Id = "NP", Name = "Nepal", Short = "Nepal", Region = "Asia", Color = Color3.fromRGB(208, 16, 16), AtlasGroup = "Asia", AtlasCell = 19, Cutout = true },
		{ Id = "NR", Name = "Nauru", Short = "Nauru", Region = "Oceania", Color = Color3.fromRGB(16, 48, 112), AtlasGroup = "Oceania", AtlasCell = 5 },
		{ Id = "NZ", Name = "New Zealand", Short = "New Zealand", Region = "Oceania", Color = Color3.fromRGB(16, 48, 112), AtlasGroup = "Oceania", AtlasCell = 6 },
		{ Id = "OM", Name = "Oman", Short = "Oman", Region = "MiddleEast", Color = Color3.fromRGB(240, 48, 48), AtlasGroup = "Review", AtlasCell = 11 },
		{ Id = "PA", Name = "Panama", Short = "Panama", Region = "Americas", Color = Color3.fromRGB(16, 16, 176), AtlasGroup = "Americas", AtlasCell = 22 },
		{ Id = "PE", Name = "Peru", Short = "Peru", Region = "Americas", Color = Color3.fromRGB(208, 16, 48), AtlasGroup = "Americas", AtlasCell = 23 },
		{ Id = "PG", Name = "Papua New Guinea", Short = "Papua NG", Region = "Oceania", Color = Color3.fromRGB(240, 16, 16), AtlasGroup = "Oceania", AtlasCell = 7, Aliases = { "PNG" } },
		{ Id = "PH", Name = "Philippines", Short = "Philippines", Region = "Asia", Color = Color3.fromRGB(208, 16, 48), AtlasGroup = "Asia", AtlasCell = 20 },
		{ Id = "PK", Name = "Pakistan", Short = "Pakistan", Region = "Asia", Color = Color3.fromRGB(16, 80, 16), AtlasGroup = "Asia", AtlasCell = 21 },
		{ Id = "PL", Name = "Poland", Short = "Poland", Region = "Europe", Color = Color3.fromRGB(208, 16, 48), AtlasGroup = "Europe", AtlasCell = 37 },
		{ Id = "PS", Name = "Palestine", Short = "Palestine", Region = "MiddleEast", Color = Color3.fromRGB(16, 144, 48), AtlasGroup = "MiddleEast", AtlasCell = 6 },
		{ Id = "PT", Name = "Portugal", Short = "Portugal", Region = "Europe", Color = Color3.fromRGB(240, 16, 16), AtlasGroup = "Europe", AtlasCell = 38 },
		{ Id = "PW", Name = "Palau", Short = "Palau", Region = "Oceania", Color = Color3.fromRGB(80, 176, 208), AtlasGroup = "Oceania", AtlasCell = 8 },
		{ Id = "PY", Name = "Paraguay", Short = "Paraguay", Region = "Americas", Color = Color3.fromRGB(16, 48, 176), AtlasGroup = "Americas", AtlasCell = 24 },
		{ Id = "QA", Name = "Qatar", Short = "Qatar", Region = "MiddleEast", Color = Color3.fromRGB(144, 16, 48), AtlasGroup = "MiddleEast", AtlasCell = 7 },
		{ Id = "RO", Name = "Romania", Short = "Romania", Region = "Europe", Color = Color3.fromRGB(16, 48, 144), AtlasGroup = "Europe", AtlasCell = 39 },
		{ Id = "RS", Name = "Serbia", Short = "Serbia", Region = "Europe", Color = Color3.fromRGB(208, 48, 48), AtlasGroup = "Europe", AtlasCell = 40 },
		{ Id = "RU", Name = "Russia", Short = "Russia", Region = "Europe", Color = Color3.fromRGB(16, 48, 176), AtlasGroup = "Europe", AtlasCell = 41 },
		{ Id = "RW", Name = "Rwanda", Short = "Rwanda", Region = "Africa", Color = Color3.fromRGB(16, 176, 208), AtlasGroup = "Africa", AtlasCell = 34 },
		{ Id = "SA", Name = "Saudi Arabia", Short = "Saudi Arabia", Region = "MiddleEast", Color = Color3.fromRGB(16, 80, 48), AtlasGroup = "Review", AtlasCell = 12 },
		{ Id = "SB", Name = "Solomon Islands", Short = "Solomon Is.", Region = "Oceania", Color = Color3.fromRGB(16, 16, 208), AtlasGroup = "Oceania", AtlasCell = 9 },
		{ Id = "SC", Name = "Seychelles", Short = "Seychelles", Region = "Africa", Color = Color3.fromRGB(208, 48, 48), AtlasGroup = "Africa", AtlasCell = 35 },
		{ Id = "SD", Name = "Sudan", Short = "Sudan", Region = "Africa", Color = Color3.fromRGB(240, 16, 16), AtlasGroup = "Africa", AtlasCell = 36 },
		{ Id = "SE", Name = "Sweden", Short = "Sweden", Region = "Europe", Color = Color3.fromRGB(16, 80, 144), AtlasGroup = "Europe", AtlasCell = 42 },
		{ Id = "SG", Name = "Singapore", Short = "Singapore", Region = "Asia", Color = Color3.fromRGB(208, 16, 16), AtlasGroup = "Asia", AtlasCell = 22 },
		{ Id = "SI", Name = "Slovenia", Short = "Slovenia", Region = "Europe", Color = Color3.fromRGB(16, 16, 176), AtlasGroup = "Europe", AtlasCell = 43 },
		{ Id = "SK", Name = "Slovakia", Short = "Slovakia", Region = "Europe", Color = Color3.fromRGB(240, 16, 48), AtlasGroup = "Europe", AtlasCell = 44 },
		{ Id = "SL", Name = "Sierra Leone", Short = "Sierra Leone", Region = "Africa", Color = Color3.fromRGB(16, 16, 208), AtlasGroup = "Africa", AtlasCell = 37 },
		{ Id = "SM", Name = "San Marino", Short = "San Marino", Region = "Europe", Color = Color3.fromRGB(16, 176, 240), AtlasGroup = "Europe", AtlasCell = 45 },
		{ Id = "SN", Name = "Senegal", Short = "Senegal", Region = "Africa", Color = Color3.fromRGB(16, 112, 48), AtlasGroup = "Africa", AtlasCell = 38 },
		{ Id = "SO", Name = "Somalia", Short = "Somalia", Region = "Africa", Color = Color3.fromRGB(80, 176, 240), AtlasGroup = "Africa", AtlasCell = 39 },
		{ Id = "SR", Name = "Suriname", Short = "Suriname", Region = "Americas", Color = Color3.fromRGB(48, 112, 48), AtlasGroup = "Americas", AtlasCell = 25 },
		{ Id = "SS", Name = "South Sudan", Short = "South Sudan", Region = "Africa", Color = Color3.fromRGB(16, 80, 176), AtlasGroup = "Africa", AtlasCell = 40 },
		{ Id = "ST", Name = "São Tomé and Príncipe", Short = "São Tomé", Region = "Africa", Color = Color3.fromRGB(16, 176, 48), AtlasGroup = "Africa", AtlasCell = 41 },
		{ Id = "SV", Name = "El Salvador", Short = "El Salvador", Region = "Americas", Color = Color3.fromRGB(16, 80, 176), AtlasGroup = "Americas", AtlasCell = 26 },
		{ Id = "SY", Name = "Syria", Short = "Syria", Region = "MiddleEast", Color = Color3.fromRGB(16, 112, 48), AtlasGroup = "MiddleEast", AtlasCell = 8 },
		{ Id = "SZ", Name = "Eswatini", Short = "Eswatini", Region = "Africa", Color = Color3.fromRGB(48, 80, 176), AtlasGroup = "Review", AtlasCell = 13, Aliases = { "Swaziland" } },
		{ Id = "TD", Name = "Chad", Short = "Chad", Region = "Africa", Color = Color3.fromRGB(16, 48, 112), AtlasGroup = "Africa", AtlasCell = 42 },
		{ Id = "TG", Name = "Togo", Short = "Togo", Region = "Africa", Color = Color3.fromRGB(16, 144, 16), AtlasGroup = "Africa", AtlasCell = 43 },
		{ Id = "TH", Name = "Thailand", Short = "Thailand", Region = "Asia", Color = Color3.fromRGB(176, 16, 48), AtlasGroup = "Asia", AtlasCell = 23 },
		{ Id = "TJ", Name = "Tajikistan", Short = "Tajikistan", Region = "Asia", Color = Color3.fromRGB(16, 112, 16), AtlasGroup = "Asia", AtlasCell = 24 },
		{ Id = "TL", Name = "Timor-Leste", Short = "Timor-Leste", Region = "Asia", Color = Color3.fromRGB(208, 16, 16), AtlasGroup = "Asia", AtlasCell = 25, Aliases = { "East Timor" } },
		{ Id = "TM", Name = "Turkmenistan", Short = "Turkmenistan", Region = "Asia", Color = Color3.fromRGB(16, 144, 48), AtlasGroup = "Asia", AtlasCell = 26 },
		{ Id = "TN", Name = "Tunisia", Short = "Tunisia", Region = "Africa", Color = Color3.fromRGB(240, 16, 16), AtlasGroup = "Africa", AtlasCell = 44 },
		{ Id = "TO", Name = "Tonga", Short = "Tonga", Region = "Oceania", Color = Color3.fromRGB(208, 16, 16), AtlasGroup = "Oceania", AtlasCell = 10 },
		{ Id = "TR", Name = "Türkiye", Short = "Türkiye", Region = "MiddleEast", Color = Color3.fromRGB(240, 16, 16), AtlasGroup = "MiddleEast", AtlasCell = 9, Aliases = { "Turkey" } },
		{ Id = "TT", Name = "Trinidad and Tobago", Short = "Trinidad", Region = "Americas", Color = Color3.fromRGB(240, 16, 16), AtlasGroup = "Americas", AtlasCell = 27 },
		{ Id = "TV", Name = "Tuvalu", Short = "Tuvalu", Region = "Oceania", Color = Color3.fromRGB(16, 144, 208), AtlasGroup = "Oceania", AtlasCell = 11 },
		{ Id = "TW", Name = "Taiwan", Short = "Taiwan", Region = "Asia", Color = Color3.fromRGB(240, 16, 16), AtlasGroup = "Asia", AtlasCell = 27 },
		{ Id = "TZ", Name = "Tanzania", Short = "Tanzania", Region = "Africa", Color = Color3.fromRGB(16, 144, 16), AtlasGroup = "Africa", AtlasCell = 45 },
		{ Id = "UA", Name = "Ukraine", Short = "Ukraine", Region = "Europe", Color = Color3.fromRGB(16, 80, 176), AtlasGroup = "Europe", AtlasCell = 46 },
		{ Id = "UG", Name = "Uganda", Short = "Uganda", Region = "Africa", Color = Color3.fromRGB(240, 240, 16), AtlasGroup = "Africa", AtlasCell = 46 },
		{ Id = "US", Name = "United States", Short = "USA", Region = "Americas", Color = Color3.fromRGB(176, 48, 80), AtlasGroup = "Americas", AtlasCell = 28, Aliases = { "America" } },
		{ Id = "UY", Name = "Uruguay", Short = "Uruguay", Region = "Americas", Color = Color3.fromRGB(16, 48, 176), AtlasGroup = "Americas", AtlasCell = 29 },
		{ Id = "UZ", Name = "Uzbekistan", Short = "Uzbekistan", Region = "Asia", Color = Color3.fromRGB(16, 176, 48), AtlasGroup = "Asia", AtlasCell = 28 },
		{ Id = "VA", Name = "Vatican City", Short = "Vatican", Region = "Europe", Color = Color3.fromRGB(240, 240, 16), AtlasGroup = "Europe", AtlasCell = 47, Aliases = { "Holy See" } },
		{ Id = "VC", Name = "Saint Vincent and the Grenadines", Short = "St Vincent", Region = "Americas", Color = Color3.fromRGB(240, 240, 16), AtlasGroup = "Americas", AtlasCell = 30 },
		{ Id = "VE", Name = "Venezuela", Short = "Venezuela", Region = "Americas", Color = Color3.fromRGB(208, 16, 48), AtlasGroup = "Americas", AtlasCell = 31 },
		{ Id = "VN", Name = "Vietnam", Short = "Vietnam", Region = "Asia", Color = Color3.fromRGB(208, 48, 16), AtlasGroup = "Asia", AtlasCell = 29 },
		{ Id = "VU", Name = "Vanuatu", Short = "Vanuatu", Region = "Oceania", Color = Color3.fromRGB(208, 16, 48), AtlasGroup = "Oceania", AtlasCell = 12 },
		{ Id = "WS", Name = "Samoa", Short = "Samoa", Region = "Oceania", Color = Color3.fromRGB(208, 16, 48), AtlasGroup = "Oceania", AtlasCell = 13 },
		{ Id = "XK", Name = "Kosovo", Short = "Kosovo", Region = "Europe", Color = Color3.fromRGB(48, 80, 176), AtlasGroup = "Europe", AtlasCell = 48 },
		{ Id = "YE", Name = "Yemen", Short = "Yemen", Region = "MiddleEast", Color = Color3.fromRGB(240, 16, 16), AtlasGroup = "MiddleEast", AtlasCell = 10 },
		{ Id = "ZA", Name = "South Africa", Short = "South Africa", Region = "Africa", Color = Color3.fromRGB(16, 112, 80), AtlasGroup = "Africa", AtlasCell = 47 },
		{ Id = "ZM", Name = "Zambia", Short = "Zambia", Region = "Africa", Color = Color3.fromRGB(16, 144, 16), AtlasGroup = "Africa", AtlasCell = 48 },
		{ Id = "ZW", Name = "Zimbabwe", Short = "Zimbabwe", Region = "Africa", Color = Color3.fromRGB(16, 112, 16), AtlasGroup = "Africa", AtlasCell = 49 },
	} :: { NationDef },
}

local denied: { [string]: boolean } = {}
for _, id in ipairs(NationConfig.Denied) do
	denied[id] = true
end

local byId: { [string]: NationDef } = {}
for _, n in ipairs(NationConfig.Nations) do
	if not denied[n.Id] then
		byId[n.Id] = n
	end
end

-- The nation for a stored or requested id, or nil (unknown, denied, switched off in OwnerReview, not a string, or
-- longer than 8 bytes). Exact match only: the id is never trimmed or case-folded. NEUTRAL is not a nation (nil here).
function NationConfig.Get(id: any): NationDef?
	if typeof(id) ~= "string" or #id > 8 then
		return nil
	end
	local n = byId[id]
	if n == nil or NationConfig.OwnerReview[id] == false then
		return nil
	end
	return n
end

function NationConfig.IsNeutral(id: any): boolean
	return id == NationConfig.NeutralId
end

-- What a saved NationId may hold after load: NeutralId, a valid nation's Id, or nil (the player is asked again).
function NationConfig.Sanitize(id: any): string?
	if id == NationConfig.NeutralId then
		return NationConfig.NeutralId
	end
	local n = NationConfig.Get(id)
	return if n then n.Id else nil
end

-- Nations the picker may show (roster order), i.e. every Get-able nation.
function NationConfig.Visible(): { NationDef }
	local out = {}
	for _, n in ipairs(NationConfig.Nations) do
		if NationConfig.Get(n.Id) then
			table.insert(out, n)
		end
	end
	return out
end

-- Player-list text: "IE", "ENG" for GB-ENG, NeutralCode for NEUTRAL, "" for anything else.
function NationConfig.Code(id: any): string
	if id == NationConfig.NeutralId then
		return NationConfig.NeutralCode
	end
	local n = NationConfig.Get(id)
	if not n then
		return ""
	end
	return (string.match(n.Id, "^GB%-(%u+)$")) or n.Id
end

-- Flag emoji (only used while PlayerListEmoji is on): regional-indicator pair for 2-letter ids, the tag sequence for
-- England / Scotland / Wales, "" otherwise.
function NationConfig.Emoji(id: any): string
	local n = NationConfig.Get(id)
	if not n then
		return ""
	end
	local a, b = string.byte(n.Id, 1, 2)
	if #n.Id == 2 and a and b then
		return utf8.char(0x1F1E6 + a - 65, 0x1F1E6 + b - 65)
	end
	local sub = string.match(n.Id, "^GB%-(%u%u%u)$")
	if sub then
		local codes = { 0x1F3F4, 0xE0067, 0xE0062 }
		for i = 1, 3 do
			table.insert(codes, 0xE0061 + string.byte(string.lower(sub), i) - 97)
		end
		table.insert(codes, 0xE007F)
		return utf8.char(table.unpack(codes))
	end
	return ""
end

-- Search folding (on the device only; search text never leaves it): ASCII lower case, the roster's accented letters
-- to plain ones, curly apostrophe to straight, runs of spaces to one.
local FOLD = { ["ô"] = "o", ["Ô"] = "o", ["é"] = "e", ["É"] = "e", ["í"] = "i", ["Í"] = "i", ["ã"] = "a", ["Ã"] = "a", ["ü"] = "u", ["Ü"] = "u", ["’"] = "'" }
function NationConfig.Fold(s: string): string
	local out = string.lower(s)
	for from, to in pairs(FOLD) do
		out = string.gsub(out, from, to)
	end
	out = string.gsub(out, "%s+", " ")
	out = string.gsub(out, "^ ", "")
	out = string.gsub(out, " $", "")
	return out
end

-- How well a folded query matches a nation (0 = no match): 4 exact Id, 3 a name starts with it, 2 a word starts with
-- it, 1 it appears inside a name. Names = Name, Short and Aliases. The picker sorts by score, then Short.
function NationConfig.MatchScore(n: NationDef, foldedQuery: string): number
	local q = foldedQuery
	if q == "" then
		return 1
	end
	if string.lower(n.Id) == q then
		return 4
	end
	local best = 0
	local wordStart = "[%s%-%.'(]" .. (string.gsub(q, "%p", "%%%0")) -- q after a space, hyphen, dot, apostrophe or "("
	local function try(text: string)
		local t = NationConfig.Fold(text)
		local at = string.find(t, q, 1, true)
		if at == nil then
			return
		end
		local score = 1
		if at == 1 then
			score = 3
		elseif string.find(t, wordStart) then
			score = 2
		end
		if score > best then
			best = score
		end
	end
	try(n.Name)
	try(n.Short)
	for _, a in ipairs(n.Aliases or {}) do
		try(a)
	end
	return best
end

return NationConfig
