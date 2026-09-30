# Authoring a third-party DSH server-side plugin package

Reference for building a plugin package outside the DSH monorepo and installing it into a
user profile with `dsh plugin --profile <name> add <package>`.

---

## Verified facts vs. inferred

**Verified** (read directly from shipped files, every claim carries a citation):

- Every `package.json`, `exports` map, `files` list and `lib/*.js` entry point quoted below was
  read from the installation.
- Every loader / patch / profile behaviour quoted below was read from the compiled CLI
  (`lib/plugin-*.js`, `lib/profile-boot-*.js`, `lib/bin.js`, `lib/dump-config-*.js`) or from
  vendored TypeScript sources that ship in the tarball (`@deepseek-ai/cordis/src/*.ts`,
  `@deepseek-ai/cordis-plugin-loader/src/*.ts`, `@deepseek-ai/cordis-plugin-include/src/index.ts`).
- One **live, working third-party plugin installation** exists on this machine and was read:
  two non-`@deepseek-ai` packages are mounted into the `web` profile from `link:` local paths.
  It is used below as the only end-to-end evidence available for "a third party can do this".

**Inferred** (reasoning, not read from a file — flagged inline as `[inferred]`):

- Node's ESM symlink-realpath resolution and its consequence for bare `@deepseek-ai/*` imports
  from a `link:`-installed plugin. The inference is corroborated by the workaround the live
  third-party plugin uses, but it was not executed.
- Whether a given package name resolves from the dsh installation or from a registry mirror.
- Anything about the upstream monorepo build (tsconfig, tsdown config, workspace root scripts):
  **none of it ships**.

**Path notation.** `$R` = `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh` (the DSH install
root; absolute). `$P` = `$R/node_modules/@deepseek-ai` (bundled packages; absolute).
`$L` = `/home/igor/.config/dsh-remote` (a live third-party plugin checkout outside the install
root; absolute). All three are absolute paths; `$R/...:line` expands to an absolute path.

---

## 1. Minimal viable plugin package

### 1.1 The five reference manifests

| field | `dsh-tool-todo` | `dsh-time-context` | `dsh-goal` | `dsh-skill` | `dsh-tool-present` |
|---|---|---|---|---|---|
| `name` | `@deepseek-ai/dsh-tool-todo` | `@deepseek-ai/dsh-time-context` | `@deepseek-ai/dsh-goal` | `@deepseek-ai/dsh-skill` | `@deepseek-ai/dsh-tool-present` |
| `type` | `module` | `module` | `module` | `module` | `module` |
| `main` | `lib/index.js` | `lib/index.js` | `lib/index.js` | `lib/index.js` | `lib/index.js` |
| top-level `types` | `lib/types/index.d.ts` | `lib/types/index.d.ts` | `lib/types/index.d.ts` | `lib/types/index.d.ts` | `lib/types/index.d.ts` |
| `exports["."]` | `./lib/index.js` | `./lib/index.js` | `./lib/index.js` | `./lib/index.js` | `./lib/index.js` |
| `./invariant` | yes | yes | yes | **no** | **no** |
| `./types` | no | no | yes | no | yes |
| `./client` | yes | no | yes | no | no |
| `./typert` `./remote` | no | no | yes | no | no |
| `./src/*` | yes (dangling) | yes (dangling) | yes (dangling) | yes (dangling) | yes (dangling) |
| `./package.json` | yes | yes | yes | yes | yes |
| `files` | `lib/index.js`, `lib/invariant.js`, `lib/types/**/*.js`, `lib/types/**/*.d.ts` | `lib/index.js`, `lib/invariant.js`, `lib/types/**/*.d.ts` | `lib/index.js`, `lib/invariant.js`, `lib/types/**/*.js`, `lib/types/**/*.d.ts`, `lib/typert.host.js`, `lib/typert.host.d.ts`, `lib/typert.remote-client.js`, `lib/typert.remote-client.d.ts` | `lib/index.js`, `lib/types/**/*.d.ts` | `lib/index.js`, `lib/types/**/*.js`, `lib/types/**/*.d.ts` |
| `license` | `MIT` | `MIT` | `MIT` | `MIT` | `MIT` |
| `dsh` field | **absent** | **absent** | **absent** | **absent** | **absent** |

Citations: `$P/dsh-tool-todo/package.json:13-38`, `$P/dsh-time-context/package.json:13-32`,
`$P/dsh-goal/package.json:13-54`, `$P/dsh-skill/package.json:13-28`,
`$P/dsh-tool-present/package.json:13-33`.

### 1.2 Required vs. optional fields

**Required to be mountable as a plugin row** (all five packages carry them; the loader needs
`name` + an importable entry):

- `name` — the specifier a loader row's `name:` resolves.
- `type: "module"` — every package in the tree sets it; the compiler emits ESM
  (`$P/dsh-tool-todo/lib/index.js:196` is a plain `export { ... }`).
- An entry point resolvable as the bare package specifier: `main` **and/or** `exports["."]`.
  All five declare both (`main` is legacy fallback; `exports` is authoritative under Node ESM).

**Required for correctness / convention:**

- `exports` with an explicit `types` condition on every subpath. Universal across the nine
  manifests surveyed: no subpath lacks `types`; no manifest uses `import`/`require` conditions.
- `files` — an npm allow-list. Without it the published tarball would include `src/` and tests.
  The one hard rule observed: **`lib/types/*.js` ships iff `files` contains
  `lib/types/**/*.js`** (`$P/dsh-tool-todo/package.json:32-37` ships them;
  `$P/dsh-time-context/package.json:28-32` does not and ships only `.d.ts`).
- `license` — all five use `MIT` (e.g. `$P/dsh-skill/package.json:26`).

**Optional:** `description`, `version`, `publishConfig.access: "public"`, `repository`,
`dependencies`, `peerDependencies`, `devDependencies`, `dsh`.

**Not used by any of the 240 first-party packages:** `imports`, `typesVersions`, `engines`
(only `node-addon-system` and its platform binary declare `"engines": {"node": ">=20"}`).
`sideEffects: false` appears exactly once, on `cordis`
(`$P/cordis/package.json:13`).

### 1.3 `dependencies` vs `peerDependencies` — the split is a convention, and it is consistent

The convention: **anything that is a Cordis service, a schema registry, or a co-mounted DSH
package is a `peerDependency`; anything that is a library private to the package is a
`dependency`.**

- `dsh-tool-todo`: `dependencies` = `zod`, `@deepseek-ai/schemastery`;
  `peerDependencies` = `@deepseek-ai/dsh-agent`, `dsh-invariants`, `dsh-session`,
  `dsh-session-projection`, `dsh-tools`, `@deepseek-ai/cordis`
  (`$P/dsh-tool-todo/package.json:39-50`).
- `dsh-time-context`: `dependencies` = `zod`, `@deepseek-ai/dsh-util-values`,
  `@deepseek-ai/schemastery`; `peerDependencies` = `cordis`, `dsh-agent`, `dsh-invariants`,
  `dsh-llm`, `dsh-session`, `dsh-session-projection`
  (`$P/dsh-time-context/package.json:34-46`).
- `dsh-skill`: `dependencies` = `@deepseek-ai/dsh-util-values`, `@deepseek-ai/schemastery`;
  `peerDependencies` = `@deepseek-ai/dsh-scope`, `dsh-llm`, `@deepseek-ai/cordis`
  (`$P/dsh-skill/package.json:29-37`).

Rule of thumb visible in the data: **`@deepseek-ai/schemastery` and `zod` are `dependencies`;
every `@deepseek-ai/dsh-*` runtime package and `@deepseek-ai/cordis` is a `peerDependency`.**
`dsh-tool-present` is the minimal illustration: `dependencies` is exactly
`{"@deepseek-ai/schemastery": "^3.18.2"}` with seven peers
(`$P/dsh-tool-present/package.json:34-45`).

Why this matters operationally is covered in §2.7 (the profile's pnpm config sets
`autoInstallPeers: false`).

### 1.4 The `./invariant` subpath convention

`./invariant` is a **second entry point of the same package**, compiled to `lib/invariant.js`,
which exports a standalone Cordis plugin that registers that package's runtime checks:

```
"exports": {
  "./invariant": {
    "types": "./lib/types/invariant.d.ts",
    "default": "./lib/invariant.js"
  }
}
```
(`$P/dsh-tool-todo/package.json:21-24`; identical shape at `$P/dsh-time-context/package.json:21-24`,
`$P/dsh-goal/package.json:21-24`, `$P/dsh-storage-domain/package.json:21-24`,
`$P/dsh-tools/package.json:21-24`.)

It is a *convention for packages that own durable invariants*, not a requirement:
`dsh-skill` and `dsh-tool-present` have no `./invariant` (`$P/dsh-skill/package.json:16-23`,
`$P/dsh-tool-present/package.json:16-27`).

`./invariant` is loaded by a **separate loader row** whose `name` is
`<package>/invariant`, e.g. `$P/dsh-sdk-minimal/cordis.patch.yml:103-116`:

```
    - id: session-invariant
      name: '@deepseek-ai/dsh-session/invariant'

    - id: agent-invariant
      name: '@deepseek-ai/dsh-agent/invariant'
```

Note: the shipped `dsh-base` patch layer mounts **no** invariant rows at all — grepping for
`invariant` in `$P/dsh-base/cordis.patch.yml` returns nothing, and the only `dsh-invariants`
service row in the whole install is `$P/dsh-sdk-minimal/cordis.patch.yml:103-104`. So a profile
that does not mount `dsh-invariants` will simply never activate your companion; a row for it is
harmless (its `inject: ["invariants"]` never becomes available, so the fiber stays `PENDING`).

### 1.5 `./src/*` — declared by ~220 packages, resolvable by 8

`"./src/*": "./src/*"` is declared by 228 packages
(`$P/dsh-tool-todo/package.json:29`, `$P/dsh-skill/package.json:21`,
`$P/dsh-goal/package.json:41`, `$P/dsh-tools/package.json:33`, …). Only 8 packages actually ship a `src/` directory:
`cordis`, `cordis-plugin-loader`, `cordis-plugin-group`, `cordis-plugin-timer`,
`cordis-plugin-include`, `cordis-plugin-hmr`, `cosmokit`, `schemastery` — and exactly those 8
list `"src"` in `files` (`$P/cordis/package.json:30`,
`$P/cordis-plugin-loader/package.json:28`, `$P/schemastery/package.json:31`).
For every other package the subpath is dangling. **Do not rely on `./src/*` for a third-party
package; it exists so the monorepo can point tooling at sources.**

### 1.6 The `dsh` field in package.json

The field is typed by `@deepseek-ai/dsh-package-manifest` — a types-only package whose runtime
entry is literally `export {};` (`$P/dsh-package-manifest/lib/index.js:1`) — and has **five
declared roles** (`$P/dsh-package-manifest/lib/types/types.d.ts:7-23`):

```ts
export interface DshManifest {
    bundle?: DshBundleManifest;
    profile?: DshProfileManifest;
    client?: DshClientManifest;
    configTrees?: DshConfigTreeDeclaration[];
    sessionFormatMigration?: DshSessionFormatMigrationManifest;
    moduleFallback?: DshModuleFallbackManifest;   // @internal, launcher-generated
}
```

The **only role relevant to mounting a server-side plugin is `bundle`**
(`$P/dsh-package-manifest/lib/types/types.d.ts:24-28`):

```ts
export interface DshBundleManifest {
    /** Patch file path relative to the declaring package root. */
    patch: string;
}
```

Definitions:

- **Plugin** — an npm package whose entry point is a Cordis plugin, mounted by a loader row
  `{ id, name: '<your-package>' }`.
- **Bundle** — a package that ships a **patch file** (a YAML list of loader patch entries) and
  declares it as `dsh.bundle.patch`. A bundle is a *profile layer*: its patch list is applied
  over the tree in `dsh.profile.bundles` order.

**Does a package need a `dsh` field to be mountable?** — **No, not to be mounted; yes, to be
auto-activated by `dsh plugin add`.**

- The loader mounts a row by importing `options.name` and calling
  `ctx.registry.plugin(plugin, options.config, …)`
  (`$P/cordis-plugin-loader/src/config/entry.ts:291-302`). Nothing in that path reads the
  package manifest.
- `dsh plugin --profile <n> add <pkg>` decides whether to add `<pkg>` to
  `dsh.profile.bundles` solely by testing `dsh.bundle.patch !== undefined` on the resolved
  package (`$DSH/lib/plugin-Ddi42qoW.js:25-33`). If absent it prints a warning and installs the
  package as a plain dependency that **nothing mounts**:

  ```
  dsh: warning: <pkg> declares no dsh.bundle — installed as a plain dependency, not a profile
  layer (a later update that gains one activates it automatically)
  ```
  (`$DSH/lib/plugin-Ddi42qoW.js:57-58`.)

