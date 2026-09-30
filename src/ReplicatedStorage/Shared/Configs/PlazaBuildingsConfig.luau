--!strict
--[[
	claude-bud JOB 32 (2026-09-30): ENTERABLE buildings round the Central Plaza. The Crossroads Town buildings are solid
	boxes with Roblox-made mesh fronts (nobody can go in). For the rows listed in Rows, WorldKits builds the "PlazaHouse"
	instead: same footprint and frame as the TownHouse it replaces, facing the plaza.
	  * Ground floor: a 6 x 8 door in the front; windows are open GAPS (no glass), so shots through them work.
	  * Stair: a ramp up the right-hand wall to the upper floor, with a rail round the stair hole. The upper floor has
	    windows on every side.
	  * Roof: a ladder (TrussPart) through a hatch in the back-left corner. A 3.2-stud parapet all round (chest-high
	    cover: shoot over it, duck behind it), plus two sandbag rows at the front corners.
	  * A few crates inside for cover.
	  * 55 parts each.
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
	MaxExtraParts = 240,
	-- WorldConfig.Town row Ids: the 4 buildings that face the plaza flag, one on each side
	Rows = { NE_E1 = true, SW_S1 = true, NE_N1 = true, NW_W1 = true } :: { [string]: boolean },
	DoorOutStuds = 10, -- where the army waits: this far out from the door, on the street side
	Parts = 55,
}

return PlazaBuildingsConfig
