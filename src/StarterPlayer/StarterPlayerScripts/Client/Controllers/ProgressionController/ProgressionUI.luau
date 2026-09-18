--!strict
--[[ Shared Progression UI helpers — reward formatting + debounced refresh. ]]

local ProgressionUI = {}

function ProgressionUI.FormatReward(reward: any): string
	if typeof(reward) ~= "table" then
		return ""
	end
	local parts = {}
	if typeof(reward.Cash) == "number" and reward.Cash > 0 then
		table.insert(parts, string.format("$%d", reward.Cash))
	end
	if typeof(reward.Gold) == "number" and reward.Gold > 0 then
		table.insert(parts, string.format("%dG", reward.Gold))
	end
	return table.concat(parts, " + ")
end

function ProgressionUI.Debounce(seconds: number): ((() -> ()) -> ())
	local token = 0
	return function(fn: () -> ())
		token += 1
		local my = token
		task.delay(seconds, function()
			if my == token then
				fn()
			end
		end)
	end
end

return ProgressionUI
