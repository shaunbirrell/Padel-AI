--!strict
--[[
	claude-bud JOB 32 (2026-09-30): ENTERABLE buildings round the Central Plaza. The Crossroads Town buildings are solid
	boxes with Roblox-made mesh fronts (nobody can go in). For the rows listed in Rows, WorldKits builds the "PlazaHouse"
	instead: same footprint and frame as the TownHouse it replaces, facing the plaza.
	  * Ground floor: a 6 x 8 door in the front; windows are open GAPS (no glass), so shots through them work.
	  * Stair: a ramp up the right-hand wall to the upper floor, with a rail round the stair hole. The upper floor has
	    windows on every side.
	  * Roof: a ladder (TrussPart) up through a hatch in the back-left corner. v133 (Code Bot): the hatch is a real
	    5.6 x 5.3 opening with a frame, a railing on its open edges and the lid propped open; the ladder stands on the
	    hole's inner edge so you climb inside the hole and step off its top onto the roof (tools/sim/run_hatch_test.py). A 3.2-stud parapet all round (chest-high
	    cover: shoot over it, duck behind it), plus two sandbag rows at the front corners.
	  * A few crates inside for cover.
	  * v133 (Code Bot): a town-centre facade per building (Styles): coloured walls, door and window frames, glass in
	    the gaps (see-through, never collides or answers a ray: shots and sight still pass), striped awnings, a shop
	    sign board, storey band and cornice, corner quoins, a balcony, planters, a bench, a lantern; rooftop AC units, a
	    water cistern and an antenna.
	  * Parts each (was 55).
	Every shooter uses the one line-of-sight rule (CombatConfig.LineOfSight / Shared/Util/LosRule): the walls stop
	shots, the window gaps and the roof edge do not.
	The army (ArmyConfig.Indoors) forms up outside the door while its owner is inside or on the roof. It never walks
	in, never gets stuck on the stair, and is never teleported.
	The Town's budget and layout do not move: the planner and the Town cap still count the TownHouse, and the extra parts
	come out of MaxExtraParts.
	Kill switch: Enabled = false (the rows build the solid TownHouse again). The world is built once for everyone, so
	this has no per-player rollout.
]]

local PlazaBuildingsConfig = {
	Enabled = true,
	MaxExtraParts = 640, -- v133: 4 x (Parts - the plain TownHouse) with room to spare (was 240 for 55-part houses)
	-- WorldConfig.Town row Ids: the 4 buildings that face the plaza flag, one on each side
	Rows = { NE_E1 = true, SW_S1 = true, NE_N1 = true, NW_W1 = true } :: { [string]: boolean },
	DoorOutStuds = 10, -- where the army waits: this far out from the door, on the street side
	Parts = 142, -- v133 (Code Bot): the facade + the real hatch (was 55); tools/sim/run_plaza_test.py counts them
	-- v133 (Code Bot): the town-centre look, one per row (walls, trim, awning, accent: a cafe, a market, a hotel, a radio shop)
	Styles = {
		NE_E1 = { Wall = Color3.fromRGB(214, 172, 104), Trim = Color3.fromRGB(240, 230, 204), Awning = Color3.fromRGB(34, 124, 122), Accent = Color3.fromRGB(92, 64, 44) },
		SW_S1 = { Wall = Color3.fromRGB(190, 110, 78), Trim = Color3.fromRGB(236, 220, 196), Awning = Color3.fromRGB(34, 52, 96), Accent = Color3.fromRGB(58, 44, 36) },
		NE_N1 = { Wall = Color3.fromRGB(176, 172, 162), Trim = Color3.fromRGB(226, 224, 216), Awning = Color3.fromRGB(150, 38, 36), Accent = Color3.fromRGB(56, 58, 62) },
		NW_W1 = { Wall = Color3.fromRGB(168, 156, 112), Trim = Color3.fromRGB(230, 222, 196), Awning = Color3.fromRGB(214, 110, 30), Accent = Color3.fromRGB(62, 66, 48) },
	} :: { [string]: { Wall: Color3, Trim: Color3, Awning: Color3, Accent: Color3 } },
}

return PlazaBuildingsConfig
