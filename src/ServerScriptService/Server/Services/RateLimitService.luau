--!strict
--[[ Per-player remote rate limiting ]]

local RateLimitService = {}

type Bucket = { tokens: number, lastRefill: number }

local buckets: { [number]: { [string]: Bucket } } = {}
local DEFAULT_RATE = 8 -- tokens per second
local DEFAULT_BURST = 12

function RateLimitService.Init()
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		buckets[player.UserId] = nil
	end)
end

local function getBucket(userId: number, key: string, rate: number, burst: number): Bucket
	if not buckets[userId] then
		buckets[userId] = {}
	end
	local userBuckets = buckets[userId]
	local b = userBuckets[key]
	if not b then
		b = { tokens = burst, lastRefill = os.clock() }
		userBuckets[key] = b
	end
	local now = os.clock()
	local elapsed = now - b.lastRefill
	b.tokens = math.min(burst, b.tokens + elapsed * rate)
	b.lastRefill = now
	return b
end

function RateLimitService.Allow(player: Player, key: string, rate: number?, burst: number?): boolean
	local r = rate or DEFAULT_RATE
	local burstAmt = burst or DEFAULT_BURST
	local b = getBucket(player.UserId, key, r, burstAmt)
	if b.tokens >= 1 then
		b.tokens -= 1
		return true
	end
	return false
end

return RateLimitService
