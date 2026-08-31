#!/usr/bin/env bun
/**
 * Build OpenCode for Android (aarch64)
 *
 * Mirrors OpenCode's own build script (packages/opencode/script/build.ts)
 * for a single target, then performs the binary surgery needed to run on
 * Android: Bun's `--compile` has no Android target, so we compile for the
 * host, extract the serialized module graph from the standalone binary,
 * and append it to a Bun binary cross-compiled for Android (bionic).
 *
 * Module-graph surgery approach: guysoft/opencode-termux (MIT).
 *
 * Env vars (set by build-opencode.sh):
 *   OPENCODE_DIR    - path to packages/opencode
 *   ANDROID_BUN     - path to the Android bun binary
 *   OUTPUT_DIR      - where to write the final binary
 *   OPENCODE_VERSION
 */

import { $ } from "bun"
import fs from "fs"
import path from "path"
import { createSolidTransformPlugin } from "@opentui/solid/bun-plugin"

// These are set by the build-opencode.sh wrapper script
const OPENCODE_DIR = process.env.OPENCODE_DIR || (() => { throw new Error("OPENCODE_DIR env var not set") })()
const ANDROID_BUN = process.env.ANDROID_BUN || (() => { throw new Error("ANDROID_BUN env var not set") })()
const OUTPUT_DIR = process.env.OUTPUT_DIR || (() => { throw new Error("OUTPUT_DIR env var not set") })()

// Validate Android bun exists
if (!fs.existsSync(ANDROID_BUN)) {
  console.error("Android bun binary not found at:", ANDROID_BUN)
  process.exit(1)
}

process.chdir(OPENCODE_DIR)

const VERSION = process.env.OPENCODE_VERSION || "1.18.25"
const CHANNEL = process.env.OPENCODE_CHANNEL || "latest"

console.log(`Building OpenCode v${VERSION} (channel: ${CHANNEL}) for Android aarch64`)

// Step 1: Load models.dev snapshot (mirrors script/generate.ts)
console.log("\n=== Step 1: Generating models.dev snapshot ===")
const modelsUrl = process.env.OPENCODE_MODELS_URL || "https://models.dev"
let modelsData: string
if (process.env.MODELS_DEV_API_JSON) {
  modelsData = await Bun.file(process.env.MODELS_DEV_API_JSON).text()
} else {
  let fetchErr: Error | null = null
  modelsData = ""
  for (let attempt = 1; attempt <= 3; attempt++) {
    try {
      const resp = await fetch(`${modelsUrl}/api.json`, { signal: AbortSignal.timeout(30000) })
      if (!resp.ok) throw new Error(`HTTP ${resp.status}`)
      modelsData = await resp.text()
      fetchErr = null
      break
    } catch (err: any) {
      fetchErr = err
      console.error(`  Attempt ${attempt}/3 failed: ${err.message}`)
      if (attempt < 3) await new Promise(r => setTimeout(r, 2000 * attempt))
    }
  }
  if (fetchErr) {
    console.error(`ERROR: Failed to fetch models after 3 attempts: ${fetchErr.message}`)
    process.exit(1)
  }
}
console.log(`Loaded models.dev snapshot (${(modelsData.length / 1024 / 1024).toFixed(1)} MB)`)

// Step 2: Resolve the tree-sitter worker.
// On host Bun 1.3.2 we can't use Bun.build's `files` option (added later),
// so we embed the real parser.worker.js from node_modules as an entrypoint
// and point OTUI_TREE_SITTER_WORKER_PATH at its embedded bunfs path.
console.log("\n=== Step 2: Resolving tree-sitter worker ===")
const workerPath = "./src/cli/tui/worker.ts"
const bunfsRoot = "/$bunfs/root/"
const localWorkerPath = path.resolve(OPENCODE_DIR, "node_modules/@opentui/core/parser.worker.js")
const rootWorkerPath = path.resolve(OPENCODE_DIR, "../../node_modules/@opentui/core/parser.worker.js")
let parserWorkerResolved: string
try {
  parserWorkerResolved = fs.realpathSync(fs.existsSync(localWorkerPath) ? localWorkerPath : rootWorkerPath)
} catch {
  parserWorkerResolved = require.resolve("@opentui/core/parser.worker.js")
}
const workerRelativePath = path.relative(OPENCODE_DIR, parserWorkerResolved).replaceAll("\\", "/")
console.log(`TUI worker: ${workerPath}`)
console.log(`Tree-sitter worker: ${parserWorkerResolved}`)