- A listed bundle with no `dsh.bundle` **fails loud** at profile load:
  `dsh: profile bundle "<pkg>" declares no dsh.bundle in its package.json`
  (`$P/dsh-app-boot/lib/index.js:852`).

Consequence for a third-party author: **declare `dsh.bundle.patch` and ship a patch file that
inserts your own row** — that is the whole of what "installable via `dsh plugin add`" means.

`configTrees` is **not** a mounting mechanism. It is documented as "Config directories consumed
by the experimental deployment-image packer"
(`$P/dsh-package-manifest/lib/types/types.d.ts:14-15`, `:53-61`) and appears in exactly one
manifest in the whole installation — the CLI itself:

```json
"dsh": { "configTrees": [ { "mount": "config/agent-presets",
                            "path": "../../packages/preset/agent-presets/presets",
                            "scanRoster": true } ] }
```
(`$R/package.json:20-28`.) Its `path` is a monorepo-relative path that does not exist in the
published layout, which is itself evidence it is not a runtime mount input.

---

## 2. How installation and mounting actually work

### 2.1 `dsh plugin --profile <name> add <package>` — exact behaviour

The CLI command is a **thin pnpm forwarder plus a reconciliation pass**
(`$DSH/lib/plugin-Ddi42qoW.js:7-17`). `runPlugin` (`$DSH/lib/plugin-Ddi42qoW.js:101-128`):

1. `const dir = resolveProfileDir(profile)` → `$DSH_HOME/profiles/<name>`
   (`$P/dsh-app-boot/lib/index.js:323-326`).
2. If `<dir>/package.json` does not exist, initialize the profile from
   `PROFILE_TEMPLATES[profile]` if the name is shipped, else `DEFAULT_PROFILE_BUNDLES`, and print
   `dsh: initialized profile <name> at <dir>`
   (`$DSH/lib/plugin-Ddi42qoW.js:103-107`, `$P/dsh-app-boot/lib/index.js:328-349`, `:357`).
3. Snapshot the pre-existing manifest (`$DSH/lib/plugin-Ddi42qoW.js:108`).
4. `spawnSync("pnpm", args.map(anchorPathSpec), { cwd: dir, stdio: "inherit" })`
   (`$DSH/lib/plugin-Ddi42qoW.js:109-113`). **Every argument** is passed through
   `anchorPathSpec`, which rewrites a bare `.`/`..`/`./x`/`../x` (optionally `file:`/`link:`
   prefixed) to an absolute path resolved against the **invoking** directory, so `add .` from a
   plugin checkout cannot self-link the profile (`$DSH/lib/plugin-Ddi42qoW.js:90-94`). Absolute
   paths, registry names, git URLs and tarball specs pass through untouched.
5. If pnpm exited 0, `reconcilePlugins(before, dir)` (`$DSH/lib/plugin-Ddi42qoW.js:122`).
   Otherwise a diagnostic is printed; for git specs the CLI explains the blocked `prepare`
   script and points at `allowBuilds` in `<dir>/pnpm-workspace.yaml`
   (`$DSH/lib/plugin-Ddi42qoW.js:124-125`).
6. `process.exit(exitCode)` (`$R/lib/bin.js:155-158`).

`pnpm` on `PATH` is required; a missing binary yields exit code 127 with
`dsh: pnpm not found on PATH — install pnpm to manage profile plugins`
(`$DSH/lib/plugin-Ddi42qoW.js:114-119`).

**Reconciling** (`$DSH/lib/plugin-Ddi42qoW.js:34-78`) is done by *installed state*, not by
dependency diff, deliberately, so that `pnpm update` activates a package that gained
`dsh.bundle` in a newer version (`$DSH/lib/plugin-Ddi42qoW.js:11-15`). For every name in the new
manifest's `dependencies`:

- if it resolves to a package declaring `dsh.bundle.patch` **and** is not already listed →
  `plugins.push(name)` (appended in dependency order);
- if it declares no bundle and is newly added → the warning above.

Then, for every currently listed bundle whose name is (or was) a dependency and which no longer
resolves to a bundle → removed from the list. The rewritten `dsh.profile.bundles` is persisted
with `writeProfileManifest` (2-space JSON + trailing newline,
`$P/dsh-app-boot/lib/index.js:763-765`). In-box bundles from the profile template are not
dependencies and are never touched (`$DSH/lib/plugin-Ddi42qoW.js:42-44`).

### 2.2 What a profile contains

`initProfile` writes exactly three files and never overwrites an existing one
(`$P/dsh-app-boot/lib/index.js:379-398`):

```js
const manifest = {
  name: `dsh-profile-${basename(dir)}`,
  private: true,
  dependencies: {},
  dsh: { profile: { bundles: [...bundles], patchReload } }
};
```

- `package.json` — name, `private: true`, `dependencies`, and the `dsh.profile` manifest.
- `cordis.patch.yml` — the user patch layer; template is a top-level `[]` with a comment
  (`$P/dsh-app-boot/lib/index.js:360-364`).
- `pnpm-workspace.yaml` — verbatim (`$P/dsh-app-boot/lib/index.js:365-370`):

  ```yaml
  packages:
    - .

  nodeLinker: hoisted
  autoInstallPeers: false
  ```

A **fourth** file, `cordis.yml`, is written on every load, not at init: the profile root is
always rewritten to an empty entry list because the whole composition is patch layers, and the
loader's tree write-back could otherwise bake composed rows into it
(`$DSH/lib/profile-boot-Dk-7KqJc.js:191-211`, template at `:124-130`).

Real, live profile at `$DSH_HOME/profiles/web`:

```
cordis.patch.yml      290 bytes
cordis.yml            223 bytes
.dsh-module-fallback/  (dir)
node_modules/          (dir; pnpm)
package.json          422 bytes
pnpm-lock.yaml        424 bytes
pnpm-workspace.yaml    61 bytes
```
`$HOME/.dsh/profiles/web` listing. Its `cordis.patch.yml` is a working id-targeted disable:

```yaml
# Your patch layer for this dsh profile, applied after every bundle layer:
# a top-level YAML array of loader patch entries (id-targeted config
# overrides, disables, and insert lists; `!!js` expressions allowed).
- id: llm-deepseek
  name: '@deepseek-ai/dsh-llm-deepseek'
  disabled: true
```
`$HOME/.dsh/profiles/web/cordis.patch.yml:1-6`.

Its `package.json` is the **key third-party evidence** — two non-`@deepseek-ai` packages,
installed from local paths and listed as profile layers:

```json
{
  "name": "dsh-profile-web",
  "private": true,
  "dependencies": {
    "dsh-locale-pt": "link:/home/igor/.config/dsh-remote/dsh-locale-pt",
    "dsh-judge": "link:/home/igor/.config/dsh-remote/dsh-judge"
  },
  "dsh": {
    "profile": {
      "bundles": [
        "@deepseek-ai/dsh-base",
        "@deepseek-ai/dsh-web-app",
        "dsh-locale-pt",
        "dsh-judge"
      ],
      "patchReload": "live"
    }
  }
}
```
`$HOME/.dsh/profiles/web/package.json:1-19` (note: `bundles` uses the **installed package
name**, not the spec — exactly what the reconcile comment promises at
`$DSH/lib/plugin-Ddi42qoW.js:36-39`).

### 2.3 The patch stack, in application order

`allPatches(composed)` (`$DSH/lib/profile-boot-Dk-7KqJc.js:213-220`):

```
[ ...bundlePatches, ...profile.patches, ...homePatches, ...overlays ]
```

i.e. bundle layers in `dsh.profile.bundles` order → profile `cordis.patch.yml` → home-level
`$DSH_HOME/cordis.patch.yml` (outranks the per-profile layer, `:222-227`) → `--patch` overlays
→ the launcher's telemetry switch, which is a synthetic `{ id, disabled: true }` patch
(`:184-190`). The composed list is then handed to `boot(...)`
(`$DSH/lib/profile-boot-Dk-7KqJc.js:311-319`).

### 2.4 The exact YAML shape of a plugin row

`EntryOptions` is the row contract
(`$P/cordis-plugin-loader/src/config/entry.ts:8-22`):

```ts
export interface EntryOptions {
  /** Stable id inside the containing entry tree. */
  id: string
  /** Module specifier imported by the entry tree. */
  name: string
  /** Config passed to the plugin. */
  config?: any
  /** Marks this entry as a nested group. */
  group?: boolean | null
  /** Prevents this entry and descendants from running. */
  disabled?: boolean | null
  /** Required services or service intercept config for this entry. */
  inject?: Inject | null
}
```

`PatchOptions` is the patch-row contract
(`$P/cordis-plugin-include/src/index.ts:144-156`):

```ts
export interface PatchOptions {
  id?: string
  insert?: EntryOptions[]
  name?: string
  config?: any
  group?: boolean | null
  disabled?: boolean | null
  inject?: any
  intercept?: any
  isolate?: any
  [key: string]: any
}
```

**Four concrete shapes.**

(a) **Insert a new row with config** — the shape a third-party bundle almost always uses.
Real third-party example, `$L/dsh-judge/cordis.patch.yml:1-14`:

```yaml
# Own plugin id and /goal-judge <objective>. Leave the shipped Goal strip and /goal alone.
- insert:
    - id: goal-judge
      name: dsh-judge
      config:
        enabled: true
        inheritAgentModel: true
        infiniteReview: true
        maxReviews: 3
        timeoutMs: 600000
        graceMs: 300000
        maxSteps: 250
        maxFileBytes: 80000
        maxClaimChars: 12000
```

(b) **Insert a row that needs service deps declared at the row level** —
`$P/dsh-headless/cordis.patch.yml:18-31`:

```yaml
- insert:
    # PTC mode is a core execution capability, not a Web component.
    - id: code-runtime
      name: '@deepseek-ai/dsh-code-runtime-worker-thread'

    - id: headless-startup
      name: '@deepseek-ai/dsh-headless/startup'

    # Reads its task from the ordinary headlessStartup provider.
    - id: headless-runner
      name: '@deepseek-ai/dsh-headless'
      inject: [headlessStartup]
      config:
        task: !!js ctx.headlessStartup.task
```

(c) **Id-targeted override of an existing row's config** (name is an optional assertion; config
*replaces* the row's whole config, it does not merge) — `$P/dsh-headless/cordis.patch.yml:7-16`:

```yaml
- id: system-prompt
  config:
    personaSuffix: Your working directory is {{cwd}}.
    personaPrefix: >-
      You are a coding agent powered by the {{model}} model.

- id: tools
  config:
    # Keep the same temporary process-wide PTC mode opt-in as the Web surface.
    mode: !!js process.env.DSH_TOOLS_MODE
```

(d) **Disable a row** — `$P/dsh-base/cordis.patch.yml:21-25` (row with `disabled: true` inside an
insert) and `$HOME/.dsh/profiles/web/cordis.patch.yml:4-6` (id-targeted disable):

```yaml
    - id: hmr
      name: '@deepseek-ai/cordis-plugin-hmr'
      disabled: true
      config:
        root: ['.']
```

`!!js <expr>` is a YAML tag defined by the include plugin
(`$P/cordis-plugin-include/src/index.ts:9-23`) whose value is a `{ __jsExpr }` node the loader
evaluates at entry activation through a `with (ctx) { return eval(expr) }` scope
(`$P/cordis-plugin-loader/src/config/utils.ts:5-9`). `ctx` is the entry's context, so
`process.env`, `ctx.<service>` and context-provided helpers are in scope; the launcher provides
`dshHomePath` (`$P/dsh-app-boot/lib/index.js:1530`), which is how `dsh-base` writes storage
outside the profile:

```yaml
    - id: storage-json
      name: '@deepseek-ai/dsh-storage-json'
      config:
        root: !!js dshHomePath('storages')
```
`$P/dsh-base/cordis.patch.yml:148-152`.

### 2.5 Loader patch-entry semantics (from the code)

`applyEntryPatches(data, patches, warn)` is *the* patch semantics, shared by mounting and by
`dsh --dump-config` so a dump can never drift from what boots
(`$P/cordis-plugin-include/src/index.ts:43-57`). The algorithm
(`$P/cordis-plugin-include/src/index.ts:58-128`):

1. The input is `structuredClone`d; the result is always detached (`:63`).
2. An `entryMap: id → EntryOptions` is built over the root list; rows with
   `group: true` **and** an array `config` recurse into `config` (`:66-75`). Nesting is the only
   hierarchy: groups are rows whose children live in their own `config` array.
