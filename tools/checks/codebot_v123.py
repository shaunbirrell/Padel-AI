# Code Bot Roblox v123 (2026-09-30): the phone "running, he stops dead while his army is behind" investigation.
# /movedebug (admin) instrumentation, tagged writers for every server write to a player's WalkSpeed / PivotTo, and the
# design rule "the army never body-blocks / slows / stops a player" enforced independent of every rollout flag.
from pathlib import Path as _P123
import re as _re123

if "must_contain" not in globals():
    def must_contain(path, needle, label):
        text = _P123(path).read_text(encoding="utf-8") if _P123(path).is_file() else ""
        if needle in text:
            print("PASS " + label)
        else:
            print("FAIL " + label)
            raise SystemExit(1)


def _cb123(cond, label):
    if "ok" in globals() and "bad" in globals():
        (ok if cond else bad)(label)
    else:
        print(("PASS " if cond else "FAIL ") + label)
        if not cond:
            raise SystemExit(1)


_cb123_S = "src/ServerScriptService/Server/"
_cb123_CL = "src/StarterPlayer/StarterPlayerScripts/Client/"
_cb123_MD = _cb123_S + "Modules/MoveDebug.luau"
_cb123_AF = _cb123_S + "Modules/ArmyFollow.luau"


def _rd(p):
    q = _P123(p)
    return q.read_text(encoding="utf-8") if q.is_file() else ""


def _code(text):
    # strip -- comments (line) so a comment never satisfies / trips a pin
    return "\n".join(l.split("--", 1)[0] for l in text.splitlines())


for _f in (_cb123_S + "Services/DataService.luau", _cb123_S + "Services/BaseService.luau", _cb123_S + "EarlyRemotes.server.luau"):
    must_contain(_f, 'SetAttribute("WE_Build", 123)', "CODEBOT v123: WE_Build=123 " + _f.rsplit("/", 1)[-1])
must_contain(_cb123_S + "Services/DataService.luau", "WE_Build=123", "CODEBOT v123: DataService profile-loaded log says WE_Build=123")

# 1. collision: soldiers (ArmyNPCs) never collide with player characters (WE_PlayerChars), whatever the flags
_af = _rd(_cb123_AF)
must_contain(_cb123_AF, "PhysicsService:CollisionGroupSetCollidable(ArmyFollow.Group, ArmyFollow.PlayerGroup, false) -- v123: soldiers never block players",
             "CODEBOT v123: ArmyNPCs x WE_PlayerChars = false unconditionally")
_i = _af.find("local function ensureGroup()")
_j = _af.find("ArmyFollow.EnsureGroup = ensureGroup", _i)
_eg = _af[_i:_j]
_cb123(_i >= 0 and _eg.rfind("CollisionGroupSetCollidable(ArmyFollow.Group, ArmyFollow.PlayerGroup, false)") > _eg.find("pcall(hookPlayers)") and "pcall(hookNow)" in _eg,
       "CODEBOT v123: the unconditional no-collide + player hook run after the gated ones in ensureGroup")
must_contain(_cb123_AF, "hookNow = function()\n\tif playersHooked then", "CODEBOT v123: hookNow puts every player character in WE_PlayerChars (flag-free)")
must_contain(_cb123_AF, "\t\t\td.CollisionGroup = ArmyFollow.Group\n", "CODEBOT v123: every soldier part (late rig / accessory / v120 body parts) joins ArmyNPCs")
must_contain(_cb123_S + "Modules/BaseGuards.luau", 'PS:CollisionGroupSetCollidable(GUARD_GROUP, "WE_PlayerChars", false)', "CODEBOT v123: friendly base guards never body-block a player")
must_contain(_cb123_S + "Services/SquadOrdersService.luau", "SquadOrdersService._AF.PrepUnit(unit)", "CODEBOT v123: the group is set on the spawn frame (before any physics step)")
# the soldier body parts are non-colliding: RigBuilder rig parts and the squad kit (only the root collides, with the world)
must_contain(_cb123_S + "Modules/RigBuilder.luau", "p.CanCollide = false", "CODEBOT v123: RigBuilder rig parts CanCollide false")
must_contain(_cb123_CL + "Modules/RigAnimator.luau", "d.CanCollide = false", "CODEBOT v123: client escort copies CanCollide false")

# 2. no army / soldier code writes to a PLAYER's movement
_army_files = [_cb123_S + "Modules/" + f for f in ("ArmyController.luau", "ArmyFollow.luau", "SoldierController.luau", "FormationController.luau")]
_army_files.append(_cb123_S + "Services/SquadOrdersService.luau")
for _f in _army_files:
    _c = _code(_rd(_f))
    _bad = _re123.findall(r"(?:playerRoot|proot|ownerRoot|ownerHum|playerHum|character|char)\s*[.:]\s*(?:WalkSpeed|JumpPower|JumpHeight|PlatformStand|Anchored|CFrame|AssemblyLinearVelocity|PivotTo|ChangeState|Move)\b\s*[=(]", _c)
    _cb123(not _bad, "CODEBOT v123: no player movement write in " + _f.rsplit("/", 1)[-1] + (" " + str(_bad) if _bad else ""))
    _cb123(_re123.search(r"WalkSpeed\s*=\s*0\b", _c) is None, "CODEBOT v123: no WalkSpeed = 0 in " + _f.rsplit("/", 1)[-1])