const plugin = createSolidTransformPlugin()

await $`rm -rf ${OUTPUT_DIR}`
await $`mkdir -p ${OUTPUT_DIR}`

// Step 3: Build with Bun.build() --compile for the HOST platform
// This creates a standalone binary for the host, from which we extract the module graph
console.log("\n=== Step 3: Bundling OpenCode (host target) ===")

const hostBinaryPath = path.join(OUTPUT_DIR, "opencode-host")

const result = await Bun.build({
  conditions: ["bun", "node"],
  tsconfig: "./tsconfig.json",
  plugins: [plugin],
  external: ["node-gyp"],
  minify: true,
  sourcemap: "none",
  compile: {
    autoloadBunfig: false,
    autoloadDotenv: false,
    autoloadTsconfig: true,
    autoloadPackageJson: true,
    outfile: hostBinaryPath,
    execArgv: [`--user-agent=opencode/${VERSION}`, "--use-system-ca", "--"],
  },
  entrypoints: ["./src/index.ts", workerPath, parserWorkerResolved],
  define: {
    FFF_LIBC: JSON.stringify("gnu"),
    OPENCODE_VERSION: `'${VERSION}'`,
    OPENCODE_MODELS_DEV: modelsData,
    OTUI_TREE_SITTER_WORKER_PATH: bunfsRoot + workerRelativePath,
    OPENCODE_WORKER_PATH: workerPath,
    OPENCODE_CHANNEL: `'${CHANNEL}'`,
    OPENCODE_LIBC: "",
  },
})

if (!result.success) {
  console.error("Build failed:")
  for (const msg of result.logs) {
    console.error(msg)
  }
  process.exit(1)
}

console.log(`Host standalone binary: ${hostBinaryPath}`)

// Step 4: Extract module graph from host binary
console.log("\n=== Step 4: Extracting module graph ===")

const hostBinary = await Bun.file(hostBinaryPath).arrayBuffer()
const hostBytes = new Uint8Array(hostBinary)

// Standalone binary format (ELF):
//   [bun binary (seek_pos bytes)]
//   [module_graph bytes]
//   [total_byte_count as u64 LE (8 bytes)]
//
// Module graph internal layout:
//   [string data] [module list] [offsets (32 bytes)] [trailer "\n---- Bun! ----\n" (16 bytes)]
//
// offsets.byte_count = len(string_data) + len(module_list)
// total_byte_count = seek_pos + len(module_graph) + 8 = file_size
//
// We derive the module graph size from the trailer and offsets struct,
// WITHOUT relying on process.execPath (which may differ from the bun
// binary that was embedded during --compile).

const TRAILER_STR = "\n---- Bun! ----\n"
const TRAILER_LEN = TRAILER_STR.length // 16
const OFFSETS_SIZE_CONST = 32

// Find trailer: it's near the end of the file, just before the final 8-byte u64.
const trailerBuf = Buffer.from(TRAILER_STR)
const searchBuf = Buffer.from(hostBytes.buffer, hostBytes.byteOffset, hostBytes.length)
const trailerEnd = hostBytes.length - 8 // trailer must end here
const expectedTrailerStart = trailerEnd - TRAILER_LEN

const foundTrailer = searchBuf.compare(
  trailerBuf, 0, TRAILER_LEN,
  expectedTrailerStart, trailerEnd,
) === 0

if (!foundTrailer) {
  console.error("ERROR: Bun standalone trailer not found at expected position")
  console.error("       The standalone binary format may have changed.")
  process.exit(1)
}

// Read offsets struct (32 bytes) just before the trailer
const offsetsStart = expectedTrailerStart - OFFSETS_SIZE_CONST
const offsetsByteCount = Number(searchBuf.readBigUInt64LE(offsetsStart))

// Module graph total size = byte_count (string data + module list) + offsets(32) + trailer(16)
const moduleGraphSize = offsetsByteCount + OFFSETS_SIZE_CONST + TRAILER_LEN
const hostBunSize = hostBytes.length - 8 - moduleGraphSize

console.log(`Host standalone size: ${hostBytes.length}`)
console.log(`Derived host bun size: ${hostBunSize}`)
console.log(`Module graph size: ${moduleGraphSize}`)