3. Non-insert patch (`:105-124`):
   - `id` is required; a patch without `id` and without `insert` warns
     `patch: id is required for non-insert patches` and is skipped (`:105-108`);
   - unknown id → warns `patch: entry %C not found` and is skipped (`:110-114`);
   - if `name` is given and differs from the target's name → warns
     `patch: name mismatch for %C (expected %C, got %C), skipping` and is skipped (`:116-119`).
     **A `name` on a non-insert patch is a guard, not a selector.** This is why the live profile
     row repeats `name: '@deepseek-ai/dsh-llm-deepseek'`.
   - every remaining key is assigned onto the target row verbatim (`:121-124`) — so `config` is
     **replaced wholesale**, and `disabled: true` disables the row and its descendants.
4. Insert patch (`:80-102`):
   - `insert` **with** `id` → the target must exist and must be a group (`group: true`),
     otherwise `patch insert: entry %C not found` or `patch insert: entry %C is not a group`;
     the rows are appended to `target.config` (`:81-92`);
   - `insert` **without** `id` → rows are appended to the root list (`:93-95`);
   - after inserting, the new rows are indexed so **a later patch in the same list can target a
     row an earlier patch inserted** (deliberate, `:96-102`).

Rows are addressed by `id`, and the effective id of a nested row is the parent chain joined with
`:` (`EntryTree.sep = ':'`, `$P/cordis-plugin-loader/src/config/tree.ts:8`, id getter at
`$P/cordis-plugin-loader/src/config/entry.ts:75-81`), which is how
`EntryTree.resolve('a:b')` works (`tree.ts:76-87`).

Disabling is inherited: `Entry.disabled` returns true if the row or any owning parent row is
disabled, except that a `group` row is never disabled by its own `disabled` flag
(`entry.ts:83-98`). `disabled` may itself be a `!!js` expression, evaluated against the loader
context on every read (`entry.ts:100-108`) — that is how the telemetry switch and the
`process.platform === 'win32'` rows work (`$P/dsh-sdk-minimal/cordis.patch.yml:123-125`).

