--!strict
--[[
	Code Bot v153 (Shaun, 2026-09-30: "ship the sales fixes"): the server's record of a soft offer it SENT but the
	client has not yet confirmed it SHOWED. Root cause it fixes: MonetizationService used to set
	profile.StarterBundleOffered = true the moment it fired the StarterBundleOffer remote. The client then often
	held the card (driving the 4x4 / tutorial card / combat), dropped it after HudConfig.Offer.DropAfterQueuedSeconds,
	and the saved flag meant the Starter Pack never came back for that player.
	Now: Sent() records a pending send; the client answers on the OfferResult remote ("shown" / "dropped" /
	"refused") with the AckId it was given. Only "shown" marks the offer done (the caller saves the flag then);
	"dropped" / "refused" / no answer within AckTimeoutSeconds = re-queue after RequeueSeconds, at most
	MaxSendsPerSession sends per offer per session (then it waits for the next session, still unmarked).
	Pure Lua state (no instances, no yields, no clock of its own): tools/sim/run_first_offer_test.py drives it.
]]

local OfferLedger = {}
OfferLedger.__index = OfferLedger

export type Config = {
	AckTimeoutSeconds: number,
	RequeueSeconds: number,
	MaxSendsPerSession: number,
}

type Entry = {
	Sends: number,
	Pending: boolean,
	Seq: number,
	SentAt: number,
	Slot: any?, -- the caller's soft-offer slot claim, handed back on a drop so the slot can be refunded
	Shown: boolean,
}

export type Action = "mark" | "requeue" | "giveup" | "ignore"

function OfferLedger.new(cfg: Config)
	local self = setmetatable({}, OfferLedger)
	self.Cfg = cfg
	self.Users = {} :: { [number]: { [string]: Entry } }
	self.Seq = 0
	return self
end

local function entryOf(self: any, uid: number, key: string): Entry
	local u = self.Users[uid]
	if u == nil then
		u = {}
		self.Users[uid] = u
	end
	local e = u[key]
	if e == nil then
		e = { Sends = 0, Pending = false, Seq = 0, SentAt = -math.huge, Slot = nil, Shown = false }
		u[key] = e
	end
	return e :: Entry
end

-- true while a send waits for the client's answer (the caller must not send the same offer again)
function OfferLedger.IsPending(self: any, uid: number, key: string): boolean
	local u = self.Users[uid]
	local e = u and u[key]
	return e ~= nil and e.Pending == true
end

-- true once this session already spent every allowed send (or the client confirmed it shown)
function OfferLedger.Exhausted(self: any, uid: number, key: string): boolean
	local u = self.Users[uid]
	local e = u and u[key]
	if e == nil then
		return false
	end
	return e.Shown or e.Sends >= math.max(1, self.Cfg.MaxSendsPerSession)
end

-- a send went out: returns the AckId the client must echo back
function OfferLedger.Sent(self: any, uid: number, key: string, now: number, slot: any?): number
	local e = entryOf(self, uid, key)
	self.Seq += 1
	e.Seq = self.Seq
	e.Sends += 1
	e.Pending = true
	e.SentAt = now
	e.Slot = slot
	return e.Seq
end

--[[ The client's answer (or "timeout" from the caller's AckTimeoutSeconds timer). Returns the action and, for a drop,
	the slot claim to refund. A stale / unknown AckId or an entry that is not pending is ignored. ]]
function OfferLedger.Result(self: any, uid: number, key: string, result: string, seq: number?, _now: number?): (Action, any?)
	local u = self.Users[uid]
	local e = u and u[key]
	if e == nil or not e.Pending then
		return "ignore", nil
	end
	if seq ~= nil and seq ~= e.Seq then
		return "ignore", nil
	end
	local slot = e.Slot
	e.Pending = false
	e.Slot = nil
	if result == "shown" then
		e.Shown = true
		return "mark", nil
	end
	if result ~= "dropped" and result ~= "refused" and result ~= "timeout" then
		e.Pending = true -- junk from the client: keep waiting (the timeout still ends it)
		e.Slot = slot
		return "ignore", nil
	end
	if e.Sends >= math.max(1, self.Cfg.MaxSendsPerSession) then
		return "giveup", slot
	end
	return "requeue", slot
end

-- the AckTimeoutSeconds timer of send `seq` ran out
function OfferLedger.Timeout(self: any, uid: number, key: string, seq: number, now: number?): (Action, any?)
	return OfferLedger.Result(self, uid, key, "timeout", seq, now)
end

function OfferLedger.Forget(self: any, uid: number)
	self.Users[uid] = nil
end

return OfferLedger
