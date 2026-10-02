--!strict
--[[
	claude-bud JOB 31 (2026-09-30): REAL DETAIL for the world props that were a few boxes (owner: "the desert tank wreck is
	a brown box and barely reads as a tank"). WorldKits.Add builds the detailed version of these kits instead of the plain
	one:
	  * tank wreck: hull, glacis, both tracks with road wheels and fenders, turret with bustle, mantlet, barrel,
	    muzzle brake and hatch, plus a jerry can and a thrown track link;
	  * truck and field-gun wrecks;
	  * two-course sandbag lines, arcs and nests (the nest with an MG on a tripod and an ammo box);
	  * jersey barriers with the real sloped profile;
	  * a braced watchtower with side rails;
	  * a bunker with a concrete roof, firing slits, roof sandbags and a vent;
	  * a tent with a ridge pole, groundsheet and a crate.
	Everything is our own design from anchored Parts: no scripts, no Neon, no lights, no real-world copies.

	Layouts and budgets do not move:
	  * WorldKits.Footprint (the planner) and every section's cap still count the plain kit;
	  * Add returns the plain count;
	  * the detail's EXTRA parts come out of ONE world allowance, MaxExtraParts. When it is spent, the rest build plain.
	So the world grows by at most MaxExtraParts parts, logged as "[WorldDetail] ... extra=N".
	These props are small decor: on the phone LOW tier QualityGovernor still hides them beyond 220-320 studs (JOB 27;
	buildings are never culled).

	Kill switch: Enabled = false builds exactly the plain kits. The world is built once on the server, for everyone, so
	this has no per-player rollout.
]]

local WorldDetailConfig = {
	Enabled = true,
	-- claude-bud JOB 37: 900 -> 1446 (+546), and the +546 is the road checkpoint's own share (KitCaps): the JOB 31 kits
	-- keep exactly their 900 (MaxExtraParts minus every KitCaps share), the checkpoints never take theirs
	MaxExtraParts = 1446,
	KitCaps = {
		Checkpoint = 546, -- 6 detailed checkpoints x 91 extra; the rest build plain (their guards need the detailed one)
	} :: { [string]: number },
	-- which kits (and Wreck variants) get the detailed build; the car wreck and crates keep their Roblox-made mesh overlay
	Kits = {
		Wreck = { tank = true, truck = true, gun = true },
		SandbagLine = true,
		SandbagArc = true,
		SandbagNest = true,
		Jersey = true,
		Watchtower = true,
		Bunker = true,
		Tent = true,
		Checkpoint = true, -- claude-bud JOB 37: the real road checkpoint (false = today's 8-part kit exactly)
	} :: { [string]: any },
}

return WorldDetailConfig
