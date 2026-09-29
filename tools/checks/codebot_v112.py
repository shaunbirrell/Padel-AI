"""v112: Shaun removed the $75 Grab Cash plate (ManualDropperConfig.Enabled = false)."""
_drop112 = open("src/ReplicatedStorage/Shared/Configs/ManualDropperConfig.luau").read()
_base112 = open("src/ReplicatedStorage/Shared/Configs/BaseConfig.luau").read()
_ok112 = "\tEnabled = false," in _drop112 and "MaxPlots = 10," in _base112
if "ok" in globals() and "bad" in globals():
    (ok if _ok112 else bad)("v112 10 base plots + dropper still off" if _ok112 else "v112 MaxPlots=10 and ManualDropper Enabled=false required")
elif __name__ == "__main__":
    import sys
    print(("PASS" if _ok112 else "FAIL") + " v112 10 base plots + dropper still off")
    sys.exit(0 if _ok112 else 1)
