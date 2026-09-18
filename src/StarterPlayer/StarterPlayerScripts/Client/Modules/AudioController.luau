--!strict
--[[
	Client audio helper — menu ambient music + UI / notification SFX.
	Respects ClientSettings music/SFX toggles with immediate mute/unmute
	(volumes 0 or restored). Placeholder SoundIds — swap in Studio.
]]

local SoundService = game:GetService("SoundService")

local ClientSettings = require(script.Parent.ClientSettings)

local AudioController = {}

--[[
	PLACEHOLDER SoundIds — replace in Studio with licensed / Roblox Creator Store audio.
	Music uses empty SoundId (muted-ready; no upload required) until Shaun sets one.
	Click / notify use built-in engine asset paths (no custom upload).
]]
local MUSIC_SOUND_ID = "" -- e.g. "rbxassetid://YOUR_AMBIENT_ID"
local CLICK_SOUND_ID = "rbxasset://sounds/electronicpingshort.wav"
local NOTIFY_SOUND_ID = "rbxasset://sounds/switch.wav"

local DEFAULT_MUSIC_VOLUME = 0.35
local DEFAULT_SFX_VOLUME = 0.55

local folder: Folder? = nil
local musicSound: Sound? = nil
local clickSound: Sound? = nil
local notifySound: Sound? = nil

local musicVolume = DEFAULT_MUSIC_VOLUME
local sfxVolume = DEFAULT_SFX_VOLUME

local function ensureFolder(): Folder
	if folder and folder.Parent then
		return folder
	end
	local existing = SoundService:FindFirstChild("WarEmpireAudio")
	if existing and existing:IsA("Folder") then
		folder = existing
		return existing
	end
	local f = Instance.new("Folder")
	f.Name = "WarEmpireAudio"
	f.Parent = SoundService
	folder = f
	return f
end

local function makeSound(name: string, soundId: string, looped: boolean, volume: number): Sound
	local parent = ensureFolder()
	local existing = parent:FindFirstChild(name)
	if existing and existing:IsA("Sound") then
		existing.SoundId = soundId
		existing.Looped = looped
		existing.Volume = volume
		return existing
	end
	local s = Instance.new("Sound")
	s.Name = name
	s.SoundId = soundId
	s.Looped = looped
	s.Volume = volume
	s.RollOffMode = Enum.RollOffMode.Linear
	s.Parent = parent
	return s
end

local function applyVolumes()
	if musicSound then
		if ClientSettings.ShouldPlayMusic() then
			musicSound.Volume = musicVolume
			if musicSound.SoundId ~= "" and not musicSound.IsPlaying then
				musicSound:Play()
			end
		else
			musicSound.Volume = 0
		end
	end
	if clickSound then
		clickSound.Volume = if ClientSettings.ShouldPlaySfx() then sfxVolume else 0
	end
	if notifySound then
		notifySound.Volume = if ClientSettings.ShouldPlaySfx() then sfxVolume else 0
	end
end

function AudioController.Init()
	musicSound = makeSound("MenuMusic", MUSIC_SOUND_ID, true, 0)
	clickSound = makeSound("UIClick", CLICK_SOUND_ID, false, 0)
	notifySound = makeSound("Notification", NOTIFY_SOUND_ID, false, 0)
	applyVolumes()
	if ClientSettings.ShouldPlayMusic() and musicSound and musicSound.SoundId ~= "" then
		musicSound:Play()
	end
	ClientSettings.OnChanged(applyVolumes)
end

--[[ UI button activate — respects SFX toggle. ]]
function AudioController.PlayClick()
	if not ClientSettings.ShouldPlaySfx() then
		return
	end
	if not clickSound then
		AudioController.Init()
	end
	if clickSound then
		clickSound.Volume = sfxVolume
		clickSound.TimePosition = 0
		clickSound:Play()
	end
end

--[[ Toast / reward ping — respects SFX toggle. ]]
function AudioController.PlayNotification()
	if not ClientSettings.ShouldPlaySfx() then
		return
	end
	if not notifySound then
		AudioController.Init()
	end
	if notifySound then
		notifySound.Volume = sfxVolume
		notifySound.TimePosition = 0
		notifySound:Play()
	end
end

function AudioController.GetMusicVolume(): number
	return musicVolume
end

function AudioController.GetSfxVolume(): number
	return sfxVolume
end

return AudioController
