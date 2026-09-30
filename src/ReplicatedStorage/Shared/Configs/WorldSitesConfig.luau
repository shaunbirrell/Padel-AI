--!strict
--[[
	claude-bud JOB 31 (2026-09-30): FILL THE MAP. The owner: "the map is big and empty ... players get lost (BASE 1.5km,
	AIRDROP 2.5km across empty sand)".

	Server Modules/WorldSites builds these named sites in the open desert between the Central Plaza, the bases and the
	POIs. It runs after WorldFill (MapDressing), so it can avoid everything already built.
	  * Each site is made of WorldKits clusters (each <= 64 studs across; the detailed kits of WorldDetailConfig).
	  * Placement: at the configured point, or the first clear point on rings around it (up to SearchStuds away).
	    "Clear" means:
	    - no road, building or prop inside the site's radius;
	    - >= PlotClearStuds from every base plot;
	    - outside every named area;
	    - on dry land.
	  * The sites show on the world map (MapService sends their real positions) and host the JOB 31 activities and
	    garrisons (SiteActivityService).
	Our own designs, fictional names; no real place, unit or brand.

	Budget: at most MaxParts plain parts in total; a site that would pass it is skipped. The detailed props' extra parts
	come out of WorldDetailConfig.MaxExtraParts.
	Kill switch: Enabled = false (no sites, no garrisons, no site activities). The world is built once for everyone, so
	this has no per-player rollout. The garrisons and activities are owner-first (SiteActivityConfig).
]]

export type KitRow = { Kit: string, X: number, Z: number, Yaw: number?, Variant: string?, Count: number?, Length: number?, Scale: number? }
export type ClusterRow = { Kind: string, X: number, Z: number, Yaw: number?, Kits: { KitRow } }
export type Site = { Id: string, Name: string, Kind: string, X: number, Z: number }

