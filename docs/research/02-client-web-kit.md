# DSH Web client-plugin kit — what it costs to put a UI on a third-party plugin

Research target: the published npm installation at `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/`
(DSH `0.1.5-rc.1` root, `0.1.5-rc.2` packages, 240 packages under `node_modules/@deepseek-ai/`).
All citations are `absolute-path:line`. Package paths are abbreviated below as
`$PKG/<name>` = `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/<name>`.

---

## Verified facts vs. inferred

**Verified** — read directly from shipped files: package manifests, compiled `lib/*.js`,
type declarations under `lib/types/**`, and the English READMEs. Every claim marked
"verified" below carries a `path:line`.

**Inferred** — three places where the shipped tarballs do not contain the artefact:

1. The *contents* of the client build preset. It is named in shipped text
   (`$PKG/dsh-client-ui-settings-plugins/README.md:96`, `$PKG/dsh-client-ui-settings/lib/client.js:1124`)
   as `packages/client/tsdown.client.ts`, but that file is not published in any tarball.
   Everything said below about what the preset *must* emit is inferred from the emitted
   bundles and from the host-side validator that consumes them.
2. The *contents* of `@deepseek-ai/dsh-client-ui-slots`, `@deepseek-ai/dsh-client-ui-primitives`,
   `@deepseek-ai/dsh-client-ui-dockkit`, `@deepseek-ai/dsh-client-store` and
   `@deepseek-ai/dsh-client-test-runtime`. Those packages are declared as dependencies by
   shipped packages but are **not present** anywhere in the install (verified by
   `find $ROOT -type d -name dsh-client-ui-slots` returning nothing, and by their absence
   from the `node_modules/@deepseek-ai/` listing). Their runtime surfaces are therefore
   reconstructed from the shell bundle that inlines them and from usage in consumers.
3. Whether a third-party bundle *actually boots* end-to-end. No example of an
   externally-built client plugin ships; the build preset is not published and there is no
   smoke-test package for it. See item 6 and Gaps.

---

## ANSWER TO ITEM 6 (critical yes/no)

> **YES — a browser/web plugin can be authored outside the DSH monorepo and mounted from a
> third-party package. The client surface is NOT monorepo-only and does not require forking
> the checkout or rebuilding the shipped Web artefacts.**
>
> The host discovers client plugins purely from the Cordis Loader entry list plus each
> package's own `package.json`; there is no allowlist, no registry file, and no
> monorepo-path assumption in the discovery or serving code
> (`$PKG/dsh-client-modules/lib/index.js:637-667`, `:775-835`). A third-party package that
> (a) is installed into a profile, (b) declares `dsh.client` with `platform: "web"`, and
> (c) ships a prebuilt `exports["./client"]` bundle in the lazy-CJS factory format, is
> scanned, served over `/plugins`, and booted exactly like a first-party one.
>
> **Three real costs, all build-side, none fatal:**
>
> 1. **You must reproduce the client bundler yourself.** The preset that emits the
>    lazy-CJS bundle lives at `packages/client/tsdown.client.ts` in the monorepo and is
>    *not published*: "the `clientBundle` preset that emits it lives in
>    `../../../packages/client/tsdown.client.ts` rather than a published package, so a
>    plugin outside this repository has to reproduce that build itself"
>    (`$PKG/dsh-client-ui-settings-plugins/README.md:96`).
> 2. **You must ship the built bundle.** The host never builds; a missing `lib/client.js`
>    is a hard activation failure: `client-modules: client bundle not found; run `pnpm run
>    build` before launch` (`$PKG/dsh-client-modules/lib/index.js:91-101`, README:46).
> 3. **You cannot import the slot/primitives type packages.** `@deepseek-ai/dsh-client-ui-slots`
>    is not published, yet `SlotMap`, `LocaleNamespaceMap` and `ResourceProtocolMap`
>    augmentations all target it
>    (`$PKG/dsh-client-ui-renderer/lib/types/client/registry.d.ts:16-37`,
>    `$PKG/dsh-client-ui-settings-plugins/lib/types/client/slot-contract.d.ts:16-25`).
>    Type-level integration therefore needs a hand-written declaration shim.
>
> The shipped documentation states the third-party case explicitly in one place:
> "Keying on the namespace is what lets a plugin distributed outside this repository
> contribute a card: it registers its own settings namespace on the Host and its own card
> under that key in the browser" (`$PKG/dsh-client-ui-settings-plugins/lib/types/client/slot-contract.d.ts:7-10`).
>
> **The shipped tarballs are sufficient to decide the architecture question (YES) but NOT
> sufficient to decide the effort question.** No published example bundle exists that was
> built outside the repo, so "reproduce the build" is documented as a requirement, not
> demonstrated.

---

## 1. Host vs. client split

**Two separate packages, mounted together by a profile composition. Never one package with
two entry points.**

Evidence — `package.json` of the four packages named in the task:

`$PKG/dsh-tool-todo/package.json` (host / server side):

```json
"main": "lib/index.js",
"exports": {
  ".": { "types": "./lib/types/index.d.ts", "default": "./lib/index.js" },
  "./invariant": { "types": "./lib/types/invariant.d.ts", "default": "./lib/invariant.js" },
  "./client": { "types": "./lib/types/client.d.ts", "default": "./lib/types/client.js" }
},
"files": ["lib/index.js", "lib/invariant.js", "lib/types/**/*.js", "lib/types/**/*.d.ts"]
```

Note: **no `dsh` field at all**, and no `scripts.bundle`/`scripts.watch`.

`$PKG/dsh-client-ui-skill/package.json` (client side):

```json
"exports": {
  ".": { "types": "./lib/types/index.d.ts", "default": "./lib/index.js" },
  "./client": { "types": "./lib/types/client/index.d.ts", "default": "./lib/client.js" }
},
"dsh": {
  "client": {
    "inject": [
      "@deepseek-ai/dsh-api-session-controller",
      "@deepseek-ai/dsh-client-locale",
      "@deepseek-ai/dsh-client-ui-renderer",
      "@deepseek-ai/dsh-client-ui-tool",
      "@deepseek-ai/dsh-client-ui-input-trigger",
      "@deepseek-ai/dsh-api-remotes"
    ],
    "platform": "web"
  }
},
"files": ["lib/index.js", "lib/client.js", "lib/types/**/*.d.ts"],
"scripts": { "bundle": "tsdown", "watch": "tsdown --watch" }
```

`$PKG/dsh-client-ui-goal/package.json` and `$PKG/dsh-client-ui-settings-plugins/package.json`
have the same shape as `dsh-client-ui-skill`: `dsh.client.platform: "web"`, an
`exports["./client"]`, and `scripts.bundle = "tsdown"`.

### The `./client` export is overloaded — two different things

| Package kind | `exports["./client"]` | `dsh.client` | Contents |
|---|---|---|---|
| Host package | `./lib/types/client.js` | absent | type-only re-export stub |
| Client package | `./lib/client.js` | present | executable browser bundle |

The host-side stub is a comment plus `export {}`
(`$PKG/dsh-tool-todo/lib/types/client.js:1-8`):

```js
/**
 * Client-namespace projection of the todo domain: a pure re-export of the package's
 * types outlet. Client code imports ONLY the client namespace (repo
 * discipline), so `./client` projects the same single-source content
 * `./types` serves to host consumers — zero duplication.
 *
 * @module @deepseek-ai/dsh-tool-todo/client
 */
export {};
```

Ten host packages carry this types-only `./client` stub and no `dsh` field — enumerated by
scanning every `package.json`: `dsh-goal`, `dsh-permission-presets`, `dsh-plan-mode`,
`dsh-schedule`, `dsh-session-stats`, `dsh-session-title`, `dsh-session-turn-outline`,
`dsh-subagent`, `dsh-token-meter`, `dsh-tool-todo`. This is a monorepo *import-discipline*
convention, not the client-module mechanism.

### A client package still has a node half — but it is inert

`$PKG/dsh-client-ui-goal/lib/index.js:1-10`:

```js
/**
* Goal surface plugin, node half. Pure UI plugin: the empty apply exists so
* the plugin appears in the host cordis.yml / Loader; the browser half
* ships via exports["./client"], discovered through the package.json
* dsh.client declaration.
*/
/** Host plugin body — no host-side behavior for this surface plugin. */
function apply() {}
export { apply };
```

So "one package, two faces" is true *within* a client package (a node loader entry plus a
browser bundle, produced by one tsdown run — `$PKG/dsh-api-remotes/README.md:56`), but a
UI feature is **not** one package: the model-facing half and the browser half are always
distinct packages.

### Worked example: the todo feature is two unrelated packages

- `$PKG/dsh-tool-todo/lib/index.js:10-11` registers the model-facing tool:
  `const name = "tool-todo"; const inject = ["tools", "sessionProjections"];`
- `$PKG/dsh-client-ui-tool/lib/client.js:2298-2308` registers the browser row:

```js
/** Registers the todo conversation row. */
const todoToolview = {
    name: "todo-toolview",
    inject: ["slots"],
    apply(ctx) {
        ctx.slots.inject("tool.call.toolview", () => ctx.slots.register({
            name: "tool.call.toolview",
            key: "todo_write",
            locale: CONVERSATION_NS
        }, TodoRow));
    }
};
```

