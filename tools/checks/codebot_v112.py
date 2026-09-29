"""v112: Shaun removed the $75 Grab Cash plate (ManualDropperConfig.Enabled = false)."""
import sys
p = "src/ReplicatedStorage/Shared/Configs/ManualDropperConfig.luau"
s = open(p).read()
ok = "\tEnabled = false," in s and "MaxPlots = 10," in open("src/ReplicatedStorage/Shared/Configs/BaseConfig.luau").read()
print(("PASS" if ok else "FAIL") + " v112 10 base plots + dropper still off")
sys.exit(0 if ok else 1)
