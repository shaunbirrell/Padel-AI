--!strict
--[[
	claude-bud JOB 32 (2026-09-30): the registry of enterable buildings (WorldKits registers each PlazaHouse it builds).
	Server only, pure maths after registration: no workspace lookups.
	  Register(id, cf, size, doorOut)  cf = the building's ground frame (local -Z = its front / door side), size = its box
	                                   (X across, Y up from the ground, Z deep), doorOut = how far out the army waits
	  At(pos) -> Entry?                the building pos is inside or on top of (the box grown 0.6 sideways, from 1 below
	                                   the ground up to the roof + 8), or nil
	  List() / Clear()
	Entry.Door = the street-side waiting point in front of the door (ground height); Entry.Face = the direction
	looking AT the building from there (the army's formation faces it, so the block forms behind, out in the street).
]]

local Enterables = {}

export type Entry = { Id: string, CF: CFrame, Size: Vector3, Door: Vector3, Face: Vector3 }

local list: { Entry } = {}

function Enterables.Register(id: string, cf: CFrame, size: Vector3, doorOut: number)
	for i = #list, 1, -1 do
		if list[i].Id == id then
			table.remove(list, i)
		end
	end
	local door = (cf * CFrame.new(0, 0, -size.Z * 0.5 - math.max(2, doorOut))).Position
	local face = -cf.LookVector -- from the street toward the building
	table.insert(list, { Id = id, CF = cf, Size = size, Door = door, Face = Vector3.new(face.X, 0, face.Z).Unit })
end

function Enterables.At(pos: Vector3): Entry?
	for _, e in ipairs(list) do
		local lp = e.CF:PointToObjectSpace(pos)
		if math.abs(lp.X) <= e.Size.X * 0.5 + 0.6 and math.abs(lp.Z) <= e.Size.Z * 0.5 + 0.6 and lp.Y >= -1 and lp.Y <= e.Size.Y + 8 then
			return e
		end
	end
	return nil
end

function Enterables.List(): { Entry }
	return list
end

function Enterables.Clear()
	table.clear(list)
end

return Enterables