There is **no dependency edge in either direction**: `$PKG/dsh-client-ui-tool/package.json`
has `dependencies: {}` and peers only on cordis; it does not mention `dsh-tool-todo`, and
`dsh-tool-todo` does not mention it. The two are joined by the string `"todo_write"` and by
the session-event wire. In the shipped Web profile the host row is even disabled, because
the agent plane moves behind agent presets
(`$PKG/dsh-web-app/cordis.patch.yml`, row `- id: tool-todo` / `disabled: true`), while the
browser row still renders from the session log.

**Consequence for a memory plugin:** expect to author at least two packages (or one bundle
package that inserts several rows — see item 6), and expect no compile-time coupling
between them. The repo calls this the "client bundle purity gate"
(`$PKG/dsh-client-ui-settings/lib/client.js:1121-1124`).

---

## 2. Client entry-point mechanism

### 2.1 What marks a package as a client module

`dsh.client` in `package.json`, validated against
`$PKG/dsh-package-manifest/lib/types/types.d.ts:33-48`:

```ts
/** Client module declaration read by client-modules and the client build. */
export interface DshClientManifest {
    /** Client platform identifier; the Web consumer selects `web`. */
    platform: string;
    /** Informational package-name dependencies, not Cordis service injection. */
    inject?: string[];
    /** Boot phase-one registration barrier; absent means the shared application batch. */
    immediately?: boolean;
    /**
     * Exact module-table requests beyond the implicit client baseline, including
     * subpaths such as `<pkg>/client`; absent means baseline externals only.
     * Type-only imports are erased and create no module request.
     */
    external?: string[];
}
```

Runtime validation of the same fields: `$PKG/dsh-client-modules/lib/index.js:139-152`
(`dsh.client.platform must be a string`, `inject`/`external` must be string arrays,
`immediately` must be a boolean).

`platform` must equal `"web"` or the package is silently skipped
(`$PKG/dsh-client-modules/lib/index.js:650-653`). Declaring `dsh.client` while exporting
no `./client` is a hard error
(`$PKG/dsh-client-modules/lib/index.js:654-655`):

```js
const clientRel = clientExportOf(packageName, pkg.exports);
if (clientRel === void 0) throw new Error(`client-modules: ${packageName} declares dsh.client but exports no "./client" bundle`);
```

### 2.2 How the host finds the package

Verified, `$PKG/dsh-client-modules/lib/index.js:67-88` (module doc):

> The package is dual-face: ... scans the host Loader's entries for packages declaring
> `dsh.client`, composes the `window.__DSH_BOOT__` entry graph ... serves one-or-more-plugin
> combo scripts plus their source maps, contributes the registration facade, application
> preloads, bootstrap scripts, and graph to the webserver's index injection table.

The scan is incremental and Loader-entry-driven
(`$PKG/dsh-client-modules/lib/index.js:775-812`):

```js
processOne(entryName, onError) {
    const nextSources = new Map();
    for (const entry of this.ctx.loader.entries()) {
        if (entry.options.name !== entryName || entry.fiber === void 0 || entry.disabled) continue;
        const source = this.resolveSource(entry);
        ...
```

`resolveSource` (`:800-812`) takes `entry.options.name` and `entry.parent.tree.ctx.baseUrl`
and calls `resolveMeta`, which locates the nearest `package.json` and reads `dsh.client`
(`:637-667`). The row id is the *package name*, not the Loader entry id
(`:823-826`): `this.table.set(packageName, { entry: graphRow(packageName, rev, source.meta), ... })`.
Two active Loader sources resolving to one package name is rejected
(`:813-819`).

### 2.3 What the host serves to the browser

The wire is `window.__DSH_BOOT__`, typed as `WebBootGraph` in
`$PKG/dsh-client-modules/lib/types/client/manifest.d.ts`:

```ts
export interface WebBootEntry {
    /** Entry name == package name. */
    id: string;
    /** Revisioned single-resource combo endpoint used by HMR. */
    url: string;
    /** Opaque plugin-artifact revision used for HMR cache busting. */
    rev: string;
    /** Package-name dependency edges used for factory arrival and plugin composition. */
    inject?: string[];
    /** Stage-one prefetch mark: load the script for factory registration during module-face boot. */
    immediately?: boolean;
    /** Non-baseline module specifiers this row requests; omitted when it requests none. */
    external?: string[];
}
export interface WebBootBatch {
    phase: WebBootBatchPhase;      // 'bootstrap' | 'application'
    url: string;
    rev: string;
    entries: string[];
}
export interface WebBootGraph {
    rev: string;
    entries: WebBootEntry[];
    batches: WebBootBatch[];
}
```

`id` is documented as "Entry name == package name" in three places
(`manifest.d.ts`, same interface; `system.ts` contract; `ClientBundleRegistration.id`).
The bundle must agree: `arrive()` fails if a fetched script registers a different id
(`$PKG/dsh-client-modules/lib/client.js:247-250`):

```js
return transport.then(() => {
    if (!this.factories.has(id)) throw new Error(`client-modules: bundle ${url} loaded without registering "${id}" via __ModuleLoader__.load`);
```

Bundles are grouped into combo URLs of the form
`/plugins/??<id>/client.js,<id>/client.js&rev=<rev>` with a 3 KiB cap per phase
(`$PKG/dsh-client-modules/lib/index.js:183`, `:70`, `:124`). Responses are served
`public, max-age=31536000, immutable` (`:121-122`).

The route is registered as a prefix on the webserver (`:480-491`):

```js
const registerWebCarrier = (webCtx) => {
    webCtx.effect(() => webCtx.webServer.register({
        kind: "prefix",
        path: "/plugins",
        handler: this.serveBundle
    }), "client-modules: bundle route");
};
...
ctx.on("webserver/index-inject", (table) => {
    table.push(...bootInjections(this.composed));
});
```

`ClientModuleRegistry.fetchBundle(request: Request): Response` serves the same bytes
without a Web server (shell-owned carrier path) — `$PKG/dsh-client-modules/lib/types/index.d.ts`.

### 2.4 The four index rows the host injects

`$PKG/dsh-client-modules/lib/index.js:387-430` (`bootInjections`) returns head rows in
execution order. The first is an inline parser-blocking script that installs the queue
facade:

```js
function bootInjections(graph) {
	const queue = `(()=>{
const pendingQueue=[]
window.__ModuleLoader__={
  mode:"queue",
  pendingQueue,
  load(registration){pendingQueue.push(registration)},
  create(options){
    if(this.mode!=="queue")throw new Error("client-modules: window.__ModuleLoader__.create called after module-system boot")
    const index=pendingQueue.findIndex(registration=>registration.id===${JSON.stringify(CLIENT_MODULES_ID)})
    ...
  }
}
})()`;
```

then `script-preload` rows for the application batches, `script-src` rows for the
parser-blocking bootstrap batches, and finally
`{ kind: "global", name: "__DSH_BOOT__", value: graph }`.

### 2.5 The browser side of the module system

`$PKG/dsh-client-modules/lib/client.js` is itself a bundle; the interesting half is
`ClientModuleSystem` (`:184-337`). Core points:

- The baseline module table is a **frozen seed** passed by the shell, resolved first on
  every require (`:300-310`):

```js
makeRequire(edges) {
    return (spec) => {
        edges.add(spec);
        if (this.seed.has(spec)) return this.seed.get(spec);
        const id = stripClientSuffix(spec);
        const record = this.loadCache.get(id);
        if (record !== void 0) return record.exports;
        if (this.factories.has(id)) return this.materialize(id).exports;
        throw new Error(`client-modules: require("${spec}") missed the module table — not a platform seed word, not a materialized module, and no registered package factory (a build-time externals drift, or a dynamic dependency that did not arrive)`);
    };
}
```

- `<pkg>/client` and `<pkg>` resolve identically (`stripClientSuffix`, `:61-63`).
- A require cycle through a factory is fatal (`:278`).
- Style tags injected during materialization are claimed for HMR bookkeeping
  (`:170-176`).
- Default transport is a same-origin classic `<script src>` (`:145-159`).

**The seed table is exactly nine words.** Extracted from the shell bundle
`$PKG/dsh-web-frontend/dist/assets/index-BKQ_L1z6.js` (minified function `by()`, offset
553121):

```js
function by(){return{react:ec,"react/jsx-runtime":ic,"react-dom":cc,"react-dom/client":fc,"@deepseek-ai/cordis":Ha,"@deepseek-ai/dsh-client-store":Hc,"@deepseek-ai/dsh-client-ui-slots":Ac,"@deepseek-ai/dsh-client-ui-primitives":Zg,"@deepseek-ai/dsh-client-ui-dockkit":Ey}}
```

That is the `PLATFORM_MODULES` baseline the `dsh-client-modules` README names
(`$PKG/dsh-client-modules/README.md:42`). Anything else a bundle `require()`s must be
either a graph row (another installed client package) or declared in `dsh.client.external`
and answered by such a row.

### 2.6 HMR node half (`dsh-client-hmr`)

`$PKG/dsh-client-hmr/lib/index.js:11-22` (module doc) and `:45-99`:

```js
const inject = ["clientModules", "webServer"];
const Config = z.object({ pollIntervalMs: z.number().step(1).min(1).default(500) });
const EVENTS_ENDPOINT = "/plugins/events";
```

It stat-polls every graph row's bundle path, reports through
`ctx.clientModules.rebuilt(id)` (the only path by which bundle content reaches the graph —
`$PKG/dsh-client-modules/lib/index.js:86-87`), and serves SSE frames `{type:"graph"}` /
`{type:"rebuilt"}` (`:105-140`). The watch set comes from
`ctx.clientModules.artifactBaseline(row.id)` with **no origin filter**, so
externally-provided plugins are polled too.

