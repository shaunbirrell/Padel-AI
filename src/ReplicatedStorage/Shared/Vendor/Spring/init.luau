--!strict
--[[ VENDORED (W2 CC-3): RbxUtil Spring v1.0.0 by Stephen Leitnick, MIT licence (see LICENSE beside this file and
	THIRD_PARTY_NOTICES.md at the repo root).
	Upstream: https://github.com/Sleitnick/RbxUtil  modules/spring/init.luau
	Source:   raw.githubusercontent.com, branch main @ 31f9120fca021e3dec275b42bc7047d626962082, fetched 2026-09-24
	          (byte-identical to the copy reviewed in scratchpad/gap/vend/spring.luau).
	Local changes: none (the upstream file is already --!strict; only this header was added).
]]

--[=[
	@class Spring

	Simulates a critically damped spring. This is mostly just a wrapper around
	[`TweenService:SmoothDamp()`](https://create.roblox.com/docs/reference/engine/classes/TweenService#SmoothDamp).
]=]

local TweenService = game:GetService("TweenService")

local Spring = {}
Spring.__index = Spring

export type Spring<T> = typeof(setmetatable(
	{} :: {
		Current: T,
		Target: T,
		Velocity: T,
		SmoothTime: number,
		MaxSpeed: number,
	},
	Spring
))

--[=[
	Creates a new spring.

	The type `T` can be a `number`, `Vector2`, `Vector3`, or `CFrame`.

	@param initial T -- Initial value
	@param smoothTime number -- Approximate time it takes to reach target
	@param maxSpeed number -- Maximum speed (defaults to infinity)
]=]
function Spring.new<T>(initial: T, smoothTime: number, maxSpeed: number?): Spring<T>
	local self = setmetatable({
		Current = initial,
		Target = initial,
		Velocity = if typeof(initial) == "CFrame" then CFrame.identity else (initial :: any) * 0,
		SmoothTime = smoothTime,
		MaxSpeed = if maxSpeed ~= nil then maxSpeed else math.huge,
	}, Spring)

	return self
end

--[=[
	@within Spring
	@method Update

	Updates the spring. This method should be called continuously, even if the target value hasn't changed.

	```lua
	local newValue = spring:Update(dt)
	```

	@param deltaTime number
	@return T
]=]
function Spring.Update<T>(self: Spring<T>, dt: number): T
	self.Current, self.Velocity =
		TweenService:SmoothDamp(self.Current, self.Target, self.Velocity, self.SmoothTime, self.MaxSpeed, dt)

	return self.Current
end

--[=[
	@within Spring
	@method Impulse

	Impulses the spring.

	```lua
	spring:Impulse(rng:NextUnitVector() * 10)
	```

	@param velocity T
]=]
function Spring.Impulse<T>(self: Spring<T>, velocity: T)
	self.Velocity += velocity :: any
end

--[=[
	@within Spring
	@method Reset

	Resets the spring to the given value.

	@param value T
]=]
function Spring.Reset<T>(self: Spring<T>, value: T)
	self.Current = value
	self.Target = value
	self.Velocity = if typeof(self.Current) == "CFrame" then CFrame.identity else (self.Current :: any) * 0
end

return Spring
