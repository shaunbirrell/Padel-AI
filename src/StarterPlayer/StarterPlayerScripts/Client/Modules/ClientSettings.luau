--!strict
--[[
	Local-only client preferences (music/SFX flags).
	Session-scoped (no DataStore). AudioController listens via OnChanged
	and mutes/restores volumes immediately. Economy stays server-authoritative.
]]

local ClientSettings = {}

local musicEnabled = true
local sfxEnabled = true

local listeners: { () -> () } = {}

local function notify()
	for _, cb in ipairs(listeners) do
		task.defer(cb)
	end
end

function ClientSettings.GetMusicEnabled(): boolean
	return musicEnabled
end

function ClientSettings.GetSfxEnabled(): boolean
	return sfxEnabled
end

function ClientSettings.SetMusicEnabled(enabled: boolean)
	musicEnabled = enabled == true
	notify()
end

function ClientSettings.SetSfxEnabled(enabled: boolean)
	sfxEnabled = enabled == true
	notify()
end

function ClientSettings.ToggleMusic(): boolean
	ClientSettings.SetMusicEnabled(not musicEnabled)
	return musicEnabled
end

function ClientSettings.ToggleSfx(): boolean
	ClientSettings.SetSfxEnabled(not sfxEnabled)
	return sfxEnabled
end

function ClientSettings.OnChanged(cb: () -> ())
	table.insert(listeners, cb)
end

--[[ Call before playing music/SFX — returns false when muted. ]]
function ClientSettings.ShouldPlayMusic(): boolean
	return musicEnabled
end

function ClientSettings.ShouldPlaySfx(): boolean
	return sfxEnabled
end

return ClientSettings
