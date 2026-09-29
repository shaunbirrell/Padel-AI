# Code Bot Roblox v122 (2026-09-30): wire the 7 nation-flag atlas IMAGE ids (uploaded by shaunie6 via Creator Hub)
# into NationFlagIds.Atlas. WE_Build 122.
from pathlib import Path as _P122

if "must_contain" not in globals():
    def must_contain(path, needle, label):
        text = _P122(path).read_text(encoding="utf-8") if _P122(path).is_file() else ""
        if needle in text:
            print("PASS " + label)
        else:
            print("FAIL " + label)
            raise SystemExit(1)

_cb122_S = "src/ServerScriptService/Server/"
for _f in (
    _cb122_S + "Services/DataService.luau",
    _cb122_S + "Services/BaseService.luau",
    _cb122_S + "EarlyRemotes.server.luau",
):
    must_contain(_f, 'SetAttribute("WE_Build", 122)', "CODEBOT v122: WE_Build=122 " + _f.rsplit("/", 1)[-1])
must_contain(_cb122_S + "Services/DataService.luau", "WE_Build=122", "CODEBOT v122: DataService profile-loaded log says WE_Build=122")

_cb122_ids = "src/ReplicatedStorage/Shared/Configs/NationFlagIds.luau"
for _k, _v in (
    ("Europe", 117922087338795),
    ("Americas", 129834397528036),
    ("Asia", 114871762121221),
    ("Africa", 132455042605948),
    ("MiddleEast", 88221072001528),
    ("Oceania", 82459247862229),
    ("Review", 98381294373531),
):
    must_contain(_cb122_ids, "\t\t%s = %d,\n" % (_k, _v), "CODEBOT v122: NationFlagIds.Atlas.%s image id wired" % _k)

must_contain("src/ReplicatedStorage/Shared/Configs/StructureVisualConfig.luau", "PreferMeshWhenAssetIdSet = false", "CODEBOT v122: PreferMesh stays OFF")