### 2.7 `dsh-client-resources` and `dsh-client-ui-cordis` (adjacent mechanisms)

- `dsh-client-resources` gives components live data by URL address
  (`dsh-resource://<type>/…`) through a `useResource` prop contributed to every slot
  component (`$PKG/dsh-client-resources/README.md:11`, `:31-36`). Providers register with
  `ctx.resources.register(...)` and a `ResourceProtocolMap` augmentation
  (`:41-58`).
- `dsh-client-ui-cordis` + `dsh-cordis-client-runner` implement **runtime dynamic
  plugins**: a browser half written in plain JavaScript (no JSX, no TS, no imports),
  evaluated in the page as an async function receiving `React`, `console`, `styles`,
  `host`, mounted through the same loader, page-local and gone on refresh
  (`$PKG/dsh-cordis-client-runner/README.md:28-40`). This is a genuine third-party UI path
  that needs no build at all — but it is user-approved per run, not package-mounted.

---

## 3. Minimal client UI plugin, end to end

### 3.1 Framework and primitives

**React 18**, not Vue and not a custom renderer. `react`/`react-dom`/`react/jsx-runtime`
are three of the nine seed words (§2.5); client packages declare `react@^18.2.0` and
`@types/react@~18.3.1` as devDependencies
(`$PKG/dsh-client-ui-goal/package.json`, `$PKG/dsh-client-ui-skill/package.json`).

Component primitives come from `@deepseek-ai/dsh-client-ui-primitives` (seed word) —
e.g. `$PKG/dsh-client-ui-brand-official/lib/client.js:8`, `:16`:

```js
let _deepseek_ai_dsh_client_ui_primitives = require("@deepseek-ai/dsh-client-ui-primitives");
...
return (0, react_jsx_runtime.jsx)(_deepseek_ai_dsh_client_ui_primitives.FishLogo, { size });
```

Every slot component also receives standard props contributed at the root: `useResource`,
`useWorkspaces`, `usePanelInfo`, `useSessions`, `useSessionPendingInteraction`
(enumerated per slot as `standardProps` in
`$PKG/dsh-cordis-client-runner/lib/client.js`, e.g. `:4143-4150`).

### 3.2 The bundle format (verified from emitted artefacts)

Every shipped client bundle is a classic script whose entire body is one call into the
page-installed facade. The complete smallest real example is
`$PKG/dsh-client-ui-brand-official/lib/client.js` (47 lines, reproduced in full minus
JSDoc):

```js
window.__ModuleLoader__.load({
	id: "@deepseek-ai/dsh-client-ui-brand-official",
	factory: (require) => {
		var module = { exports: {} };
		var exports = module.exports;
		Object.defineProperty(exports, Symbol.toStringTag, { value: "Module" });
		let react_jsx_runtime = require("react/jsx-runtime");
		let _deepseek_ai_dsh_client_ui_primitives = require("@deepseek-ai/dsh-client-ui-primitives");

		function OfficialBrandMark({ size }) {
			return (0, react_jsx_runtime.jsx)(_deepseek_ai_dsh_client_ui_primitives.FishLogo, { size });
		}
		function OfficialBrandName() {
			return (0, react_jsx_runtime.jsx)(_deepseek_ai_dsh_client_ui_primitives.BrandWordmark, { includeMark: false });
		}

		/** Required service: the UI slot registry. */
		const inject = ["slots"];
		function apply(ctx) {
			ctx.slots.inject("sidebar.brand.mark", () => ctx.slots.inject("sidebar.brand.name", function* () {
				yield ctx.slots.register({ name: "sidebar.brand.mark" }, OfficialBrandMark);
				yield ctx.slots.register({ name: "sidebar.brand.name" }, OfficialBrandName);
			}));
		}

		exports.apply = apply;
		exports.inject = inject;
		return module.exports;
	}
});

//# sourceMappingURL=client.js.map
```

Requirements this pins down (each corroborated host-side):

| Requirement | Enforced at |
|---|---|
| `window.__ModuleLoader__.load({id, factory})` | `$PKG/dsh-client-modules/lib/client.js:223-233` |
| `id` === package name (a `/client` suffix is stripped) | `$PKG/dsh-client-modules/lib/client.js:61-63`, `:247-250` |
| `factory(require)` returns exports with named `apply(ctx)` | `$PKG/dsh-client-modules/lib/index.js:394-401` (bootstrap face check), README:46-47 |
| body is lazy — only registration at script execution; side effects at materialization | `$PKG/dsh-client-modules/lib/client.js:16-23` |
| a `//# sourceMappingURL=` trailer is expected (used for HMR revisions) | `$PKG/dsh-client-modules/lib/index.js:127-128` |

### 3.3 The registration API: `ctx.slots`

`ctx.slots` is a Cordis service of type `SlotRegistry`, provided by
`dsh-client-ui-renderer` (`$PKG/dsh-client-ui-renderer/lib/types/client/index.d.ts:30-40`):

```ts
declare module '@deepseek-ai/cordis' {
    interface Context {
        /** Renderer-owned UI composition registry. */
        slots: SlotRegistry;
        /** Mount face provided after the UI renderer activates. */
        uiRenderer: UiRendererService;
    }
}
```

The service methods a plugin actually uses
(`$PKG/dsh-client-ui-renderer/lib/types/client/registry.d.ts`):

| Method | Line | Signature / meaning |
|---|---|---|
| `register` | `:84` | `readonly register: SlotCore['register']` — "The single registration API"; routed through the **caller's** `ctx.effect`, so fiber unload cascades the entry away |
| `inject` | `:100` | `inject(key, callback): () => void` — run `callback` for each declaration *lifetime* of a slot; re-runs if the owner re-declares |
| `entries` | `:154` | snapshot of raw registered entries for a key |
| `entriesOfSlot` | `:164` | shadowing winners per cell |
| `subscribe` | `:197` | microtask-batched change subscription |
| `getVersion` | `:203` | version counter for `useSyncExternalStore` pairing |
| `onEntryError` | `:182` | render-crash seam with an `abdicated` flag |
| `spec` | `:190` | declared spec lookup |

`inject` is mandatory in practice, not optional: the `client-ui-settings-plugins` doc
comment explains why (`$PKG/dsh-client-ui-settings-plugins/lib/client.js:402`, and the
loader source ships the same teaching example at
`$PKG/dsh-cordis-client-runner/lib/client.js:3823`):

```js
inject: ['slots'],
apply(ctx) {
  ctx.slots.inject('settings.plugin.item', () => ctx.slots.register(
    { name: 'settings.plugin.item', key: '<one key the owner dispatches>' },
    () => React.createElement('div', null, 'hello'),
  ))
}
```

Registration options depend on the slot's `kind`, and the shipped runner bundle carries a
generated contract for all 61 slots. Extracted from
`$PKG/dsh-cordis-client-runner/lib/client.js` (regex over `key`/`kind`/`scope`):

```
L3372  main                      keyed/root          Central panel selected by sidebar entry id
L3435  rightbar                  single/root
L3495  root                      single/root
L3521  settings.action           list/root
L3592  settings.general.item     list/root
L3670  settings.models.footer    list/root
L3746  settings.onboarding       list/root
L3791  settings.plugin.item      keyed/root          One plugin's card in the Plugins section
L3827  settings.plugins.tab      list/root           One page inside the Plugins settings section
L3872  settings.section          list/root           One settings page per list entry
L3948  shell.overlay             list/root
L4071  sidebar.footer.action     list/root
L4116  sidebar.panellist         list/root           Global panel icons
L4385  sidebar.settings          single/root
L4161  sidebar.right.pane.tab    keyed/session
L4497  tool.call.toolview        keyed/session
L4558  tool.view.cordis          keyed/session
...   (61 total: conversation.*, sidebar.*, settings.*, tool.*, shell.overlay, main, rightbar)
```

Slot kinds and their options, from the shipped contract text
(`$PKG/dsh-cordis-client-runner/lib/client.js:4116-4159` for a `list` slot,
`:3791-3826` for a `keyed` slot):

- `list` — options `{ id (required), order (optional, default 0), label (optional,
  `string | (() => string)`) }`. A fresh `id` adds a cell; reusing a shipped `id` **replaces**
  that occupant. Labels as thunks follow the active locale without re-registering.
- `keyed` — option `{ key (required) }`; "Registering an already-occupied key replaces that
  occupant."
- `single` — no cell option; a second entry **shadows** the first, and a dynamically
  registered entry wins (that is why `root` carries an explicit "DO NOT register here"
  warning at `$PKG/dsh-client-ui-renderer/lib/types/client/registry.d.ts:18-31`).
- `chain` — election consumes every entry (e.g. `conversation.chat.turnTail`).

A plugin can also **declare its own slot** and let others fill it, by registering a
declaring entry with a `children` map — the pattern used by the settings section
(`$PKG/dsh-client-ui-settings-plugins/lib/client.js:1761-1784`):

```js
ctx.slots.inject("settings.section", () => ctx.slots.register({
    name: "settings.section",
    id: "plugins",
    order: 15,
    label: () => t("nav"),
    locale: NS,
    inject: sectionInjected,
    children: { "settings.plugins.tab": { kind: "list", scope: "root" } }
}, PluginsSettingsSection));
```

Type-level, a plugin augments `SlotMap` in the (unpublished) `@deepseek-ai/dsh-client-ui-slots`
module — see `$PKG/dsh-client-ui-settings-plugins/lib/types/client/slot-contract.d.ts:16-25`
and `$PKG/dsh-client-ui-renderer/lib/types/client/registry.d.ts:16-37`.

