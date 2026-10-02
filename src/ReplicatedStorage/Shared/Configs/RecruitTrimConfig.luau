--!strict
--[[ claude-bud JOB 45 (2026-10-01): the Recruit Pack's GOLD GATE ARCH (Services/RecruitTrimService), built on the
	owner's plot for WE_Ent_RecruitPack (the existing entitlement, granted by the Recruit Pack receipt). Its own file so
	MonetizationConfig keeps only products / prices (codebot_v167). Enabled = false: nothing built. ]]
-- claude-bud JOB 45: the Recruit Pack's GOLD GATE ARCH (Services/RecruitTrimService), built on the owner's plot for
-- WE_Ent_RecruitPack (the existing entitlement). Enabled = false: nothing built (the sign / marker accents stay).
local RecruitTrimConfig = {
	Enabled = true,
	Text = "RECRUIT",
	InsetStuds = 4, -- no walls (Lv 0) only: this far in from the plot's front edge
	Height = 18, -- pillar height (studs); Code Bot v172: at least HeightOverWall above the gate-face wall
	-- Code Bot v172: the arch is placed from the REAL gate (the GatePost parts in WE_PerimeterWalls): the pillars stand
	-- WallClearStuds behind the furthest gate furniture (the wall's inner face + the gate arch overhang, or the post roofs /
	-- Tier 3 gatehouse / Bastion crest at GateFurnitureStuds), in front of the gate guards (10 studs in)
	GateFurnitureStuds = 2.6,
	WallClearStuds = 1.0,
	HeightOverWall = 5, -- the banner's bottom (4.6 under the pillar top) stays above the gate opening's height
	PillarWidth = 2.2,
	PillarGap = 1.2, -- from the gate opening's edge (the 14-stud lane stays clear)
	BannerSize = Vector2.new(12, 3),
	TextMaxDistance = 80, -- SurfaceGui cap (CLAUDE.md budget)
	Gold = Color3.fromRGB(232, 184, 58),
	GoldDark = Color3.fromRGB(168, 122, 30),
	Plinth = Color3.fromRGB(58, 52, 44),
	BannerColor = Color3.fromRGB(26, 34, 22),
	Reflectance = 0.25,
	SweepSeconds = 5,
}

return RecruitTrimConfig
