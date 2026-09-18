--!strict
--[[ Ownership sync, bonus aggregation, radar entitlement helpers. ]]

local TerritoryOwnership = {}

export type Bindings = {
	territories: { [string]: any },
	ownerTypes: () -> any,
	DataService: any,
}

local B: Bindings

function TerritoryOwnership.Bind(bindings: Bindings)
	B = bindings
end

function TerritoryOwnership.CountPersonal(userId: number): number
	local n = 0
	local ot = B.ownerTypes()
	for _, rt in pairs(B.territories) do
		if rt.OwnerType == ot.Player and rt.OwnerUserId == userId then
			n += 1
		end
	end
	return n
end

function TerritoryOwnership.SyncProfile(player: Player)
	local profile = B.DataService.GetProfile(player)
	if not profile then
		return
	end
	if typeof(profile.Territories) ~= "table" then
		profile.Territories = {}
	end
	for id in pairs(profile.Territories) do
		profile.Territories[id] = nil
	end
	local ot = B.ownerTypes()
	for id, rt in pairs(B.territories) do
		if rt.OwnerType == ot.Player and rt.OwnerUserId == player.UserId then
			profile.Territories[id] = true
		end
	end
	B.DataService.MarkDirty(player)
end

function TerritoryOwnership.BonusesForPlayer(player: Player): { [string]: number }
	local bonuses: { [string]: number } = {}
	local profile = B.DataService and B.DataService.GetProfile(player)
	local clanId = if profile then profile.ClanId else nil
	local ot = B.ownerTypes()
	for _, rt in pairs(B.territories) do
		local owns = (rt.OwnerType == ot.Player and rt.OwnerUserId == player.UserId)
			or (rt.OwnerType == ot.Clan and clanId ~= nil and rt.ClanId == clanId)
		if owns then
			local key = rt.Def.BonusType
			local value = rt.Def.BonusValue
			bonuses[key] = (bonuses[key] or 0) + value
		end
	end
	return bonuses
end

function TerritoryOwnership.HasRadar(player: Player): boolean
	local b = TerritoryOwnership.BonusesForPlayer(player)
	return (b.MinimapReveal or 0) > 0
end

return TerritoryOwnership
