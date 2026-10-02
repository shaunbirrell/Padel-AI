#!/usr/bin/env python3
"""claude-bud JOB 15 (2026-09-29): anti-exploit coverage audit (static).

  1. Every server OnServerEvent / OnServerInvoke handler (and NationColorService.onRequest) calls RemoteGate.Check as
     its first statement, and names a remote that has a SecurityConfig.Schemas entry.
  2. Every Schemas key is a real Constants.RemoteNames entry.
  3. Every remote the CLIENT fires (a FireServer / InvokeServer line naming Constants.RemoteNames.X, or a remote
     name string nearby) has a Schemas entry; otherwise RemoteSetup's sink would count real play as bad requests.
  4. No Give* remote names exist.
Exit 1 on any failure.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "src"
SEC = (SRC / "ReplicatedStorage/Shared/Configs/SecurityConfig.luau").read_text(encoding="utf-8")
CONST = (SRC / "ReplicatedStorage/Shared/Constants.luau").read_text(encoding="utf-8")


def schemas():
    i = SEC.index("Schemas = {")
    j = SEC.index("} :: { [string]: { string } }", i)
    return set(re.findall(r"^\t\t(\w+) = \{", SEC[i:j], re.M))


def remote_names():
    i = CONST.index("RemoteNames = {")
    j = CONST.index("\n}", i)
    return set(re.findall(r"^\t(\w+) = \"", CONST[i:j], re.M))


def server_handlers():
    out = []
    for p in (SRC / "ServerScriptService").rglob("*.luau"):
        lines = p.read_text(encoding="utf-8").splitlines()
        for n, ln in enumerate(lines):
            code = ln.split("--", 1)[0]
            is_handler = (re.search(r"OnServerEvent:Connect\(function\(player", code)
                          or re.search(r"OnServerInvoke = function\(player", code)
                          or "local function onRequest(player: Player, payload: any)" in code
                          or "local function handlePurchaseRemote(" in code
                          or "local function onBoardSetting(player: Player" in code)
            if not is_handler:
                continue
            nxt = "\n".join(lines[n + 1: n + 6])
            m = re.search(r'RemoteGate\)\.Check\(player, (?:"(\w+)"|Constants\.RemoteNames\.(\w+))', nxt)
            out.append((str(p.relative_to(ROOT)), n + 1, (m.group(1) or m.group(2)) if m else None, ln.strip()))
    return out


def client_fired():
    fired = {}
    for p in (SRC / "StarterPlayer").rglob("*.luau"):
        lines = p.read_text(encoding="utf-8").splitlines()
        for n, ln in enumerate(lines):
            code = ln.split("--", 1)[0]
            if "FireServer" not in code and "InvokeServer" not in code:
                continue
            window = "\n".join(l.split("--", 1)[0] for l in lines[max(0, n - 4): n + 1])
            for name in re.findall(r"RemoteNames\.(\w+)", window):
                fired.setdefault(name, "%s:%d" % (p.relative_to(ROOT), n + 1))
    return fired


if __name__ == "__main__":
    fails = []
    sch, names = schemas(), remote_names()
    hs = server_handlers()
    for f, line, name, text in hs:
        if f.endswith("BaseService.luau") and "handlePurchaseRemote" in text:
            continue  # the fallback handler; RemoteSetup's create-time hook gates RequestPurchaseUpgrade
        if f.endswith("RemoteSetup.luau") and "(child :: any).OnServerEvent" in text:
            continue  # the sink listener itself (RemoteGate.Sink) on client-never remotes
        if name is None:
            fails.append("ungated handler %s:%d  %s" % (f, line, text[:90]))
        elif name not in sch:
            fails.append("handler %s:%d gates %s which has no schema" % (f, line, name))
    for k in sorted(sch - names):
        fails.append("schema %s is not a Constants.RemoteNames entry" % k)
    fired = client_fired()
    for k, where in sorted(fired.items()):
        if k not in sch:
            # a push remote named near a FireServer line (e.g. a bind next to it) is fine only if the server never
            # listens: report it so a human looks once
            fails.append("client fires %s (%s) but it has no schema: the sink would count it" % (k, where))
    for k in names:
        if k.startswith("Give"):
            fails.append("forbidden remote name %s" % k)
    print("[remote_audit] %d handlers, %d schemas, %d client-fired remotes" % (len(hs), len(sch), len(fired)))
    for x in fails:
        print("  FAIL " + x)
    print("[remote_audit] %s" % ("OK" if not fails else "FAIL"))
    sys.exit(0 if not fails else 1)
