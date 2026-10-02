"""Code Bot (army command bug, 2026-10-01): the module set the army command path needs in the Studio-free sims
(ArmyState / ArmyTargets / ArmyCommand + the shared configs ArmyTargets resolves map areas / sites / roads with)."""
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
SH = ROOT / "src/ReplicatedStorage/Shared"; SV = ROOT / "src/ServerScriptService/Server"
CONFIGS = ["MapConfig", "HudConfig", "RetentionConfig", "AdminConfig", "EconomyConfig", "BaseConfig", "BaseLayoutConfig",
           "BusinessConfig", "BankRaidConfig", "WaterConfig", "WorldSitesConfig", "SiteActivityConfig", "WorldConfig",
           "TerritoryConfig", "OutpostDefenderConfig", "OrdersConfig", "ArmyOrdersConfig"]
UTILS = ["MapAreas", "MapLabelLayout", "PlotFrame", "ArmyLog"]


def army_cmd_mods(server=True):
    m = {}
    for n in CONFIGS:
        m["Configs/" + n] = SH / ("Configs/%s.luau" % n)
    for n in UTILS:
        p = SH / ("Util/%s.luau" % n)
        if p.exists():
            m["Util/" + n] = p
    if server:
        for n in ["ArmyState", "ArmyTargets", "ArmyCommand"]:
            m["Modules/" + n] = SV / ("Modules/%s.luau" % n)
    return m
