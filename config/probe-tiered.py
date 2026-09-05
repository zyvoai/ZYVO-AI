#!/usr/bin/env python
"""Probe the tiered Cline-source models, resume-safe; final: write config."""
import json, os, re, sys, urllib.request

BASE = "https://personality-tba-incoming-cove.trycloudflare.com/v1"
KEY = "sk-397a485ebe5ead01-39f994-dff3ac9d"
HERE = os.path.dirname(os.path.abspath(__file__))
STATE = os.environ.get("TEMP", "/tmp") + "/zyvo-tiered-state.json"
BATCH = int(sys.argv[1]) if len(sys.argv) > 1 else 8
WRITE = "--write" in sys.argv

TIERED = [
    ("T1", "Claude Opus 5", "claude-opus-5"),
    ("T1", "Claude Fable 5.1", "claude-fable-5.1"),
    ("T1", "Claude Fable 5", "claude-fable-5"),
    ("T1", "Claude Opus 4.8", "claude-opus-4.8"),
    ("T1", "GPT-5.6 Sol Pro", "gpt-5.6-sol-pro"),
    ("T1", "GPT-5.6 Terra Pro", "gpt-5.6-terra-pro"),
    ("T1", "GPT-5.6 Luna Pro", "gpt-5.6-luna-pro"),
    ("T1", "GPT-5.5 Pro", "gpt-5.5-pro"),
    ("T1", "GPT-5.4 Pro", "gpt-5.4-pro"),
    ("T1", "GPT-5 Pro", "gpt-5-pro"),
    ("T1", "Claude Opus 4.7", "claude-opus-4.7"),
    ("T1", "Claude Opus 4.6", "claude-opus-4.6"),
    ("T1", "Claude Sonnet 5", "claude-sonnet-5"),
    ("T2", "Kimi K3", "kimi-k3"),
    ("T2", "Kimi K2.7 Code", "kimi-k2.7-code"),
    ("T2", "Grok 4.6", "grok-4.6"),
    ("T2", "Grok 4.5", "grok-4.5"),
    ("T2", "Gemini 3.7 Flash", "gemini-3.7-flash"),
    ("T2", "Gemini 3.1 Pro Preview", "gemini-3.1-pro-preview"),
    ("T2", "DeepSeek V4 Pro 0813", "deepseek-v4-pro-0813"),
    ("T2", "Qwen3.8 Max", "qwen3.8-max"),
    ("T2", "Qwen3.8 2.4T A95B", "qwen3.8-2.4t-a95b"),
    ("T2", "GLM 5.3", "glm-5.3"),
    ("T2", "Qwen3.7 Max", "qwen3.7-max"),
    ("T2", "GLM 5.2", "glm-5.2"),
    ("T2", "Claude Sonnet 4.6", "claude-sonnet-4.6"),
    ("T2", "Grok 4.20 Multi-Agent", "grok-4.20-multi-agent"),
    ("T3", "Qwen3 Max Thinking", "qwen3-max-thinking"),
    ("T3", "Qwen3 Max", "qwen3-max"),
    ("T3", "Kimi K2.6", "kimi-k2.6"),
    ("T3", "Kimi K2.5", "kimi-k2.5"),
    ("T3", "Kimi K2 Thinking", "kimi-k2-thinking"),
    ("T3", "GLM 5.1", "glm-5.1"),
    ("T3", "GPT-5.5", "gpt-5.5"),
    ("T3", "GPT-5.4", "gpt-5.4"),
    ("T3", "GPT-5.3 Codex", "gpt-5.3-codex"),
    ("T3", "GPT-5.2 Pro", "gpt-5.2-pro"),
    ("T3", "Qwen3 Coder 480B", "qwen3-coder-480b"),
    ("T3", "Qwen3.5 397B", "qwen3.5-397b"),
    ("T3", "DeepSeek R1 0528", "r1-0528"),
    ("T3", "Claude Opus 4.1", "claude-opus-4.1"),
    ("T3", "Claude Sonnet 4.5", "claude-sonnet-4.5"),
    ("T3", "Mistral Large 3", "mistral-large-3"),
    ("T3", "Mistral Medium 3.5", "mistral-medium-3.5"),
    ("T3", "Seed 2.0 Code", "seed-2.0-code"),
    ("T3", "MiMo V2.5 Pro", "mimo-v2.5-pro"),
    ("T3", "Gemini 2.5 Pro", "gemini-2.5-pro"),
    ("T3", "o3 Pro", "o3-pro"),
    ("FREE", "Free Models Router", "free"),
    ("FREE", "DeepSeek V4 Flash (free)", "deepseek-v4-flash"),
    ("FREE", "StepFun: Step 3.7 Flash (free)", "step-3.7-flash"),
    ("FREE", "GLM 5.2 (free)", "glm-5.2"),
    ("FREE", "MiniMax: MiniMax M3 (free)", "minimax-m3"),
    ("FREE", "MiniMax: MiniMax M2.7 (free)", "minimax-m2.7"),
    ("FREE", "Gemma 4 31B (free)", "gemma-4-31b"),
    ("FREE", "Poolside: Laguna S 2.1 (free)", "laguna-s-2.1"),
    ("FREE", "LiquidAI: LFM2.5 (free)", "lfm-2.5"),
    ("FREE", "Ling 3.0 Flash Fin (free)", "ling-3.0-flash-fin"),
    ("FREE", "Dots Studio: Dots3-Note (free)", "dots-3-note"),
    ("FREE", "Cohere: North Mini Code (free)", "north-mini-code"),
    ("FREE", "NVIDIA: Nemotron 3 Ultra (free)", "nemotron-3-ultra"),
    ("FREE", "Auto Free", "auto/best-free"),
]