local WorldSitesConfig = {
	Enabled = true,
	MaxParts = 240,
	SearchStuds = 260,
	PlotClearStuds = 200,
	-- the dry land the sites may use (WorldConfig: x +-1760, z -1760 .. 1490), kept off the edges
	Land = { X0 = -1650, X1 = 1650, Z0 = -1650, Z1 = 1380 },

	Sites = {
		{ Id = "CampViper", Name = "Camp Viper", Kind = "camp", X = -450, Z = -650 },
		{ Id = "DryWell", Name = "Dry Well Village", Kind = "village", X = 450, Z = 650 },
		{ Id = "PumpSeven", Name = "Pump Station 7", Kind = "oil", X = -560, Z = 0 },
		{ Id = "Kestrel", Name = "Kestrel Supply Depot", Kind = "depot", X = 560, Z = 0 },
		{ Id = "Hawk", Name = "Hawk Checkpoint", Kind = "checkpoint", X = 0, Z = -480 },
		{ Id = "Overwatch", Name = "Overwatch Ridge", Kind = "overwatch", X = -400, Z = -1000 },
		{ Id = "Anvil", Name = "Anvil Scrapyard", Kind = "tankyard", X = 1200, Z = 420 },
		{ Id = "DustCamp", Name = "Dust Camp", Kind = "camp", X = 300, Z = 1000 },
	} :: { Site },

	-- what each kind is made of: cluster rows around the site centre (studs; local -Z = the site's front)
	Kinds = {
		camp = {
			R = 46,
			Clusters = {
				{ Kind = "camp", X = 0, Z = 0, Kits = {
					{ Kit = "Tent", X = -8, Z = 0 },
					{ Kit = "Tent", X = 8, Z = 2, Yaw = 15 },
					{ Kit = "DrumGroup", X = 0, Z = -9, Variant = "fire", Count = 1 },
					{ Kit = "CrateStack", X = -1, Z = 11, Count = 3 },
				} },
				{ Kind = "tower", X = 26, Z = -14, Kits = { { Kit = "Watchtower", X = 0, Z = 0 } } },
				{ Kind = "cover", X = -24, Z = -16, Kits = {
					{ Kit = "SandbagNest", X = 0, Z = 0 },
					{ Kit = "SandbagLine", X = 11, Z = 2, Length = 10 },
				} },
				{ Kind = "wreck", X = -22, Z = 24, Yaw = 30, Kits = { { Kit = "Wreck", X = 0, Z = 0, Variant = "truck" } } },
			} :: { ClusterRow },
		},
		village = {
			R = 50,
			Clusters = {
				{ Kind = "ruins", X = -16, Z = -10, Kits = { { Kit = "RuinedHouse", X = 0, Z = 0 }, { Kit = "CompoundWall", X = 14, Z = 6, Length = 16 } } },
				{ Kind = "ruins", X = 18, Z = -6, Yaw = 90, Kits = { { Kit = "RuinedHouse", X = 0, Z = 0 } } },
				{ Kind = "ruins", X = 4, Z = 22, Yaw = 200, Kits = { { Kit = "RuinedHouse", X = 0, Z = 0 }, { Kit = "DrumGroup", X = 10, Z = -2, Count = 2 } } },
				{ Kind = "well", X = 0, Z = 4, Kits = { { Kit = "Fountain", X = 0, Z = 0, Variant = "well" } } },
			} :: { ClusterRow },
		},
		oil = {
			R = 46,
			Clusters = {
				{ Kind = "pumpjack", X = -16, Z = 0, Kits = { { Kit = "Pumpjack", X = 0, Z = 0 }, { Kit = "Pumpjack", X = 12, Z = 4, Yaw = 20 } } },
				{ Kind = "tanks", X = 20, Z = -8, Kits = { { Kit = "FuelTank", X = 0, Z = 0 }, { Kit = "DrumGroup", X = 9, Z = 8, Count = 3 } } },
				{ Kind = "pipes", X = 0, Z = 20, Kits = { { Kit = "PipeRun", X = 0, Z = 0, Length = 40 } } },
			} :: { ClusterRow },
		},
		depot = {
			R = 46,
			Clusters = {
				{ Kind = "containers", X = -14, Z = 0, Kits = { { Kit = "ContainerStack", X = 0, Z = 0, Count = 3 } } },
				{ Kind = "crates", X = 14, Z = -6, Kits = {
					{ Kit = "CrateStack", X = 0, Z = 0, Count = 4 },
					{ Kit = "CrateStack", X = 7, Z = 5, Count = 3, Variant = "ammo" },
					{ Kit = "Jersey", X = -6, Z = -10 },
					{ Kit = "Jersey", X = 0, Z = -10 },
				} },
				{ Kind = "fence", X = 0, Z = -28, Kits = { { Kit = "WireFence", X = 0, Z = 0, Length = 48 } } },
				{ Kind = "wreck", X = 18, Z = 22, Kits = { { Kit = "Wreck", X = 0, Z = 0, Variant = "truck" } } },
			} :: { ClusterRow },
		},
		checkpoint = {
			R = 40,
			Clusters = {
				{ Kind = "checkpoint", X = 0, Z = 0, Kits = { { Kit = "Checkpoint", X = 0, Z = 0 } } },
				{ Kind = "barricade", X = -2, Z = -16, Kits = {
					{ Kit = "Jersey", X = -8, Z = 0 },
					{ Kit = "Jersey", X = 8, Z = 0 },
					{ Kit = "SandbagNest", X = 20, Z = 4 },
				} },
			} :: { ClusterRow },
		},
		overwatch = {
			R = 44,
			Clusters = {
				-- the sniper perch: the Rooftop Sniper activity stands on this tower's deck
				{ Kind = "tower", X = 0, Z = 0, Kits = { { Kit = "Watchtower", X = 0, Z = 0 }, { Kit = "SandbagArc", X = 0, Z = -10 } } },
				{ Kind = "bunker", X = -6, Z = 26, Kits = { { Kit = "Bunker", X = 0, Z = 0 } } },
				{ Kind = "cover", X = 24, Z = 8, Kits = { { Kit = "SandbagLine", X = 0, Z = 0, Length = 15 }, { Kit = "Tent", X = 0, Z = 12 } } },
			} :: { ClusterRow },
		},
		tankyard = {
			R = 46,
			Clusters = {
				{ Kind = "wrecks", X = -14, Z = -8, Kits = { { Kit = "Wreck", X = 0, Z = 0, Variant = "tank" }, { Kit = "Wreck", X = 4, Z = 14, Variant = "tank", Yaw = 40 } } },
				{ Kind = "wrecks", X = 18, Z = 6, Yaw = 70, Kits = { { Kit = "Wreck", X = 0, Z = 0, Variant = "gun" }, { Kit = "Wreck", X = -4, Z = 12, Variant = "truck" } } },
				{ Kind = "cover", X = 0, Z = -26, Kits = { { Kit = "SandbagArc", X = 0, Z = 0 }, { Kit = "Jersey", X = 9, Z = 1 } } },
			} :: { ClusterRow },
		},
	} :: { [string]: { R: number, Clusters: { ClusterRow } } },
}

return WorldSitesConfig