### 3.4 Styling

CSS is emitted as a plain string and injected by the factory at materialization, tagged
`data-plugin` (owner) and `data-plugin-css` (tag id) so HMR can remove it. Real pattern
(`$PKG/dsh-client-ui-approval/lib/client.js:10-19`, Vite-style CSS-module output):

```js
//#region \0dsh-css:/home/runner/work/deepseek-harness/deepseek-harness/packages/client/ui-approval/src/client/ApprovalPanel.module.css.mjs
const css = ".mna1RW_root{padding:8px calc(var(--dsh-composer-side-clearance) + 16px) 12px;...}";
const tagId = "@deepseek-ai/dsh-client-ui-approval/ApprovalPanel.module.css";
if (typeof document !== "undefined" && document.querySelector("style[data-plugin-css=" + JSON.stringify(tagId) + "]") === null) {
    const tag = document.createElement("style");
    tag.dataset.plugin = "@deepseek-ai/dsh-client-ui-approval";
    tag.dataset.pluginCss = tagId;
    tag.textContent = css;
    document.head.appendChild(tag);
}
```

The host side of this convention is `claimStyles` in
`$PKG/dsh-client-modules/lib/client.js:170-176`, and the HMR removal of `<style data-plugin>`
tags is documented at `$PKG/dsh-client-hmr/README.md:66`.

Styling values reference the theme's CSS custom properties (`--dsw-*`, `--dsh-*`), owned
by `dsh-client-ui-theme` (a `dsh.client` package with `immediately: true`).

### 3.5 The build step

- Each client package declares `"bundle": "tsdown"` and `"watch": "tsdown --watch"`
  (`$PKG/dsh-client-ui-goal/package.json`, `$PKG/dsh-client-ui-skill/package.json`, and 40+
  others).
- The monorepo preset is `packages/client/tsdown.client.ts` — cited by shipped text at
  `$PKG/dsh-client-ui-settings-plugins/README.md:96` and
  `$PKG/dsh-client-ui-settings/lib/client.js:1124`. **It is not published.**
- Build-time gates the preset implements, per shipped documentation: bundle purity — no
  cross-plugin value imports, "cross-plugin collaboration through cordis services"
  (`$PKG/dsh-client-ui-settings/lib/client.js:1121-1124`); externals declaration for every
  non-baseline request (`$PKG/dsh-client-modules/README.md:42`); and a runtime mirror of
  the same gate that throws on a missed require (`$PKG/dsh-client-modules/lib/client.js:308`).
- The output must land at the path `exports["./client"]` names; the host reads it verbatim
  from disk (`$PKG/dsh-client-modules/lib/index.js:750-764`) and throws
  `MissingClientBundleError` on `ENOENT` (`:93-105`).
- `pnpm run build` at the repo root is what produces it (`$PKG/dsh-client-modules/README.md:46`).

### 3.6 Complete minimal memory-plugin shape (synthesised, not shipped)

Nothing in the install registers a page-like surface end to end in under ~50 lines, so
the smallest honest complete registration for a "Memories" panel is the union of two
shipped patterns — the brand bundle's skeleton (§3.2) and the sidebar panel slot
contract (`$PKG/dsh-cordis-client-runner/lib/client.js:4116-4158`):

```js
window.__ModuleLoader__.load({
  id: "@acme/dsh-memory",                       // MUST equal package.json name
  factory: (require) => {
    var module = { exports: {} }; var exports = module.exports;
    const React = require("react");
    const { jsx } = require("react/jsx-runtime");
    const inject = ["slots", "locale", "remote"];

    function MemoriesPanel() { return jsx("div", { children: "memories" }); }

    function apply(ctx) {
      // sidebar icon cell -> the `main` keyed panel
      ctx.slots.inject("sidebar.panellist", () => ctx.slots.register(
        { name: "sidebar.panellist", id: "memory", order: 100, label: () => t("nav") },
        () => jsx("span", { children: "M" })));
      ctx.slots.inject("main", () => ctx.slots.register(
        { name: "main", key: "memory" }, MemoriesPanel));
    }
    const t = (k) => k;
    exports.apply = apply; exports.inject = inject;
    return module.exports;
  }
});
```

Caveat: this is *my* composition of the documented contracts. It is not a shipped file and
has not been booted. See Gaps.

---

## 4. Configuration UI

### 4.1 Short answer

**No — configuration is NOT rendered automatically from a plugin's schema.** The shipped
Plugins settings section renders a card only if the plugin's *browser half* registers one.
What *is* automatic is the dispatch: the tab enumerates the Host's served settings
namespaces and asks for one card per namespace.

### 4.2 The mechanism

`$PKG/dsh-client-ui-settings-plugins/README.md:32`:

> The tab reads which settings namespaces the Host serves and dispatches one slot key per
> namespace, so what renders is the intersection of two ledgers: the namespaces a live Host
> plugin registered, and the cards registered under those keys. A served namespace no card
> claims renders nothing, and a card whose namespace this deployment does not serve is
> never dispatched.

`$PKG/dsh-client-ui-settings-plugins/README.md:56`:

> The package registers its own `configurable` contribution, which declares the nested
> `settings.plugin.item` slot — keyed on the settings namespace a card edits. A plugin that
> ships a browser half registers its own card under its own namespace and owns every part
> of it: chrome, controls, and copy.

The dispatch loop is four lines (`$PKG/dsh-client-ui-settings-plugins/lib/client.js:416`):

```js
children: namespaces.map((ns) => (0, react_jsx_runtime.jsx)(react.Fragment, { children: renderSlot("settings.plugin.item", {}, { entryKey: ns }) }, ns))
```

and the shipped cards are four hardcoded registrations keyed by namespace constant
(`$PKG/dsh-client-ui-settings-plugins/lib/client.js:1785-1810`):

```js
ctx.slots.inject("settings.plugin.item", function* () {
    yield ctx.slots.register({ name: "settings.plugin.item", key: SHELL_NS, locale: NS, inject: () => bash.inject() }, BashCard);
    yield ctx.slots.register({ name: "settings.plugin.item", key: AGENT_LOOP_NS, ... }, AgentLoopCard);
    yield ctx.slots.register({ name: "settings.plugin.item", key: SUBAGENT_MODEL_SELECTION_NS, ... }, SubagentModelSelectionCard);
    yield ctx.slots.register({ name: "settings.plugin.item", key: WEB_SEARCH_NS, ... }, WebSearchCard);
});
```

The card controls are explicitly hand-written, not schema-generated
(`$PKG/dsh-client-ui-settings-plugins/lib/types/client/fields.d.ts:1-6`):

> Hand-written controls for the plugin configuration forms. Each renders one field's label,
> its staged text, whether saving would leave an override, and — when one stands — the
> reset that stages a clear back to the composition layer.

`ValueField` and `SecretField` are the only two shipped field primitives
(`fields.d.ts`, both declared there).

### 4.3 What the plugin must declare to appear

**Host half** — register a settings namespace. `$PKG/dsh-settings/README.md:46-58`:

```text
const scope = ctx.settings.register('ui-theme', ThemeSchema, {
  base: config,   // composition entry config; the user layer resolves above it
})
const theme = scope.get()              // deep-frozen resolved snapshot
scope.update({ density: 'compact' })   // merges into the user section and persists
```

`ctx.settings.installSection(owner, ns, schema, entry, hooks)` is the packaged form for a
consumer plugin, tolerating a missing settings provider. Namespace literal grammar is
lowercase letter, digit, hyphen (`$PKG/dsh-settings/lib/types/index.d.ts:14-19`).
Registration is a fiber effect — disposing the fiber removes the namespace
(`$PKG/dsh-settings/README.md:94`).

**The wire** — the browser learns the namespace list from `settings.describe`, which the
client reads once and mirrors. `SettingsDescriptor`
(`$PKG/dsh-settings/lib/types/index.d.ts`) carries:

```ts
export interface SettingsDescriptor {
    ns: SettingsNamespace;
    /** Serialized schemastery schema (`schema.toJSON()`). */
    schema: unknown;
    value: unknown;
    revision: number;
    base?: unknown;
    user?: unknown;
    applies: SettingsApplies;
    /** Schema-declared secret positions; present only under `redactSecrets`. */
    secrets?: RedactedSecret[];
}
```

The host side of the read is
`$PKG/dsh-api-settings-controller/lib/index.js:429`:

```js
namespaces: settings.describe({ redactSecrets: true }).map(namespaceView),
```

and the browser side is the single mirror owned by `dsh-client-ui-settings`
(`$PKG/dsh-client-ui-settings/README.md:28`, `:52-58`), exposed as
`ctx.settingsScope.describe()` and `ctx.settingsScope.bind({ namespace })`. A new direct
`settings.describe` caller in client code is a pinned regression
(`$PKG/dsh-client-ui-settings/README.md:58`).

**Browser half** — register a card:

```js
ctx.slots.inject("settings.plugin.item", () => ctx.slots.register(
  { name: "settings.plugin.item", key: "my-memory-ns" }, MyCard));
```

and bind the namespace for reads/writes through `ctx.settingsScope.bind({ namespace:
"my-memory-ns" })` — `$PKG/dsh-client-ui-settings/README.md:32`. Writes are
revision-fenced; `set`/`unset` are single-op forms of `mutate`; a `SecretField` writes
through the credentials domain, never the settings document
(`$PKG/dsh-client-ui-settings-plugins/README.md:42`, `:60`).

