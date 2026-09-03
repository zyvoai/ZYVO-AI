#!/usr/bin/env python
"""Probe omniroute models for availability, then build config/zyvo.json with
vendor-prefixed display names matching the Zyvo model list."""
import json, os, urllib.request, concurrent.futures, collections

BASE = "http://localhost:20128/v1"
KEY = "sk-397a485ebe5ead01-3502cf-9b868f70"
TEMP = os.environ.get("TEMP", "/tmp")

d = json.load(open(TEMP + "/omni-models.json", encoding="utf-8"))
ALL = [m["id"] for m in (d.get("data") or [])]
ALLSET = set(ALL)

def find(*parts, free=None):
    """find a model id containing all parts; prefer :free if free=True, else non-free"""
    hits = [i for i in ALL if all(p in i.lower() for p in parts)]
    if free is True:
        f = [i for i in hits if ":free" in i]
        if f: return f[0]
    if free is False:
        nf = [i for i in hits if ":free" not in i]
        if nf: return nf[0]
    return hits[0] if hits else None

# --- candidates: (display_name, api_id) ------------------------------------
C = []
def add(name, *parts, free=None):
    mid = find(*[p.lower() for p in parts], free=free)
    if mid: C.append((name, mid))
    else: print("  !! not found:", name)

# flagship auto combos first (owner-curated)
C += [("Best Coding", "auto/best-coding"), ("Best Reasoning", "auto/best-reasoning"),
      ("Best Fast", "auto/best-fast"), ("Best Chat", "auto/best-chat"),
      ("Best Vision", "auto/best-vision"), ("Best Free", "auto/best-free"),
      ("Pro Coding", "auto/pro-coding"), ("Pro Reasoning", "auto/pro-reasoning"),
      ("Pro Chat", "auto/pro-chat")]

# Kilo Code free section (names like the website list)
add("StepFun: Step 3.7 Flash (free)", "stepfun", "step-3.7-flash", free=True)
add("Tencent: Hy3 (free)", "tencent", "hy3", free=True)
add("Poolside: Laguna S 2.1 (free)", "poolside", "laguna-s-2.1", free=True)
add("Meituan: LongCat 2.0 (free)", "meituan", "longcat", free=True)
add("Ling 3.0 Flash Fin (free)", "inclusionai", "ling-3.0-flash-fin", free=True)
add("Dots Studio: Dots3-Note Preview (free)", "dots-studio", "dots-3-note", free=True)
add("LiquidAI: LFM2.5-2.6B (free)", "liquid", "lfm-2.5", free=True)
add("NVIDIA: Nemotron 3.5 Lightning (free)", "nemotron-3.5-lightning", free=True)
add("Thinking Machines: Inkling Small (free)", "thinkingmachines", "inkling-small", free=True)
add("Thinking Machines: Inkling (free)", "thinkingmachines", "inkling", free=True)
add("Poolside: Laguna XS 2.1 (free)", "poolside", "laguna-xs-2.1", free=True)
add("Cohere: North Mini Code (free)", "cohere", "north-mini-code", free=True)
add("NVIDIA: Nemotron 3.5 Content Safety (free)", "nemotron-3.5-content-safety", free=True)
add("NVIDIA: Nemotron 3 Ultra (free)", "nemotron-3-ultra", free=True)
add("NVIDIA: Nemotron 3 Nano Omni (free)", "nemotron-3-nano-omni", free=True)
add("NVIDIA: Nemotron 3 Super (free)", "nemotron-3-super", free=True)
add("MiniMax: MiniMax M3 (free)", "minimax-m3", free=True)
add("MiniMax: MiniMax M2.7 (free)", "minimax-m2.7", free=True)

# OpenCode Free section
add("Big Pickle (free)", "opencode", "big-pickle")
add("Muse Spark 1.2 Contributor (free)", "muse-spark-1.2-contributor")
add("MiMo V2.5 (free)", "mimo-v2.5", free=True)
add("Nemotron 3 Ultra (free)", "nemotron-3-ultra", free=True)

# Agnes AI section
add("Agnes AI: Agnes 2.0 Flash", "agnes-2.0-flash")
add("Agnes AI: Agnes 2.5 Flash", "agnes-2.5-flash")

# Xkiro section (limited availability)
add("Xkiro: Grok 4.6 (Limited)", "grok-4.6")
add("Xkiro: DeepSeek V4 Pro (Limited)", "deepseek-v4-pro")
add("Xkiro: DeepSeek V4 Flash (Limited)", "deepseek-v4-flash")
add("Xkiro: Qwen3.8 Max (Limited)", "qwen3.8-max")
add("Xkiro: Qwen3.7 Plus (Limited)", "qwen3.7-plus")
add("Xkiro: Kimi K2.6 (Limited)", "kimi-k2.6")
add("Xkiro: Mistral Large (Limited)", "mistral-large-2512")
add("Xkiro: Nemotron 3 Super (Limited)", "nemotron-3-super")
add("Xkiro: MiniMax M2.7 Highspeed (Limited)", "minimax-m2.7-highspeed")
add("Xkiro: Qwen3.5 Plus (Limited)", "qwen3.5-plus")
add("Xkiro: Qwen3.6 Plus (Limited)", "qwen3.6-plus")
add("Xkiro: Codestral (Limited)", "codestral-2508")

print(f"candidates: {len(C)}")

# --- probe ------------------------------------------------------------------
def probe(item):
    name, mid = item
    try:
        req = urllib.request.Request(
            BASE + "/chat/completions",
            data=json.dumps({"model": mid, "messages": [{"role": "user", "content": "hi"}], "max_tokens": 1}).encode(),
            headers={"Authorization": "Bearer " + KEY, "Content-Type": "application/json"},
        )
        with urllib.request.urlopen(req, timeout=25) as r:
            return (name, mid, r.status == 200)
    except Exception as e:
        return (name, mid, False)

ok, dead = [], []
with concurrent.futures.ThreadPoolExecutor(max_workers=8) as ex:
    for name, mid, alive in ex.map(probe, C):
        (ok if alive else dead).append((name, mid))
        print(("PASS " if alive else "DEAD ") + mid)

print(f"\navailable: {len(ok)} / {len(C)}")

# --- build config -----------------------------------------------------------
cfg = {
    "$schema": "https://opencode.ai/config.json",
    "model": "zyvo/auto/best-coding",
    "provider": {
        "zyvo": {
            "name": "Zyvo",
            "npm": "@ai-sdk/openai-compatible",
            "options": {
                "baseURL": "https://jaguar-event-lawyer-downloaded.trycloudflare.com/v1",
                "apiKey": KEY,
            },
            "models": { mid: {"name": name} for name, mid in ok },
        }
    },
}
out = "config/zyvo.json"
json.dump(cfg, open(out, "w", encoding="utf-8"), indent=2, ensure_ascii=False)
open(out, "a", encoding="utf-8").write("\n")
print("wrote", out, "with", len(ok), "models")
print("dead list:", [mid for _, mid in dead])
