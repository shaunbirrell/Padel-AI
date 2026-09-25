--!strict
--[[
	Uploaded nation-flag image ids (numbers of rbxassetid://<id>). 0 = not uploaded yet: the flag part shows its
	banner colour and the picker shows colour + code tiles (NationConfig.LiveRequiresArt keeps the picker from opening
	by itself for non-admins until every Atlas id is set).

	Written by tools/wire-nation-flag-ids.py (never by hand, so a typo cannot slip in):
	  Atlas  the 7 atlas images from tools/gen_nation_flags.py (assets/flags/atlas_<group>.png), one per
	         NationConfig.Atlas.Groups entry. Upload them as the account or group that owns the game and paste the
	         IMAGE ids (Studio Asset Manager ids), not Decal ids.
	  Flags  per-flag fallback (only if the Studio atlas-crop test fails): ["IE"] = <image id>. A nation listed here
	         uses its own image instead of its atlas cell (NationTexture.Source). Keys must be NationConfig ids.
]]

local NationFlagIds = {
	Atlas = {
		Europe = 0,
		Americas = 0,
		Asia = 0,
		Africa = 0,
		MiddleEast = 0,
		Oceania = 0,
		Review = 0,
	} :: { [string]: number },
	Flags = {
	} :: { [string]: number },
}

return NationFlagIds
