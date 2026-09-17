--!strict
--[[ STUB — Clans. ]]

local ClanService = {}

function ClanService.Init(_deps: { [string]: any })
	-- TODO: create/join/leave clan, shared bank, wars
end

function ClanService.CreateClan(_leader: Player, _name: string): (boolean, string?)
	return false, "NotImplemented"
end

function ClanService.GetClanId(player: Player): string?
	-- wired when DataService available via deps if needed
	return nil
end

return ClanService
