--!strict
--[[
	Levels 1–100 via formula.
	XP to go from level L to L+1: floor(100 * L ^ 1.45)
	Rewards granted on level-up (cash + optional gold every 5).
]]

local LevelConfig = {}

LevelConfig.MaxLevel = 100
LevelConfig.MaxLevelBeforePrestige = 100

function LevelConfig.GetXPRequiredForLevel(level: number): number
	if level < 1 then
		return 0
	end
	if level >= LevelConfig.MaxLevel then
		return math.huge
	end
	return math.floor(100 * (level ^ 1.45))
end

function LevelConfig.GetTotalXPForLevel(level: number): number
	local total = 0
	for l = 1, level - 1 do
		total += LevelConfig.GetXPRequiredForLevel(l)
	end
	return total
end

function LevelConfig.GetLevelUpReward(newLevel: number): { Cash: number, Gold: number }
	local cash = 500 + (newLevel * 150)
	local gold = if newLevel % 5 == 0 then math.floor(newLevel / 5) else 0
	return { Cash = cash, Gold = gold }
end

-- Explicit first 20 for designers / BALANCE.md
LevelConfig.Preview = {}
for i = 1, 20 do
	LevelConfig.Preview[i] = {
		Level = i,
		XPToNext = LevelConfig.GetXPRequiredForLevel(i),
		Reward = LevelConfig.GetLevelUpReward(i + 1),
	}
end

return LevelConfig
