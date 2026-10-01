--!strict
--[[ Code Bot v185: DOUBLE WEEKEND server side (Shared/Configs/EventConfig). The one place the grants ask "how much
	extra right now". Server only: os.time() is the server's UTC clock; the owner preview switch is a ReplicatedStorage
	attribute only the server writes (a client-side attribute change never replicates to the server). ]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EventConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Configs"):WaitForChild("EventConfig")) :: any

local DoubleEvent = {}

function DoubleEvent.PreviewOn(): boolean
	local v = ReplicatedStorage:GetAttribute(EventConfig.PreviewAttr)
	if v == nil then
		return EventConfig.OwnerFirst == true
	end
	return v == true
end

-- owner /eventpreview on|off (AdminService); also published so the owner's client banner follows it
function DoubleEvent.SetPreview(on: boolean)
	ReplicatedStorage:SetAttribute(EventConfig.PreviewAttr, on == true)
end

function DoubleEvent.Init()
	if ReplicatedStorage:GetAttribute(EventConfig.PreviewAttr) == nil then
		ReplicatedStorage:SetAttribute(EventConfig.PreviewAttr, EventConfig.OwnerFirst == true)
	end
end

function DoubleEvent.ActiveFor(player: Player?): boolean
	if typeof(player) ~= "Instance" then
		return false
	end
	return EventConfig.ActiveFor((player :: Player).UserId, os.time(), DoubleEvent.PreviewOn())
end

local function clampMult(m: any): number
	local n = tonumber(m) or 1
	if n ~= n or n < 1 then
		return 1
	end
	return math.min(n, 5)
end

function DoubleEvent.IsKillReason(reason: string?): boolean
	return reason ~= nil and EventConfig.KillReasons[reason] == true
end

-- cash x for `reason` (called only inside EconomyService's non-exempt stack): kill reasons -> KillMult
function DoubleEvent.CashMult(player: Player, reason: string?): number
	if not DoubleEvent.ActiveFor(player) then
		return 1
	end
	local key = reason or ""
	if EventConfig.KillReasons[key] then
		return clampMult(EventConfig.KillMult)
	end
	if EventConfig.CashExemptReasons[key] then
		return 1
	end
	return clampMult(EventConfig.CashMult)
end

-- XP x for `reason` (XPService.AddXP, after the pass multiplier's own exemptions): kill reasons -> KillMult
function DoubleEvent.XPMult(player: Player, reason: string?): number
	if not DoubleEvent.ActiveFor(player) then
		return 1
	end
	local key = reason or ""
	if EventConfig.KillReasons[key] then
		return clampMult(EventConfig.KillMult)
	end
	if EventConfig.XPExemptReasons[key] then
		return 1
	end
	return clampMult(EventConfig.XPMult)
end

-- how many a kill counts for (missions KillPlayer / KillNPC, MOST KILLS / ARMY KILLS boards)
function DoubleEvent.KillCount(player: Player): number
	if not DoubleEvent.ActiveFor(player) then
		return 1
	end
	return math.floor(clampMult(EventConfig.KillMult))
end

-- offline pay factor for a counted span [fromUnix, fromUnix + seconds): only the part inside the window is doubled
function DoubleEvent.OfflineFactor(fromUnix: number, seconds: number): number
	if seconds <= 0 then
		return 1
	end
	local inside = EventConfig.OverlapSeconds(fromUnix, fromUnix + seconds)
	return 1 + (clampMult(EventConfig.CashMult) - 1) * inside / seconds
end

return DoubleEvent
