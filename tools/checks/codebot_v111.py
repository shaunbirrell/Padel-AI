"""v111: Shaun removed the $75 Grab Cash plate (ManualDropperConfig.Enabled = false)."""
import sys
p = "src/ReplicatedStorage/Shared/Configs/ManualDropperConfig.luau"
s = open(p).read()
ok = "\tEnabled = false," in s
print(("PASS" if ok else "FAIL") + " v111 manual dropper disabled")
sys.exit(0 if ok else 1)