**Also required for a new tab entry:** either reuse the shipped `configurable` tab or add
your own `settings.plugins.tab` entry
(`$PKG/dsh-client-ui-settings-plugins/lib/client.js:1773-1784`;
`$PKG/dsh-client-ui-settings-plugin-inventory/lib/client.js:666-667`).

### 4.4 What is *not* automatic, and what a schema-driven alternative would cost

- `dsh-host-plugin-inventory` lists Loader entries for display only: "It cannot enable,
  disable, add, or remove plugins, and it carries no history"
  (`$PKG/dsh-host-plugin-inventory/README.md:40`). Its Remote is `pluginInventory/list`
  (`:12`). It has nothing to do with configuration editing.
- `dsh-plugin-package-inventory-deepseek` is something else entirely — an inventory of
  active plugin packages for official DeepSeek LLM API requests (see its `package.json`
  description and `peerDependencies` on `dsh-deepseek-llm-api-extensions`). It is **not**
  a UI or configuration package.
- `dsh-client-ui-settings-plugin-inventory` renders the read-only **Plugin list** tab
  (`$PKG/dsh-client-ui-settings-plugin-inventory/README.md:12`, `:22-32`). It writes
  nothing.
- Because `SettingsDescriptor.schema` *is* on the wire, a third-party plugin could ship a
  generic schema→form renderer. Nothing shipped does. The shipped `dsh-client-ui-settings`
  does provide the pieces: `ctx.settingsSchema.rehydrate(serialized)`,
  `.validate(schema, draft)`, `.nodeAtPath`, `.getPath`, `.hasPath`, `.setPath`,
  `.deletePath` (`$PKG/dsh-client-ui-settings/lib/types/client/schema.d.ts`). So a
  self-written generic card is realistic — it is just not free.
- Card ordering: "Tabs follow the contribution's `order`; cards follow registration
  order" (`$PKG/dsh-client-ui-settings-plugins/README.md:56`). There is no per-card order.
- The served namespace list re-reads on two signals only — settings-document commits and
  connection resets — not on registrations
  (`$PKG/dsh-client-ui-settings-plugins/README.md:97`). A namespace registered late joins
  the list only after a commit or reconnect.

---

## 5. Development loop and hot reload

### 5.1 What `pnpm run dev:web` provides

`$PKG/dsh-client-hmr/README.md:12`:

> The reload chain stays idle without a rebuild watcher: only a `pnpm run dev:web`-style
> process rewriting client bundles produces the rebuilds it reacts to.

`$PKG/dsh-client-hmr/README.md:32`:

> Run `pnpm run dev:web` (or any tsdown watch process that writes the plugin's
> `lib/client.js`) against the same host; rebuilt plugins are then swapped into the running
> browser automatically, one at a time.

What the swap does (`$PKG/dsh-client-hmr/README.md:66`): on an SSE `rebuilt` frame, the
new one-resource combo URL is selected, the new factory is prefetched while the old fiber
still serves, then registry-first teardown, drain unload, delete `entry.fiber`, remove
owned `<style data-plugin>` tags, `entry.refresh()` re-imports and remounts. React state
inside the reloaded plugin is lost; session/workspace/connection state survives
(`:116`). No rollback on failure (`:117`).

The web-app prompt text shipped to the model states the same constraint
(`$PKG/dsh-web-app/lib/index.js:92`):

> The client-plugin HMR receiver is active, but client-plugin changes reload without a
> refresh only while `pnpm run dev:web` is also running from this same checkout to rebuild
> their bundles; verify that watcher before promising automatic updates. Every other change
> — the apps/web shell and plain packages — requires rebuilding the affected Web artifacts
> and verifying this existing URL after a page refresh. Starting another server does not
> update this GUI.

### 5.2 Whether a plugin outside the monorepo can hot-reload

**Yes for the reload chain; no for `pnpm run dev:web` itself.**

- The reload chain is origin-agnostic: the node half stat-polls
  `ctx.clientModules.artifactBaseline(row.id)` for every row in the composed graph with no
  filter (`$PKG/dsh-client-hmr/lib/index.js:94-99`), and the README explicitly allows "any
  tsdown watch process that writes the plugin's `lib/client.js`"
  (`$PKG/dsh-client-hmr/README.md:32`).
