# Code Bot Roblox v120 (2026-09-29): Army Soldier 7703684779 body for the player's army (Squad + escorts) and the base /
# tower guards (Guard, GateGuard), fallback Roblox Soldier 187790284; scripts / remotes stripped; cloth Textures;
# client helmet triangle budget. WE_Build 120. (Owner asked for "v119"; Claude-watch shipped v119 JOB 24c+25 first.)
from pathlib import Path as _P120
import re as _re120

if "must_contain" not in globals():
    def must_contain(path, needle, label):
        text = _P120(path).read_text(encoding="utf-8") if _P120(path).is_file() else ""
        if needle in text:
            print("PASS " + label)
        else:
            print("FAIL " + label)
            raise SystemExit(1)

_cb120_S = "src/ServerScriptService/Server/"
_cb120_C = "src/ReplicatedStorage/Shared/Configs/"
_cb120_VAC = _cb120_C + "VisualAssetConfig.luau"
_cb120_VAS = _cb120_S + "Services/VisualAssetService.luau"
_cb120_RB = _cb120_S + "Modules/RigBuilder.luau"
_cb120_RA = "src/StarterPlayer/StarterPlayerScripts/Client/Modules/RigAnimator.luau"
for _f in (
    _cb120_S + "Services/DataService.luau",
    _cb120_S + "Services/BaseService.luau",
    _cb120_S + "EarlyRemotes.server.luau",
):
    pass  # v121 (Code Bot Roblox): retired, superseded in tools/checks/codebot_v121.py: #must_contain(_f, 'SetAttribute("WE_Build", 120)', "CODEBOT v120: WE_Build=120 " + _f.rsplit("/", 1)[-1])
# v121 (Code Bot Roblox): retired, superseded in tools/checks/codebot_v121.py: #must_contain(_cb120_S + "Services/DataService.luau", "WE_Build=120", "CODEBOT v120: DataService profile-loaded log says WE_Build=120")

# the asset switch + fallback
must_contain(_cb120_VAC, "local SOLDIER_ASSET_ID = 7703684779\n", "CODEBOT v120: SoldierAssetId = Army Soldier 7703684779")
must_contain(_cb120_VAC, "local SOLDIER_FALLBACK_ID = 187790284\n", "CODEBOT v120: fallback = Roblox Soldier 187790284")
must_contain(_cb120_VAC, "\tSoldierAssetId = SOLDIER_ASSET_ID,", "CODEBOT v120: VisualAssetConfig.SoldierAssetId exposed")
for _k in ("Squad", "Guard", "GateGuard"):
    must_contain(_cb120_VAC, "\t\t" + _k + ' = { ModelAssetId = SOLDIER_ASSET_ID, FallbackAssetId = SOLDIER_FALLBACK_ID, Rig = "R6", Headwear = "Beret"',
                 "CODEBOT v120: Characters." + _k + " = Army Soldier rig with fallback")
must_contain(_cb120_VAC, 'Infantry = { ModelAssetId = 187790284, Rig = "R6", Headwear = "KitHelmet"', "CODEBOT v120: hostile infantry keeps the Roblox Soldier")
_vac = _P120(_cb120_VAC).read_text(encoding="utf-8")
if _re120.search(r"(ModelAssetId|FallbackAssetId|_ID)\s*=\s*3924234975", _vac):
    print("FAIL CODEBOT v120: rejected Rthro 3924234975 must not be wired"); raise SystemExit(1)
print("PASS CODEBOT v120: Rthro 3924234975 not wired")
must_contain(_cb120_VAS, "local function rigIdOf(ref: any): number", "CODEBOT v120: rigIdOf (fallback once the preferred rig failed for good)")
must_contain(_cb120_VAS, "if id > 0 and failed[id] and fb > 0 and fb ~= id then", "CODEBOT v120: fallback only after a final failure")
must_contain(_cb120_VAS, "local rid = rigIdOf(rigRef)", "CODEBOT v120: TryAttachCharacterVisual resolves through rigIdOf")
must_contain(_cb120_VAS, "and rigIdOf(ref) == assetId and host:IsDescendantOf(world)", "CODEBOT v120: late attach (flushRigPending) follows the fallback")
must_contain(_cb120_VAS, "task.defer(rigFallback, assetId) -- v119: hosts waiting on a rig id that never came get its fallback", "CODEBOT v120: giveUp hands waiting hosts the fallback rig")
must_contain(_cb120_VAS, "ref.ModelAssetId == assetId or ref.FallbackAssetId == assetId", "CODEBOT v120: fallback ids are baked as rigs too")

