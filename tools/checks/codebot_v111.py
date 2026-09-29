"""v111: Shaun removed the $75 Grab Cash plate (ManualDropperConfig.Enabled = false)."""
p = "src/ReplicatedStorage/Shared/Configs/ManualDropperConfig.luau"
s = open(p).read()
_ok111 = "\tEnabled = false," in s
if "ok" in globals() and "bad" in globals():
    (ok if _ok111 else bad)("v111 manual dropper disabled" if _ok111 else "v111 ManualDropperConfig.Enabled must be false")
elif __name__ == "__main__":
    import sys
    print(("PASS" if _ok111 else "FAIL") + " v111 manual dropper disabled")
    sys.exit(0 if _ok111 else 1)
