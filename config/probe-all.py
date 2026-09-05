#!/usr/bin/env python
"""Probe every model in config/zyvo.json (sequential, resume-safe)."""
import json, os, sys, urllib.request

BASE = "https://personality-tba-incoming-cove.trycloudflare.com/v1"
KEY = "sk-397a485ebe5ead01-39f994-dff3ac9d"
HERE = os.path.dirname(os.path.abspath(__file__))
STATE = os.path.join(TEMP := os.environ.get("TEMP", "/tmp"), "zyvo-probe-state.json")
BATCH = int(sys.argv[1]) if len(sys.argv) > 1 else 10

cfg = json.load(open(os.path.join(HERE, "zyvo.json"), encoding="utf-8"))
models = list(cfg["provider"]["zyvo"]["models"].keys())

try:
    state = json.load(open(STATE))
except Exception:
    state = {}

def probe(mid):
    try:
        req = urllib.request.Request(
            BASE + "/chat/completions",
            data=json.dumps({"model": mid, "messages": [{"role": "user", "content": "hi"}], "max_tokens": 1, "stream": False}).encode(),
            headers={"Authorization": "Bearer " + KEY, "Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=90) as r:
            return r.status == 200
    except urllib.error.HTTPError as e:
        return False
    except Exception:
        return "timeout"

done = 0
for mid in models:
    if mid in state:
        continue
    print("probing:", mid, flush=True)
    r = probe(mid)
    state[mid] = {"alive": r is True, "code": str(r)}
    print("  =>", "ALIVE" if r is True else f"no ({r})", flush=True)
    json.dump(state, open(STATE, "w"))
    done += 1
    if done >= BATCH:
        break

alive = [m for m in models if state.get(m, {}).get("alive") is True]
unprobed = [m for m in models if m not in state]
print(f"\nprobed: {len(state)}/{len(models)} | alive: {len(alive)} | unprobed: {len(unprobed)}")
if unprobed: print("next:", unprobed[0])