# script stripping (unconditional for rig files)
must_contain(_cb120_VAS, 'local RIG_HAZARDS = { "LuaSourceContainer", "RemoteEvent", "RemoteFunction", "UnreliableRemoteEvent", "BindableEvent", "BindableFunction" }',
             "CODEBOT v120: rig files lose every script / remote / bindable")
must_contain(_cb120_VAS, "local stripped = stripRigHazards(model)\n\t\tif stripped > 0 then", "CODEBOT v120: stripRigHazards runs before BakeTemplate")
_vas = _P120(_cb120_VAS).read_text(encoding="utf-8")
_i_strip, _i_bake = _vas.find("local stripped = stripRigHazards(model)"), _vas.find("local rig, why = RigBuilder.BakeTemplate(model, assetId)")
if not (0 < _i_strip < _i_bake):
    print("FAIL CODEBOT v120: strip must come before BakeTemplate"); raise SystemExit(1)
print("PASS CODEBOT v120: strip before BakeTemplate")

# rig validation + cloth + headwear pick
must_contain(_cb120_RB, 'return nil, "no Humanoid (not a character rig)"', "CODEBOT v120: BakeTemplate refuses a file with no Humanoid")
must_contain(_cb120_RB, "if (fileHum :: Humanoid).RigType ~= Enum.HumanoidRigType.R6 then", "CODEBOT v120: BakeTemplate refuses a non-R6 rig")
must_contain(_cb120_RB, "function RigBuilder.PaintCloth(", "CODEBOT v120: RigBuilder.PaintCloth (Shirt / Pants as Textures)")
must_contain(_cb120_RB, 'RigBuilder.ClothName = "WE_Cloth"', "CODEBOT v120: cloth Textures are named WE_Cloth")
must_contain(_cb120_RB, "Torso = { Front = { 231, 74, 128, 128 }", "CODEBOT v120: shirt template torso front region")
_rb = _P120(_cb120_RB).read_text(encoding="utf-8")
if 'Instance.new("Humanoid")' in _rb:
    print("FAIL CODEBOT v120: RigBuilder must never add a Humanoid to a rig"); raise SystemExit(1)
print("PASS CODEBOT v120: no Humanoid in WE_Rig (catalog rule)")
must_contain(_cb120_C + "RigConfig.luau", 'HeadwearPrefer = { "helmet", "beret", "cap", "hat" }', "CODEBOT v120: headwear pick prefers the helmet")
must_contain(_cb120_C + "RigConfig.luau", "HeadwearTris = 2103,", "CODEBOT v120: FAST helmet LOD0 triangles pinned")
must_contain(_cb120_C + "RigConfig.luau", "BodyTris = 60,", "CODEBOT v120: block body triangles pinned")

# client LOD
must_contain(_cb120_RA, "local function helmetBudget(hn: number)", "CODEBOT v120: RigAnimator helmet triangle budget")
must_contain(_cb120_RA, "local show = used + want <= budget", "CODEBOT v120: helmets only inside Budget.MaxMeshedTriangles")
must_contain(_cb120_RA, "HasLod = #meshes > 0 or #cloth > 0,", "CODEBOT v120: cloth bodies get the far (blocks) look")
must_contain(_cb120_RA, "elseif not e.Picked and not e.SPicked and e.HasLod then\n\t\t\tsetFar(e, true) -- v119: a cloth body", "CODEBOT v120: far swap covers cloth bodies")
_rc = _P120(_cb120_C + "RigConfig.luau").read_text(encoding="utf-8")
_num = lambda k: float(_re120.search(r"\b" + k + r"\s*=\s*([0-9.]+)", _rc).group(1))
_worst = (_num("MaxAnimated") + _num("MaxMeshedStatic") + _num("MaxPerClient")) * max(_num("TrianglesPerMeshedFigure"), _num("BodyTris"))
if _worst > _num("MaxMeshedTriangles"):
    print("FAIL CODEBOT v120: body triangles alone exceed MaxMeshedTriangles"); raise SystemExit(1)
print("PASS CODEBOT v120: worst-case bodies %d <= MaxMeshedTriangles %d (helmets fill the rest)" % (_worst, _num("MaxMeshedTriangles")))

# never touched
must_contain(_cb120_S + "Modules/HollowBuildingBuilder.luau", 'local MODEL_NAME = "WE_Building"', "CODEBOT v120: WE_Building untouched")
must_contain("src/ReplicatedStorage/Shared/Configs/StructureVisualConfig.luau", "PreferMeshWhenAssetIdSet = false", "CODEBOT v120: PreferMesh stays OFF")