if (hostBunSize <= 0) {
  console.error(`ERROR: Derived host bun size is ${hostBunSize} — something is wrong`)
  process.exit(1)
}

const moduleGraphBytes = hostBytes.slice(hostBunSize, hostBytes.length - 8)
console.log(`Module graph extracted: ${moduleGraphBytes.length} bytes`)
console.log(`Trailer verified: OK`)

// Step 5: Patch the module graph for Android
console.log("\n=== Step 5: Patching module graph for Android ===")

// The module graph format (from StandaloneModuleGraph.zig):
//   [string data: all file names, contents, sourcemaps, bytecodes concatenated]
//   [CompiledModuleGraphFile array]
//   [Offsets struct: 32 bytes]
//   [trailer: "\n---- Bun! ----\n"]
//
// Offsets struct layout (32 bytes, little-endian, unchanged across Bun versions):
//   byte_count:              u64  (8 bytes)
//   modules_ptr.offset:      u32  (4 bytes)
//   modules_ptr.length:      u32  (4 bytes)
//   entry_point_id:          u32  (4 bytes)
//   compile_exec_argv.offset:u32  (4 bytes)
//   compile_exec_argv.length:u32  (4 bytes)
//   flags:                   u32  (4 bytes)
//
// NOTE: CompiledModuleGraphFile layout varies between Bun versions:
//   - Bun <= 1.3.2:  36 bytes
//   - Bun >= 1.3.11: 52 bytes
// Host and target Bun are both 1.3.11 here, so the layouts match. All
// patches below are same-size in-place byte replacements in the raw string
// data, so we don't need to know the module struct layout at all.

const mgTrailer = "\n---- Bun! ----\n"
const mgTrailerBuf = Buffer.from(mgTrailer)
const OFFSETS_SIZE = 32

const mgBuf = Buffer.from(moduleGraphBytes)
const trailerPosInMg = mgBuf.lastIndexOf(mgTrailerBuf)
if (trailerPosInMg < 0) throw new Error("Trailer not found in module graph!")

// Offsets struct is just before the trailer
const mgOffsetsStart = trailerPosInMg - OFFSETS_SIZE
const byteCount = Number(mgBuf.readBigUInt64LE(mgOffsetsStart))
const modOff = mgBuf.readUInt32LE(mgOffsetsStart + 8)
const modLen = mgBuf.readUInt32LE(mgOffsetsStart + 12)
const entryId = mgBuf.readUInt32LE(mgOffsetsStart + 16)
const argvOff = mgBuf.readUInt32LE(mgOffsetsStart + 20)
const argvLen = mgBuf.readUInt32LE(mgOffsetsStart + 24)
const flags = mgBuf.readUInt32LE(mgOffsetsStart + 28)

console.log(`Module graph: trailer at ${trailerPosInMg}, offsets at ${mgOffsetsStart}`)
console.log(`byte_count=${byteCount}, modules_ptr=(${modOff},${modLen}), entry_id=${entryId}`)
console.log(`String data region: [0, ${modOff}), Module list: [${modOff}, ${modOff + modLen})`)

// ---- Patch 1: Fix undici reference ----
// The host bun bundler compiles `import "undici"` as a bare global reference `undici`.
// Android bun doesn't expose globalThis.undici, but it does expose `Undici`
// (capital U, the moduleExports object). `__reExport` skips the "default" key anyway,
// so the result is identical.
//
// This is a same-byte-count replacement: we search the entire string data region
// for the pattern and replace in-place. No module struct parsing required.
const UNDICI_SEARCH = Buffer.from('__reExport(exports_Undici, undici)')
const UNDICI_REPLACE = Buffer.from('__reExport(exports_Undici, Undici)')
console.log(`\nPatch 1: Replacing undici->Undici in string data (same size, no offset changes)`)

let undiciPatchCount = 0
let searchPos = 0
// Search only within the string data region [0, modOff)
const strDataRegion = mgBuf.slice(0, modOff)
while (true) {
  const pos = strDataRegion.indexOf(UNDICI_SEARCH, searchPos)
  if (pos < 0) break
  console.log(`  Found at string data offset ${pos}, replacing...`)
  UNDICI_REPLACE.copy(mgBuf, pos)
  undiciPatchCount++
  searchPos = pos + UNDICI_SEARCH.length
}
if (undiciPatchCount === 0) {
  console.log("NOTE: __reExport(exports_Undici, undici) not found — skipping Patch 1 (not needed in this Bun version)")
} else {
  console.log(`  Patched ${undiciPatchCount} occurrence(s)`)
}