Missing-target patches are **warnings, not errors** (`:52` "A patch that matches nothing warns
and is skipped"), so a bundle whose row another bundle never inserted fails silently — check
`dsh --profile <n> --dump-config`.

### 2.6 Registry vs. local path

**A plugin package does not need to be published.** The live profile proves it: both
`dsh-locale-pt` and `dsh-judge` are `link:` local paths, and the reconcile pass placed the true
package names in `dsh.profile.bundles`
(`$HOME/.dsh/profiles/web/package.json:5-15`). Any spec pnpm accepts works — the forwarding is
verbatim except for the relative-path rewrite (`$DSH/lib/plugin-Ddi42qoW.js:90-94`, `:109`),
and the reconciliation comment explicitly names "a git/path/tarball/alias spec"
(`$DSH/lib/plugin-Ddi42qoW.js:36-38`).

Two caveats are read directly off the code:

- **git specs need a build allowance.** The CLI prints a remediation pointing at `allowBuilds` in
  the profile's `pnpm-workspace.yaml` when pnpm blocks a `prepare` script
  (`$DSH/lib/plugin-Ddi42qoW.js:125`). Note that **no shipped DSH manifest has a `prepare`
  script** — the only install-time hooks in the whole tree are one `postinstall`
  (`$P/dsh-subprocess-local/package.json:52-54`) and one `prepack`
  (`$P/node-addon-system-linux-x64/package.json:21-23`). So a git-hosted third-party plugin is
  in uncharted territory here.
- **bundle resolution is two-anchor** — installation first, then the profile directory
  (`$P/dsh-app-boot/lib/index.js:814-832`). The error message names the recovery command:
  `... run 'dsh plugin --profile <name> install' if its dependency is not installed`
  (`$P/dsh-app-boot/lib/index.js:831`). Hand-editing the profile manifest therefore works, but
  you then run `dsh plugin --profile <n> install` rather than `add`.

### 2.7 How a mounted third-party plugin resolves `@deepseek-ai/*` imports

This is the single largest practical hazard, and the evidence is unambiguous but partly
inferential.

- `healProfilesModuleFallback` maintains `$DSH_HOME/profiles/node_modules` as a mirror of the
  installation's dependency closure (`$P/dsh-app-boot/lib/types/profile.d.ts:103-115`). Verified
  live: that directory contains 240 symlinks under `@deepseek-ai/`, each pointing into
  `$R/node_modules/` (e.g. `$HOME/.dsh/profiles/node_modules/@deepseek-ai/dsh-tools`). For a
  **pnpm-installed** plugin, whose real path is under
  `$DSH_HOME/profiles/<n>/node_modules/.pnpm/...`, Node's ordinary parent walk reaches that
  mirror, so bare `@deepseek-ai/*` specifiers resolve to the installation's exact module
  instances.
- For a **`link:`-installed** plugin, pnpm creates only
  `$DSH_HOME/profiles/web/node_modules/dsh-judge -> ../../../../.config/dsh-remote/dsh-judge`
  (verified live), and Node resolves ESM symlinks to their **real** path by default `[inferred]`.
  The real path is `/home/igor/.config/dsh-remote/dsh-judge/index.js`, whose parent walk cannot
  reach `$DSH_HOME/profiles/node_modules`.

Corroborating evidence that this is real and not theoretical: `$L/dsh-judge/index.js` imports
**nothing** as a bare specifier. Its entire dependency access is re-anchored on the DSH install:

```js
import { createRequire } from "node:module";
import { pathToFileURL } from "node:url";

const requireDsh = createRequire("/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/package.json");
const z = (await import(pathToFileURL(requireDsh.resolve("@deepseek-ai/schemastery")).href)).default;
const llm = await import(pathToFileURL(requireDsh.resolve("@deepseek-ai/dsh-llm")).href);
const { BlockAssembler, createUserMessage, createAssistantMessage, createToolResultMessage } = llm;
const { GoalError } = await import(pathToFileURL(requireDsh.resolve("@deepseek-ai/dsh-goal")).href);
```
`$L/dsh-judge/index.js:1-8`.

Second factor: the profile sets `autoInstallPeers: false`
(`$P/dsh-app-boot/lib/index.js:368`), so a plugin that lists `@deepseek-ai/*` only in
`peerDependencies` will not have them installed into the profile by pnpm.

**Practical guidance** (partly `[inferred]`): the DSH convention of putting `@deepseek-ai/*` in
`peerDependencies` is safe for a **published** plugin (the installation-closure mirror satisfies
resolution) and safe for the monorepo. For a **local `link:`/`file:` plugin**, either use the
`createRequire`-against-the-install-anchor idiom above, or accept duplicate module instances.

---

## 3. Plugin entry-point shape

### 3.1 The three accepted shapes

```ts
/** Supported plugin entrypoint shapes. */
export type Plugin<T = any> =
  | Plugin.Function<T>
  | Plugin.Constructor<T>
  | Plugin.Object<T>

export namespace Plugin {
  /** Shared metadata understood by the plugin registry and related tooling. */
  export interface Base<T = any> {
    /** Display name used for fiber diagnostics and logger names. */
    name?: string
    /** Standard-schema validator applied to config before the plugin starts. */
    Config?: StandardSchemaV1<any, T>
    /** Services the plugin requires; it only loads while all are available. */
    inject?: Inject
    /** Service name(s) the plugin provides (read by `Service` and by loaders). */
    provide?: string | string[]
    /** Service names whose intercept config the plugin declares it consumes. */
    intercept?: Dict<boolean>
  }

  /** Function plugin called with `(ctx, config)`. */
  export interface Function<T = any> extends Base<T> { (ctx: Context, config: T): any }

  /** Class plugin constructed with `(ctx, config)`. */
  export interface Constructor<T = any> extends Base<T> { new (ctx: Context, config: T): any }

  /** Object plugin with an `apply(ctx, config)` method. */
  export interface Object<T = any> extends Base<T> { apply(ctx: Context, config: T): any }
}
```
`$P/cordis/src/registry.ts:91-133`.

Resolution: `resolve()` returns `plugin` itself for a function, or `plugin.apply` for anything
with an `apply` method (`$P/cordis/src/registry.ts:216-228`). `ctx.plugin(plugin, config)` →
`RegistryService.plugin` creates or reuses a per-callback `Runtime` record, then starts a new
`Fiber` (`$P/cordis/src/registry.ts:304-336`). Note line 324-325: if `plugin.name === 'apply'`
the display name is discarded — so on an object plugin, always set an explicit `name`.

### 3.2 Default export vs. named exports — and the trap

The loader normalizes module shapes before applying
(`$P/cordis-plugin-loader/src/index.ts:191-199`):

```ts
/** Normalize ESM/CJS/default export shapes before applying a plugin. */
unwrapExports(exports: any) {
  if (isNullable(exports)) return exports
  exports = exports.default ?? exports
  // https://github.com/evanw/esbuild/issues/2623
  if (!exports.__esModule) return exports
  return exports.default ?? exports
}
```

**Consequence: if your module has a default export, `unwrapExports` returns it and the module
namespace — with its `name`/`inject`/`Config` named exports — is discarded.** Two idioms exist in
the tree, and they are mutually exclusive:

**Idiom A — no default export, metadata as named exports.** Use when the plugin is a function or
`{ apply }` object. `dsh-time-context`:

```js
// ...
/** Cordis plugin name used by loader diagnostics. */
const name = "time-context";
/** Schemastery validation for {@link Config}. */
const Config = z.object({ timeZone: z.string(), refreshIntervalMs: z.number() });
/** The agent registry that owns pre-step processing. */
const inject = ["agents", "sessionProjections"];
function apply(ctx, config) { /* ... */ }
// ...
export { Config, apply, inject, name };
```
`$P/dsh-time-context/lib/index.js:101-102`, `:111-117`, `:160`, `:250`.
Identical idiom in `dsh-tool-todo` (`$P/dsh-tool-todo/lib/index.js:11-12`, `:20`, `:78`,
`:196`) and `dsh-tool-present` (`$P/dsh-tool-present/lib/index.js:6-14`, `:20`, `:123`).

**Idiom B — default export is a `Service` subclass; metadata is `static` on the class.**
`dsh-goal`:

```js
export { GOAL_CHANGE_VERSION, GoalError, GoalId, GoalService, GoalService as default, ... };
```
`$P/dsh-goal/lib/index.js:906`; and on the class itself

```js
static inject = ["agents", "sessionProjections"];
static Config = z.object({ defaultMaxGoalRounds: z.number().default(256) });
...
super(ctx, "goals");
```
`$P/dsh-goal/lib/index.js:587-592`; declared in types at `$P/dsh-goal/lib/types/index.d.ts:56-57`.
Same for `dsh-skill`: `export { ..., SkillRegistry, SkillRegistry as default, ... }`
(`$P/dsh-skill/lib/index.js:565`) with `static Config` at `:120` and `super(ctx, "skills")` at
`:132`. `dsh-skill` declares no `inject` at all — it is a root service with no dependencies.

**Do not mix the idioms.** A default export plus module-level `inject`/`Config` named exports is a
silent bug: the metadata is dropped.

### 3.3 Declaring service dependencies

Two mechanisms:

1. **`inject` metadata** (module-level named export in Idiom A, `static inject` in Idiom B, or
   the row's `inject:` in YAML). The registry resolves it into the fiber, and the fiber stays
   `PENDING` until every named service is available
   (`$P/cordis/src/registry.ts:330`; states documented at `$P/cordis/src/fiber.ts:139-146`;
   dependency checks at `:597-609`). A rule row can also *extend* the plugin's inject map at
   activation (`$P/cordis-plugin-loader/src/index.ts:117-123`).
2. **`ctx.inject(deps, callback)`** for late-bound / optional deps — "the callback is unloaded
   and re-run whenever a required service changes"
   (`$P/cordis/src/registry.ts:164-176`). Real third-party usage, for optional services:

```js
ctx.inject(["settings"], (settingsCtx) => {
  settingsCtx.settings.installSection(ctx, NS, Config, entry, {
    setSource: (current) => { source = current; },
    onChange: () => {}
  });
});
ctx.inject(["commands"], (commandsCtx) => {
  commandsCtx.commands.register({ name: "goal-judge", /* ... */ });
});
```
`$L/dsh-judge/index.js:652-665`.

Service *availability* is what gates activation; **row order in the patch list carries no load
semantics** — stated explicitly at `$P/dsh-base/cordis.patch.yml:12-13`
("Row order carries no load semantics (activation is service-availability driven)").

A plugin that *provides* a service subclasses `Service` and calls `super(ctx, '<name>')`; the
service is unregistered automatically when the owning fiber unloads
(`$P/cordis/lib/types/service.d.ts:28-38`). Consumers get it typed via declaration merging:

```ts
declare module '@deepseek-ai/cordis' {
    interface Context { invariants: InvariantRegistry; }
}
```
`$P/dsh-invariants/lib/types/index.d.ts:51-55`.

### 3.4 `apply`

`apply(ctx, config)` is the plugin body. Its return value is not used for control flow; an async
`apply` is awaited (`$P/cordis-plugin-loader/src/config/entry.ts:291-302` awaits
`fiber.await()`). Errors thrown from `apply` are wrapped as
`failed to apply loader entry <id> (<name>): <detail>` (`entry.ts:24-27`).

Disposal: anything registered through `ctx.on(...)`, `ctx.effect(...)`, or a registry disposer is
torn down with the fiber. Registries return the disposer; `dsh-tool-present` relies on fiber
disposal implicitly (`$P/dsh-tool-present/lib/index.js:23`, `:110`), whereas
`dsh-session-projection-cache` stores it explicitly:

```js
this.ctx.effect(() => () => domain.close(), "sessionProjectionCache.domainClose");
```
`$P/dsh-session-projection-cache/lib/index.js:152`.

### 3.5 `reusable`

**`reusable` does not exist in this version.** Grepping the entire `@deepseek-ai` tree for
`reusable` finds it only as English prose inside skill descriptions and README text (e.g.
`$P/dsh-skill-badge/lib/index.js:18`), never as a symbol, field or exported identifier. Neither
`@deepseek-ai/cordis` 4.0.2 nor `@deepseek-ai/cordis-plugin-loader` 1.0.3 declares it.

The nearest real concept is the registry's per-callback runtime: **one callback maps to one
`Runtime` shared by every fiber**, so calling `ctx.plugin(sameFn, cfgA)` and
`ctx.plugin(sameFn, cfgB)` produces two fibers over one runtime record
(`$P/cordis/src/registry.ts:316-336`, `Plugin.Runtime` at `:135-145`). If you were expecting a
`reusable: false` opt-out that forces a fresh runtime per mount, it is not present.

---

## 4. Config declaration and validation

### 4.1 Which schema library

**Plugin `Config` is `@deepseek-ai/schemastery` in every first-party package surveyed.** `zod` is
used *inside* packages for non-plugin schemas (session-projection records, domain record
schemas), never for `Config`.

- `$P/dsh-tool-todo/lib/index.js:1-2` — `import z from "@deepseek-ai/schemastery";` and
  `import { z as z$1 } from "zod";`; `Config` uses `z`, the projection schema uses `z$1`
  (`:20`, `:64-71`).
- `$P/dsh-time-context/lib/index.js:1-2`, `Config` at `:114-117` (schemastery), projection state
  schema at `:103-110` (zod).
- `$P/dsh-skill/lib/index.js:4`, `Config` at `:120` (schemastery only; the package has no zod
  dependency at all — `$P/dsh-skill/package.json:34-37`).
- `$P/dsh-storage-domain/lib/types/index.d.ts:5-6` states the split in words: "Plugin `Config`
  is schemastery; record schemas inside domain specs are zod (see `src/spec.ts` for the split
  rationale)."

The reason both work is that Cordis accepts any **Standard Schema**:

```ts
Config?: StandardSchemaV1<any, T>
```
`$P/cordis/src/registry.ts:103-104`. `@deepseek-ai/schemastery` 3.18.2 implements it and depends
on `@standard-schema/spec` (`$P/schemastery/package.json:36-37`).

### 4.2 How validation happens

```ts
export function resolveConfig(runtime: Plugin.Runtime, config: any) {
  if (!runtime.Config) return config
  // TODO: async validation
  const result = runtime.Config['~standard'].validate(config)
  if ('then' in result) {
    throw new TypeError('Async config validation is not supported')
  }
  if (result.issues) {
    throw new ValidationError(result.issues)
  } else {
    return result.value
  }
}
```
`$P/cordis/src/fiber.ts:42-61`. `ValidationError` renders one line per issue, with the issue path
when present (`$P/cordis/src/fiber.ts:18-36`):

```
invalid config:
  - <message> (at <path>)
```

The validated output is what `apply` receives. Async validation is rejected.

### 4.3 Defaults and required fields

From the schemastery surface (`$P/schemastery/lib/types/index.d.ts`):

- `.default(value)` — "Return the default value instead of throwing when validation fails"
  (`:151`, `:158`). The default appears in normalized output.
- `.required(value?)` — "Mark nullable input as invalid unless a default supplies a fallback"
  (`:147-148`).
- `description(text)` / `comment(text)` — attach docs for the generated catalog and form UIs
  (`:159-162`).
- Schema-level metadata fields: `default`, `required`, `description`, `comment`
  (`:99-113`).

Observed usage in real `Config` declarations:

- **Defaults present** — `z.object({ maxFiles: z.number().default(8) })`
  (`$P/dsh-tool-present/lib/index.js:8`);
  `z.object({ collectCacheMaxEntries: z.number().default(DEFAULT_COLLECT_CACHE_ENTRIES) })`
  (`$P/dsh-skill/lib/index.js:120`);
  `z.object({ defaultMaxGoalRounds: z.number().default(256) })`
  (`$P/dsh-goal/lib/index.js:588`).
- **Required** — `z.object({ allowParallelInProgress: z.boolean().required() })`
  (`$P/dsh-tool-todo/lib/index.js:20`). Because a boolean is not nullable and has no default, this
  is the idiomatic way to say "the deployment must state this explicitly".
- **Required, no default at all** — `z.object({ timeZone: z.string(), refreshIntervalMs: z.number() })`
  (`$P/dsh-time-context/lib/index.js:114-117`). The plugin then re-validates the *semantics* in
  `apply`, because schemastery cannot express them:

```js
/** Reject refresh intervals that cannot represent an exact elapsed-millisecond threshold. */
function validateRefreshInterval(refreshIntervalMs) {
  if (refreshIntervalMs !== void 0 && (!Number.isSafeInteger(refreshIntervalMs) || refreshIntervalMs < 0))
    throw new TypeError(`time-context: refreshIntervalMs must be a non-negative safe integer, got ${String(refreshIntervalMs)}`);
}
```
`$P/dsh-time-context/lib/index.js:150-153`, called at `:163`.

- **Empty schema for a no-config service** — `z.object({})` semantics via
  `z.object({ backend: z.string(), routes: ... })`
  (`$P/dsh-storage-domain/lib/types/index.d.ts:40-46`), or no `Config` at all.

Real third-party `Config` (a hand-written plugin, the closest thing to a template):

```js
export const Config = z.object({
	enabled: z.boolean().default(true),
	inheritAgentModel: z.boolean().default(true),
	provider: z.string(),
	model: z.string(),
	reasoningEffort: z.string(),
	timeoutMs: z.number().default(REVIEW_MS_DEFAULT),
	graceMs: z.number().default(GRACE_MS_DEFAULT),
	maxSteps: z.number().default(MAX_STEPS_DEFAULT),
	maxFileBytes: z.number().default(80000),
	maxClaimChars: z.number().default(12000),
	infiniteReview: z.boolean().default(true),
	maxReviews: z.number().default(3),
	systemPrompt: z.string().default(""),
	userPrompt: z.string().default("")
});
```
`$L/dsh-judge/index.js:83-96`.

### 4.4 The "generated configuration catalog" and JSDoc

The READMEs assert the relationship but do not name a generator. The strongest statements:

- "The generated [configuration catalog](../../../docs/config-catalog.md#deepseek-aidsh-time-context)
  is the exhaustive source for every accepted field and its JSDoc."
  `$P/dsh-time-context/README.md:49` (same sentence at `$P/dsh-storage-json/README.md:52`,
  `$P/dsh-invariants/README.md:52`, `$P/dsh-storage-domain/README.md:69`).
- "- [Generated configuration catalog](../../../docs/config-catalog.md#deepseek-aidsh-tool-todo) —
  every accepted config field and its source declaration." `$P/dsh-tool-todo/README.md:116`.

So: **the catalog is generated from the `Config` schema's field-level JSDoc**, and the README is
expected to link to `<catalog>#deepseek-aidsh-<package-name-without-scope>`. The catalog file
itself is **not shipped** (`$R/docs/config-catalog.md` does not exist), and no shipped text names
the generator. Adding field-level JSDoc to every `Config` property is therefore the only
actionable part of this convention for a third-party author.

### 4.5 Complete minimal example

```ts
// src/index.ts — a plugin with a validated, documented Config.
import z from '@deepseek-ai/schemastery'
import type { Context } from '@deepseek-ai/cordis'

/** Cordis plugin name used by loader diagnostics. */
export const name = 'greeting'

/** Services this plugin needs before it may activate. */
export const inject = ['tools']

/** Plugin configuration. */
export interface Config {
  /** Salutation placed before the name. Defaults to `Hello`. */
  salutation?: string
  /** Whether to append an exclamation mark. Defaults to `true`. */
  exclaim?: boolean
}

/** Schemastery validation for {@link Config}. */
export const Config = z.object({
  salutation: z.string().default('Hello').description('Salutation placed before the name.'),
  exclaim: z.boolean().default(true).description('Whether to append an exclamation mark.'),
})

/** Register the plugin's effects for the lifetime of `ctx`. */
export function apply(ctx: Context, config: Config): void {
  const greet = (who: string) =>
    `${config.salutation ?? 'Hello'}, ${who}${config.exclaim === false ? '' : '!'}`
  ctx.logger?.('greeting').info(greet('world'))
}
```

```json
// package.json
{
  "name": "@acme/dsh-greeting",
  "version": "1.0.0",
  "type": "module",
  "main": "lib/index.js",
  "types": "lib/types/index.d.ts",
  "exports": {
    ".": { "types": "./lib/types/index.d.ts", "default": "./lib/index.js" },
    "./package.json": "./package.json"
  },
  "files": ["lib/index.js", "lib/types/**/*.d.ts"],
  "license": "MIT",
  "dependencies": { "@deepseek-ai/schemastery": "^3.18.2" },
  "peerDependencies": { "@deepseek-ai/cordis": "^4.0.2", "@deepseek-ai/dsh-tools": "^0.1.5-rc.2" },
  "dsh": { "bundle": { "patch": "./cordis.patch.yml" } }
}
```

```yaml
# cordis.patch.yml — what makes `dsh plugin add` activate the package.
- insert:
    - id: greeting
      name: '@acme/dsh-greeting'
      config:
        salutation: 'Olá'
        exclaim: false
```

Mount row shape verified against `$P/dsh-headless/cordis.patch.yml:18-31` and
`$L/dsh-judge/cordis.patch.yml:1-14`. Note the row's `config` is what the schema validates; a
missing required field fails the boot with `invalid config: …`
(`$P/cordis/src/fiber.ts:27-35`).

---

## 5. Tool registration

### 5.1 `defineTool`

```ts
export declare function defineTool<const S extends ParameterSchemaSpec, const O extends ValueSchemaSpec>(
  options: DefineToolOptions<S, O>,
): ToolDefinition;
```
`$P/dsh-tools/lib/types/schema.d.ts:239`.

`DefineToolOptions` (`$P/dsh-tools/lib/types/schema.d.ts:178-231`) — every field:

| field | required | notes |
|---|---|---|
| `name` | yes | "Tool name (must be unique)" (`:180`) |
| `description` | yes | "Human-readable description sent to the model" (`:182`) |
| `parameters` | yes | `ParameterSchemaSpec` — a property map compiled to an implicit **open** object root (`:183-184`, `:77-84`) |
| `output.schema` | yes | canonical output schema (`:186-188`) |
| `output.render` | yes | pure `(args, value) => ContentBlock[]` (`:190`) |
| `output.presentationMeta` | no | pure `(args, value) => JsonValue`, top-level calls only (`:191-192`) |
| `timeoutMs` | no | positive cooperative budget (`:194-195`) |
| `isConcurrencySafe` | no | pure classifier for sibling overlap (`:196-201`) |
| `execute` | yes | `(args, exec: ToolRunContext) => Promise<InferValue<O>>` (`:202-208`) |
| `finalizeContent` | no | last-mile content transform; args stay `unknown` (`:209-217`) |
| `presentCall` | no | pending-state render intent (`:218-223`) |
| `presentResult` | no | completed-state render intent (`:224-230`) |

What `defineTool` *does* at runtime (`$P/dsh-tools/lib/index.js:837-884`):

- rejects `timeoutMs` unless it is a positive finite number (`:845`);
- compiles the author schema DSL into raw JSON Schema via `parameterSchemaSpecToJsonSchema`
  (`:846`) and `valueSchemaSpecToJsonSchema` (`:847`);
- wraps `execute` so **arguments are validated on every call** and violations throw
  `ToolArgsError` with code `INVALID_ARGS` (`:863-867`; `ToolArgsError` at `:812-821`);
- wraps the presenters so they validate softly and return `undefined` for obsolete logged args
  (`:870-881`);
- wraps `isConcurrencySafe` so invalid args classify as exclusive (`:878-881`).

### 5.2 The `ToolDefinition` contract

```ts
export interface ToolDefinition extends ToolSchema {
    /** Mandatory canonical output declaration. */
    readonly output: ToolOutputDefinition;
    execute(args: unknown, exec: ToolRunContext): Promise<unknown>;
    finalizeContent?(exec: Readonly<ToolExecution>, result: Readonly<ToolExecutionResult>): ContentBlock[] | undefined;
    timeoutMs?: number;
    isConcurrencySafe?(args: unknown): boolean;
    presentCall?(args: unknown): ToolCallView | undefined;
    presentResult?(args: unknown, result: ToolResult): ToolResultView | undefined;
}

export interface ToolOutputDefinition {
    /** Raw supported JSON Schema enforced against every successful canonical value. */
    readonly schema: JsonSchemaNode;
    /** Pure projection from validated arguments and value to Native/model content. */
    render(args: unknown, value: JsonValue): ContentBlock[];
    /** Pure replayable presentation projection, computed only for top-level calls. */
    presentationMeta?(args: unknown, value: JsonValue): JsonValue;
}
```
`$P/dsh-tools/lib/types/index.d.ts:96-172`.

`ToolSchema` itself is minimal and comes from `dsh-llm` (declared there because it is also part of
`GenerateOptions`): `{ name: string; description: string; parameters: Record<string, unknown> }`
(`$P/dsh-llm/lib/types/types.d.ts:390-402`).

**`output.schema` + `output.render` are mandatory** (`:97-104`, `:106-108`). There is no
"free-form content" tool: a tool's durable value must be lossless JSON and is schema-checked.
`render` returns `ContentBlock[]` (`ContentBlock` union at `$P/dsh-llm/lib/types/types.d.ts:102`,
`TextBlock` at `:39`).

**On "read-only"/"kind" metadata:** there is **no** `readOnly`, `readonlyHint`, `kind` or
`mutating` field on `ToolDefinition`. The only scheduling metadata is `isConcurrencySafe`, whose
doc says "Only `true` opts in; omission, exceptions, non-`true` returns, and invalid `defineTool`
arguments are exclusive" (`$P/dsh-tools/lib/types/index.d.ts:140-153`). `kind` exists only as
`ToolCallKind = 'read' | 'edit' | 'delete' | 'move' | 'search' | 'execute' | 'fetch' | 'other'`
inside a *view* (`$P/dsh-tools/lib/types/presentation.d.ts:13`), i.e. presentation only, never
policy. Read-only-ness is enforced elsewhere (sandbox, guards), not declared on the tool.

`timeoutMs` is likewise cooperative and never model-visible: "Enforced by
`@deepseek-ai/dsh-tool-call-timeout-policy` (a `tools/execute` wrapper); it is NEVER sent to the
model — `schemas()` whitelists only name/description/parameters"
(`$P/dsh-tools/lib/types/index.d.ts:132-139`).

### 5.3 `ToolRunContext`

```ts
export interface ToolRunContext extends ToolExecution {
    deferContext(context: UserMessage): void;
    concludeTurn(): void;
}

export interface ToolExecution extends ToolExecutionInput {
    readonly rootCallId: ToolCallId;
    readonly token: ToolExecutionToken;
}

export interface ToolExecutionInput {
    readonly callId: ToolCallId;
    readonly rootCallId?: ToolCallId;
    readonly name: string;
    readonly arguments: unknown;
    readonly agent?: Agent;
    readonly parent?: ToolExecutionToken;
    readonly signal: AbortSignal;
}
```
`$P/dsh-tools/lib/types/index.d.ts:284-301`, `:261-266`, `:197-221`.

Practical notes read off the docs: async work **must observe or forward `exec.signal`** and settle
only after its owned work reaches quiescence (`:109-119`); `exec.agent` is optional, so a tool
that needs a session must check it.

### 5.4 Registration and the disposer

```ts
/**
 * Register globally or in the calling agent scope. Scoped tools shadow
 * globals; duplicates within one layer and the reserved `run_code` name fail.
 * @returns the exact disposer that unregisters the tool.
 */
register(definition: ToolDefinition): () => void;
```
`$P/dsh-tools/lib/types/index.d.ts:595-601`.

`ctx.tools` is the service name — `ToolRuntime extends Service` calls `super(ctx, "tools")`
(`$P/dsh-tools/lib/index.js:2606`), and every tool plugin declares `inject: ["tools"]`.
`ctx.tools.register(...)` is called synchronously during `apply`; the disposer is rarely stored
because fiber disposal unregisters. `dsh-tool-present` ignores it
(`$P/dsh-tool-present/lib/index.js:23`); `dsh-tool-todo` likewise
(`$P/dsh-tool-todo/lib/index.js:95`).

Related registry surface, all returning disposers:
`restrict(filter): () => void` (`$P/dsh-tools/lib/types/index.d.ts:602-609`),
`guard(guard): () => void` (`:610-620`).

`ToolRuntime`'s own plugin `Config` is `{ mode?: 'native' | 'ptc' | 'both'; maxParallelSubCalls?: number }`
(`$P/dsh-tools/lib/types/index.d.ts:448-471`) — it is mounted by the `tools` row
(`$P/dsh-base/cordis.patch.yml:460-461`), not by your plugin.

### 5.5 A complete, minimal tool definition

Reconstructed from `$P/dsh-tool-present/lib/index.js` (read in full, 123 lines), whose Config,
schema, render and execute are quoted above at `:8`, `:23-75`, `:76-108`. Written as the
TypeScript a third-party author would write:

```ts
// src/index.ts
import z from '@deepseek-ai/schemastery'
import { defineTool } from '@deepseek-ai/dsh-tools'
import type { Context } from '@deepseek-ai/cordis'

/** Stable Loader identity. */
export const name = 'tool-wordcount'
/** Validated limits. */
export const Config = z.object({ maxTexts: z.number().default(8) })
/** Services used by the tool. */
export const inject = ['tools']

export function apply(ctx: Context, config: { maxTexts: number }): void {
  if (!Number.isSafeInteger(config.maxTexts) || config.maxTexts < 1) {
    throw new Error('wordcount requires a positive integer maxTexts')
  }
  ctx.tools.register(defineTool({
    name: 'wordcount',
    description: 'Count the words in each of up to maxTexts text strings.',
    parameters: {
      texts: {
        type: 'array',
        required: true,
        description: 'The texts to count; at least one.',
        items: { type: 'string' },
      },
    },
    output: {
      schema: {
        type: 'object',
        additionalProperties: false,
        properties: {
          total: { type: 'integer', required: true },
          counts: {
            type: 'array',
            required: true,
            items: { type: 'integer' },
          },
        },
      },
      render: (_args, value) => [
        { type: 'text', text: `Counted ${value.total} words across ${value.counts.length} texts.` },
      ],
      presentationMeta: (_args, value) => ({ total: value.total }),
    },
    presentCall: (args) => ({
      card: 'generic',
      title: 'Count words',
      kind: 'other',
      rawInput: args.texts,
    }),
    async execute(args, exec) {
      if (args.texts.length === 0 || args.texts.length > config.maxTexts) {
        throw new Error(`wordcount accepts 1 to ${config.maxTexts} texts`)
      }
      const counts = args.texts.map((text) => text.trim().split(/\s+/).filter(Boolean).length)
      exec.signal.throwIfAborted()
      return { total: counts.reduce((a, b) => a + b, 0), counts }
    },
  }))
}
```

Every construct above is copied from a real package and keeps its shape:
`parameters: { texts: { type: 'array', required: true, items: { type: 'string' } } }` mirrors
`$P/dsh-tool-present/lib/index.js:26-44`; `output.schema` + `render` mirror `:45-75`;
`presentCall: (args) => ({ card: 'generic', title, kind, rawInput })` mirrors
`$P/dsh-tool-todo/lib/index.js` (tail: `presentCall: (args) => ({ card: "generic", title: "Update
todo list", kind: "other", rawInput: args.todos })`); `exec.signal.throwIfAborted()` mirrors
`$P/dsh-tool-present/lib/index.js:98`; the in-`apply` semantic re-validation mirrors `:21`.

Note `ObjectValueSchemaSpec.additionalProperties` is **mandatory** — "Openness is mandatory so a
nested or output object never acquires an accidental JSON Schema default"
(`$P/dsh-tools/lib/types/schema.d.ts:54-62`).

---

## 6. Invariant companion

### 6.1 What it is for

From the service's own module doc: "Configurable registry for package-owned runtime invariant
contributions. Every workspace package registers checks from a `./invariant` companion; ordinary
package entrypoints stay independent of diagnostics."
`$P/dsh-invariants/lib/types/index.d.ts:1-7`.

An invariant is a **validation hook over durable state**, run against history that already exists
(sessions loaded from disk) and against newly appended events, so a package's durable contract
cannot be violated silently. It is diagnostic infrastructure, not a runtime guard.

### 6.2 The `ctx.invariants` API

```ts
export type InvariantFailure = (message: string) => never;

export interface InvariantInstaller {
    (ctx: Context, fail: InvariantFailure): void | Promise<void>;
    /** Services the child installer fiber may access. */
    readonly inject?: Inject;
}

export declare class InvariantRegistry extends Service {
    static Config: Schema<Config>;
    register(packageName: string, installer: InvariantInstaller): () => void;
}

export interface Config {
    readonly enabled?: boolean;                 // defaults to true
    readonly package_allowlist?: string[];      // regex sources
    readonly package_blocklist?: string[];      // regex sources
}
```
`$P/dsh-invariants/lib/types/index.d.ts:25-37`, `:56-81`, `:11-19`.

`register` reserves the package name even when filtering disables the checks; enabled installers
run in a **child fiber**, and a failure disposes that fiber and releases the reservation
(`$P/dsh-invariants/lib/types/index.d.ts:72-80`). Failures throw `InvariantError` with
`code: "INVARIANT"` and the owning `packageName` (`:38-50`).

### 6.3 The companion module

Its own plugin, with `inject: ["invariants"]` and a `name` distinct from the host package's.
`dsh-time-context`'s companion (`$P/dsh-time-context/lib/invariant.js`):

```js
/** Package-owned durable clock-context invariants. @module @deepseek-ai/dsh-time-context/invariant */
const PACKAGE_NAME = "@deepseek-ai/dsh-time-context";
const SOURCE_NAME = "time-context";
// ...
/** Cordis companion plugin name. */
const name = "time-context-invariant";
/** Service required before the companion can reserve package ownership. */
const inject = ["invariants"];
// ...
/** Install validation for loaded and newly appended context readings. */
const install = Object.assign((ctx, fail) => {
	for (const session of ctx.sessions.list()) validateSession(session, fail);
	ctx.on("session/created", (session) => {
		validateSession(session, fail);
	}, { global: true });
	ctx.on("internal/dispatch", (_mode, eventName, args) => {
		if (eventName !== "session/event") return;
		const [session, event] = args;
		if (event.type !== "user/message" || event.data.source.kind !== "plugin" || event.data.source.plugin !== SOURCE_NAME) return;
		validateReading(session.snapshotEvents(), event, fail);
	}, { global: true });
}, { inject: ["sessions"] });

/**
 * Register the time-context invariant companion.
 * @param ctx - Cordis context carrying the invariant service.
 * @returns the installed registration's disposer after setup succeeds.
 */
const apply = (ctx) => Promise.resolve(ctx.invariants.register(PACKAGE_NAME, install));

export { apply, inject, name };
```
`$P/dsh-time-context/lib/invariant.js:91-98`, `:189-207`.

`dsh-tool-todo`'s companion is structurally identical and slightly smaller
(`$P/dsh-tool-todo/lib/invariant.js:1-88`), with the same two named exports plus
`PACKAGE_NAME`/`inject`/`name`:
`export declare const apply: (ctx: Context) => Promise<() => void>` —
`$P/dsh-tool-todo/lib/types/invariant.d.ts:12`.

Two details worth copying:

- `install` gets an **extra** `inject` of its own (`{ inject: ["sessions"] }`,
  `$P/dsh-time-context/lib/invariant.js:201`) — a per-installer inject map, resolved by the child
  fiber.
- The companion validates **history first, then new events**, using the same function. That is
  what makes it useful: replay of an old log is checked against today's contract.

### 6.4 Minimal example

```ts
// src/invariant.ts — companion entry point, exported as `<pkg>/invariant`.
import type { Context } from '@deepseek-ai/cordis'
import type { InvariantFailure } from '@deepseek-ai/dsh-invariants'

/** Full npm package name that owns these checks. */
const PACKAGE_NAME = '@acme/dsh-greeting'
/** Cordis companion plugin name. */
export const name = 'greeting-invariant'
/** Service required before the companion can reserve package ownership. */
export const inject = ['invariants']

/** Validate every greeting event already in one session, then keep watching. */
const install = Object.assign((ctx: Context, fail: InvariantFailure) => {
  const check = (session: { snapshotEvents(): Array<{ type: string; data: any }> }) => {
    for (const event of session.snapshotEvents()) {
      if (event.type !== 'greeting/said') continue
      if (typeof event.data.who !== 'string' || event.data.who.length === 0) {
        fail('greeting/said must carry a non-empty who')
      }
    }
  }
  for (const session of ctx.sessions.list()) check(session)
  ctx.on('session/created', (session) => check(session), { global: true })
}, { inject: ['sessions'] })

export const apply = (ctx: Context) => Promise.resolve(ctx.invariants.register(PACKAGE_NAME, install))
```

---

## 7. Persistence

### 7.1 `ctx.storage` — a registry of backends, not a KV store

"The hub itself performs no IO — backends own media, data forms (the domain layer first) own
semantics." `$P/dsh-storage/lib/types/index.d.ts:2-5`.

```ts
export declare class Storage extends Service {
    /** Named backend table; multiple backends stay mounted side by side. */
    readonly backend: BackendRegistry;
    mount<K extends keyof StorageForms>(form: K, facility: StorageForms[K]): () => void;
    form<K extends keyof StorageForms>(form: K): StorageForms[K];
    get domain(): /* StorageForms['domain'] */;
}

export interface StorageForms {}   // form owners extend this by declaration merging

export declare class BackendRegistry {
    register(name: string, backend: StorageBackend): () => void;
    get(name: string): StorageBackend;
    names(): string[];
}
```
`$P/dsh-storage/lib/types/index.d.ts:28-63`; `BackendRegistry` at
`$P/dsh-storage/lib/types/registry.d.ts:141-163`.

```ts
export interface StorageBackend {
    readonly kv?: KvFacet;
    close(): Promise<void>;
}
export interface KvFacet {
    open(descriptor: KvUnitDescriptor): Promise<KvUnit>;
}
export interface KvUnitDescriptor {
    readonly name: string;              // must match UNIT_NAME_RE
    readonly version: number;
    readonly tables: readonly string[];
    readonly hasGlobal: boolean;
    readonly layout?: 'single' | 'per-record';
    readonly compatibleVersions?: readonly number[];
}
export interface KvUnit {
    loadAll(): Promise<{ tables: Record<string, Record<string, unknown>>; global: unknown }>;
    putRecord(table: string, key: string, value: unknown): Promise<void>;
    deleteRecord(table: string, key: string): Promise<void>;
    backupRecord?(table: string, key: string): Promise<string>;
    setGlobal(value: unknown): Promise<void>;
    close(): Promise<void>;
}
```
`$P/dsh-storage/lib/types/backend.d.ts:15-24`, `:26-39`, `:41-69`, `:79-130`.

Operational rules stated in the contract text that a backend author must respect:
`open()` rejects a mismatched version stamp with `version-mismatch` and an unparseable medium with
`malformed-medium`; opening the same unit twice without closing is a caller bug and rejects
(`:28-38`). A unit does **not** serialize concurrent writes — "write ordering is the caller's
responsibility (the domain layer runs one write chain per unit)" (`:70-78`).

### 7.2 The capability a plugin actually wants: `ctx.storage.domain`

`@deepseek-ai/dsh-storage-domain` is "the single implementation of the domain layer — consumers
depend on this package and never touch backends directly"
(`$P/dsh-storage-domain/lib/types/index.d.ts:2-4`). It mounts the `domain` form and provides
`ctx.storageDomain`:

```ts
declare module '@deepseek-ai/dsh-storage' {
    interface StorageForms { domain: DomainFacility; }
}
declare module '@deepseek-ai/cordis' {
    interface Context { storageDomain: DomainFacility; }
}

export declare class DomainFacility {
    open<S extends DomainSpec>(spec: S): Promise<Domain<S>>;
    get(name: string): DomainImpl | undefined;
    closeAll(): Promise<void>;
}
```
`$P/dsh-storage-domain/lib/types/index.d.ts:20-29`, `:52-99`.

Its `Config` is `{ backend: string; routes?: Record<string, string> }` — "`backend` is the default
route and `routes` overrides it per domain name. A route naming an unregistered backend fails
loud at `open` with `backend-not-found`" (`:34-46`).

A domain is declared with `defineDomain` and its tables with `domainTable(schema)`:
`$P/dsh-storage-domain/lib/types/spec.d.ts:80`, `:93`. `defineDomain` validates at module load —
"a domain or table name outside `UNIT_NAME_RE`, a version that is not a non-negative integer, or a
global schema that accepts `null` all throw" (`:81-92`).

Table handle (`$P/dsh-storage-domain/lib/types/domain.d.ts:36-78`): `get(key)`, `entries()`,
`keys()`, `size`, `put(key,value)`, `delete(key)`, `update(key, fn)` — with the important
guarantee that `update` is an atomic read-modify-write on the domain's write chain
("`fn` sees the value current at its queue slot, so concurrent updates never interleave", `:70-77`),
and that reads are synchronous from memory while writes await durability *first*, then mutate
memory, then emit `domain/changed` (`domain.d.ts:1-8`).

**Real consumer pattern** (`dsh-session-projection-cache`) — this is the template:

```js
const projectionCacheDomainSpec = defineDomain({
	name: "session_projcache",
	version: 7,
	compatibleVersions: [3, 4, 5, 6],
	invalidRecords: "backup-and-skip",
	layout: "per-record",
	tables: { sessions: domainTable(checkpointRecord) }
});
```
`$P/dsh-session-projection-cache/lib/index.js:89-101`; opened and closed as

```js
const domain = await this.ctx.storageDomain.open(projectionCacheDomainSpec);
// ...
this.ctx.effect(() => () => domain.close(), "sessionProjectionCache.domainClose");
```
`$P/dsh-session-projection-cache/lib/index.js:151-152`, with `storageDomain` in the plugin's
inject list at `:138`.

Note the ownership rule: `DomainFacility.open` does **not** tie the domain to a fiber — "the
CALLER owns the returned handle and closes it via `Domain.close()` (typically as its own
`ctx.effect` disposer)" (`$P/dsh-storage-domain/lib/types/index.d.ts:75-83`).

### 7.3 `@deepseek-ai/dsh-storage-json`

"JSON storage backend: one human-readable document per unit under a configured root — a
whole-unit file (`single` layout) or one document per record (`per-record` layout), published by
atomic rewrite. Registers as backend `json` on the storage hub."
`$P/dsh-storage-json/lib/types/index.d.ts:2-6`.

```ts
export interface Config {
    /** Directory holding one `<unit>.json` file (or `<unit>/` tree) per unit. */
    root: string;
}
```
`$P/dsh-storage-json/lib/types/index.d.ts:15-24` — with an explicit rationale for having no
default: "`root` has NO default on purpose: a `process.cwd()` fallback would scatter unit files
wherever the process happens to start; assemblies state the location explicitly." (`:17-20`).

### 7.4 Where data lands on disk under `$DSH_HOME`

`$DSH_HOME` resolution: precedence "an explicit configured path, `$DSH_HOME`, then `~/.dsh`"; a
blank `$DSH_HOME` is treated as unset (`$P/dsh-home-paths/lib/types/index.d.ts:37-48`).

| path | owner |
|---|---|
| `$DSH_HOME/profiles/<name>/` | profile dir: `package.json`, `cordis.patch.yml`, `cordis.yml`, `pnpm-workspace.yaml`, `pnpm-lock.yaml`, `node_modules/`, `.dsh-module-fallback/` (`$P/dsh-app-boot/lib/index.js:379-398`, `:316`; verified live) |
| `$DSH_HOME/profiles/node_modules/` | installation dependency-closure mirror (symlinks) written by `healProfilesModuleFallback` (`$P/dsh-app-boot/lib/types/profile.d.ts:103-115`; verified live: 240 `@deepseek-ai/*` symlinks) |
| `$DSH_HOME/storages/` | the JSON storage backend root, set by the base bundle patch |
| `$DSH_HOME/cordis.patch.yml` | home-level user patch layer, applied over every profile (`$DSH/lib/profile-boot-Dk-7KqJc.js:110-118`) |
| `$DSH_HOME/settings.yaml`, `.credentials.yaml`, `sessions/`, `attachments/`, `.anonymous-user-id` | other subsystems (verified live; not covered here) |

The storages path is fixed by this row:

```yaml
    - id: storage-json
      name: '@deepseek-ai/dsh-storage-json'
      config:
        root: !!js dshHomePath('storages')
```
`$P/dsh-base/cordis.patch.yml:148-152`. `dshHomePath` is provided as a context value by the boot
glue (`$P/dsh-app-boot/lib/index.js:1530`) and joined onto the resolved home
(`$P/dsh-home-paths/lib/types/index.d.ts:49-54`). Unit layout on disk is
`<root>/<unit>.json` (single) or `<root>/<unit>/<table>/<key>.json` plus `global.json`
(per-record) — `$P/dsh-storage-json/lib/index.js:55-63`.

`dsh-base` mounts the whole stack already (`$P/dsh-base/cordis.patch.yml:145-156`):

```yaml
    - id: storage
      name: '@deepseek-ai/dsh-storage'

    - id: storage-json
      name: '@deepseek-ai/dsh-storage-json'
      config:
        root: !!js dshHomePath('storages')

    - id: storage-domain
      name: '@deepseek-ai/dsh-storage-domain'
      config:
        backend: json
```

So a third-party plugin that runs under a `dsh-base`-backed profile (every shipped template
except `sdk-minimal`, per `$P/dsh-app-boot/lib/index.js:328-349`) needs only
`inject: ["storageDomain"]` and `ctx.storageDomain.open(spec)` — no config and no row of its own.

### 7.5 `@deepseek-ai/dsh-atomic-write`

"Do not use it unless you need it" is the honest summary. It is **not** used by
`dsh-storage-json`: that backend carries its own inlined `writeAtomic` + `fsyncDirectory`
(`$P/dsh-storage-json/lib/index.js:6-53`) rather than depending on the package —
`@deepseek-ai/dsh-atomic-write` is absent from `$P/dsh-storage-json/package.json`.

Its API (`$P/dsh-atomic-write/lib/types/index.d.ts:12-74`):

```ts
export declare function writeFileAtomic(filename: string, content: string, options: WriteFileAtomicOptions): Promise<void>;
export declare function withFileLock<T>(filename: string, operation: () => Promise<T>, options?: FileLockOptions): Promise<T>;
export interface WriteFileAtomicOptions { mode: number; dirMode?: number; }
export interface FileLockOptions { waitMs?: number; }
```

Guarantees: exclusive-create (`wx`) random-suffix sibling + `rename` commit, so readers see old or
new complete content; the fresh inode carries `options.mode`; symlinked targets are replaced not
followed; Windows retries `EACCES`/`EBUSY`/`EPERM` for a bounded interval; **crash durability
(fsync) is explicitly out of scope** (`:29-45`). `withFileLock` serializes cross-process writers
through a `wx`-created `<file>.lock` sibling, with exponential backoff and a timed-out error;
"the contender never removes an existing lock because file age cannot prove that its owner
stopped; orphan recovery is an operator action" (`:58-74`).

Actual first-party consumers, for reference: `dsh-agent-presets`, `dsh-app-boot`,
`dsh-credentials-local`, `dsh-llm-deepseek`, `dsh-settings-file`.

### 7.6 `@deepseek-ai/dsh-storage-domain`'s own companion

It ships a `./invariant` entry point like any other package that owns durable state
(`$P/dsh-storage-domain/package.json:23-26`, `files` at `:28-32`), reinforcing the §6 convention.

---

## 8. Testing a plugin

### 8.1 The short answer

**Neither `@deepseek-ai/dsh-loader-smoke` nor `@deepseek-ai/dsh-agent-loop-testkit` is installed
in this distribution, and neither appears in any package's `dependencies` or
`peerDependencies`.** Verified: neither directory exists under `$P/`; a JSON scan of all 240
manifests finds both names only under `devDependencies`, across 40 packages.

- `@deepseek-ai/dsh-agent-loop-testkit` — devDependency of 39 packages, e.g.
  `$P/dsh-tool-todo/package.json:56`, `$P/dsh-tool-present/package.json:55`,
  `$P/dsh-time-context/package.json:50`, `$P/dsh-goal/package.json:73`.
- `@deepseek-ai/dsh-loader-smoke` — devDependency of 6 packages:
  `$P/dsh-goal/package.json:59`, `$P/dsh-time-context/package.json:53`,
  `$P/dsh-subprocess-local/package.json`, `$P/dsh-pwsh`, `$P/dsh-session-telemetry-otel`,
  `$P/dsh-tool-pwsh`.
- The CLI's own manifest is the exception that proves the rule: both appear under
  `devDependencies` of the CLI package (`$R/package.json:112`, `:131`) — so they are real
  published packages, just not part of a production install.

**Because their manifests are not present, their `files` and `exports` maps cannot be inspected
here.** What *is* verifiable is that they are declared as `devDependencies` everywhere, never as
runtime or peer dependencies, which means a third-party package cannot assume they are installed
alongside DSH. **`[inferred]`** Treat them as usable only if you add them to your own
`devDependencies` and a registry that carries the `0.1.5-rc.*` range carries them too.

### 8.2 `@deepseek-ai/dsh-tools`' `defineContentToolFixture` — shipped, and importable

The task brief points at `@deepseek-ai/dsh-tools/lib/types/testing`. The reality is more
convenient: the symbol is exported from the package's **main** entry, so no deep import is
needed.

```ts
/**
 * Define a test fixture that deliberately uses its content blocks as the
 * canonical JSON value. Product tools must declare domain-owned DTOs instead.
 * @param options - ordinary fixture fields plus a content-producing body.
 * @returns a registry-ready tool with an explicit JSON-array output contract.
 * @internal
 */
export declare function defineContentToolFixture<const S extends ParameterSchemaSpec>(
  options: ContentToolFixtureOptions<S>,
): ToolDefinition;
```
`$P/dsh-tools/lib/types/testing.d.ts:16-23`.

- Re-exported from the main types entry: `export { defineContentToolFixture, type ContentToolFixtureOptions } from './testing.ts';`
  — `$P/dsh-tools/lib/types/index.d.ts:22`.
- Re-exported from the main runtime entry: the `export { …, defineContentToolFixture, … }` list at
  `$P/dsh-tools/lib/index.js:3588`.
- Implementation (`$P/dsh-tools/lib/index.js:2380-2392`): it forces
  `output = { schema: { type: 'array', items: { type: 'json' } }, render: (_args, value) => value }`
  and delegates to `defineTool`. So the fixture's *canonical value is its content blocks*.
- **`@internal`**: the JSDoc says it is for repository tests, and "Product tools must declare
  domain-owned DTOs instead" (`testing.d.ts:16-20`). The module banner is
  "Canonical tool-definition fixtures for repository tests"
  (`$P/dsh-tools/lib/index.js:2368`).
- There is **no `./testing` subpath** in the `exports` map
  (`$P/dsh-tools/package.json:16-35` lists only `.`, `./invariant`, `./types`, `./presentation`,
  `./src/*`, `./package.json`), so the deep path
  `@deepseek-ai/dsh-tools/lib/types/testing.js` is **not** importable — use the main entry.
- It ships only because `files` includes `lib/types/**/*.js`
  (`$P/dsh-tools/package.json:36-41`).

### 8.3 What a third-party author can actually test with

Verified as present and importable in this distribution:

- `defineContentToolFixture` and `defineTool` from `@deepseek-ai/dsh-tools`
  (`$P/dsh-tools/lib/index.js:3588`).
- The full `ToolRuntime` service: `ToolRuntime` / default export (`$P/dsh-tools/lib/index.js:3588`),
  so a test can mount the registry as a plugin and register a definition.
- The schema compilers `parameterSchemaSpecToJsonSchema`, `valueSchemaSpecToJsonSchema`,
  `validateArgs`, `assertSupportedJsonSchema` (`$P/dsh-tools/lib/index.js:3588`) — enough to unit-test
  a tool's schema without a context.
- The Cordis `Context`, `Service`, `Fiber` and `@deepseek-ai/cordis-plugin-loader` in full source
  form (`$P/cordis/src/`, `$P/cordis-plugin-loader/src/`), so a test can boot a real loader tree.
- `@deepseek-ai/dsh-app-boot`'s `boot`, `loadProfile`, `composeEntries`, `initProfile`
  (`$P/dsh-app-boot/lib/types/index.d.ts:19`) — a programmatic profile boot, which is the closest
  published equivalent of a "loader smoke" test.
- `@deepseek-ai/dsh-invariants` `InvariantRegistry` (`$P/dsh-invariants/lib/types/index.d.ts:57`)
  for testing a companion.
- `@deepseek-ai/dsh-storage` + `dsh-storage-domain` + `dsh-storage-json` (`$P/dsh-storage/lib/types/index.d.ts:39`,
  `$P/dsh-storage-domain/lib/types/index.d.ts:52`, `$P/dsh-storage-json/lib/types/index.d.ts:28`) —
  a storage domain can be opened against a temp-dir JSON root in a test.

Nothing else test-shaped ships. In particular, the 240 packages ship **no test files at all** —
`files` allow-lists exclude them, and no `tests/` directory exists anywhere under `$P/`.

---

## 9. Build and TypeScript setup

### 9.1 What the tarballs show

**No build configuration ships.** Glob-scoped to `$P`:

| pattern | result |
|---|---|
| `**/tsconfig*.json` | none |
| `**/.swcrc` | none |
| `**/tsup.config.*` | none |
| `**/rollup.config.*` | none |
| `**/vite.config.*` | none |
| `**/webpack.config.*`, `**/esbuild.config.*`, `**/.babelrc*`, `**/babel.config.*` | none |
| `**/*.config.*` (catch-all) | none |

Widening to the whole install root finds tsconfigs only in third-party packages
(`$R/node_modules/hasown/tsconfig.json`, `$R/node_modules/openai/src/tsconfig.json`, …).

### 9.2 `scripts`: absent from essentially every plugin package

**None of the 12 packages examined** — `dsh-tool-todo`, `dsh-time-context`, `dsh-goal`,
`dsh-skill`, `dsh-tool-present`, `dsh-tools`, `dsh-invariants`, `dsh-storage`,
`dsh-storage-domain`, `dsh-app-boot`, `cordis`, `cordis-plugin-loader` — **has a `scripts` key
at all.** The CLI package has none either (`$R/package.json` has keys `name`, `description`,
`version`, `publishConfig`, `repository`, `type`, `bin`, `files`, `dsh`, `license`,
`dependencies`, `devDependencies`).

Across all 240 first-party manifests, only **58** declare `scripts`, and the breakdown is narrow:

- **54 packages** carry exactly `"bundle": "tsdown", "watch": "tsdown --watch"` (e.g.
  `$P/dsh-client-ui-layout/package.json:60-63`, `$P/dsh-api-gateway/package.json:69-71`,
  `$P/dsh-typert-registry/package.json:56-58`).
- `dsh-web-frontend/package.json:53-59` — `build`/`dev`/`watch`/`build:preview`/`serve:preview`;
  `"build": "vite build"` (`:54`) and `:57` the only shipped manifest that shows *how* tsdown is
  invoked: `pnpm --filter @deepseek-ai/dsh-experimental-webworker-runtime exec tsdown && …`.
- `node-addon-system/package.json:42-44` — `"build:js": "tsc -b"`, with
  `"!lib/*.tsbuildinfo"` in `files` (`:25`) proving an incremental tsc build whose tsconfig does
  not ship.
- `node-addon-system-linux-x64/package.json:21-23` — `"prepack"`.
- `dsh-subprocess-local/package.json:52-54` — `"postinstall"`.

**No package has `prepare` or `prepublishOnly`.** This directly contradicts the CLI's own
git-plugin narrative at `$DSH/lib/plugin-Ddi42qoW.js:125` — that path is documented but not
exercised by any shipped manifest.

### 9.3 What the compiled output looks like — and what it implies

Two output shapes are visible, and they are the strongest available evidence about the pipeline:

**Shape 1 — unbundled per-module emit at `lib/types/*.js`.** tsc-style (4-space indent, single
quotes, semicolons, `__runInitializers` helpers). Only present when `files` includes
`lib/types/**/*.js`. Example: `$P/dsh-goal/lib/types/index.js:6`
(`var __runInitializers = …`), `$P/dsh-goal/lib/types/fold.js:2`
(`import { … } from "./runtime.js";` — internal specifiers rewritten to `.js`).

**Shape 2 — one bundled entry at `lib/index.js`.** Tabs, double quotes, all own modules inlined
under `//#region lib/types/<module>.js` banners, external bare imports hoisted to the top, one
trailing `export { … }` list. Examples: `$P/dsh-tool-todo/lib/index.js:1-4` (imports then
`//#region lib/types/index.js`), `$P/dsh-tool-todo/lib/index.js:196`,
`$P/dsh-time-context/lib/index.js:1-6` and `:250`,
`$P/dsh-skill/lib/index.js:1-5` and `:565`.

Critically, **JSDoc survives into the bundle**. Compare `$P/dsh-time-context/lib/index.js:95-100`
(the module doc plus `@module` tag) with `$P/dsh-time-context/lib/types/index.d.ts` — the same
prose. Same for `$P/dsh-tool-todo/lib/index.js:5-10`. This means the bundles are emitted with
comments preserved, and it is why "the generated configuration catalog … and its JSDoc"
(§4.4) is meaningful: the JSDoc reaches the shipped artifact.

The banner names the **intermediate** path (`lib/types/index.js`) even in packages that ship no
`lib/types/*.js`, e.g. `$P/dsh-time-context/lib/index.js:94` — evidence that the bundle is built
*from* the per-module emit. `[inferred]` the pipeline is `src/*.ts` → `tsc`-style emit to
`lib/types/*.js` (+ `.d.ts`) → `tsdown` bundle of `lib/types/index.js` → `lib/index.js`, with
tsdown also emitting the extra entry points (`lib/invariant.js`, `lib/startup.js`, …) as separate
bundles.

**A third, generated style exists** for Typert files:
`$P/dsh-goal/lib/typert.host.js:1` —
`/* Generated by @deepseek-ai/dsh-typert-generator from FaceModel — do not edit. */`
(2-space indent, no semicolons). Not reproducible by a third party; it is monorepo tooling.

**Source maps:** zero `.js.map` files exist anywhere under `$P`. 283 `lib/types/*.js` files end
in a dangling `//# sourceMappingURL=<name>.js.map` comment. Only 28 `.d.ts.map` files exist, in
exactly the 8 packages that ship `src/` and list `lib/types/**/*.d.ts.map` in `files`
(`$P/cordis/package.json:28`, `$P/cordis-plugin-loader/package.json:27`,
`$P/schemastery/package.json:30`).

**`src/` ships in exactly 8 TS packages** (plus C sources in `node-addon-system`): `cordis`,
`cordis-plugin-loader`, `cordis-plugin-group`, `cordis-plugin-timer`, `cordis-plugin-include`,
`cordis-plugin-hmr`, `cosmokit`, `schemastery`. Those are exactly the 8 whose `files` lists
`"src"` and exactly the 8 that ship `.d.ts.map`. The other 232 ship **no source at all**. Those
8 are therefore the only DSH sources readable from a published install, and they are the ones
that matter most for a plugin author (the framework and the loader).

### 9.4 What a new package must do — verifiable vs. inferred

**Verifiable from the tarball:**

- Ship ESM only, with `"type": "module"` and an `exports` map whose every subpath carries a
  `types` condition.
- Emit `.d.ts` under `lib/types/`, not `lib/`. `"."` types must be `./lib/types/index.d.ts`; no
  first-party package points `types` at `lib/index.d.ts` (the sole exception is
  `node-addon-system`, `$P/node-addon-system/package.json:13`, which is not a plugin).
- Keep JSDoc in the emitted JavaScript if you want the config-catalog convention to hold, i.e.
  enable `removeComments: false`.
- List only what you ship in `files`. If your build produces per-module JS under `lib/types/`,
  include `lib/types/**/*.js`; otherwise `.d.ts` alone is the norm
  (`$P/dsh-time-context/package.json:28-32`).
- Your `main`/`exports["."]` target must exist and be a valid ESM module with a Cordis plugin
  export shape (§3).

**Not verifiable — do not guess:** the compiler `target`/`module`/`moduleResolution`, whether
`tsdown` or `tsc` or something else is used, the bundler options that produce the
`//#region lib/types/*.js` banners, and whether any workspace-root orchestration is required.
Because DSH itself ships no config, **a third-party author must supply their own build setup**;
the only constraint the runtime imposes is the output shape (ESM, `lib/` layout, `exports` map).

**Bottom line:** the shipped artifacts prove the *output contract* precisely and the *build
toolchain* not at all. That is the largest single gap for someone writing a package from scratch
outside the monorepo.

---

## 10. README conventions for a package

### 10.1 YAML front matter — exactly two keys

Lines 1-4, `---` / `description` / `kind` / `---`. No `schemaVersion`, `tags`, `since`, `summary`
or `title` exists in any of the 231 front-mattered READMEs.

```yaml
---
description: "The model-facing todo_write tool over the DeepSeek Harness session log: whole-list replacement, per-session ownership, and the todos projection, for users and maintainers choosing, configuring, or debugging the tool."
kind: "package-reference"
---
```
`$P/dsh-tool-todo/README.md:1-4`.

```yaml
---
description: "Shared Loader boot support for dsh profiles and the temporary Python SDK runtime: environment layers, patches, diagnostics, and configuration preview."
kind: "package-library"
---
```
`$P/dsh-app-boot/README.md:1-4`.

```yaml
---
description: "Runtime invariant checks for live compositions: the registry service that runs package-owned checks, for users and maintainers choosing, configuring, or debugging them."
kind: "package-reference"
---
```
`$P/dsh-invariants/README.md:1-4`.

- Both keys are double-quoted single sentences. The recurring template is
  "<what it is>: <mechanism>, for <audience> choosing, configuring, or debugging <thing>"
  (`$P/dsh-tool-todo/README.md:2`, `$P/dsh-time-context/README.md:2`,
  `$P/dsh-storage-json/README.md:2`, `$P/dsh-storage-domain/README.md:2`).
- `kind` is always line 3 and takes exactly three values: `package-reference` (193 packages),
  `package-library` (32, e.g. `$P/dsh-app-boot/README.md:3`), `package-bundle` (6 — the six
  bundle packages: `dsh-base`, `dsh-web-app`, `dsh-acp-app`, `dsh-headless`, `dsh-sdk-app`,
  `dsh-sdk-minimal`). A server-side plugin package is `package-reference`; a bundle is
  `package-bundle`.

### 10.2 Section skeleton

The seven `##` headings, in this order, in all 8 sampled packages:

1. `## Summary`
2. `## Table of Contents`
3. `## Use this package`
4. `## Understand the implementation`
5. `## Further Exploration`
6. `## Model Experience`
7. `## Known Limitations and Deferred Work`

Then `<a id="dev-note"></a>` + `### Dev Note` at the end. Representative line numbers (the pairs
are anchor-then-heading): `$P/dsh-tool-todo/README.md:10,14,25/26,60/61,108/109,122/123,153,164/165`;
`$P/dsh-time-context/README.md:10,14,25/26,60/61,87/88,98/99,130,144/145`;
`$P/dsh-tool-present/README.md:10,14,25/26,48/49,64/65,70/71,86,94/95`;
`$P/dsh-storage-json/README.md:10,14,25/26,64/65,107/108,119/120,134,145/146`;
`$P/dsh-invariants/README.md:10,14,25/26,96/97,126/127,138/139,145,157/158`;
`$P/dsh-tools/README.md:10,14,25/26,95/96,140/141,154/155,216,231/232`.

Fixed scaffolding:

- H1 is the package name: `# @deepseek-ai/dsh-tool-todo` (`$P/dsh-tool-todo/README.md:6`).
- Line 8 is the language switch: `English | [中文](README.zh.md)` (`$P/dsh-tool-todo/README.md:8`),
  mirrored as `[English](README.md) | 中文` in the `.zh.md` (`$P/dsh-tool-todo/README.zh.md:8`).
- `## Summary` at line 10 and `## Table of Contents` at line 14 in every sample.
- `-----` horizontal rules separate the ToC and most major sections, but not uniformly:
  `$P/dsh-tool-present/README.md` omits the rule before `## Model Experience` while
  `$P/dsh-tools/README.md:150` and `$P/dsh-invariants/README.md:133` have it. No sample puts one
  before `## Known Limitations and Deferred Work`.
- The `known-limitations-and-deferred-work` anchor is the one anchor placed **after** its heading
  (`$P/dsh-tool-todo/README.md:153` heading, `:155` anchor; `$P/dsh-tools/README.md:216`/`:218`;
  `$P/dsh-storage-domain/README.md:144`/`:146`).
- `## Understand the implementation` is wrapped in
  `<details><summary>Implementation internals — click to expand</summary>`
  (`$P/dsh-tool-todo/README.md:63-64` … `:104`). `### Dev Note` is wrapped in
  `<details><summary>Working context for maintainers — click to expand</summary>`
  (`:167-168` … `:176`).

Required tables:

- **Config options**, header exactly `| Field | Default | Meaning |`, immediately preceded by a
  fenced `yaml` mount snippet: `$P/dsh-tool-todo/README.md:38-46`,
  `$P/dsh-time-context/README.md:44-47`, `$P/dsh-tool-present/README.md:38-40`,
  `$P/dsh-storage-json/README.md:48-50`, `$P/dsh-invariants/README.md:46-50`,
  `$P/dsh-storage-domain/README.md:64-67`, `$P/dsh-tools/README.md:72-75`. Absent only for a
  package with no plugin `Config` (`$P/dsh-app-boot/README.md`).
- **Source map**, header exactly `| File | Role |`, rows linking `src/*.ts`: 
  `$P/dsh-tool-todo/README.md:81-86`, `$P/dsh-time-context/README.md:71-76`,
  `$P/dsh-storage-json/README.md:92-99`, `$P/dsh-invariants/README.md:111-114`,
  `$P/dsh-tools/README.md:107-117`, `$P/dsh-storage-domain/README.md:98-105`.
  `dsh-tool-present` instead uses prose ending `**Runtime invariant:** No companion is
  published.` (`$P/dsh-tool-present/README.md:56`).

`## Model Experience` uses a per-surface `###` followed by `#### What the model sees`,
`#### Token effect`, `#### KV Cache effect` (`$P/dsh-tool-todo/README.md:125,127,131,135`;
`$P/dsh-storage-json/README.md:120,122,126,130`). Packages with no model-visible surface collapse
it — `$P/dsh-invariants/README.md:139` is one line then a bare `#### KV Cache effect` at `:141`.

`## Known Limitations and Deferred Work` is normally bold-lead bullets
(`- **Single-owner scope only** — …`, `$P/dsh-tool-todo/README.md:160`).

The generated-catalog sentence closes the config table (§4.4), and appears again as a
`## Further Exploration` bullet with the tail "every accepted config field and its source
declaration." (`$P/dsh-tool-todo/README.md:48`, `:116`).

### 10.3 `README.i18n.yaml`

Exactly 6 lines: a 4-line comment header (lines 1-3 byte-identical across all samples, line 4
differs only by the monorepo path) plus two keys whose values are 40-hex git blob hashes:

```yaml
# Bilingual-pair consistency record (docs/i18n/README.md): the git blob hash of each
# side as of the last confirmed-consistent state. Both languages carry equal authority;
# after editing either side, bring the other along and re-record with:
#   pnpm run verify-translation-pairing --write packages/todo/tool-todo/README.md
README.md: 0547688d833f10ae9504496d703ed7532e397e3e
README.zh.md: 23d4f71a41403711a2cdf639d01bf6f33c8f803d
```
`$P/dsh-tool-todo/README.i18n.yaml:1-6`.

```yaml
#   pnpm run verify-translation-pairing --write packages/runtime-diagnostics/invariants/README.md
README.md: 3841ca14f2236ddba1976926c13242b6f92bc16f
README.zh.md: fd32d89f69d1516c5a2d2ac6c4bd54f632197dae
```
`$P/dsh-invariants/README.i18n.yaml:4-6`.

Keys are the sibling filenames, in that order, unquoted hex values. Line 4's path is the
**monorepo** path, which does not exist in the npm layout — and the referenced policy document
`docs/i18n/README.md` is not shipped. **A third-party package cannot satisfy this convention as
written**; the honest options are to omit `README.i18n.yaml` and `README.zh.md` entirely, or to
keep the pair and record the hashes by hand.

`README.zh.md` is a full translation of the same skeleton, not a summary: same front-matter keys
with the `description` translated and `kind` byte-identical (`$P/dsh-tool-todo/README.zh.md:1-4`),
identical H1 (`:6`), the same seven headings in Chinese (`:10,14,26,109,123,153,165`), anchors and
ToC targets reused verbatim in Latin script (`:25`, `:16-21`), translated table headers but the
same columns (`:44-46` is `| 字段 | 默认值 | 含义 |`), outbound links re-pointed at `.zh.md`
counterparts (`:113-116`), and identical total line counts in every sample (176/176 for
`dsh-tool-todo`, 151/151 for `dsh-time-context`, 102/102 for `dsh-tool-present`, 153/153 for
`dsh-storage-json`, 165/165 for `dsh-invariants`, 239/239 for `dsh-tools`, 158/158 for
`dsh-app-boot`, 163/163 for `dsh-storage-domain`).

### 10.4 What a real third-party README looks like

For calibration, `$L/dsh-judge/README.md` (33 lines) follows **none** of the above: H1
`# dsh-judge (`/goal-judge`)`, prose, a fenced usage block, and a `## Settings (…)` section with a
YAML block (`:1-33`). So the skeleton is a first-party convention policed by monorepo tooling,
not a runtime requirement. Nothing in the loader or the profile reads a README.

---

## Gaps / could not determine

1. **The build toolchain is not recoverable from any shipped artifact.** No tsconfig, no tsdown
   config, no bundler config, no `build` script on any TypeScript package. The 54
   `"bundle": "tsdown"` declarations and the `//#region lib/types/*.js` banners are the only
   evidence, and they establish the *output* shape, not the *input* configuration. A third-party
   author gets no template from this install.
2. **`@deepseek-ai/dsh-loader-smoke` and `@deepseek-ai/dsh-agent-loop-testkit` are not
   installed**, so their `files` and `exports` maps could not be inspected. They are declared only
   as `devDependencies` (40 manifests), never as runtime or peer dependencies of anything.
   Whether their published versions are usable by a third party, and what they export, is
   unknown from here.
3. **The stage-by-stage build order** (`tsc` → `tsdown`, or a single tsdown pass emitting both)
   is inferred from banners and from `node-addon-system`'s `tsc -b`. Not verified.
4. **Whether the ~220 dangling `./src/*` exports resolve in the monorepo** cannot be determined
   from a published install; they provably do not resolve in this layout.
5. **Whether any DSH package would actually work as a git-hosted plugin.** The CLI documents the
   `prepare`-blocked `allowBuilds` remediation (`$DSH/lib/plugin-Ddi42qoW.js:125`) but no shipped
   manifest has a `prepare` script, so the path is untested by any evidence available here.
6. **Module resolution for `link:`-installed plugins is inferred, not executed.** The evidence —
   the 240-symlink `$DSH_HOME/profiles/node_modules/@deepseek-ai/` mirror, the `link:` symlinks in
   the profile, and `$L/dsh-judge`'s `createRequire`-against-the-install-anchor workaround — is
   strong and mutually consistent, but I did not run Node to confirm that bare specifiers fail
   from a `link:`ed package's realpath.
7. **No `reusable` field or symbol exists** in `@deepseek-ai/cordis` 4.0.2 or
   `@deepseek-ai/cordis-plugin-loader` 1.0.3. If the specification expects one, it comes from a
   different (probably later or upstream-Cordis) version than the one shipped here.
8. **No `readOnly` / read-only metadata on `ToolDefinition`.** The only scheduling metadata is
   `isConcurrencySafe`; `kind` lives in presentation views only. If the specification assumes a
   read-only declaration, it does not exist in this version.
9. **The generated configuration catalog does not ship** (`$R/docs/config-catalog.md` absent),
   and no shipped file names its generator. The JSDoc→catalog relationship is asserted only by
   README prose (`$P/dsh-time-context/README.md:49`, `$P/dsh-tool-todo/README.md:116`).
10. **`docs/i18n/README.md`**, referenced by every `README.i18n.yaml` header line, is not shipped;
    the full bilingual-pairing policy could not be read.
11. **No test files ship in any of the 240 packages**, so there is no first-party test to imitate.
    `defineContentToolFixture` is the only shipped test-shaped API and it is marked `@internal`.
12. **`dsh plugin add` behaviour was read from code, not executed.** No command was run against a
    profile in this session; the live `~/.dsh/profiles/web` state is *evidence that the mechanism
    worked at some point*, not a reproduction of it.
13. **Whether a plugin can be added purely by hand-editing the profile manifest** is `[inferred]`
    yes, from `resolveBundleDir`'s two-anchor resolution (`$P/dsh-app-boot/lib/index.js:826-832`)
    and its error message naming `dsh plugin --profile <n> install`. Not executed.
