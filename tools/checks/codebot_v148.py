# Code Bot Roblox v148 (2026-09-30): the two remaining top live errors (Creator Hub error report CSV).
#  * "Failed to load animation with sanitized ID" (1,878 client + 277 server): not game assets. Roblox's own face
#    bundles The Winning Smile (957), Shiny Teeth (265345), Silly Fun (299652), Woman Face (948) ship moods whose
#    Animation ids (104666063103723, 122193759333439, 121132383996019, 96806611330323; + 114302219876492) are uploaded
#    by user 8923762 and fail AnimationClipProvider in this place. Server/AvatarMoodGuard swaps a player's
#    Animate.mood for Roblox's default mood 14366558676 (loads here) unless the id loads.
#  * "value of type nil cannot be converted to a number" (GateDefenseService spawnGuardModel, via BaseGuards
#    spawnTower / ThinkTowers): the tower stats table had no GuardWalkSpeed -> humanoid.WalkSpeed = nil.
# Unchanged: prices, passes, shop, ads, server size 10, PreferMesh OFF, WE_Building*, no fast travel. WE_Build 148.
from pathlib import Path as _P148


def _cb148(cond, label):
	if "ok" in globals() and "bad" in globals():
		(ok if cond else bad)(label)
	else:
		print(("PASS " if cond else "FAIL ") + label)
		if not cond:
			raise SystemExit(1)


def _rd148(p):
	q = _P148(p)
	return q.read_text(encoding="utf-8") if q.is_file() else ""


_S148 = "src/ServerScriptService/Server/"
_C148 = "src/ReplicatedStorage/Shared/Configs/"

# v149 (Code Bot Roblox): the WE_Build=148 pins are superseded in tools/checks/codebot_v149.py (WE_Build=149).
# for _f in (_S148 + "Services/DataService.luau", _S148 + "Services/BaseService.luau", _S148 + "EarlyRemotes.server.luau"):
# 	_cb148('SetAttribute("WE_Build", 148)' in _rd148(_f), "CODEBOT v148: WE_Build=148 " + _f.rsplit("/", 1)[-1])
# _cb148("WE_Build=148" in _rd148(_S148 + "Services/DataService.luau"), "CODEBOT v148: DataService profile-loaded log says WE_Build=148")

# tower guards: the stats table carries every field spawnGuardModel assigns to the Humanoid
_BG = _rd148(_S148 + "Modules/BaseGuards.luau")
_GD = _rd148(_S148 + "Services/GateDefenseService.luau")
_cb148("local stats = { GuardHealth = C.Tower.Health, GuardDamage = C.Tower.Damage, GuardWalkSpeed = 0 }" in _BG,
	"CODEBOT v148: BaseGuards spawnTower passes GuardWalkSpeed (was nil -> 'value of type nil cannot be converted to a number')")
_cb148("humanoid.WalkSpeed = tonumber(stats.GuardWalkSpeed) or humanoid.WalkSpeed" in _GD
	and "local guardHp = tonumber(stats.GuardHealth) or humanoid.MaxHealth" in _GD,
	"CODEBOT v148: spawnGuardModel never assigns nil to a Humanoid number")
_cb148("humanoid.WalkSpeed = stats.GuardWalkSpeed\n" not in _GD, "CODEBOT v148: the raw nil-able WalkSpeed assignment is gone")
_cb148("g.Root.Anchored = true" in _BG, "CODEBOT v148: tower guard stays anchored on its platform (WalkSpeed 0 is moot)")

# avatar mood guard
_RC = _rd148(_C148 + "RigConfig.luau")
_AM = _rd148(_S148 + "AvatarMoodGuard.server.luau")
_cb148(_AM != "", "CODEBOT v148: Server/AvatarMoodGuard.server.luau exists (runs at server start, before Bootstrap init)")
_cb148("AvatarMood = {" in _RC and 'FallbackId = "rbxassetid://14366558676"' in _RC, "CODEBOT v148: RigConfig.AvatarMood fallback = Roblox default mood 14366558676")
for _id in ("104666063103723", "114302219876492", "122193759333439", "96806611330323", "121132383996019"):
	_cb148(_id in _RC, "CODEBOT v148: known-bad mood id listed " + _id)
_cb148("AnimationClipProvider:GetAnimationClipAsync" in _AM, "CODEBOT v148: unknown mood ids judged by the place's own animation permission")
_cb148('p.Name ~= "mood"' in _AM and 'a.Name == "Animate"' in _AM, "CODEBOT v148: only Animate.mood Animations are touched")
_cb148("plr.CharacterAdded:Connect(watchCharacter)" in _AM and "char.DescendantAdded:Connect" in _AM,
	"CODEBOT v148: player characters only; late Animate / mood caught")
_cb148("LoadAnimation" not in _AM and "SoldierService" not in _AM and "WE_Rig" not in _AM,
	"CODEBOT v148: soldiers / army rigs untouched by the mood guard")
# the army animation ids stay Roblox-owned and unchanged
for _id in ("182393478", "180435571", "180426354", "183817498"):
	_cb148(_id in _RC, "CODEBOT v148: RigConfig soldier animation id unchanged " + _id)
_cb148("3972151362" in _rd148(_C148 + "HudConfig.luau"), "CODEBOT v148: RPG hold stays 3972151362")