// Since all patches are same-size in-place edits, the module graph is unchanged
// in structure. We just pass through the entire mgBuf (with our in-place edits)
// as the final module graph.
var finalModuleGraph = mgBuf.slice(0, trailerPosInMg + mgTrailerBuf.length)
console.log(`Module graph size: ${finalModuleGraph.length} bytes (unchanged)`)

// Step 6: Create Android standalone binary
console.log("\n=== Step 6: Creating Android standalone binary ===")

// ANDROID_BUN is the prebuilt runtime from guysoft's release: an android bun
// WITH his opencode module graph already appended. Strip that graph so we
// append ours to the bare bun runtime ([bun][graph][total u64]).
function stripModuleGraph(bytes: Uint8Array): Uint8Array {
  const buf = Buffer.from(bytes.buffer, bytes.byteOffset, bytes.length)
  const TRAILER = Buffer.from("\n---- Bun! ----\n")
  const trailerEnd = bytes.length - 8
  const trailerStart = trailerEnd - TRAILER.length
  if (trailerStart < 0 || buf.compare(TRAILER, 0, TRAILER.length, trailerStart, trailerEnd) !== 0) {
    // No module graph (bare bun runtime) — use as-is
    console.log("Android bun has no embedded module graph (bare runtime)")
    return bytes
  }
  const offsetsStart = trailerStart - 32
  const graphBytes = Number(buf.readBigUInt64LE(offsetsStart))
  const graphSize = graphBytes + 32 + TRAILER.length
  const bunSize = bytes.length - 8 - graphSize
  console.log(`Stripping existing module graph: ${graphSize} bytes (bun core: ${bunSize} bytes)`)
  if (bunSize <= 0) throw new Error("Failed to parse android bun module graph")
  return bytes.slice(0, bunSize)
}

const androidBunStripped = stripModuleGraph(new Uint8Array(await Bun.file(ANDROID_BUN).arrayBuffer()))
const androidBunBytes = androidBunStripped
const androidBunSize = androidBunBytes.length
console.log(`Android bun size: ${androidBunSize}`)

// New total_byte_count = android_bun_size + module_graph.length + 8
const newTotalByteCount = androidBunSize + finalModuleGraph.length + 8

// Create the output buffer
const outputSize = androidBunSize + finalModuleGraph.length + 8
const output = new Uint8Array(outputSize)

// Copy Android bun binary
output.set(androidBunBytes, 0)

// Copy patched module graph
output.set(new Uint8Array(finalModuleGraph.buffer, finalModuleGraph.byteOffset, finalModuleGraph.length), androidBunSize)

// Write new total_byte_count as u64 LE
const totalView = new DataView(output.buffer, outputSize - 8, 8)
totalView.setUint32(0, newTotalByteCount & 0xFFFFFFFF, true)
totalView.setUint32(4, Math.floor(newTotalByteCount / 0x100000000), true)

const androidOutputPath = path.join(OUTPUT_DIR, "opencode")
await Bun.write(androidOutputPath, output)
fs.chmodSync(androidOutputPath, 0o755)

console.log(`\nAndroid standalone binary: ${androidOutputPath}`)
console.log(`Size: ${(outputSize / 1024 / 1024).toFixed(1)} MB`)

// Verify
const verifyBytes = new Uint8Array(await Bun.file(androidOutputPath).arrayBuffer())
const verifyView = new DataView(verifyBytes.buffer, verifyBytes.length - 8, 8)
const verifyTotal = verifyView.getUint32(0, true) + verifyView.getUint32(4, true) * 0x100000000
console.log(`Verification: total_byte_count=${verifyTotal}, file_size=${verifyBytes.length}, match=${verifyTotal === verifyBytes.length}`)

// Check ELF header
const elfMagic = String.fromCharCode(verifyBytes[0], verifyBytes[1], verifyBytes[2], verifyBytes[3])
console.log(`ELF magic: ${elfMagic === "\x7fELF" ? "OK" : "INVALID"}`)

console.log("\n=== Build complete! ===")
console.log(`Output: ${androidOutputPath}`)