- The chain is mounted unconditionally in the shipped Web profile
  (`$PKG/dsh-web-app/cordis.patch.yml`, row `- id: client-hmr`, with the comment "always
  mounted: it is idle until a rebuild watcher (pnpm run dev:web) actually rewrites client
  bundles").
- **`pnpm run dev:web` is a monorepo root script and does not exist in the published
  installation.** Verified: the root `package.json` of the install has **no `scripts` key
  at all**, and the string `dev:web` appears in no shipped `package.json`
  (`grep -rn "dev:web" $ROOT/node_modules/@deepseek-ai/*/package.json $ROOT/package.json`
  → empty). It is a root-workspace script that fans out tsdown/vite across the monorepo.
- The plugin's own `package.json` does carry the primitive: `"watch": "tsdown --watch"`
  (`$PKG/dsh-client-ui-goal/package.json`), so an external plugin can run its own watcher
  and get the same effect — as long as its tsdown config reproduces the client preset.

### 5.3 The constraint actually stated

`$PKG/dsh-client-hmr/README.md:44` points at the generated config catalog for the only
config field:

```
| `pollIntervalMs` | `500` | Bundle stat-poll interval in milliseconds |
```

and coding against the graph bundle format requires the unpublished preset (§3.5,
§6). Note also `$PKG/dsh-client-modules/README.md:46`:

> The host serves built client bundles, so `pnpm run build` must have produced each
> `lib/client.js` before launch; a missing bundle fails activation loudly with one build
> instruction and a package/path list. Source launch maps host imports to TypeScript source
> but still consumes the built client export.

---

## 6. Third-party client plugin outside the monorepo (full evidence)

### 6.1 Installation path — verified

`dsh plugin --profile <name> add <package>` forwards to pnpm inside the profile directory
and then reconciles the layer stack
(`$ROOT/lib/plugin-Ddi42qoW.js:10-16`, `:95-130`):

```js
/**
* `dsh plugin --profile <name> <args...>` — profile plugin management as a
* thin pnpm forwarder: initialize the profile on first use, run
* `pnpm <args...>` in the profile directory, then reconcile the
* `dsh.profile.bundles` layer list against the installed state (a dependency
* resolving to a package that declares `dsh.bundle` joins the layer stack; a
* removed or bundle-less dependency leaves it).
* @module @deepseek-ai/dsh/plugin
*/
```

Usage line, `$ROOT/lib/bin.js:41`: `dsh plugin --profile tui add <package>     install a plugin into the tui profile`.

`runPlugin` spawns `pnpm` with the user's args in the profile dir, and even documents the
git-hosted case (`$ROOT/lib/plugin-Ddi42qoW.js:118-129`):

```js
if (args.some((argument) => /^git\+|^github:|\.git(?:#|$)/.test(argument))) process.stderr.write(`${NAME}: git-hosted plugins build on install via their prepare script, which pnpm blocks until allowed — add the exact key pnpm printed above under allowBuilds in ${join(dir, "pnpm-workspace.yaml")}, then re-run\n`);
```

**Catch:** joining the *layer stack* requires `dsh.bundle.patch`. A dependency that
declares only `dsh.client` is installed but not layered — with an explicit warning
(`$ROOT/lib/plugin-Ddi42qoW.js:56-58`):

```js
} else if (!isBundle && !beforeDeps.has(packageName)) process.stderr.write(`${NAME}: warning: ${packageName} declares no dsh.bundle — installed as a plain dependency, not a profile layer (a later update that gains one activates it automatically)\n`);
```

So a self-contained third-party *UI* plugin should ship **both** `dsh.bundle.patch`
(a `cordis.patch.yml` that inserts its own host + `dsh.client` rows) **and** `dsh.client`.

### 6.2 External bundles are explicitly supported by the boot system — verified

`$PKG/dsh-app-boot/README.md:89`:

> **Profile module fallback.** Bare plugin specifiers resolve through the Loader from the
> config directory. Plain Node maintains one symlink per package in the installation
> dependency closure. A packaged executable instead reads each installed export map with
> Node ESM conditions and writes real proxy packages that re-export virtual module URLs...
> **A selected external bundle absent from the installation closure receives a
> profile-local `.dsh-module-fallback` link**; existing pnpm entries win, projected links
> are excluded from later closure discovery, and cleanup removes only dsh-owned links.

Implementation: `PROFILE_MODULE_FALLBACK_DIR = ".dsh-module-fallback"`
(`$PKG/dsh-app-boot/lib/index.js:316`), `ownedModulesDir = join(profile.dir,
PROFILE_MODULE_FALLBACK_DIR, "node_modules")` (`:714`).

`$PKG/dsh-app-boot/README.md:59`:

> Inserted plugin names may be absolute filesystem paths, file URLs, or package specifiers.
> Patch loading converts absolute paths and patch-relative `./` or `../` paths to file URLs
> within `insert` rows and their nested groups.

`$PKG/dsh-app-boot/README.md:50`:

> A profile is how one dsh installation ships different app surfaces... A profile lives at
> `$DSH_HOME/profiles/<name>` and combines installable bundles, its own `cordis.patch.yml`,
> and `patchReload: live | startup`. ... `dsh plugin` initializes a base-backed profile and
> manages its installed bundles. A missing bundle or one without a patch declaration fails
> startup loudly.

### 6.3 Discovery and serving have no allowlist — verified

`$PKG/dsh-client-modules/lib/index.js:67-88` (module doc) describes the scan as purely
Loader-entry-driven. The three places a monorepo path could have been hardcoded are all
package-relative:

- `resolveMeta` locates the nearest `package.json` up from the resolved module URL and
  reads `dsh.client` (`:637-667`, `:710-726`).
- The client bundle path is `join(dirname(pkgPath), clientRel)` where `clientRel` comes
  from the package's own `exports` (`:654-659`).
- `locatePkgJson` uses the Loader's own resolution first, falling back to
  `createRequire(baseUrl).resolve(<pkg>/package.json)` (`:679-709`).

The graph row id is the package name (`:826`), so nothing ties an entry to a workspace.

### 6.4 Where the monorepo assumption actually lives — verified

Three places, all build-time or type-time, none runtime:

1. **The bundler preset is not published.**
   `$PKG/dsh-client-ui-settings-plugins/README.md:96`:
   > **A card still needs a browser bundle** — the browser half must be a `dsh.client`
   > package built in the client module system's lazy-CJS factory format, and the
   > `clientBundle` preset that emits it lives in `../../../packages/client/tsdown.client.ts`
   > rather than a published package, so a plugin outside this repository has to reproduce
   > that build itself.

   Corroborated inside a bundle's own JSDoc:
   `$PKG/dsh-client-ui-settings/lib/client.js:1121-1124`
   > the client bundle purity gate forbids cross-plugin value imports and directs
   > cross-plugin collaboration through cordis services (`packages/client/tsdown.client.ts`).

   Verified absent: no package in the install is named `*tsdown*`, `*client-build*`, or
   `*vite*`, and no shipped `lib/` file implements `clientBundle`.

2. **`pnpm run build` / `pnpm run dev:web` are root scripts.** The install root
   `package.json` has no `scripts` key (`python3 -c "import json; ..."` → `False`), and no
   shipped package mentions `dev:web`. The host's error text nonetheless instructs
   `run `pnpm run build` before launch` (`$PKG/dsh-client-modules/lib/index.js:91`), which
   is a monorepo instruction leaking into runtime diagnostics.

3. **The slot/primitives type packages are not published.** `@deepseek-ai/dsh-client-ui-slots`,
   `@deepseek-ai/dsh-client-ui-primitives`, `@deepseek-ai/dsh-client-ui-dockkit`,
   `@deepseek-ai/dsh-client-store`, `@deepseek-ai/dsh-client-test-runtime` appear as
   devDependencies across client packages but exist nowhere in the install. They are
   inlined into the shell bundle (seed table, §2.5) and referenced *by name* at runtime.
   Every public `SlotMap` / `LocaleNamespaceMap` / `ResourceProtocolMap` augmentation
   targets `@deepseek-ai/dsh-client-ui-slots`
   (`$PKG/dsh-client-ui-renderer/lib/types/client/registry.d.ts:14-16`,
   `$PKG/dsh-client-ui-settings-plugins/lib/types/client/slot-contract.d.ts:16`,
   `$PKG/dsh-client-resources/README.md:44-46`), and `dsh-client-ui-renderer`'s own
   declaration re-exports from it (`$PKG/dsh-client-ui-renderer/lib/types/client/index.d.ts:9-13`).
   A TypeScript project outside the repo cannot resolve those specifiers without shims.

### 6.5 A monorepo-layout assumption that is stated outright (different subsystem)

`$PKG/dsh-package-manifest/lib/types/types.d.ts` (JSDoc on
`DshSessionFormatMigrationManifest`):

> The catalog generator discovers only packages/session/session-format-vN-to-vN+1, not
> external plugins.

This is about session-format migrations, not client UI, but it shows the codebase does
contain hardcoded `packages/...` discovery where it chooses to.

### 6.6 Verdict

| Question | Answer | Confidence |
|---|---|---|
| Can a third-party package be discovered as a client plugin? | Yes | High — code path is package-relative and Loader-driven |
| Can its bundle be served to the browser? | Yes | High — `/plugins` prefix route serves whatever the table holds |
| Can the browser boot it as a plugin? | Yes | High — the boot graph only needs `id` == package name |
| Is a monorepo checkout required? | **No** | High |
| Is a rebuild of `dsh-web-frontend/dist` required? | **No** | High — the shell is generic; plugins are separate scripts |
| Is the build preset published? | **No** | High — stated in two shipped files |
| Would I bet it works first try? | **No** | The exact preset semantics (externals are emitted as `require()` calls; `id` must be the package name; lazy-CJS factory wrapper; CSS tag convention; `//# sourceMappingURL` trailer) must be reverse-engineered and there is no shipped example of an externally built bundle. |

**If the tarballs were the only input available**, this is decidable at the architecture
level (YES) and *not* decidable at the level of "write these 30 lines of tsdown config and
it works". The honest recommendation is to prototype one bundle by hand against the format
in §3.2 before committing to the plugin design.

---

## 7. Internationalization and locale

### 7.1 Service and registration API

`ctx.locale` is a Cordis service of type `LocaleRuntime`
(`$PKG/dsh-client-locale/lib/types/client/index.d.ts:56-59`). Two registration overloads
(`:186-188`, `:198`):

```ts
/**
 * @returns disposer removing every locale registered by this call (idempotent).
 */
register<N extends Extract<keyof LocaleNamespaceMap, string>>(ns: N, dicts: Record<BuiltInLocaleId, LocaleDictOf<N>>): () => void;
register(ns: string, locale: string, dict: LocaleDict): () => void;
```

and a binder (`:203-215`):

```ts
/**
 * is stable per namespace (repeat binds return the same function), so ...
 */
bind<N extends Extract<keyof LocaleNamespaceMap, string>>(ns: N): TranslateNS<N>;
bind(ns: string): Translate;
```

Real call site (`$PKG/dsh-client-ui-settings-plugins/lib/client.js:1702-1706`):

```js
const t = ctx.locale.bind(NS);
ctx.effect(() => ctx.locale.register(NS, {
    zh,
    en
}), "ui-settings-plugins: section dictionaries");
```

`LocaleDict` is a flat `Record<string, string>` with `{name}` placeholders
(`$PKG/dsh-client-locale/lib/types/client/index.d.ts`).

### 7.2 Built-in locales, fallback chain, persistence

`$PKG/dsh-client-locale/lib/types/locale-settings.d.ts`:

```ts
/** Settings namespace owned by the locale plugin. */
export declare const LOCALE_SETTINGS_NAMESPACE = "locale";
/** Field carrying an explicit locale selection; absence delegates to the browser. */
export declare const LOCALE_PREFERENCE_FIELD = "preference";
/** Accepted BCP 47-style language ids. */
export declare const LOCALE_ID_PATTERN: RegExp;
/** Locale identifiers shipped by the browser client. */
export declare const LOCALE_IDS: readonly ["zh", "en"];
export type BuiltInLocaleId = typeof LOCALE_IDS[number];
/** Open locale identifier accepted from language-pack plugins. */
export type LocaleId = string;
```

The active locale persists in the Host settings document under namespace `locale`, field
`preference`; absence delegates to the browser. `LocaleSnapshot` carries
`{ active, locales, revision }` and the revision is bumped by registry changes so already
mounted slots re-render (`index.d.ts:47-53`, `:121-128`, `:219-223`).

Language packs are a first-class extension point
(`$PKG/dsh-client-locale/lib/types/client/index.d.ts`):

```ts
/** Input accepted when a language-pack plugin adds a selectable language. */
export interface LanguageRegistration {
    /** Stable BCP 47-style id stored as the locale preference. */
    id: LocaleId;
    /** Display name written in the represented language. */
    label: string;
    /** Registered language consulted when this language lacks a dictionary key. */
    fallback: LocaleId;
}
```

Fallback definitions "must terminate at English" (`:149-150`). A shared `common` namespace
is consulted after the entry's own namespace misses (`:19-26`).

### 7.3 Where strings physically live

Strings are compiled **into the client bundle as object literals**, not shipped as data
files. Location and shape, from real packages:

- Declaration: `$PKG/dsh-client-ui-settings-plugins/lib/types/client/locales.d.ts`

```ts
/** Locale bundles for the plugin configuration section and its plugin cards. */
/** Locale keys these surfaces render. */
export type PluginsSettingsLocaleKey = 'nav' | 'title' | 'intro' | 'tabs' | 'configurableTab' | ... ;
/** English copy. */
export declare const en: Record<PluginsSettingsLocaleKey, string>;
/** Simplified Chinese copy. */
export declare const zh: Record<PluginsSettingsLocaleKey, string>;
```

- Implementation: inlined in `$PKG/dsh-client-ui-settings-plugins/lib/client.js` under the
  region marker `//#region lib/types/client/locales.js` (`:1562`).
- Smallest readable real pair — `$PKG/dsh-client-ui-goal/lib/client.js:472-497`, region
  `lib/types/client/locales.js`:

```js
//#region lib/types/client/locales.js
/** `goal` namespace dictionaries. */
/** Simplified Chinese dictionary (the key-set source of truth). */
const zh = {
    "phase.active": "进行中的目标",
    "phase.active.disarmed": "未运行的目标",
    "phase.paused": "已暂停的目标",
    "phase.blocked": "受阻的目标",
    "objective.aria": "目标内容",
    "commandInput.aria": "指令输入",
    "action.save": "保存目标",
    "action.cancel": "取消编辑",
    "action.pause": "暂停目标",
    "action.resume": "恢复目标",
    "action.edit": "编辑目标",
    "action.clear": "清除目标"
};
/** English dictionary, checked complete against the zh key set. */
const en = {
    "phase.active": "Ongoing Goal",
    ...
```

  Note the convention stated in the comments: **`zh` is the key-set source of truth;
  `en` is checked complete against it.**
- For the locale package itself, the source files are `src/locales/{zh,en,settings,index}.ts`
  compiled to `lib/types/locales/{zh,en,settings,index}.d.ts`, visible both as the shipped
  declarations (`$PKG/dsh-client-locale/lib/types/locales/`) and as the bundle's region
  markers (`$PKG/dsh-client-locale/lib/client.js:815` `//#region lib/types/locales/zh.js`,
  `:859` `//#region lib/types/locales/en.js`, `:903` `.../settings.js`).
- **No `locales/` directory and no JSON/YAML string file ships in any client package.**
  Verified by directory listings for every `dsh-client-*` package and by the absence of any
  locale data file outside `lib/types/**/*.d.ts`.

Incidental evidence of the build environment: a CSS-module region marker in a published
bundle carries the CI checkout path —
`$PKG/dsh-client-locale/lib/client.js:910`:

```js
//#region \0dsh-css:/home/runner/work/deepseek-harness/deepseek-harness/packages/client/locale/src/client/LanguageRow.module.css.mjs
```

The same pattern appears at `$PKG/dsh-client-ui-approval/lib/client.js:10` and in most
other UI bundles. The `\0dsh-css:` prefix is a virtual module id emitted by the unpublished
client preset, and the absolute path shows the bundles are built from a monorepo checkout,
not from the tarball.

### 7.4 `README.i18n.yaml` — real file, verbatim

`$PKG/dsh-client-modules/README.i18n.yaml` (complete file):

```yaml
# Bilingual-pair consistency record (docs/i18n/README.md): the git blob hash of each
# side as of the last confirmed-consistent state. Both languages carry equal authority;
# after editing either side, bring the other along and re-record with:
#   pnpm run verify-translation-pairing --write packages/client/modules/README.md
README.md: 246293de32483adba0ee93d2d9bdbe8b8dbcd5fa
README.zh.md: 759eb5b94e63c7108013ed9b223393ba405adc33
```

`$PKG/dsh-client-ui-settings-plugins/README.i18n.yaml` (complete file):

```yaml
# Bilingual-pair consistency record (docs/i18n/README.md): the git blob hash of each
# side as of the last confirmed-consistent state. Both languages carry equal authority;
# after editing either side, bring the other along and re-record with:
#   pnpm run verify-translation-pairing --write packages/client/ui-settings-plugins/README.md
README.md: cea5dd292634fe033ba9f12c9e8fe5daedc1d2ab
README.zh.md: cc3bd4b3fcb35ce9f39fd978e3424919c66b2edc
```

Field by field:

| Key | Meaning |
|---|---|
| comment header | States the convention: the file records the git blob hash of each language side "as of the last confirmed-consistent state". |
| `README.md` | Git blob SHA-1 of the English README at the recorded state. |
| `README.zh.md` | Git blob SHA-1 of the Chinese README at the recorded state. |
| `pnpm run verify-translation-pairing --write <pkg>/README.md` | The re-record command, with the **monorepo-relative source path** of the package. |

Notes:

- It is a **docs-tooling artefact, not an i18n string bundle.** It contains no UI copy.
- It is a monorepo process record keyed on git blob hashes — it has no meaning for a
  tarball and nothing reads it at runtime.
- It is present on essentially every shipped package including the install root
  (`$ROOT/README.i18n.yaml` records `apps/cli/README.md`).
- `docs/i18n/README.md` (which defines the rule) is **not shipped**, and neither is the
  `verify-translation-pairing` script.

### 7.5 `README.md` / `README.zh.md` conventions

Every package (and the install root) ships a pair: `README.md`, `README.zh.md`,
`README.i18n.yaml`. The READMEs cross-link on their first lines, e.g.
`$PKG/dsh-client-modules/README.md:8`: `English | [中文](README.zh.md)`. Both files carry
YAML front matter with `description:` and `kind: "package-reference"` (e.g. `:1-4`).

The yaml's own header asserts equal authority for both sides ("Both languages carry equal
authority"). Nothing in the shipped tarballs states that the pair is *required*; the
consistency record plus the visible rule that both sides are edited together implies it
for repo-owned packages. Whether a third-party package must ship `README.zh.md` and
`README.i18n.yaml` is **not determinable from the shipped files** — no runtime or
build-time code reads either.

---

## 8. Web-only operational constraints

### 8.1 Content Security Policy

Grepping the whole install for `Content-Security-Policy`, `script-src`, `frame-ancestors`
and `X-Frame-Options` yields exactly **one** CSP header, and it is not on the app shell:

`$PKG/dsh-api-session-controller/lib/index.js:2315`:

```js
"Content-Security-Policy": "sandbox; default-src 'none'"
```

That is the response for a session-log / download route (a `sandbox` + `default-src 'none'`
lockdown), not the page. **No CSP is set on the served `index.html` or on `/plugins`
bundles**, and no `X-Frame-Options` or `frame-ancestors` directive appears anywhere.

Consequences for a plugin UI:

- The bundle is loaded as a **classic same-origin `<script src>`**
  (`$PKG/dsh-client-modules/lib/client.js:145-159`), which would break under a strict
  `script-src` policy — but no such policy is applied.
- The host injects an **inline** `<script>` for the `__ModuleLoader__` queue facade
  (`$PKG/dsh-client-modules/lib/index.js:389-409`) and a `__DSH_BOOT__` global row. Inline
  script would break under `script-src 'self'` without a nonce. There is no nonce mechanism.
- No `unsafe-eval` requirement is visible in the shipped client path: dynamic Cordis
  packages are evaluated with `new Function`-style closure evaluation
  (`$PKG/dsh-cordis-client-runner/README.md:71`), which *would* need `unsafe-eval` — but
  again, no CSP header exists to block it.

**Therefore: CSP is not currently a constraint, and there is no shipped CSP knob for a
plugin to declare.** If a deployment adds a reverse proxy with a strict CSP, the inline
boot facade breaks before any plugin does.

### 8.2 iframe / sandbox boundaries

The plugin UI runs **in the page's own JS realm** — there is no iframe, no worker, and no
sandbox around plugin UI. The client module system loads bundles via
`document.createElement("script")` appended to `document.head`
(`$PKG/dsh-client-modules/lib/client.js:145-159`) and materializes factories in-process
(`:272-293`).

Two narrower isolation mechanisms do exist, neither aimed at UI plugins:

- **The guard façade for dynamic Cordis packages.** A runtime-evaluated browser half is
  wrapped in a whitelist that exposes only lifecycle verbs plus declared services, and its
  symbol surface is fixed to `React`, `console`, `styles`, `host` — "browser globals like
  `fetch` and `setTimeout` are unavailable"
  (`$PKG/dsh-cordis-client-runner/README.md:32`, `:54`). A statically mounted plugin bundle
  gets **no such guard**; it has full page access.
- **A self-contained Worker** in `dsh-client-file-upload`, emitted from a function string
  (`$PKG/dsh-client-file-upload/README.md:91`).

So: a third-party UI plugin is fully trusted page code. There is no sandbox boundary to
design around, and equally no sandbox to protect it.

### 8.3 Static hosting of the shell

- `$PKG/dsh-web-frontend` **does ship the built browser bundle**. `dist/` contains
  `index.html` (679 B), `assets/index-BKQ_L1z6.js` (555 959 B), `assets/vendor-CCJJTK99.js`
  (740 575 B), two CSS files, `favicon.svg`, `manifest.webmanifest`, and font/langs
  directories. `package.json` exports only `./dist/*` and `./package.json`, and
  `files` is `["dist", "!dist/**/*.map", "!dist/preview.html", "!dist/preview"]`.
- Its own build scripts (`build: vite build`, `dev: vite`, `watch: vite build --watch`,
  plus a `build:preview` that also runs two `pnpm --filter ...` tsdown builds and
  `dsh-pack-vfs-image`) are **workspace scripts that never run from the published
  tarball** — `pnpm --filter` requires the monorepo.
- `$PKG/dsh-web-frontend/dist/index.html` is a plain Vite shell with `<div id="root">`; the
  boot protocol arrives entirely through the server's index-injection table, which is why
  it is not a standalone app: "The apps/web Vite entry builds the shell but is not a
  standalone application because only `dsh web` injects `window.__DSH_BOOT__`"
  (`$PKG/dsh-web-app/lib/index.js:92`).
- `dsh-host-frontend-static` serves the dist as a **fallback route** with 404 for missing
  paths, 403 for traversal outside the dist root, and an authorization hook for the index
  (`$PKG/dsh-host-frontend-static/lib/index.js:9`, `:44-50`, `:87-94`).
- The webserver binds `host: 127.0.0.1`, `port: 3080` by default with gzip
  (`$PKG/dsh-web-app/cordis.patch.yml`, row `- id: webserver`).

**Consequence:** a plugin must not add files to the shell dist. Its assets arrive as the
`/plugins`-served bundle; nothing else is addable without rebuilding `dsh-web-frontend`.

### 8.4 Authentication / authorization of the browser session

This applies to the **browser session**, and it is fully specified in
`$PKG/dsh-client-connection/README.md:35`, `:37`, `:39`. Verbatim (`:35`):

> Every Host RPC method and WebSocket stream requires one browser session; there is no
> method-specific loopback tier. Each process mints a random launch token. `dsh-web-app`
> prints and opens the ordinary root URL with `?token=...`; `frontend-static` delegates root
> and index requests to `ctx.connection.authorizeIndex`, which accepts that token only on
> `GET /`, writes an authority-bound signed cookie, and redirects to clean `/`. A missing,
> expired, malformed, or wrong-authority cookie returns 401 before RPC dispatch. **Static
> assets remain public.** The HTTP carrier accepts no query token outside the root exchange
> and no `Authorization`-header token.

> The cookie signing secret is the owner-scoped `client-connection/browser-session` grant
> record in `ctx.credentials`. The local provider persists it in
> `$DSH_HOME/.credentials.yaml`; `BrowserAuth` loads or creates the record during Connection
> activation and retains the secret in memory, so request authentication is synchronous.
> ... Cookies carry an absolute issue/expiry interval, defaulting to 30 days through
> `cookieMaxAgeDays`, and bind the normalized hostname plus port in both their deterministic
> name and signed payload. They are host-only, `Path=/`, `HttpOnly`, and `SameSite=Strict`;
> they deliberately omit `Secure` because the shipped server uses loopback HTTP.

> Before authentication, every request still passes `src/api-request-trust.ts`. Its `Host`
> must be loopback or match a `trustedHosts` entry: exact on `host:port`, any port on
> port-less entries, both sides WHATWG-normalized. An attached `Origin` must equal that Host
> and `sec-fetch-site: cross-site` is refused. Malformed configured authorities fail plugin
> load. These checks defend DNS rebinding and cross-site browser requests; they never
> establish identity. A failed Host/Origin check returns 403, while a trusted but
> unauthenticated request returns 401. `dsh web --host 0.0.0.0` remains unsupported.

Implementation corroboration: the fallback static handler passes `serveStatic` an
`authorizeIndex` hook, and that hook is used only for the dist root / configured index path
(`$PKG/dsh-host-frontend-static/lib/index.js:49`, `:87-95`);
`authorizeIndex` is a method of the connection service
(`$PKG/dsh-client-connection/lib/index.js:386`), and the trust fence is
`isTrustedApiRequest(request, trustedHosts)` (`:201-206`) with
`isLoopbackHostname(...) || isTrustedAuthority(...)`.

**Three consequences for a plugin UI:**

1. **`/plugins/<pkg>/client.js` is public.** It is registered as an ordinary prefix route on
   the webserver (`$PKG/dsh-client-modules/lib/index.js:480-485`) and static assets are
   explicitly public. A plugin's browser code is readable by anyone who can reach the port;
   only its `/api` calls carry the session cookie.
2. **Any custom HTTP route a plugin registers is also public** unless it routes through the
   connection's exact-route registries. `ctx.webServer.register` gives raw
   `(req, res)` ownership with no auth
   (`$PKG/dsh-host-webserver/lib/types/index.d.ts:30-39`). A memory plugin exposing its own
   `/memory` route would be exposing it unauthenticated.
3. **Non-loopback pages get no durable settings.** `$PKG/dsh-client-ui-settings/README.md:97`:
   > **Non-loopback pages get no durable settings** — this Client keeps Host persistence
   > disabled there, so a scope starts `unavailable` and never crosses the wire; every row it
   > backs is inert even though Connection authentication covers the API.

   If the user opens the GUI from a non-loopback address, a settings-backed configuration
   UI is inert. A memory plugin whose only storage is the settings document becomes
   unusable over LAN. Combined with `dsh web --host 0.0.0.0` being unsupported, the shipped
   deployment posture is loopback-only.

**`@deepseek-ai/dsh-authorization` is NOT browser-session authentication.** Its description
is "Authorization seam (`ctx.authorization`): plugin-owned flows that obtain a credential
through a conversation with the human"
(`$PKG/dsh-authorization/package.json:3-4`), and its README calls it "The authorization flow
registry ... obtain credentials that configuration cannot supply" — OAuth-style sign-in,
one-time codes, account picks (`$PKG/dsh-authorization/README.md:2`, `:12`, `:20-28`). It is
irrelevant to how the browser session is authenticated; that is entirely
`dsh-client-connection` + `dsh-credentials`. If a memory plugin needs, say, a hosted-vector-store
API key obtained by OAuth, *this* is the package to use.

### 8.5 Other constraints worth designing around

| Constraint | Evidence |
|---|---|
| Every client bundle is held in host memory (bundle + source map + combo responses, plus one prior HMR generation) | `$PKG/dsh-client-modules/README.md:120` |
| Bundle combo URLs are capped at 3 KiB per phase, so a plugin bundle is partitioned but its identity is per-package | `$PKG/dsh-client-modules/lib/index.js:123-124`, `:70` |
| Advertised responses are immutable and an unknown combination/revision 404s | `$PKG/dsh-client-modules/README.md:70` |
| Client bundles execute lazily; nothing runs until the plugin is first used | `$PKG/dsh-client-modules/README.md:12`, `lib/client.js:16-23` |
| Only nine module-table words are seeded; anything else must be a graph row or a declared `external` | `$PKG/dsh-web-frontend/dist/assets/index-BKQ_L1z6.js` (seed fn), `$PKG/dsh-client-modules/README.md:42` |
| A require cycle across factories is fatal at runtime | `$PKG/dsh-client-modules/lib/client.js:278` |
| Cross-plugin value imports are forbidden by the build gate | `$PKG/dsh-client-ui-settings/lib/client.js:1121-1124` |
| A render crash in a slot entry can abdicate the entry from its cell | `$PKG/dsh-client-ui-renderer/lib/types/client/registry.d.ts:171-184` |
| The settings namespace list refreshes only on document commits and reconnects | `$PKG/dsh-client-ui-settings-plugins/README.md:97` |
| `immediately: true` exists and marks stage-one prefetch (registration barrier); used by shell-critical packages only (`dsh-client-modules`, `dsh-client-ui-renderer`, `dsh-client-connection`, `dsh-client-ui-theme`, `dsh-client-locale`, `dsh-api-gateway`, `dsh-api-remotes`, `dsh-typert-registry`, `dsh-client-hmr`, `dsh-client-file-upload`) | `dsh.client.immediately` in each `package.json`; semantics `$PKG/dsh-package-manifest/lib/types/types.d.ts:38-39` |

---

## Gaps / could not determine

Stated plainly rather than guessed:

1. **The client build preset's contents.** `packages/client/tsdown.client.ts` is named in
   two shipped files but not published. Everything about "how to emit a conforming bundle"
   in §3.2/§3.5 is reverse-engineered from emitted output plus the host-side validator. The
   *exact* tsdown/rollup options (external list derivation, `id` injection, CSS-module
   transform, sourcemap handling) are unknown.
2. **No shipped example of an externally built client bundle.** The
   `slot-contract.d.ts:7-10` statement that an out-of-repo plugin can contribute a card is
   an assertion in a type JSDoc, not a demonstrated build. I could not verify that the
   documented path has ever been exercised.
3. **`dsh-authorization`'s relation to a plugin.** Resolved: it is not browser-session
   authentication at all — it is the credential-acquisition flow registry
   (`$PKG/dsh-authorization/package.json:3-4`, `README.md:12`, `:20-28`). It is not
   referenced by the web profile patch, so it is opt-in for plugins that need a
   human-guided sign-in.
4. **Origin of `trustedHosts`.** The patch shows `webRuntime.trustedHosts` is sampled "after
   the server binds", but the sampling rule for LAN literals lives in `dsh-web-app/lib/*`
   beyond what was read. The connection README states the trust fence accepts loopback plus
   `trustedHosts` entries and that `--host 0.0.0.0` is unsupported
   (`$PKG/dsh-client-connection/README.md:39`); whether an arbitrary LAN origin can reach
   `/plugins` (which is public, §8.4) was not tested.
5. **Whether a third-party package must ship `README.zh.md` / `README.i18n.yaml`.** No
   shipped code reads either; no shipped statement requires them. `docs/i18n/README.md`
   and `verify-translation-pairing` are not published, so the rule itself is unavailable.
6. **Whether `dsh-client-ui-slots` will ever be published.** It is referenced by name at
   runtime (seed word) and by type from at least five shipped packages, yet it is absent
   from npm-side resolution here. Whether that is deliberate (bundled-only) or an
   packaging gap could not be determined from the tarballs.
7. **Behaviour without the HMR package.** `dsh-client-hmr` is the only caller of
   `clientModules.rebuilt()`. A deployment that omits it has no way to refresh a bundle
   short of a page reload — not verified experimentally, inferred from the "only entry
   point through which bundle content changes reach the graph" comment
   (`$PKG/dsh-client-modules/lib/types/index.d.ts`).
8. **The `main` slot's Session binding.** `main` is documented as "other keys receive no
   Session binding" (`$PKG/dsh-cordis-client-runner/lib/client.js:3375-3376`). Whether a
   plugin can obtain per-session data in a `root`-scoped panel (needed for "memories of
   this session") without going through `conversation.*` session-scoped slots was not
   established.
9. **The exact `SlotCore.register` overload surface.** `SlotRegistry.register` is declared
   as `readonly register: SlotCore['register']`
   (`$PKG/dsh-client-ui-renderer/lib/types/client/registry.d.ts:84`) where `SlotCore` lives
   in the unpublished `dsh-client-ui-slots`. The observable shape is reconstructed from 61
   generated examples in `dsh-cordis-client-runner/lib/client.js`; a field of the options
   object could still be missed.
