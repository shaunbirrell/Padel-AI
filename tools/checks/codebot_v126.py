# Code Bot Roblox v126 (2026-09-30): owner "the Speed Boost barely makes me faster". Live proof (Open Cloud probe):
# shaunie6 owns the Speed Pass (1998656357) AND Entitlements.SpeedBoost, so SpeedMultFor = max(1.15, 1.25) = 1.25 ->
# WalkSpeed 20 (+4 studs/s); MonetizationService is the only server writer of a player's WalkSpeed (no armour / gun /
# combat slowdown). Fix: Speed Boost x1.6 (25.6), Speed Pass x1.4 (22.4), MAX_WALK_SPEED_MULT 1.75, the paid multiplier
# applied AFTER any other WalkSpeed writer + re-applied on seat exit, army catch-up cap 28 -> 40. Prices / Ids unchanged.
from pathlib import Path as _P126


def _cb126(cond, label):
    if "ok" in globals() and "bad" in globals():
        (ok if cond else bad)(label)
    else:
        print(("PASS " if cond else "FAIL ") + label)
        if not cond:
            raise SystemExit(1)


def _rd126(p):
    q = _P126(p)
    return q.read_text(encoding="utf-8") if q.is_file() else ""


def _fn126(src, head):
    i = src.find(head)
    if i < 0:
        return ""
    j = src.find("\nend\n", i)
    return src[i:j + 5] if j > 0 else src[i:]


_S126 = "src/ServerScriptService/Server/"
for _f in (_S126 + "Services/DataService.luau", _S126 + "Services/BaseService.luau", _S126 + "EarlyRemotes.server.luau"):
    _cb126('SetAttribute("WE_Build", 126)' in _rd126(_f), "CODEBOT v126: WE_Build=126 " + _f.rsplit("/", 1)[-1])
_cb126("WE_Build=126" in _rd126(_S126 + "Services/DataService.luau"), "CODEBOT v126: DataService profile-loaded log says WE_Build=126")

_mc = _rd126("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau")
_sp = _mc[_mc.find("ImpulseSpeed = {"):][:700]
_sb = _mc[_mc.find("\t\tSpeedBoost = {"):][:900]
_cb126("Id = 1998656357," in _sp and "RobuxPrice = 99," in _sp and "WalkSpeedMult = 1.4," in _sp and 'Description = "Run 40% faster, forever"' in _sp,
       "CODEBOT v126: Speed Pass Id / 99 R$ unchanged, x1.4, 'Run 40% faster, forever'")
_cb126("Id = 3713839342," in _sb and "RobuxPrice = 99," in _sb and "OneTime = true" in _sb and "WalkSpeedMult = 1.6," in _sb and 'Description = "Run 60% faster, forever"' in _sb,
       "CODEBOT v126: Speed Boost Id / 99 R$ / OneTime unchanged, x1.6, 'Run 60% faster, forever'")

_ms = _rd126(_S126 + "Services/MonetizationService.luau")
_cb126("local MAX_WALK_SPEED_MULT = 1.75" in _ms, "CODEBOT v126: MAX_WALK_SPEED_MULT = 1.75 (x1.6 fits; sane cap 28)")
_cb126("SPEED_BOOST_MULT" not in _ms, "CODEBOT v126: no hard-coded speed multiplier (config only)")
_wp = _fn126(_ms, "local function writePaidSpeed(")
_cb126("MonetizationService.SpeedMultFor(player)" in _wp and "default * MAX_WALK_SPEED_MULT" in _wp and "MoveDebug).SetWalkSpeed(hum, want, who)" in _wp,
       "CODEBOT v126: paid WalkSpeed = base x SpeedMultFor, capped, via the tagged MoveDebug setter")
_ap = _fn126(_ms, "local function applySpeedBoostToCharacter(")
_cb126('GetPropertyChangedSignal("WalkSpeed")' in _ap and "writePaidSpeed(player, hum, hum.WalkSpeed" in _ap,
       "CODEBOT v126: another WalkSpeed writer -> the paid multiplier is applied on top of its value (never silently cancelled)")
_cb126("hum.Seated:Connect" in _ap and "not active" in _ap, "CODEBOT v126: leaving a seat (vehicle exit) re-applies the paid speed")
_cb126("player.CharacterAdded:Connect" in _ms and "applySpeedBoostToCharacter(player)" in _ms, "CODEBOT v126: respawn re-applies (CharacterAdded)")

# no other server write to a player's WalkSpeed (NPC / soldier humanoids are fine)
_cb126(_rd126(_S126 + "Modules/MoveDebug.luau").count("hum.WalkSpeed = value") == 1, "CODEBOT v126: MoveDebug.SetWalkSpeed is the one tagged player writer")
_ae = _rd126(_S126 + "Services/AntiExploitService.luau")
_cb126("WalkSpeed" not in _ae and "AssemblyLinearVelocity" not in _ae, "CODEBOT v126: AntiExploit has no speed check that could flag the paid speed")

_ac = _rd126("src/ReplicatedStorage/Shared/Configs/ArmyConfig.luau")
_cb126("MaxSpeed = 40, -- v126: was 28" in _ac, "CODEBOT v126: Follow.CatchUp MaxSpeed 40 (25.6 x 1.5 = 38.4)")
_cb126("MatchMult = 1.08," in _ac and "MaxSpeed = 50," in _ac, "CODEBOT v126: Follow2 MatchMult 1.08 / MaxSpeed 50 cover 25.6 x 1.08 = 27.6")
_cb126("PreferMesh = true" not in _rd126("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau"), "CODEBOT v126: PreferMesh stays OFF")
