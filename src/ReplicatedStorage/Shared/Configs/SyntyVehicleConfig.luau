--!strict
--[[ claude-bud (Shaun 2026-10-02, item 4): DRIVABLE SYNTY VEHICLES. Shaun's paid Synty Polygon Military Vehicles pack
	(119390702773907, audited by Code Bot: 0 scripts, docs/we_check2_job67_b1.txt; batch 3 already uses its destroyed
	variants as wrecks) dresses the drivable wheeled vehicles. Dress-only, like every store body
	(VisualAssetService.TryAttachVehicleVisual, Fit = "Kit"): the Part-kit chassis keeps driving (the same thumbstick
	controls, the same light hinge physics, the same seats); the Synty body is anchored-free, welded, massless and never
	collides (the kit stays the collider).

	Candidates: the pack's intact vehicle names, tried in order (the destroyed ones on record are
	"SM_Veh_Truck_01_Destroyed", "SM_Veh_Pickup_Technical_Destroyed_01", "SM_Veh_SUV_Destroyed_01"; Synty names the intact
	model the same without "_Destroyed"). The first one the pack really holds is used; none = today's body exactly (a
	missing name is logged once by VisualAssetService and never retried). Synty models are long along Z with the front
	toward +Z, so Yaw 180 points the front down the kit's -Z (its LookVector).
	OwnerFirst by the VEHICLE OWNER. Tanks stay on their Part kits (owner list: low-poly tanks declined; a Synty hull would
	hide the kit turret). ]]

local SyntyVehicleConfig = {
	Enabled = true,
	OwnerFirst = true, -- NEW-OWNER-FIRST (claude-bud item 4): flip after Shaun's phone test
	PackId = 119390702773907,
	Rows = {
		ArmoredTruck = { Candidates = { "SM_Veh_Truck_01", "SM_Veh_Truck_02", "SM_Veh_Truck_Cargo_01" }, Yaw = 180 },
		ArmedJeep = { Candidates = { "SM_Veh_Pickup_Technical_01", "SM_Veh_Pickup_Technical_02" }, Yaw = 180, KeepVisible = { "GunMount", "Barrel" } },
		ScoutCar = { Candidates = { "SM_Veh_SUV_01", "SM_Veh_Pickup_Small_01" }, Yaw = 180 },
	} :: { [string]: { Candidates: { string }, Yaw: number, KeepVisible: { string }? } },
}

local refsCache: { any }? = nil
local byVehicle: { [string]: { any } } = {}

-- every candidate as a VisualAssetService AssetRef (pure; cached): the pack splitter extracts each, the vehicle takes
-- the first that exists
function SyntyVehicleConfig.Refs(): { any }
	if refsCache then
		return refsCache :: { any }
	end
	local out: { any } = {}
	for vehicleId, row in pairs(SyntyVehicleConfig.Rows) do
		local list: { any } = {}
		for _, name in ipairs(row.Candidates) do
			local ref = {
				ModelAssetId = SyntyVehicleConfig.PackId,
				ChildName = name,
				Fit = "Kit",
				Yaw = row.Yaw,
				HideKit = true,
				KeepVisible = row.KeepVisible,
				StripDecals = true,
				Note = "claude-bud item 4: Synty drivable body (" .. vehicleId .. ")",
			}
			table.insert(list, ref)
			table.insert(out, ref)
		end
		byVehicle[vehicleId] = list
	end
	refsCache = out
	return out
end

-- the candidate refs for a vehicle id, in order (pure)
function SyntyVehicleConfig.RefsFor(vehicleId: string): { any }
	SyntyVehicleConfig.Refs()
	return byVehicle[vehicleId] or {}
end

return SyntyVehicleConfig