# every server WalkSpeed write to a PLAYER goes through the tagged setter; every player PivotTo is tagged
must_contain(_cb123_S + "Services/MonetizationService.luau", 'MoveDebug).SetWalkSpeed(hum, base * mult, "MonetizationService.SpeedBoost")', "CODEBOT v123: Speed Pass WalkSpeed via the tagged setter")
_cb123("hum.WalkSpeed = base * mult" not in _code(_rd(_cb123_S + "Services/MonetizationService.luau")), "CODEBOT v123: no untagged Speed Pass write")
for _f, _tag in (("Modules/StreamPrefetch.luau", "StreamPrefetch.Place"), ("Services/CombatService/init.luau", "CombatService.TeleportToBase"),
                 ("Services/VehicleService.luau", "VehicleService.ExitSpot"), ("Modules/VehicleWaterGuard.luau", "VehicleWaterGuard.placeRider"),
                 ("Services/FallSafetyService.luau", "FallSafetyService")):
    must_contain(_cb123_S + _f, '"' + _tag + '"', "CODEBOT v123: tagged player move " + _tag)
# AntiExploitService has no movement / speed correction (no rubber-band): proven by absence
_ae = _code(_rd(_cb123_S + "Services/AntiExploitService.luau"))
_cb123(not _re123.search(r"PivotTo|\.CFrame\s*=|WalkSpeed|AssemblyLinearVelocity|Anchored", _ae), "CODEBOT v123: AntiExploitService never moves / slows a player (no rubber-banding)")

# 3. instrumentation (quiet unless WE_MoveDebug)
must_contain(_cb123_MD, 'MoveDebug.Attr = "WE_MoveDebug"', "CODEBOT v123: MoveDebug keyed on WE_MoveDebug")
must_contain(_cb123_MD, "[MOVEMENT OWNER LOST]", "CODEBOT v123: server flags a lost network owner")
must_contain(_cb123_MD, "[MOVEMENT SOLDIER CAN COLLIDE]", "CODEBOT v123: server flags a soldier part that could collide with him")
must_contain(_cb123_MD, "\t\t\tif MoveDebug.On(p) then\n\t\t\t\tlocal ok, err = pcall(sample, p, now)", "CODEBOT v123: the sampler runs only for debugging players")
must_contain(_cb123_S + "Services/SquadOrdersService.luau", "require(script.Parent.Parent.Modules.MoveDebug).Start({", "CODEBOT v123: MoveDebug started with the squads")
_mdc = _cb123_CL + "Modules/MoveDebugClient.luau"
must_contain(_mdc, "[MOVEMENT BLOCK DETECTED]", "CODEBOT v123: client block detector")
must_contain(_mdc, "local BLOCK_MOVE = 0.5\nlocal BLOCK_SPEED = 1\nlocal BLOCK_SECONDS = 0.25", "CODEBOT v123: block = |MoveDirection| > 0.5, speed < 1 for > 0.25 s")
must_contain(_mdc, "[MOVEMENT INPUT LOST]", "CODEBOT v123: client input-sink detector")
must_contain(_mdc, "l.Active = false", "CODEBOT v123: the debug label never takes a touch")
must_contain(_mdc, "setOn(player:GetAttribute(ATTR) == true)", "CODEBOT v123: client debug keyed on WE_MoveDebug")
must_contain(_cb123_CL + "Bootstrap.client.luau", 'safeInit("MoveDebugClient"', "CODEBOT v123: MoveDebugClient initialised")
_adm = _cb123_S + "Services/AdminService.luau"
must_contain(_adm, 'local isMoveDebugCmd = cmd == "movedebug"', "CODEBOT v123: /movedebug admin command")
must_contain(_adm, '{ "WE_MoveDebug", "/movedebug" }', "CODEBOT v123: /movedebug TextChatCommand")
_ai = _rd(_adm).find("local function onAdminChat(")
_cb123(_ai >= 0 and _rd(_adm).find("if not AdminService.IsAdmin(player) then", _ai) < _rd(_adm).find("if isMoveDebugCmd then", _ai),
       "CODEBOT v123: /movedebug is admin-allowlist only")
# 4. unchanged rules
must_contain("src/ReplicatedStorage/Shared/Configs/ArmyConfig.luau", "\t\tSteer = true,", "CODEBOT v123: Follow3.Steer kept")
must_contain("src/ReplicatedStorage/Shared/Configs/ArmyConfig.luau", "\t\tAttackSteer = true,", "CODEBOT v123: Follow3.AttackSteer kept")
