import path from "path"
import fs from "fs/promises"
import { existsSync } from "fs"
import { xdgData, xdgCache, xdgConfig, xdgState } from "xdg-basedir"
import os from "os"
import { Context, Effect, Layer } from "effect"
import { Flock } from "./util/flock"
import { Flag } from "./flag/flag"
import { LayerNode } from "./effect/layer-node"

const app = "opencode"
const data = path.join(xdgData!, app)
const cache = path.join(xdgCache!, app)
const config = path.join(xdgConfig!, app)
const state = path.join(xdgState!, app)
// On Android the default tmpdir is /tmp, which lives on a read-only rootfs.
// Workers spawned by the compiled binary may not inherit any environment, so
// detect Termux from its constant app data path instead of relying on $PREFIX.
function termuxPrefix(): string | undefined {
  if (process.env.PREFIX) return process.env.PREFIX
  if (existsSync("/data/data/com.termux")) return "/data/data/com.termux/files/usr"
  return undefined
}

const prefix = termuxPrefix()
const tmpRoot = process.env.OPENCODE_TMPDIR ?? (prefix ? path.join(prefix, "tmp") : os.tmpdir())
const tmp = path.join(tmpRoot, app)

const paths = {
  get home() {
    return process.env.OPENCODE_TEST_HOME ?? os.homedir()
  },
  data,
  bin: path.join(cache, "bin"),
  log: path.join(data, "log"),
  repos: path.join(data, "repos"),
  cache,
  config,
  state,
  tmp,
}

export const Path = paths

Flock.setGlobal({ state })

// Create the app directories, but never let one unwritable path (e.g. a
// read-only tmpdir on Android) take down the whole CLI at import time.
await Promise.all(
  [Path.data, Path.config, Path.state, Path.tmp, Path.log, Path.bin, Path.repos].map(
    async (dir) => {
      try {
        await fs.mkdir(dir, { recursive: true })
      } catch (e) {
        console.error(`[zyvo] warning: could not create directory ${dir}:`, (e as Error).message)
      }
    },
  ),
)

export class Service extends Context.Service<Service, Interface>()("@opencode/Global") {}

export interface Interface {
  readonly home: string
  readonly data: string
  readonly cache: string
  readonly config: string
  readonly state: string
  readonly tmp: string
  readonly bin: string
  readonly log: string
  readonly repos: string
}

export function make(input: Partial<Interface> = {}): Interface {
  return {
    home: Path.home,
    data: Path.data,
    cache: Path.cache,
    config: Flag.OPENCODE_CONFIG_DIR ?? Path.config,
    state: Path.state,
    tmp: Path.tmp,
    bin: Path.bin,
    log: Path.log,
    repos: Path.repos,
    ...input,
  }
}

export const layer = Layer.effect(
  Service,
  Effect.sync(() => Service.of(make())),
)

export const defaultLayer = layer
export const node = LayerNode.make(layer, [])

export const layerWith = (input: Partial<Interface>) =>
  Layer.effect(
    Service,
    Effect.sync(() => Service.of(make(input))),
  )

export * as Global from "./global"
