#!/usr/bin/env node
/**
 * Zyvo config generator
 *
 * Fetches the model list from the omniroute endpoint (GET /models), ranks it
 * (family priority -> context size -> name), and writes the top 50 as the
 * default "Zyvo" provider into config/opencode.json — which install.sh
 * deploys to ~/.config/opencode/opencode.json on the phone.
 *
 * Usage:
 *   node config/generate.mjs <baseURL> <apiKey> [modelListFile]
 *
 * baseURL example: https://api.omniroute.example/v1
 * modelListFile (optional): newline-separated model IDs; only these are
 * considered (still ranked, still capped at 50).
 */

import fs from "node:fs"
import path from "node:path"
import { fileURLToPath } from "node:url"

const [, , baseURLArg, keyArg, listFile] = process.argv
const baseURL = (baseURLArg || process.env.ZYVO_BASE_URL || "").replace(/\/+$/, "")
const apiKey = keyArg || process.env.ZYVO_API_KEY || ""
const TOP = 50

if (!baseURL || !apiKey) {
  console.error("usage: node config/generate.mjs <baseURL> <apiKey> [modelListFile]")
  process.exit(1)
}

// --- fetch models -----------------------------------------------------------
console.log(`Fetching ${baseURL}/models ...`)
const res = await fetch(`${baseURL}/models`, {
  headers: { Authorization: `Bearer ${apiKey}` },
  signal: AbortSignal.timeout(30000),
})
if (!res.ok) {
  console.error(`ERROR: /models returned HTTP ${res.status}`)
  process.exit(1)
}
const data = await res.json()
const raw = Array.isArray(data) ? data : (data.data ?? data.models ?? [])
if (!raw.length) {
  console.error("ERROR: /models returned no models")
  process.exit(1)
}
console.log(`Fetched ${raw.length} models`)

// optional allowlist filter
let allowed = null
if (listFile && fs.existsSync(listFile)) {
  allowed = new Set(
    fs
      .readFileSync(listFile, "utf8")
      .split(/\r?\n/)
      .map((x) => x.trim())
      .filter(Boolean),
  )
  console.log(`Allowlist: ${allowed.size} model IDs`)
}

// --- ranking ----------------------------------------------------------------
// Family priority: the well-known strong general/coding families first.
const FAMILY_PRIORITY = [
  "gpt-5", "gpt-4.1", "gpt-4o", "gpt-4",
  "claude-4", "claude-3.7", "claude-3.5",
  "gemini-2.5", "gemini-2",
  "deepseek-r1", "deepseek-v3", "deepseek",
  "qwen3", "qwen-3", "qwen2.5",
  "llama-4", "llama-3.3", "llama-3",
  "mistral-large", "mistral",
  "grok",
  "kimi", "glm", "nova", "phi",
]
function familyRank(id) {
  const lower = id.toLowerCase()
  for (let i = 0; i < FAMILY_PRIORITY.length; i++) {
    if (lower.includes(FAMILY_PRIORITY[i])) return i
  }
  return FAMILY_PRIORITY.length
}

const models = raw
  .map((m) => {
    const id = typeof m === "string" ? m : (m.id ?? m.model ?? m.name)
    return { id, ctx: Number(m.context_length ?? m.context_size ?? m.max_tokens ?? m.max_context ?? 0) }
  })
  .filter((m) => m.id && (!allowed || allowed.has(m.id)))

models.sort((a, b) => {
  const fa = familyRank(a.id)
  const fb = familyRank(b.id)
  if (fa !== fb) return fa - fb
  if (b.ctx !== a.ctx) return b.ctx - a.ctx
  return a.id.localeCompare(b.id)
})

const top = models.slice(0, TOP)
console.log(`Ranked; taking top ${top.length}`)

// --- build config -----------------------------------------------------------
const providerModels = {}
for (const m of top) {
  providerModels[m.id] = { name: m.id }
}

const config = {
  $schema: "https://opencode.ai/config.json",
  model: `zyvo/${top[0].id}`,
  provider: {
    zyvo: {
      name: "Zyvo",
      npm: "@ai-sdk/openai-compatible",
      options: {
        baseURL,
        apiKey,
      },
      models: providerModels,
    },
  },
}

const here = path.dirname(fileURLToPath(import.meta.url))
const out = path.join(here, "opencode.json")
fs.writeFileSync(out, JSON.stringify(config, null, 2) + "\n")
console.log(`Wrote ${out} (${top.length} models, default: zyvo/${top[0].id})`)
console.log("NOTE: apiKey is baked in this file — do not publish the repo if the key is secret.")