d = json.load(open(os.environ.get("TEMP", "/tmp") + "/omni-fresh.json", encoding="utf-8"))
ALL = [m["id"] for m in (d.get("data") or [])]

def candidate(frag):
    """prefer cl/ cline ids with a vendor segment (vendor/model) - bare aliases 400"""
    frag_l = frag.lower()
    hits = [i for i in ALL if frag_l in i.lower()]
    if not hits:
        return None
    cl = [i for i in hits if i.lower().startswith(("cl/", "cline/"))]
    pool = cl if cl else hits
    vendored = [i for i in pool if i.count("/") >= 2]
    if vendored:
        pool = vendored
    free = [i for i in pool if ":free" in i]
    if free:
        pool = free
    pool = sorted(pool, key=len)
    return pool[0]

try:
    state = json.load(open(STATE))
except Exception:
    state = {}

if not WRITE:
    done = 0
    for tier, name, frag in TIERED:
        if name in state:
            continue
        mid = candidate(frag)
        if not mid:
            state[name] = {"alive": False, "code": "no-id", "id": ""}
            print("  !! no cl/id:", name, flush=True)
            json.dump(state, open(STATE, "w"))
            continue
        try:
            req = urllib.request.Request(
                BASE + "/chat/completions",
                data=json.dumps({"model": mid, "messages": [{"role": "user", "content": "hi"}], "max_tokens": 1, "stream": False}).encode(),
                headers={"Authorization": "Bearer " + KEY, "Content-Type": "application/json"})
            with urllib.request.urlopen(req, timeout=90) as r:
                alive = r.status == 200
            code = str(r.status)
        except urllib.error.HTTPError as e:
            alive, code = False, str(e.code)
            try:
                print("   body:", e.read().decode()[:120], flush=True)
            except Exception:
                pass
        except Exception as e:
            alive, code = False, "timeout"
        state[name] = {"alive": alive, "code": code, "id": mid}
        print(("ALIVE " if alive else "no    ") + name + " -> " + mid + f" ({code})", flush=True)
        json.dump(state, open(STATE, "w"))
        done += 1
        if done >= BATCH:
            break
    probed = sum(1 for k in TIERED if k[1] in state)
    alive_n = sum(1 for k in TIERED if state.get(k[1], {}).get("alive"))
    print(f"\nprogress: {probed}/{len(TIERED)} probed | alive: {alive_n}", flush=True)
else:
    cfg = json.load(open(os.path.join(HERE, "zyvo.json"), encoding="utf-8"))
    models = {}
    order = []
    for tier, name, frag in TIERED:
        st = state.get(name, {})
        if st.get("alive") and st.get("id"):
            models[st["id"]] = {"name": name}
            order.append(name)
    cfg["provider"]["zyvo"]["models"] = models
    cfg["model"] = "zyvo/" + order[0] if False else cfg["model"]
    first_id = list(models.keys())[0] if models else cfg["model"].split("/", 1)[1]
    json.dump(cfg, open(os.path.join(HERE, "zyvo.json"), "w", encoding="utf-8"), indent=2, ensure_ascii=False)
    open(os.path.join(HERE, "zyvo.json"), "a", encoding="utf-8").write("\n")
    print("config written with", len(models), "verified models; default:", list(models.keys())[0] if models else "?")
