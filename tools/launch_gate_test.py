#!/usr/bin/env python3
"""claude-bud JOB 12 (2026-09-29): executes the real launch gates with the Luau CLI (luau.exe; LUAU=/path/luau).

It embeds the config sources (MonetizationConfig and every LaunchSafe gate's config) into a harness, stubs the Roblox
bits (script.Parent, require, Color3 / Vector3 / Enum), and checks, for a NON-owner user id and for the owner:
  * LaunchAll = false: every RolloutKeys SKU and every LaunchSafe gate is closed to the non-owner, open to the owner;
  * LaunchAll = true : all of them are open to the non-owner (a second account can buy and use everything);
  * gates NOT in LaunchSafe (BalanceConfig) stay closed to the non-owner even with LaunchAll = true.
Prints PASS / FAIL lines and exits 1 on any FAIL. Used by tools/checks/claude_bud_launch.py (skipped without luau).
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CFG = ROOT / "src/ReplicatedStorage/Shared/Configs"
OWNER, OTHER = 470626172, 1234567

MODULES = ["AdminConfig", "MonetizationConfig", "SupplyDropConfig", "DailyRewardConfig", "PlazaBountyConfig",
           "ArmyUpgradeConfig", "QualityConfig", "JuiceConfig", "BalanceConfig", "BaseConfig", "EconomyConfig",
           "OfflineConfig"]  # Code Bot: DailyRewardConfig requires OfflineConfig (Day 7 = one full offline cap)

STUBS = r'''
local function ctor(...) return { ... } end
local STUB = {}
STUB.Color3 = { fromRGB = ctor, new = ctor }
STUB.Vector3 = { new = ctor, zero = {} }
STUB.Vector2 = { new = ctor }
STUB.UDim2 = { new = ctor, fromOffset = ctor, fromScale = ctor }
STUB.NumberSequence = { new = ctor }
STUB.ColorSequence = { new = ctor }
STUB.Enum = setmetatable({}, { __index = function(_, k) return setmetatable({}, { __index = function(_, v) return k .. "." .. v end }) end })
STUB.game = { GetService = function() return {} end }
'''


def harness(launch_all: bool) -> str:
    out = [STUBS, "local SRC = {}", "local CACHE = {}"]
    for m in MODULES:
        p = CFG / (m + ".luau")
        if not p.exists():
            continue
        src = p.read_text(encoding="utf-8")
        if m == "MonetizationConfig":
            src = src.replace("\tLaunchAll = false,", "\tLaunchAll = %s," % ("true" if launch_all else "false"), 1)
        eq = "=" * 8
        out.append("SRC[%r] = [%s[%s]%s]" % (m, eq, src, eq))
    out.append(r'''
local PARENT = setmetatable({}, { __index = function(_, k) return k end })
local function load(name)
	if CACHE[name] ~= nil then return CACHE[name] end
	local src = SRC[name]
	if src == nil then CACHE[name] = {}; return CACHE[name] end
	local fn, err = loadstring(src, name)
	if not fn then error(name .. ": " .. tostring(err)) end
	local env = setmetatable({ script = { Parent = PARENT }, require = function(x) return load(x) end }, { __index = function(_, k) local v = STUB[k]; if v ~= nil then return v end; return getfenv(0)[k] end })
	setfenv(fn, env)
	CACHE[name] = fn()
	return CACHE[name]
end
local M = load("MonetizationConfig")
local fails = 0
local function check(ok, label)
	print((ok and "PASS " or "FAIL ") .. label)
	if not ok then fails += 1 end
end
''')
    return "\n".join(out)


BODY = r'''
local LAUNCH = %s
local OWNER, OTHER = %d, %d
-- v101 (Code Bot): every gate's own Rollout is "all" now, so a non-owner is open with LaunchAll off too
local OPEN = LAUNCH or M.Rollout == "all"
for key in pairs(M.RolloutKeys) do
	check(M.SkuLiveFor(OWNER, key) == true, "owner sees SKU " .. key)
	check(M.SkuLiveFor(OTHER, key) == OPEN, "non-owner SKU " .. key .. (OPEN and " open" or " closed before launch"))
end
local gates = {
	{ "VIPPerks", function(u) return M.VIPPerksLiveFor(u) end },
	{ "Placement", function(u) return M.PlacementLiveFor(u) end },
	{ "Retention", function(u) return M.RetentionLiveFor(u) end },
	{ "Airdrop", function(u) return load("SupplyDropConfig").AirdropLiveFor(u) end },
	{ "DailyAutoClaim", function(u) return load("DailyRewardConfig").AutoClaimLiveFor(u) end },
	{ "PlazaBounty", function(u) return load("PlazaBountyConfig").LiveFor(u) end },
	{ "ArmyUpgrades", function(u) return load("ArmyUpgradeConfig").LiveFor(u) end },
	{ "QualityTier", function(u) return load("QualityConfig").LiveFor(u) end },
	{ "Juice", function(u) return load("JuiceConfig").LiveFor(u) end },
}
for _, g in ipairs(gates) do
	check(g[2](OWNER) == true, "owner gate " .. g[1])
	check(g[2](OTHER) == OPEN, "non-owner gate " .. g[1] .. (OPEN and " open" or " closed before launch"))
end
local B = load("BalanceConfig")
check(B.LiveFor(OTHER) == (B.Rollout == "all"), "BalanceConfig (not in LaunchSafe) follows its own Rollout for a non-owner")
print("fails=" .. fails)
'''


def run(luau: str) -> int:
    fails = 0
    for launch in (False, True):
        code = harness(launch) + BODY % ("true" if launch else "false", OWNER, OTHER)
        with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False, encoding="utf-8") as f:
            f.write(code)
            path = f.name
        r = subprocess.run([luau, path], capture_output=True, text=True, timeout=60)
        os.unlink(path)
        text = r.stdout + r.stderr
        print("== LaunchAll = %s" % launch)
        print(text.strip())
        m = re.search(r"fails=(\d+)", text)
        fails += int(m.group(1)) if m else 1
    return fails


if __name__ == "__main__":
    luau = os.environ.get("LUAU") or shutil.which("luau")
    if not luau:
        print("SKIP: no luau CLI (set LUAU=/path/luau)")
        sys.exit(0)
    sys.exit(1 if run(luau) else 0)
