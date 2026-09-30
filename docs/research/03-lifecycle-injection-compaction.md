# DSH plugin seams: lifecycle injection, compaction, background work

Install root: `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/`
Bundled packages: `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/<pkg>/`
All citations are `absolute-path:line` into **that installation**, read with `read`/`grep`. No file under the install root was modified.

## Verified facts vs. inferred

- **Verified**: every signature, field name, and mechanism below is quoted from a file in the install, with a line citation. Where a claim is about *behavior*, the citation is the compiled implementation (`lib/index.js`, readable, not minified) that performs it.
- **Verified by type + implementation cross-check**: the `agent/pre-step`, `agent/session-start`, `agent/turn-stopping`, `agent/request`, `compaction/*`, `ctx.jobs`, `ctx.tokenMeter`, `ctx.invariants` contracts. Their `.d.ts` declarations and their consumers agree.
- **Reconstructed**: code blocks marked `RECONSTRUCTED FROM TYPES` were written by composing the declared types with the patterns the shipped plugins use. They are **not** copied from a shipped source file and were not compiled or executed.
- **Uncertain / not determinable**: collected in "Gaps / could not determine". The most consequential one: the `'compact'` value of `SessionStartSource` is declared but **no shipped emitter was found**, so a spec that relies on session-start to re-inject after compaction rests on an unverified seam. Re-injecting from `agent/pre-step` plus observing `compaction/end` on `session/event` is verified.
- Only compiled `lib/` ships in this install (`src/*.ts` is absent; `package.json` maps `"./src/*": "./src/*"` but no `src/` directory exists). All line numbers are compiled-`lib` line numbers, not source line numbers. README `src/index.ts` links could not be checked.

---

## 1. `agent/pre-step`

### Declaration

`/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-agent/lib/types/runtime-types.d.ts:302-319`

```ts
'agent/pre-step'(this: Scoped<Agent>, payload: {
    agent: Agent;
    messages: UserMessage[];
    turn: number;
    step: number;
    signal: AbortSignal;
}, next: () => Promise<PreStepDecision>): Promise<PreStepDecision>;
```

Doc (same lines): "Reject a proposed step or replace the messages that enter it. Calling `next()` preserves the current messages." `@mode waterfall`. Scope-filtered: agent-scoped listeners receive only that agent (`runtime-types.d.ts:310`).

### `PreStepDecision`

`/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-agent/lib/types/runtime-types.d.ts:91-99`

```ts
export type PreStepDecision = {
    kind: 'reject';
} | {
    kind: 'enter';
    messages: UserMessage[];
    /** Start a distinct model-message series before this step's admitted messages. */
    startsRequestSeries?: true;
};
```

`startsRequestSeries` is consumed by the loop as `firstAttempt && decision.startsRequestSeries === true` and OR-ed into the system-prompt series decision — `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-agent-loop/lib/index.js:1018-1023`.

### How a listener appends a durable message, and where it lands

The loop builds the default decision itself. `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-agent-loop/lib/index.js:887-908`:

```js
async preStep(target, position) {
    if (this.phase.kind !== "running") throw ...
    const signal = this.phase.abort.signal;
    const claimed = this.inbox.claim(target, position.turn);          // 889
    const assembly = await this.loopCtx.systemPrompt.assemble(...);   // 890
    const sections = renderContextSections(assembly);                 // 892
    const context = this.runtimeContext.project(joinContextSections(sections), sections); // 893
    const decision = await this.dispatch.waterfall("agent/pre-step", { // 894
        messages: claimed, ...position, signal
    }, () => Promise.resolve({
        kind: "enter",
        messages: context === void 0 ? claimed : [...claimed, context]  // 899
    }));
```

So the entering batch is `[...claimed, runtimeContextSnapshot]` by default. `claimed` is every pending `next-step` message followed by one queued `next-turn` prompt — `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-agent-loop/lib/index.js:104-110`:

```js
claim(target, turn) {
    const claimed = this.mutate("next-step", 0, this.nextStep.length, [], false);
    if (target === "next-turn") claimed.push(...this.mutate("next-turn", 0, 1, [], false));
```

Therefore **the position of an appended message is a choice**:

- `messages: [...decision.messages, msg]` → lands **after** the runtime-context snapshot. Shipped precedent: `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-time-context/lib/index.js:229-246`.
- Insert immediately after the last claimed message → lands **between the claimed user input and the runtime-context snapshot**. Shipped precedent: `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-agent-instructions/lib/index.js:1282-1287`:
  ```js
  const lastClaimedIndex = decision.messages.findLastIndex((message) => messages.includes(message));
  const entered = decision.messages.toSpliced(lastClaimedIndex + 1, 0, desired);
  ```
  Note the `messages` bound to the payload at line 894 is the *original* `claimed` array, so `messages.includes(...)` identifies the claimed prefix even after earlier listeners rewrote the batch.

Durability: every message in `decision.messages` is appended as a real `user/message` event, only on the first attempt of the step — `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-agent-loop/lib/index.js:1029`:

```js
if (firstAttempt) for (const message of decision.messages) this.session.append("user/message", message, { surfaceOp: "append" });
```

Retries do **not** re-run pre-step: "Retries reuse the same rendered assembly without repeating assembly, `agent/pre-step`, or user admission" — `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-agent-loop/README.md:119`.

Rejection: a `{ kind: 'reject' }` decision ends the turn as `blocked` and the claimed message "is neither discarded nor re-emitted as a `user/message`" — `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-agent/lib/types/runtime-types.d.ts:262-276`; loop path `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-agent-loop/lib/index.js:941-944`.

A listener that wants only to append **must call `next()` first** and spread the resolved decision; both shipped plugins do exactly that (`dsh-time-context/lib/index.js:216-219`, `dsh-agent-instructions/lib/index.js:1271-1284`). A listener that returns without calling `next()` short-circuits every later listener.

### `UserMessage` shape

`/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-llm/lib/types/message.d.ts:119-133`

```ts
export interface Message {
    /** Stable identity preserved across every representation boundary. */
    readonly id: MessageId;
    /** Provider-neutral conversation role. */
    readonly role: 'system' | 'user' | 'assistant';
    /** Exact model-facing blocks. */
    readonly content: ContentBlock[];
    /** Required source fields supplied by the producer. */
    readonly source: MessageSource;
}
export interface UserMessage extends Message {
    readonly role: 'user';
}
```

Constructor (`message.d.ts:175-183`):

```ts
export declare function createUserMessage<T extends NewUserMessage>(input: T & {
    readonly id?: never;
    readonly role?: never;
}): T & Pick<UserMessage, 'id' | 'role'>;
```

where `NewUserMessage = Omit<UserMessage, 'id' | 'role'>` (`message.d.ts:155`). `MessageId` is branded and assigned by the constructor; callers must not supply it. Text block: `{ type: 'text'; text: string }` — `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-llm/lib/types/types.d.ts:39-42`.

### Plugin-attributed `source` variants — the full enumeration

Base kind (`message.d.ts:94-104`):

```ts
export interface MessageSourceMap {
    user: { kind: 'user' };
    plugin: { kind: 'plugin'; plugin: string } & ContextFormed;
    model: ModelMessageSource;   // { kind: 'model'; provider; model; replayState? }
    tool: ToolMessageSource;     // { kind: 'tool'; callId }
}
```

`plugin` is the only plugin-attributable kind; it intersects the `ContextFormed` union, so `form` selects exactly one arm (`message.d.ts:71-89`):

| `source` shape | Declared at | Meaning (verbatim from the doc) | Appropriate for a bounded memory document? |
|---|---|---|---|
| `{ kind:'plugin', plugin }` (no `form`) | `message.d.ts:72` (`form?: never`) | "an undeclared context is the documented default" (`message.d.ts:68-69`) | Valid but presentation-blind. Acceptable fallback. |
| `{ kind:'plugin', plugin, form:'instructions' }` | `message.d.ts:74` | "Instructions read out of workspace files the model is expected to follow" (`message.d.ts:43-44`) | **No** — memory is not file instructions. This is `agent-instructions`' form. |
| `{ kind:'plugin', plugin, form:'catalog' }` | `message.d.ts:76` | "A catalog of items available in this session, republished as it changes" (`message.d.ts:45-46`) | **No** — a memory document is not a catalog of items. |
| `{ kind:'plugin', plugin, form:'snapshot', sections: readonly { name: string; text: string }[] }` | `message.d.ts:77-80` (+ `ContextSnapshotSection` at `56-61`) | "Current state, where a later snapshot from the same producer supersedes an earlier one" (`message.d.ts:47-48`) | **Yes — best fit.** A memory document re-published at session start and after compaction is superseding state. This is exactly what `dsh-time-context` uses. |
| `{ kind:'plugin', plugin, form:'notice', summary: string }` | `message.d.ts:81-84`; `summary` bounded to 120 chars by `CONTEXT_SUMMARY_MAX_CHARS` (`110`) / `boundContextSummary` (`116`) | "A one-off account of something that just happened; it supersedes nothing" (`message.d.ts:49-50`) | **Yes, for the compression result only.** The notice rides "a collapsed transcript row" (`message.d.ts:106-109`). Not for the memory body. |
| `{ kind:'plugin', plugin, form:'relay' }` | `message.d.ts:86` | "A message another agent addressed to this one" (`message.d.ts:51-52`) | Only if the memory was written by another agent. |
| `{ kind:'plugin', plugin, form:'recall' }` | `message.d.ts:88` | "Material lifted out of another session's log, possibly reduced on the way in" (`message.d.ts:53-54`) | **Yes** if memories are recalled from another session's log; otherwise no. |

The union is **merge-extensible**: a plugin may add its own `kind` by declaration-merging `MessageSourceMap`. Shipped precedent — `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-agent-instructions/lib/types/state.d.ts:24-28`:

```ts
declare module '@deepseek-ai/dsh-llm' {
    interface MessageSourceMap {
        'agent-instructions': AgentInstructionSource;
    }
}
```

used at `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-agent-instructions/lib/index.js:766-778`. A memory plugin that needs structured provenance beyond the built-in forms can do the same; `switch` on `kind` and fall through unknowns (`message.d.ts:117`).

Note the vocabulary rule: "The vocabulary is SEMANTIC, never visual ... Colors, icons, ordering, and collapse defaults are the consumer's business and must not enter this union." (`message.d.ts:35-41`).

### Reconstructed — appending at pre-step

```js
// RECONSTRUCTED FROM TYPES — not copied from any shipped source file.
import { createUserMessage } from '@deepseek-ai/dsh-llm';

const name = 'optmem';

ctx.on('agent/pre-step', async ({ agent, messages, step, signal }, next) => {
  const decision = await next();
  if (decision.kind === 'reject' || signal.aborted) return decision;

  const text = renderMemoryDocument(agent); // bounded; see item 5
  if (text === undefined) return decision;

  const message = createUserMessage({
    content: [{ type: 'text', text }],
    source: {
      kind: 'plugin',
      plugin: name,
      form: 'snapshot',
      sections: [{ name, text }],
    },
  });

  // Option A: after the runtime-context snapshot (matches dsh-time-context).
  return { ...decision, messages: [...decision.messages, message] };

  // Option B: immediately after the claimed input, before runtime context
  // (matches dsh-agent-instructions). `messages` is the payload's claimed batch.
  // const at = decision.messages.findLastIndex((m) => messages.includes(m));
  // return { ...decision, messages: decision.messages.toSpliced(at + 1, 0, message) };
});
```

Also available and cheaper than pre-step when the plugin only wants to queue context: `Agent.inject(message)` — `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-agent/lib/types/runtime-types.d.ts:201-209`, implemented as `this.send(input, "next-step", false)` at `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-agent-loop/lib/index.js:795-797`. Its documented hazard: "It may miss a request whose pre-step already claimed its batch" (`runtime-types.d.ts:205-207`). `inject` is still the right call at session start (item 2) and from a background job reporter (item 10).

---

## 2. `agent/session-start`

### Declaration and payload

`/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-agent/lib/types/runtime-types.d.ts:288-301`

```ts
/**
 * The session lifecycle began, once before the first turn. Use
 * `agent.inject()` to seed model-facing context. This is a notification, not
 * a veto; disposal requested by a lifecycle owner is rechecked before the
 * driver starts.
 */
'agent/session-start'(this: Scoped<Agent>, payload: {
    agent: Agent;
    source: SessionStartSource;
}): void;
```

`@mode emit`. Scope-filtered (`runtime-types.d.ts:295`). Fires once, before the first turn.

### All `SessionStartSource` values

`/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-agent/lib/types/runtime-types.d.ts:104-105`

```ts
/** Why a session lifecycle began; seeded creates are `startup`, while persisted loads are `resume`. */
export type SessionStartSource = 'startup' | 'resume' | 'clear' | 'compact';
```

### When `'compact'` occurs — **not determinable from the shipped install**

The emitter is one line, parameterized by `source`:

- `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-agent-loop/lib/index.js:1720` — `emitAgentEvent(loopCtx, agent, "agent/session-start", { source });` inside the `publish` closure built by `prepare(...)`.
- `setupAndPublish(ownerCtx, id, preparation, agentOptions, setup, signal, source, stored, parentAgent)` takes `source` as a parameter — `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-agent-loop/lib/index.js:1840`.

Grep over all shipped packages found exactly three call sites, all `'startup'` or `'resume'`:

- `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-agent-loop/lib/index.js:1763` — `return prepared.publish("startup").agent;` (create)
- `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-agent-loop/lib/index.js:1834` — `... "startup", stored, options.parentAgent` (create with stored session)
- `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-agent-loop/lib/index.js:1925` — `... "resume", owned, options.parentAgent` (resume)

`'clear'` and `'compact'` have **no emitter** in this install. `dsh-command-compact` does not republish a session; it calls `ctx.compaction.compactNow(...)` — `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-command-compact/lib/index.js:54`. See Gaps.

### Can a listener inject at session start? Yes, and it reaches the first request

Ordering, from the shipped creation transaction — `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-agent-loop/README.md:111`:

> "Creation is one rollback-covered transaction: construct a private session, concrete agent, and scoped context; await optional setup with the context and Agent passed separately; enter both registries; announce `session/created` then `agent/created`; emit `agent/session-start`; **only then start the driver**."

So at `agent/session-start` no pre-step has run and no batch has been claimed. A listener that calls `agent.inject(message)` **synchronously** places the message at the tail of `inbox.nextStep`; it is claimed at the first turn boundary (`target = "next-turn"`) **before** the queued prompt, because `claim` drains all of `next-step` first and then takes one `next-turn` item — `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-agent-loop/lib/index.js:104-110` (also `let target = "next-turn";` at `:932`). It is then committed as a durable `user/message` at `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-agent-loop/lib/index.js:1029`.

**It can miss the first request only if the listener does asynchronous work before injecting.** `inject` itself is synchronous; the documented miss window ("may miss a request whose pre-step already claimed its batch", `runtime-types.d.ts:205-207`) cannot apply at session start because no pre-step has run. The shipped Claude Code bridge demonstrates the failure mode to avoid — `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-hooks-claude-code/README.md:175`: "The hook runs detached, so context can miss the first request."

Practical conclusion for the spec: do **not** depend on `source === 'compact'`. Inject synchronously at `agent/session-start`, and additionally re-inject from `agent/pre-step` (item 1) and/or on `compaction/end` observed through `session/event` (item 7). Pre-step is the only seam verified to run before *every* request.

### Reconstructed — session-start injection

```js
// RECONSTRUCTED FROM TYPES — not copied from any shipped source file.
import { createUserMessage } from '@deepseek-ai/dsh-llm';

ctx.on('agent/session-start', ({ agent, source }) => {
  // source is 'startup' | 'resume' | 'clear' | 'compact'; 'compact' has no
  // shipped emitter, so never branch on it exclusively.
  if (isSubagent(agent)) return;                  // item 9

  const text = loadBoundedMemoryDocument(agent);  // MUST be synchronous here
  if (text === undefined) return;

  // inject() is synchronous, does not wake the driver, and lands in next-step,
  // which the first turn boundary claims BEFORE the queued prompt.
  agent.inject(createUserMessage({
    content: [{ type: 'text', text }],
    source: {
      kind: 'plugin',
      plugin: 'optmem',
      form: 'snapshot',
      sections: [{ name: 'optmem', text }],
    },
  }));
});
```

---

## 3. `agent/turn-stopping`

### Declaration and payload

`/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-agent/lib/types/runtime-types.d.ts:379-400`

```ts
/**
 * The turn is about to close: the model owes no response (no live tool
 * calls, no fresh steering). Awaited before the boundary commits — a
 * listener that objects steers (`agent.steer(...)`) and the machine
 * re-reads its inbox: fresh steering runs another step, none closes the
 * turn. Data decides, so listener order cannot change the outcome. ...
 */
'agent/turn-stopping'(this: Scoped<Agent>, payload: {
    agent: Agent;
    turn: number;
    signal: AbortSignal;
}): Promise<void> | void;
```

`@mode serial`. Scope-filtered (`runtime-types.d.ts:393`).

### Exact return shape

`Promise<void> | void`. There is **no** return-value protocol — the listener cannot return a decision. It forces another step by **writing data into the inbox**.

### The steering mechanism

Dispatch site and re-read — `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-agent-loop/lib/index.js:965-974`:

```js
signal.throwIfAborted();                                         // 965
if (turnEnds && this.inbox.nextStep.length === 0) {              // 966
    await this.dispatch.serial("agent/turn-stopping", {          // 967
        turn,                                                    // 968
        signal                                                   // 969
    });                                                          // 970
    signal.throwIfAborted();                                     // 971
}                                                                // 972
if (turnEnds && this.inbox.nextStep.length === 0) break;         // 973
target = "next-step";                                            // 974
```

The listener calls `agent.steer(message)`; implementation `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-agent-loop/lib/index.js:792-794`:

```js
steer(input) {
    this.send(input, "next-step", true);
}
```

`wakeup = true`; because the driver is already running, `send` (`:786-791`) appends to `next-step` and the armed `wakeDriver` is a no-op for a live driver. The `while (true)` at `:936` then loops with `target = "next-step"` and the fresh steering is claimed at `:104`. Doc for `steer` — `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-agent/lib/types/runtime-types.d.ts:193-200`.

Guard condition: the dispatch runs **only when the inbox has no pending next-step work** (`:966`), and the turn closes **only when that inbox is still empty after the serial dispatch** (`:973`). Also stated at `runtime-types.d.ts:388-389`: "The conclusion never short-circuits already-submitted next-step work: same-step `additionalContexts` or racing steering still runs, and the turn closes only when that inbox drains."

Shipped precedent for using this seam to bound runaway turns — `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-agent-loop/README.md:200`: "a policy that bounds runaway turns must cancel from an existing lifecycle extension point such as `agent/turn-stopping`."

---

## 4. `agent/request`

### Declaration

`/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-agent/lib/types/runtime-types.d.ts:320-341`

```ts
/**
 * Replace the frozen call configuration. `await next()` yields the config
 * the machine would use (agent options on the first request, the logged
 * header afterwards); return a replacement to switch. On step admission,
 * this runs after assembly and `step/start`, before the system prompt and
 * accepted user batch are committed. Cancellation here or during subsequent
 * `prepareCall()` resolution commits neither. The prepared call capability
 * governs prompt admission. Model-visible content must use logged channels;
 * this waterfall cannot mutate messages.
 */
'agent/request'(this: Scoped<Agent>, payload: {
    agent: Agent;
    turn: number;
    step: number;
    signal: AbortSignal;
}, next: () => Promise<LlmCallConfig>): Promise<LlmCallConfig>;
```

### When it runs relative to pre-step

Verified by the loop's own call order:

1. `agent/pre-step` waterfall — `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-agent-loop/lib/index.js:894`
2. decision accepted; step/start appended — `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-agent-loop/lib/index.js:951-954`
3. `this.step(decision)` — `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-agent-loop/lib/index.js:957`
4. `await this.prepareRequest(turn, step, signal)` inside `while (true)` — `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-agent-loop/lib/index.js:1016-1017`
5. `agent/request` waterfall — `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-agent-loop/lib/index.js:1141-1145`
6. `ctx.llm.prepareCall(proposedConfig, signal)` — `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-agent-loop/lib/index.js:1148`
7. system-prompt commits, then the accepted user batch — `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-agent-loop/lib/index.js:1023-1029`

It runs **once per model attempt**, including retries (`prepareRequest` sits inside `while (true)`), not once per step.

### What it may mutate

Exactly one thing: the return value, an `LlmCallConfig` (`/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-llm/lib/types/call-config.d.ts:16-23`):

```ts
export interface LlmCallConfig {
    provider: string;
    model: string;
    reasoningEffort?: ReasoningEffortId;
    temperature?: number;
    maxTokens?: number;
    stop?: string[];
}
```

The proposal is deep-frozen before the waterfall (`deepFreeze(structuredClone(...))`, `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-agent-loop/lib/index.js:1138-1145`), so mutation in place throws; a listener must return a new object. The returned config is then normalized by the adapter (`prepareCall`), and the loop logs a changed header rather than letting per-call drift pass silently (`call-config.d.ts:1-7`).

### What it may **not** mutate

- **Messages.** Verbatim: "Model-visible content must use logged channels; this waterfall cannot mutate messages." (`runtime-types.d.ts:327-328`). The payload has no `messages` field at all.
- **Tools or the system prompt.** Those are decided by `systemPrompt.assemble(...)` at pre-step (`:890`) and `assembly.tools`; `startsRequestSeries` and the prepared call capability govern prompt admission (`README.md:121`).
- **Anything durable.** It is not a logging path.

### What it is for

Route/model selection and sampling for one request: switching model per turn, downgrading for a cheap step, enforcing a max-token cap. It cannot carry injected content. Shipped users: `dsh-agent-loop/README.md:32` ("a model call additionally requires both `provider` and `model` — `agent/request` may supply a missing pair before dispatch") and `README.md:51` (reasoning-effort override). `dsh-agent-loop/lib/index.js:1150-1151` throws `agent "<id>" has no provider/model ... or supply both via the agent/request waterfall` if the resolved config is incomplete.

---

## 5. Worked template: `@deepseek-ai/dsh-agent-instructions`

Package root for this section: `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-agent-instructions/`.

### README orientation

- `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-agent-instructions/README.md:86` — "Baseline and refresh messages are ordinary sourced `user/message` events, so they replay, compact, and resume exactly like other history ... The plugin owns the complete `<system-reminder>` framing and every injected message reaches the model verbatim."
- `README.md:102` — main flow: "At the first eligible `agent/pre-step` of a session, the plugin composes the baseline and folds it into the entering batch right after the claimed messages."
- `README.md:106` — invariants: typed source with the change list; baseline identity; no hidden state markers; `</system-reminder>` escaping.
- `README.md:215` — refresh is touch-driven; "or when an entering pre-step restores a shadowed baseline".

### 5.1 How it composes and frames the injected message

Frame constants — `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-agent-instructions/lib/index.js:111-116`:

```js
const SYSTEM_REMINDER_OPEN = "<system-reminder>";
const SYSTEM_REMINDER_CLOSE = "</system-reminder>";
const WORKSPACE_CONTEXT_INTRO = "The following workspace instructions may be relevant to your work. ...";
const REPLACEMENT_WORKSPACE_CONTEXT_INTRO = "This complete workspace instruction baseline replaces all earlier workspace instruction baselines. ...";
const EMPTY_REPLACEMENT_WORKSPACE_CONTEXT_INTRO = "This complete workspace instruction baseline replaces all earlier workspace instruction baselines. No workspace instructions are currently active.";
const COMPACT_WORKSPACE_CONTEXT_INTRO = "Workspace instructions were omitted or truncated to fit the configured byte budget.";
```

Frame assembly — `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-agent-instructions/lib/index.js:256-266`:

```js
function buildInstructionText(files, maxBytes, omitted, truncated, style) {
    return [
        SYSTEM_REMINDER_OPEN,
        escapeInstructionFrameBody([
            markerText(maxBytes, omitted, truncated),
            style.intro,
            ...files.map((file) => style.section(file))
        ].filter((block) => block.length > 0).join("\n\n")),
        SYSTEM_REMINDER_CLOSE
    ].join("\n");
}
```

Per-file section text — `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-agent-instructions/lib/index.js:130-132` and `191-…`:

```js
function sectionText(file) {
    return `Instructions from: ${file.displayPath}\n\n${file.content}`;
}
```

Message construction. Two source shapes exist:

- the plain renderer used for the message *body* extracted in `compose` — `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-agent-instructions/lib/index.js:784-794`:
  ```js
  function workspaceContextMessage(text) {
      return createUserMessage({
          content: [{ type: "text", text }],
          source: { kind: "plugin", plugin: name }   // name === "agent-instructions" (:765)
      });
  }
  ```
- the durable baseline/delta message actually pushed — `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-agent-instructions/lib/index.js:1169-1178` and `1199-1208`:
  ```js
  createUserMessage({
      content: baselineContent,
      source: {
          kind: "agent-instructions",
          form: "instructions",
          baseline: true,
          baselineIdentity: identity,
          changes: baselineChanges
      }
  })
  ```
  i.e. a **merge-extended source kind** (`lib/types/state.d.ts:24-28`), which is how it carries structured provenance (`baseline`, `baselineIdentity`, `changes`) without putting state markers into model-visible text. The README makes that an explicit invariant at `README.md:106`.

Composition is a message factory that concatenates multiple producers' content and one merged `changes` list — `lib/index.js:1110-1209`: the baseline blocks are pushed at `:1160-1161`, reconciliation blocks at `:1192`, and the final single `createUserMessage` at `:1199-1208`.

Entry into the batch — `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-agent-instructions/lib/index.js:1270-1288`:

```js
ctx.on("agent/pre-step", async ({ agent, messages, step, signal }, next) => {
    const decision = await next();
    await waitForProjections(agent);
    const pending = agent.inbox.nextStep.filter(isWorkspaceContext);
    const desired = await compose(agent, signal, messages, pending);
    signal.throwIfAborted();
    if (decision.kind === "reject" || step === 1 && decision.messages.length === 0) {
        syncInbox(agent, messages, desired);
        return decision;
    }
    for (const message of pending) agent.inbox.remove(message.id);
    if (desired === void 0 || decision.messages.some((message) => sameContextPayload(message, desired))) return decision;
    const lastClaimedIndex = decision.messages.findLastIndex((message) => messages.includes(message));
    const entered = decision.messages.toSpliced(lastClaimedIndex + 1, 0, desired);
    return { ...decision, messages: entered };
});
```

Note the guard at `:1276`: a rejected decision **does not** consume the composed context; it is parked in `inbox.nextStep` instead (`syncInbox`), and a first step with no admitted messages is treated the same way.

### 5.2 How it escapes literal `</system-reminder>` text

`/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-agent-instructions/lib/index.js:127-129`:

```js
function escapeInstructionFrameBody(body) {
    return body.replaceAll(SYSTEM_REMINDER_CLOSE, "<\\/system-reminder>");
}
```

The replacement string is the five+ characters `<\/system-reminder>` (backslash inserted before the slash). Applied to the **entire frame body** — marker notice, intro, and every file section — at `:259`, and again at `:358` and `:359` for the degraded notices. The opening tag is not escaped. Rationale, verbatim at `README.md:106`: "literal `</system-reminder>` text anywhere in instruction content or model-visible metadata is escaped so repository-controlled text cannot close the plugin-owned frame."

### 5.3 How it bounds size

Budget input — `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-agent-instructions/lib/index.js:25-32`: `maxBytes` is `.required()` (no default); `maxSourceBytes` defaults to `1048576` (`:19`).

Byte accounting uses **UTF-8 bytes**, not JS string length — `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-agent-instructions/lib/index.js:117-126`:

```js
function byteLength(value) {
    return Buffer.byteLength(value, "utf8");
}
function truncateUtf8(value, maxBytes) {
    const bytes = Buffer.from(value, "utf8");
    if (bytes.length <= maxBytes) return value;
    let end = Math.max(0, Math.trunc(maxBytes));
    while (end > 0 && (bytes.readUInt8(end) & 192) === 128) end -= 1;   // never split a continuation byte
    return bytes.subarray(0, end).toString("utf8");
}
```

Degradation ladder — `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-agent-instructions/lib/index.js:293-372`:

1. `maxBytes <= 0 || !Number.isFinite(maxBytes)` → empty text (`:294-299`).
2. whole frame fits → return all files (`:300-306`).
3. drop **whole broader files from the front**, one at a time, until the suffix fits (`:307-320`) — "broader files are omitted before the most specific file is truncated" (`README.md:72`).
4. truncate only the most-specific file by **binary search** over byte prefixes — `truncateToFit` at `:273-292`, driven from `:338`; tried first with the normal intro, then with `COMPACT_WORKSPACE_CONTEXT_INTRO` (`:334-337`).
5. finally a notice-only message, itself truncated if necessary (`:353-369`).

The visible accounting notice — `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-agent-instructions/lib/index.js:249-255`:

```js
return `Workspace instruction budget ${maxBytes} bytes: ${parts.join("; ")}`;
```

where parts are `omitted <paths>` and `truncated <path> from <originalBytes> to <includedBytes> bytes`. The renderer returns not just text but `represented` (the files actually carried), and the caller filters the `changes` list to that set so durable state never claims more than the message says — `lib/index.js:243-247`. Separate cap on one source file before rendering: `readScopeInstruction(probedFile, resolved.maxSourceBytes, ...)` at `:1016`.

### 5.4 How it establishes a durable identity

`/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-agent-instructions/lib/index.js:40-49`:

```js
function workspaceBaselineIdentity(config, cwd, projectRoot) {
    return JSON.stringify({
        projectRoot: relative(cwd, projectRoot),
        projectRootMarkers: config.projectRootMarkers,
        maxBytes: config.maxBytes,
        maxSourceBytes: config.maxSourceBytes,
        instructionFileCandidates: config.instructionFileCandidates,
        localInstructionFileCandidates: config.localInstructionFileCandidates
    });
}
```

It is a stable serialization of **discovery, precedence, project-root, and budget semantics** — not content. It is written into the durable message source as `baselineIdentity` (`:1175` for the first baseline, `:1205` for a composed replacement) together with `baseline: true` (`:1174`, `:1204`). Comparing it on a later pass decides whether the visible baseline is still *compatible* rather than merely present.

Content identity is separate: SHA-1 hex of the file content (`instructionContentSha1`, `:90-93`) and a trimmed-content SHA-1 for per-directory duplicate suppression (`trimmedInstructionDigest`, `:101-…`, applied at `:642-644`). Both ride in the `changes` list as `{ action: 'set'|'remove', scope, path, digest }` (`:845-851`).

### 5.5 How it avoids re-injecting unchanged content

Four layers, all in `lib/index.js`:

1. **Baseline identity match.** `visibleBaselineSource(agent, authorityMessages)` (`:1073-1079`) finds the most recent `source.kind === 'agent-instructions' && source.baseline === true` — first scanning the authority messages (claimed + this pass's own additions) in reverse, then scanning `agent.session.surface.nodes` in reverse via `agent.session.eventAt(seq)`. Then `keepVisibleBaseline = visibleBaseline?.baselineIdentity === identity` (`:1126`). When true, the whole reload+render block at `:1130-1181` is skipped.
2. **Per-scope version + digest fast path.** `reconcileInstructionContext` compares the cached `{ path, version: FsVersion, digest, trimmedDigest }` against the probed file — `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-agent-instructions/lib/index.js:1011-1015`:
   ```js
   const cached = versions.get(scope);
   if (cached !== void 0 && cached.path === probedFile.displayPath && cached.version === probedFile.version
       && previous !== void 0 && previous.action !== "remove"
       && previous.path === cached.path && previous.digest === cached.digest) {
       if (registerKeptTrimmed(directory, cached.trimmedDigest)) pushRemoval(scope, previous.path);
       continue;    // no read, no message
   }
   ```
   The cache is per-session and per-scope (`versionStatesFor(session, cache)` `:864-871`, held in a `WeakMap<Session, Map<scope, state>>` created at `:1100`) and stores metadata only — "instruction prose is deliberately not retained" (`lib/types/state.d.ts:30`).
3. **Visible change fold.** `visibleInstructionChanges(agent, authorityMessages)` (`:821-834`) folds every visible `agent-instructions` source in `session.surface.nodes`, plus the authority messages, into a `Map<scope, change>`; the reconciler only emits a scope whose current probe differs from that.
4. **Inbox dedup.** `syncInbox` (`:1210-1229`) uses `sameContextPayload` = `isDeepStrictEqual` over `content` and `source` (`:1083-1085`) and checks three places before queueing: the claimed batch, the already-logged surface nodes, and the existing pending inbox messages:
   ```js
   const alreadySupplied = desired !== void 0 && (claimed.some((m) => sameContextPayload(m, desired))
       || agent.session.surface.nodes.some((seq) => { const e = agent.session.eventAt(seq);
            return e?.type === "user/message" && sameContextPayload(e.data, desired); }));
   if (desired === void 0 || alreadySupplied) { for (const m of pending) agent.inbox.remove(m.id); return; }
   const reusable = pending.find((m) => sameContextPayload(m, desired));
   if (reusable !== void 0) { for (const m of pending) if (m !== reusable) agent.inbox.remove(m.id); return; }
   const replaced = pending[0];
   if (replaced === void 0) agent.inbox.prepend("next-step", desired);
   else agent.inbox.replace(replaced.id, desired);
   for (const message of pending.slice(1)) agent.inbox.remove(message.id);
   ```
   So pending workspace contexts are replaced in place, never stacked.

### 5.6 How it reconciles state on resume

- The visible baseline source read at `:1073-1079` comes from the **durable log** (`session.eventAt`) via the surface, so a resumed session re-derives it without a process-local cache. README `:131`: "Resume reuses that message when its visible baseline is compatible."
- Compatibility is the `baselineIdentity` equality at `:1126`. On a mismatch with a baseline present, `replacePreviousBaseline` is set (`:1131`) and the new message uses `REPLACEMENT_WORKSPACE_CONTEXT_INTRO` (`:114`) plus a synthesized removal set for scopes the new baseline no longer covers (`:1162-1167`). README `:155`: "an incompatible identity appends a complete replacement, so discovery, precedence, project-root, or budget changes affect reuse only from that history position."
- The reconciliation set is rebuilt from the visible log each pass — `effective = visibleInstructionChanges(agent, options.authorityMessages)` (`:909`) — and a scope whose probe is `unavailable` rolls back the whole batch it was part of (`:992-1001`), so a transient I/O failure never produces a spurious removal. A scope that is `absent` while previously visible produces `pushRemoval` (`:1002-1005`).
- **Important limitation, verified**: this plugin reads only `agent.session.surface.nodes` (`:1075`, `:1212`, `:823`) — the derived, model-visible surface — never raw seqs below a compaction. A baseline shadowed by compaction is therefore invisible and gets re-injected as a full replacement baseline. That is the intended behavior here, but it is the *opposite* of the raw-log scan `dsh-time-context` uses (item 6). If the memory plugin needs "did I already inject, even though compaction hid it?", the time-context scan is the correct template.
- Projection-based touches: `tools/result` records file touches and defers them to the enclosing durable step via `ctx.on("session/event", ...)` on `step/end` (`:1263-1269`, `:1289-1308`), and a pre-step waits for in-flight projections with `waitForProjections(agent)` (`:1244-1247`, `:1272`), serialized per agent by `projectionTails` (`:1108`, `:1235-1243`).

### 5.7 Reconstructed — the five mechanisms reduced to a skeleton

```js
// RECONSTRUCTED FROM TYPES — not copied from any shipped source file.
// Mirrors dsh-agent-instructions/lib/index.js:111-129, 256-266, 293-372,
// 766-794, 1073-1079, 1126, 1169-1178, 1210-1288.
import { createHash } from 'node:crypto';
import { createUserMessage } from '@deepseek-ai/dsh-llm';

const OPEN = '<system-reminder>';
const CLOSE = '</system-reminder>';
const INTRO = 'The following memory document may be relevant to your work.';
const CLOSE_RE = '</system-reminder>';

const esc = (body) => body.replaceAll(CLOSE_RE, '<\\/system-reminder>');           // 5.2
const bytes = (s) => Buffer.byteLength(s, 'utf8');
const truncUtf8 = (s, max) => {                                                   // 5.3
  const b = Buffer.from(s, 'utf8');
  if (b.length <= max) return s;
  let end = Math.max(0, Math.trunc(max));
  while (end > 0 && (b.readUInt8(end) & 192) === 128) end -= 1;
  return b.subarray(0, end).toString('utf8');
};
const frame = (body, max) => {                                                    // 5.1
  const inner = esc(body);
  const text = [OPEN, inner, CLOSE].join('\n');
  return bytes(text) <= max ? text : [OPEN, esc(truncUtf8(body, max)), CLOSE].join('\n');
};
const sha1 = (s) => createHash('sha1').update(s).digest('hex');

const identityOf = (cfg) => JSON.stringify({                                      // 5.4
  maxBytes: cfg.maxBytes, sourceIds: [...cfg.sourceIds].sort(),
});

function messageFor(text, identity, digest) {                                     // 5.1
  return createUserMessage({
    content: [{ type: 'text', text }],
    source: {
      kind: 'plugin', plugin: 'optmem', form: 'snapshot',
      sections: [{ name: 'optmem', text }],
      // merge-extend MessageSourceMap to carry these durably (agent-instructions/lib/types/state.d.ts:24-28):
      // baselineIdentity: identity, digest,
    },
  });
}

ctx.on('agent/pre-step', async ({ agent, messages, signal }, next) => {
  const decision = await next();
  if (decision.kind === 'reject' || signal.aborted) return decision;

  // 5.5 + 5.6: durable identity + digest read back from the visible log.
  const identity = identityOf(cfg);
  const prior = lastOwnSource(agent, messages);   // reverse scan of decision.messages then session.surface.nodes
  const body = renderBoundedMemory(cfg);
  const digest = sha1(body);
  if (prior?.baselineIdentity === identity && prior?.digest === digest) return decision;

  const at = decision.messages.findLastIndex((m) => messages.includes(m));
  return { ...decision, messages: decision.messages.toSpliced(at + 1, 0,
    messageFor(frame(body, cfg.maxBytes), identity, digest)) };
});
```

---

## 6. Avoiding duplicate injection when history is shadowed by compaction

Package root for this section: `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-time-context/`.

### README statement

`/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-time-context/README.md:80`:

> "Positive-interval scheduling **scans raw durable session events for the latest plugin-attributed message — including one shadowed by compaction** — so the schedule survives resume without a process-local cache."

And `README.md:67`:

> "Each reading uses the exact snapshot source `{ kind: 'plugin', plugin: 'time-context', form: 'snapshot', sections: [{ name: 'time-context', text }] }`".

### Exact service and method calls, verbatim

**(a) The projection fold.** `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-time-context/lib/index.js:181-214`:

```js
ctx.sessionProjections.register({          // 181
    key: "timeContext",                    // 182
    stateVersion: 2,                       // 183
    stateSchema: timeContextStateSchema,   // 184
    init: () => ({                         // 185
        lastMessageTime: null, lastInjectionTime: null, lastTurnInjectionTime: null
    }),
    apply: (state, event) => {             // 190
        if (event.type === "turn/start" || event.type === "turn/end") return ...;
        if (event.type === "user/message") {                                    // 195
            const injected = event.data.source.kind === "plugin" && event.data.source.plugin === "time-context";  // 196
            const withMessage = state.lastMessageTime === event.time ? state : { ...state, lastMessageTime: event.time };
            if (!injected) return withMessage;
            return { ...withMessage, lastInjectionTime: event.time, lastTurnInjectionTime: event.time };          // 202-206
        }
        if (event.type === "assistant/message" || event.type === "tool/result") return ...;                       // 208
        return state;
    }
});
```

**(b) The state read.** `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-time-context/lib/index.js:219`:

```js
const state = ctx.sessionProjections.stateOf(agent.session, "timeContext");
```

**(c) The raw durability gate.** `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-time-context/lib/index.js:220-223`:

```js
if (refreshIntervalMs !== void 0 && refreshIntervalMs > 0) {
    const lastInjection = state.lastInjectionTime;
    if (lastInjection != null && now >= lastInjection && now - lastInjection < refreshIntervalMs) return decision;
}
```

**(d) The backwards raw-seq scan.** `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-time-context/lib/index.js:135-143`:

```js
function requestMessages(agent, turn, proposed) {
    const entered = [];
    for (let seq = agent.session.seq - 1; seq >= 0; seq -= 1) {                 // 137
        const event = agent.session.eventAt(SessionSeq(seq));                   // 138
        if (event?.type === "turn/start" && event.data.turn === turn) return [...entered.reverse(), ...proposed];  // 139
        if (event?.type === "user/message") entered.push(event.data);           // 140
    }
    return [...proposed];
}
```

Imports: `import { SessionSeq } from "@deepseek-ai/dsh-session";` — `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-time-context/lib/index.js:4`.

### Why this reads RAW durable events, not the derived surface

- `Session.eventAt(seq: SessionSeq): SessionEvent | undefined` returns the immutable event at **one exact sequence number** from the raw append-only log — `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-session/lib/types/index.d.ts:173-178`.
- `Session.seq` is "the next event's sequence number — always the log length (the `seq = log.length` contiguity contract)" — `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-session/lib/types/index.d.ts:199-200`. So `seq - 1 … 0` walks **every** event ever logged, shadowed or not. `SessionSeq` is the brand constructor (`dsh-session/lib/types/types.d.ts:18-23`).
- By contrast the derived surface **deletes** shadowed nodes: "a compaction `replace` deletes the shadowed nodes from the derivation" — `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-session/lib/types/index.d.ts:269-274`. `Session.surface` (`:107-108`) exposes only `readonly nodes: readonly SessionSeq[]` and `readonly replaceGeneration: number` — `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-session/lib/types/surface.d.ts:92-96`.
- The projection registry drives `apply` "on every committed session event" and "The framework drives `apply` on every committed session event" — `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-session-projection/lib/types/index.d.ts:30-36`, transition contract at `:58`. `session/event` is the post-commit firehose over every appended event — `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-session/lib/types/index.d.ts:52-62` — and it is not filtered by surface membership.
- Survival across resume: `apply` is a pure fold replayed from the log; `stateVersion` invalidates stale persisted checkpoints, and the persisted cache stores `(sessionId, key, ver, seq, val)` rows — `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-session-projection/lib/types/index.d.ts:70-77`; `README.md:67-69` and `:133` ("a restart rebuilds by folding the log on first touch"). The registration is fiber-scoped and self-disposing: `register(...): () => void` — `index.d.ts:150`, `:159`.
- `stateOf(session, key)` returns "current state, or `undefined` when the key is not registered" — `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-session-projection/lib/types/index.d.ts:168-175`.
- The identity test is on the **durable source**, not on a process-local marker: `event.data.source.kind === "plugin" && event.data.source.plugin === "time-context"` — `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-time-context/lib/index.js:196`.

### Consequence for the memory plugin

Storage of "I already injected my document" must live in the raw durable log — either as the `user/message` event's own `source` (`{ kind:'plugin', plugin:'optmem', … }`) folded by a session projection, or by scanning `session.eventAt(SessionSeq(i))` for `i` from `session.seq - 1` down to `0`. Scanning `session.surface.nodes` (as `dsh-agent-instructions` does at `lib/index.js:1075`, `:1212`, `:823`) will **not** see a document shadowed by a compaction.

### Reconstructed — compaction-proof "already injected?" check

```js
// RECONSTRUCTED FROM TYPES — not copied from any shipped source file.
// Mirrors dsh-time-context/lib/index.js:135-143, 181-223.
import { SessionSeq } from '@deepseek-ai/dsh-session';

const PLUGIN = 'optmem';

// Fold raw events, so a compaction-shadowed injection still counts.
ctx.sessionProjections.register({
  key: 'optmemState',
  stateVersion: 1,
  stateSchema: optmemStateSchema,           // zod schema for { lastInjectionTime, lastDigest }
  init: () => ({ lastInjectionTime: null, lastDigest: null }),
  apply: (state, event) => {
    if (event.type !== 'user/message') return state;
    const s = event.data.source;
    if (s.kind !== 'plugin' || s.plugin !== PLUGIN) return state;
    return { lastInjectionTime: event.time, lastDigest: s.digest ?? null };
  },
});

// Raw backwards scan (survives compaction because eventAt() reads the log,
// not the surface).
function lastOwnInjectionSeq(session) {
  for (let seq = session.seq - 1; seq >= 0; seq -= 1) {
    const event = session.eventAt(SessionSeq(seq));
    if (event?.type !== 'user/message') continue;
    const s = event.data.source;
    if (s.kind === 'plugin' && s.plugin === PLUGIN) return { seq, source: s, time: event.time };
  }
  return undefined;
}
```

---

## 7. Compaction

### 7.1 Abstract backend surface

`/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-compaction/lib/types/index.d.ts:75-131`.

Class and registration — `index.d.ts:75-76`; implementation `class extends Service` registering the name `"compaction"` at `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-compaction/lib/index.js:172-175`:

```js
var CompactionEngine = class extends Service {
    constructor(ctx) { super(ctx, "compaction"); }
};
```

Service augmentation — `index.d.ts:61-65`: `interface Context { compaction: CompactionEngine }`. "Load one implementation per context as `ctx.compaction`" (`index.d.ts:72-73`).

**Automatic** — `index.d.ts:89`:

```ts
abstract compactIfNeeded(agent: CompactionAgentContext, trigger: CompactionTrigger, signal: AbortSignal): Promise<CompactionResult | null>;
```

`CompactionTrigger = 'pressure' | 'context-overflow'` — `index.d.ts:19`. "Return `null` when no safe range can be compacted. A single oversized retained unit or request envelope cannot be repaired through surface compaction." — `index.d.ts:80-82`.

**On demand (explicit, idle session)** — `index.d.ts:110`:

```ts
abstract compactNow(agent: ManualCompactAgentContext, signal: AbortSignal, sourceCommandId?: CommandId): Promise<CompactionResult | null>;
```

`ManualCompactAgentContext extends CompactionAgentContext` and adds `runMaintenance` — `index.d.ts:51-60`. Contract: "Implementations synchronously start an idle task before any asynchronous work ... then append a standalone `compaction/start` before summarization. That durable marker is the compaction lock until one `compaction/end` attempt." — `index.d.ts:91-99`. Throws `ManualCompactionError` (`index.d.ts:27-37`, codes `'busy' | 'cancelled' | 'changed' | 'summary' | 'commit' | 'persistence'` at `:21`).

**Explicit region** — `index.d.ts:130`:

```ts
abstract compactRegion(start: SessionSeq, end: SessionSeq, agent: CompactionAgentContext, signal?: AbortSignal): Promise<CompactionResult>;
```

"`start` and `end` name an inclusive span by surface position, not numeric seq order; replacements can make visible seqs non-monotonic. Both edges must be balanced so assistant tool calls remain paired with their results." — `index.d.ts:112-116`. Edge helpers: `toolPairingBalancedBefore(session, seq)` / `toolPairingBalancedAfter(session, seq)` — `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-compaction/lib/types/tool-pairing.d.ts:15-25`, re-exported at `index.d.ts:15`.

`CompactionAgentContext` — `index.d.ts:38-45`:

```ts
export interface CompactionAgentContext {
    session: Session;
    options: { provider?: string; model?: string };
}
```

### 7.2 Checkpoint / marker contract

`/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-compaction/lib/types/checkpoint.d.ts:17-38`:

```ts
declare const COMPACT_CHECKPOINT_MARKER: Readonly<{
    readonly kind: "plugin";
    readonly plugin: "compact";
}>;
export type CompactionCheckpointSource = typeof COMPACT_CHECKPOINT_MARKER & {
    readonly compactionId: CompactionId;
    readonly sourceCommandId?: CommandId;
};
export declare function compactCheckpointSource(compactionId: CompactionId, sourceCommandId?: CommandId): CompactionCheckpointSource;
export declare function isCompactCheckpointSource(source: MessageSource): boolean;
```

Implementation: `Object.freeze({ kind: "plugin", plugin: "compact", compactionId, ... })` — `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-compaction/lib/index.js:85-95`; predicate at `:96-104`. A backend **must** attach this source to its replacement user message — stated twice: `index.d.ts:70-73` ("The replacement user message uses `compactCheckpointSource` with the transaction identity so consumers recognize and correlate it independently of the backend") and `index.d.ts:118-119`.

The shipped backend does exactly that: `session.append("user/message", checkpointMessage, { surfaceOp: { op: "replace", startSeq: start, endSeq: end }, sourceEventSeqs: [startEvent.seq, summaryEvent.seq, ...shadowedSeqs] })` — `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-compaction-basic/lib/index.js:621-634`.

`CompactionResult` — `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-compaction/lib/types/types.d.ts:101-131`: `compactionId`, `sourceCommandId?`, `startSeq`, `summarySeq`, `endSeq`, `summary: ContentBlock[]`, `shadowedRange: { start: SessionSeq; end: SessionSeq }`, `shadowedSeqs: SessionSeq[]`, `shadowedTokenCount: number`. Note the warning at `:115-122`: "A surface-POSITION span, not a numeric seq interval — after a prior replace lands a fresh high-seq summary node at an older range's position, `start` can be GREATER than `end`. `shadowedSeqs` is the authoritative set."

### 7.3 How the shipped backend's `summarize()` is meant to be overridden

`/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-compaction-basic/lib/types/index.d.ts:16-23`:

> "Dependency-light compaction backend using `ctx.tokenMeter` for pressure, retention, cited source events, and summary-convergence pricing. **`summarize()` is the sole subclass customization hook**; the replay and durable mutation strategy stays fixed so every pricing decision uses the singleton token meter."

Signature — `index.d.ts:49`:

```ts
protected summarize(input: SummarizationInput, agent: Agent, signal?: AbortSignal): Promise<SummaryResult>;
```

`SummarizationInput` — `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-compaction-basic/lib/types/summarizer.d.ts:20-25`: `{ tools?: readonly ToolSchema[]; messages: readonly Message[] }` — "The derived system head, when present, followed by the shadowed region in surface order."

`SummaryResult` — `summarizer.d.ts:27-44`: `summary: ContentBlock[]`, `provider`, `model`, `maxTokens?`, `usage?`, and a discriminated pair forcing the backend to declare whether the output came from this context's `ctx.llm.stream()` (`{ rawOutput: ContentBlock[]; llmStreamCall: true }`) or from "an unmarked template, remote, or other summarizer" (`{ rawOutput?; llmStreamCall?: never }`).

Default implementation — `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-compaction-basic/lib/index.js:858-861`:

```js
async summarize(input, agent, signal) {
    const target = conversationTarget(agent);
    const config = target === void 0 ? this.config : resolveTargetPolicy(this.config, target);
    return summarizeWithLlm(this.ctx, config, input, agent, signal);
}
```

Override dispatch: `regionDependencies()` returns `{ meter: this.ctx.tokenMeter, summarize: (input, owner, abort) => this.summarize(input, owner, abort) }` — `lib/index.js:972-977`; the caller invokes `dependencies.summarize(...)` — `lib/index.js:565-568`. So subclass overrides are honored because the call is late-bound through `this`.

The base overrides are declared with a narrowed agent parameter (`Agent` instead of `CompactionAgentContext`): `compactIfNeeded(agent: Agent, ...)` `index.d.ts:60`, `compactRegion(..., agent: Agent, ...)` `:70`, `compactNow(agent: Agent, ...)` `:79`. TypeScript accepts this (method-parameter bivariance); a strict-mode subclass author should keep the base signatures.

Default summarization framing (useful if the memory compressor wants the same shape):

- instruction is the **final** user message after the replayed prefix so the KV cache is reused — comment `lib/index.js:213-219`, instruction text `:220-255`.
- the `GenerateOptions` it builds — `lib/index.js:292-301`: `{ provider, model, messages, tools?, maxTokens, sessionId: agent.session.session.id, purpose: "compaction", signal? }`, then `for await (const chunk of ctx.llm.stream(options)) assembler.push(chunk);` at `:302`.
- the durable framing — `frameSummary` at `:323-335` wraps `summary` between `<compacted-summary>` and `</compacted-summary>` (`:211-212`), preceded by `CHECKPOINT_PREAMBLE` (`:257`).
- fail-closed finish handling — `finishError(assembler.finish)` at `:303-304`, defined at `:337-…`.

### 7.4 Can a non-backend plugin observe compaction? Yes

**Session events** (declaration-merged into `SessionEventMap`, so they are ordinary appendable events):

| Event | Declared at | Payload |
|---|---|---|
| `compaction/start` | `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-compaction/lib/types/types.d.ts:21-25` | `{ compactionId, sourceCommandId?, turn: number \| null }` |
| `compaction/summary` | `types.d.ts:35-68` | `{ compactionId, sourceCommandId?, summary: ContentBlock[], shadowedRange, shadowedSeqs, shadowedTokenCount, provider, model, maxTokens?, usage?, rawOutput?, llmStreamCall? }` |
| `compaction/end` | `types.d.ts:73-78` | `{ compactionId, sourceCommandId?, turn: number \| null, error?: string }` |
| `compaction/prune` | `types.d.ts:88-98` | `{ shadowedRange, shadowedSeqs, shadowedTokenCount }` |

All four are "log-only" with **no `surfaceOp`** (`types.d.ts:2-4`, `:27`, `:70`, `:80-81`), so they never enter the derived message surface. Adjacency contract: the replacement `user/message` is the surface event immediately after `compaction/summary` (`types.d.ts:28-33`).

**How to observe them**: the `session/event` firehose — `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-session/lib/types/index.d.ts:52-62`:

```ts
'session/event'(this: Scoped<Session>, session: Session, event: SessionEvent): void;
```

Shipped precedents: `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-agent-instructions/lib/index.js:1263-1269` (filters `step/end`) and `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-compaction-basic/lib/index.js:815-819`.

**Other observable surfaces**:

- `agent/pre-step` runs on every step and sees the post-compaction derived history, which is the natural place to re-inject a document that compaction shadowed. `dsh-compaction-basic` itself triggers automatic compaction from this seam: `ctx.on("agent/pre-step", async ({ agent, signal }, next) => { ... await this.compactIfNeeded(agent, "pressure", signal) ... return next(); })` — `lib/index.js:798-811`.
- `session.surface.replaceGeneration` — "Monotonic count of committed positional replacements" — `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-session/lib/types/surface.d.ts:94-96`. The loop uses it to start a new request series after any replacement: `startsSeries: startsRequestSeries || this.requestSurfaceGeneration !== this.session.surface.replaceGeneration || this.toolsChanged(assembly.tools)` — `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-agent-loop/lib/index.js:1021`.
- `isCompactCheckpointSource(source: MessageSource)` (`checkpoint.d.ts:38`) identifies a compaction replacement in the derived history without knowing the backend.

**Cordis event around compaction: none found.** No `ctx.emit`/`ctx.on("compaction/...")` exists in `dsh-compaction` or `dsh-compaction-basic`; the only service face is `ctx.compaction` with its three abstract methods. The names `compaction/start|summary|end|prune` are **session event types**, not Cordis events. A non-backend plugin cannot veto or intercept a compaction — it can only observe it and react.

### 7.5 Claude Code `PreCompact` / `PostCompact` — **not supported**

`/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-hooks-claude-code/README.md:174`:

> "**Unsupported hook events (23 of Claude Code's current 30)** — `Setup`, `InstructionsLoaded`, `UserPromptExpansion`, `MessageDisplay`, `PermissionRequest`, `PostToolUseFailure`, `PostToolBatch`, `PermissionDenied`, `Notification`, `TaskCreated`, `TaskCompleted`, `StopFailure`, `TeammateIdle`, `ConfigChange`, `CwdChanged`, `FileChanged`, `WorktreeCreate`, `WorktreeRemove`, **`PreCompact`**, **`PostCompact`**, `SessionEnd`, `Elicitation`, and `ElicitationResult`. Config for these events is ignored before group parsing, so an unsupported event cannot invalidate or register hooks."

This seam does not exist. Do not build the spec on it.

### 7.6 Reconstructed — re-inject after compaction without being the backend

```js
// RECONSTRUCTED FROM TYPES — not copied from any shipped source file.
// Observe via session/event (dsh-compaction/lib/types/types.d.ts:73-78 +
// dsh-session/lib/types/index.d.ts:62). Re-inject via agent.inject() or the
// next agent/pre-step, exactly as dsh-tool-jobs/lib/index.js:206-227 does.

ctx.inject(['sessionProjections'], (child) => { /* register a projection for the raw scan, item 6 */ });

ctx.on('session/event', (session, event) => {
  if (event.type !== 'compaction/end') return;
  if (event.error !== undefined) return;              // failed attempt: leave state alone
  const agent = agentForSession(session);             // your own session -> agent map
  if (agent === undefined) return;
  if (delegationDepthOf(agent) > 0) return;           // item 9: never in a subagent

  const text = renderBoundedMemoryDocument(agent);
  if (text === undefined) return;
  const message = createUserMessage({
    content: [{ type: 'text', text }],
    source: { kind: 'plugin', plugin: 'optmem', form: 'snapshot',
              sections: [{ name: 'optmem', text }] },
  });

  // Session events are post-commit and synchronous; the driver may or may not
  // be running. inject() never wakes, so it is claimed at the nearest later
  // step boundary and cannot itself start a turn.
  agent.inject(message);
});

// The load-bearing belt-and-braces pass: pre-step runs before EVERY request,
// which is the only seam verified to reach the first request and every
// post-compaction request regardless of which events fired.
ctx.on('agent/pre-step', async ({ agent, messages, signal }, next) => {
  const decision = await next();
  if (decision.kind === 'reject' || signal.aborted) return decision;
  if (delegationDepthOf(agent) > 0) return decision;
  // ... raw durable "already injected this exact body?" check (item 6) ...
  return decision;
});
```

---

## 8. `ctx.tokenMeter`

Package root: `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-token-meter/`.

### Service

`/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-token-meter/lib/types/index.d.ts:14-24`:

```ts
declare module '@deepseek-ai/cordis' {
    interface Context { tokenMeter: TokenMeter; }
}
export declare class TokenMeter extends Service {
    static Config: z<TokenMeterConfig>;
    static inject: string[];
```

`TokenMeterConfig = Record<string, never>` — `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-token-meter/lib/types/types.d.ts:10` ("the fixed estimator has no settings").

### API surface

**Measure a request** — `index.d.ts:46`:

```ts
measure(session: Session, requestHeader?: EpochHeader): TokenMeasurement;
```

Doc (`index.d.ts:26-45`): "Measure current request pressure and surface through the durable tail. The effective envelope's routed provider/model selects the request-image pricing every node is priced under ... `requestHeader` replaces the latest logged envelope for pressure and node pricing; the node set always describes the current session surface. Every call clones those positional nodes, so measurement is O(surface)."

`TokenMeasurement` — `types.d.ts:24-37`:

```ts
export interface TokenMeasurement {
    readonly logRevision: SessionLogOffset;
    readonly baseline: TokenMeasurementBaseline;
    readonly surfaceDeltaTokens: number;
    readonly totalTokens: number;      // request-and-response pressure
    readonly surfaceTokens: number;    // == sum of nodes[].tokens
    readonly nodes: readonly TokenSurfaceNode[];
}
export interface TokenSurfaceNode {
    readonly seq: SessionSeq;
    readonly tokens: number;           // route-priced
    readonly heuristicTokens: number;  // route-independent, used for shadow prices
}
```

`TokenMeasurementBaseline` is `{kind:'none';tokens:0} | {kind:'estimated';tokens} | {kind:'usage';tokens;usage}` — `types.d.ts:12-22`.

**Price one message** — `index.d.ts:57`:

```ts
estimateMessage(message: Message): number;
```

### Counting tokens for a string

**There is no string API.** `grep` over the package finds no `countTokens`-style export. The only string→tokens route is the pure heuristic over content blocks — `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-token-meter/lib/types/estimate.d.ts:25`:

```ts
export declare function estimateContent(blocks: readonly ContentBlock[]): number;
```

so a string must be wrapped: `estimateContent([{ type: 'text', text }])`. Other exports: `ROLE_OVERHEAD = 4` (`estimate.d.ts:11`), `estimateStructuralBlock(block)` (`:19`), `estimateSystemMessage(message)` (`:34`), `estimateToolsTokens(header: EpochHeader | undefined)` (`:48`). The heuristic is "four characters per token plus block and role overhead" — `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-token-meter/README.md:85`; note `README.md:64` warns "CJK text and JSON schemas underprice badly at four characters per token."

### What a plugin can rely on

- **Deterministic, no model calls, no model-visible surface.** `README.md:28` ("The estimator has no settings and adds no model-visible surface") and `README.md:64` ("nothing in the harness makes decisions from it, and compaction reads `measure()` instead").
- **Approximate, not billing.** Limitations bullet at `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-token-meter/README.md:133`: "The fixed heuristic is approximate — text without reusable provider usage is priced by character count plus structural overhead, not an exact provider tokenizer or request serializer."
- **Provider usage reuse is conditional.** "Provider usage is reused only when the latest successful call's canonical request envelope matches the measured envelope and its total is no lower than that call's full route-priced anchor" — `README.md:43`.
- **Cost is O(current surface).** "Every measurement clones the current surface" — `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-token-meter/README.md:135`; `index.d.ts:39-40`.
- **Session projections.** "When the composition provides `ctx.sessionProjections`, token-meter registers three projection units" — `README.md:47` — keys `tokenUsage`, `contextPressure`, `contextBreakdown`; "Unloading the plugin removes all three keys" (`README.md:47` section). These are cheaper than repeated `measure()` calls for an occupancy display.
- **Capacity is not here.** "model capacity belongs to the adapter that owns the exact provider/model route and is available through `ctx.llm.resolveModelInfo().context`" — `README.md:28`; signature at `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-llm/lib/types/index.d.ts:354`.

---

## 9. Subagent detection

### `delegationDepthOf` and related helpers

`/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-subagent/lib/types/depth.d.ts:9-30`:

```ts
declare module '@deepseek-ai/dsh-agent' {
    interface AgentOptions {
        /** Delegation depth: zero for a top-level agent and parent depth + 1 for a child. */
        subagentDepth?: number;
    }
}
export declare function delegationDepthOf(agent: Agent): number;
export declare function assertSubagentMaxDepth(maxDepth: unknown): void;
```

Semantics (`depth.d.ts:15-24`): "Read an agent's delegation depth, treating absence as top-level depth zero. The persisted session header is authoritative and monotone: runtime `AgentOptions.subagentDepth` may DEEPEN the count but can never lower it — a resumed child arrives with fresh options, and counting it from zero would let it delegate as if it were top-level." Throws if the runtime option is not a non-negative safe integer.

Implementation — `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-subagent/lib/index.js:144-148`:

```js
function delegationDepthOf(agent) {
    const runtime = agent.options.subagentDepth;
    if (runtime !== void 0 && (!Number.isSafeInteger(runtime) || runtime < 0 || Object.is(runtime, -0))) throw new TypeError("agent subagentDepth must be a non-negative safe integer");
    return Math.max(agent.session.header.delegationDepth ?? 0, runtime ?? 0);
}
```

**Import path**: only the package root. `lib/types/index.d.ts:50` re-exports `{ assertSubagentMaxDepth, delegationDepthOf }`; `package.json` has no `./depth` subpath export (only `.`, `./internal`, `./invariant`, `./client`, `./typert`, `./remote`, `./src/*`, `./package.json`). Import from `@deepseek-ai/dsh-subagent`.

Related helpers in `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-subagent/lib/types/child-agent.d.ts`:

- `resolveChildDepth(parent: Agent, maxDepth: number | undefined): number` — `:31`; "The persisted parent header is the monotone floor, so a resumed parent cannot delegate as if it were top-level"; throws `SubagentDepthError` (`:16-20`).
- `SubagentDepthError` — `:16-20` (`attemptedDepth`, `maxDepth`).
- `childSessionMeta(parent, childDepth, isSeeded)` — `:70`; persists the depth into the child's durable header.

Durable header fields — `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-session/lib/types/types.d.ts:77-87`:

```ts
readonly origin?: 'subagent';        // coarse product classification, "not proof that the child is continuable"
readonly delegationDepth?: number;   // "Persisted so a recursion budget survives restart and resume"
```

### How a pre-step listener determines the current agent is a subagent

`delegationDepthOf(agent) > 0` is the direct test, and it is monotone across resume (header floor). Two alternatives with different semantics:

- `agent.session.header.origin === 'subagent'` (`types.d.ts:81`) — presentation metadata, explicitly "not proof that the child is continuable". Weaker.
- Runtime ownership: `ctx.agents.roots(): Agent[]` — "All live top-level agents in registration order. A top-level agent was created without an owning agent context; durable session lineage does not affect this runtime relation, so a resumed fork may still be a root." — `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-agent/lib/types/index.d.ts:356-362`. Also `isOwnedBy(id, owner)` at `:350`.

### The recommended way to scope a listener to a specific agent

`Scoped<Agent>` is a **routing-only** receiver — `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-scope/lib/types/index.d.ts:13-20`:

```ts
export type Scoped<T extends object> = object & {
    readonly [ScopedBrand]: T;
};
```

"The carrier does not expose the subject's properties. Event payloads carry the real subject." So scope routing and payload are separate; the payload always has `agent`.

The dispatcher couples them — `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-agent/lib/types/dispatch.d.ts:38-93`: `agentEvents(ctx, agent, carrier?)` builds a dispatcher whose `emit`/`serial`/`waterfall` "dispatch the named agent-subject event with the agent's scope carrier as `thisArg` and the agent itself injected into the payload"; `agentCarrier(agent)` at `:83`; `emitAgentEvent` at `:101`. Lower-level primitives: `scopeTarget(base, key)` (`dsh-scope/lib/types/index.d.ts:97`), `createScope(ctx, key, options?)` (`:78`), `scopeOf(ctx)` (`:84`), `bindScopeParent(key, parent)` (`:43`), `scopeChainOf(key)` (`:55`).

Declared routing rule, per event (`agent/pre-step` shown) — `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-agent/lib/types/runtime-types.d.ts:310`:

> "Scope-filtered dispatch (`@deepseek-ai/dsh-scope`): agent-scoped listeners receive only that agent."

**Recommended scoping: register the listener on `agent.ctx`, not on the plugin's own `ctx`.** `Agent.ctx` is documented as "Agent-scoped context; its contributions are agent-local, unwind on disposal, and reject registration afterward" — `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-agent/lib/types/runtime-types.d.ts:148-149`. The registration window is `agent/created`, whose doc says "Setup is composition-only; `agent/session-start` is the first startup-driving extension point" — `runtime-types.d.ts:215-216`.

Shipped precedents:

- `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-schedule/lib/index.js:1459-1483`:
  ```js
  ctx.on("agent/created", ({ agent }) => {
      if (stopping || runtimes.has(agent) || !ctx.agents.roots().includes(agent)) return;   // 1462
      const cleanup = agent.ctx.effect(() => {
          const disposeTools = registerScheduleTools(ctx, agent.ctx, agent, () => { runtime.requestDrive(); });
          const stopStatus = agent.ctx.on("agent/status", ({ status }) => { ... });
          runtime.start();
          return async () => { stopStatus(); disposeTools(); ... };
      }, "schedule.runtime()");
      runtimes.set(agent, cleanup);
  });
  ```
  This is the canonical "one plugin instance per agent, tools exposed per agent, listener owned by the agent" shape.
- `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-subagent/lib/index.js:1107-1108` — `handle.agent.ctx.on("agent/inbox/claimed", wakeOnInboxRemoval); handle.agent.ctx.on("agent/inbox/discarded", wakeOnInboxRemoval);`

### Reconstructed — "never in a subagent", both layers

```js
// RECONSTRUCTED FROM TYPES — not copied from any shipped source file.
import { delegationDepthOf } from '@deepseek-ai/dsh-subagent';

// Layer 1 (strongest): never install per-agent work on a child at all.
// Mirrors dsh-schedule/lib/index.js:1459-1483.
ctx.on('agent/created', ({ agent }) => {
  if (!ctx.agents.roots().includes(agent)) return;         // runtime top-level only
  if (delegationDepthOf(agent) > 0) return;                // durable depth floor
  agent.ctx.effect(() => {
    const off = agent.ctx.on('agent/pre-step', preStepHandler(agent));
    const offStop = agent.ctx.on('agent/turn-stopping', turnStoppingHandler(agent));
    return () => { off(); offStop(); };
  }, 'optmem.runtime()');
});

// Layer 2 (defensive): a globally registered listener still refuses children.
// Necessary because a plugin-wide ctx.on('agent/pre-step', ...) sees EVERY agent.
ctx.on('agent/pre-step', async ({ agent, messages, signal }, next) => {
  const decision = await next();
  if (delegationDepthOf(agent) > 0) return decision;       // or === 0 to require top-level
  ...
});
```

---

## 10. Background work

### 10.1 Three distinct mechanisms

**(a) `Agent.runMaintenance` — agent-owned, serialized with turns.**

`/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-agent/lib/types/runtime-types.d.ts:165-174`:

```ts
/**
 * Run one non-turn maintenance task from the true idle phase. The task starts
 * synchronously after claiming that phase; later waking input remains in the
 * inbox until the task settles, while public status stays `idle`.
 * `whenIdle()` follows both the task and any waking work released behind it.
 * @param task - operation whose fulfillment or rejection is preserved, with a signal aborted by {@link cancel}.
 * @throws synchronously when turn-driving or another maintenance task already owns the agent.
 * @returns the task promise.
 */
runMaintenance<T>(task: (signal: AbortSignal) => Promise<T>): Promise<T>;
```

Implementation — `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-agent-loop/lib/index.js:800-828`. `status` stays `idle` for a maintenance phase (`:775-777`). Companion `whenIdle(): Promise<void>` at `runtime-types.d.ts:158-164`.

Shipped precedent: `dsh-compaction`'s `ManualCompactAgentContext` requires exactly this method (`dsh-compaction/lib/types/index.d.ts:51-60`), and `dsh-subagent` uses "The synchronous task entry of `Agent.runMaintenance()` claims the idle phase and closes the private subagent Inbox in the same JavaScript turn before handle disposal" — `dsh-subagent/README.md:97`.

**(b) `ctx.jobs` — the background-job registry.**

`/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-jobs/lib/types/index.d.ts:13-16, 45-56`:

```ts
declare module '@deepseek-ai/cordis' { interface Context { jobs: JobRegistry } }

export declare abstract class JobRegistry extends Service {
    abstract start(spec: JobStart): JobId;
```

Full abstract surface (all in `dsh-jobs/lib/types/index.d.ts`):

| Method | Line |
|---|---|
| `start(spec: JobStart): JobId` | `:56` |
| `list(caller?: Agent): JobSnapshot[]` | `:63` |
| `get(id: JobId, caller?: Agent): JobSnapshot` | `:71` |
| `read(id: JobId, caller?: Agent): JobRead` | `:80` |
| `kill(id: JobId, caller?: Agent, reason?: string): 'requested' \| 'already-finished'` | `:90` |
| `wait(id: JobId, timeoutMs: number, caller?: Agent, signal?: AbortSignal): Promise<JobSnapshot>` | `:102` |
| `onJobDone(listener: JobDoneListener): () => void` | `:111` |
| `onJobsChanged(listener: JobsChangedListener): () => void` | `:134` |
| `attachController(name: string): () => void` | `:142` |

`JobStart` — `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-jobs/lib/types/types.d.ts:39-62`:

```ts
export interface JobStart {
    kind: JobKind;                 // JobKindMap is merge-extensible; shipped: 'bash' | 'subagent' (:19-24)
    label: string;                 // one-line model-facing label
    outputLimitBytes?: number;     // UTF-8 byte cap per completion notice / output read
    owner?: Agent;                 // omitting creates an unowned job
    run(): JobHooks;               // called once, synchronously; a throw leaves nothing registered
}
export interface JobHooks {
    cancel(reason?: string): void;                 // synchronous, idempotent
    done: Promise<JobOutcome>;                     // must not reject
    readOutput?(): string;                         // absence marks a final-output-only job
}
```

`JobOutcome` — `types.d.ts:25-33`: `{ status: 'completed' | 'killed' | 'failed'; detail?: string; output?: string }`. `JobSnapshot` — `types.d.ts:88-119` (`id`, `kind`, `label`, `outputLimitBytes?`, `ownerSession?`, `status`, `detail?`, `startedAt`, `finishedAt?`, `reported`).

**Hard prerequisite**: `start` "refuses work while no attached job controller serves the spec's owner, so a producer cannot start work that owner cannot collect or stop" — `dsh-jobs/lib/types/index.d.ts:37-43`. Shipped controller: `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-tool-jobs/lib/index.js:205` — `ctx.jobs.attachController("tool-jobs");`. A composition that loads no controller cannot start background work (`dsh-jobs/README.md:38-40`).

Implementation: `dsh-jobs-local` provides the in-process registry with a per-owner `maxConcurrentJobsPerOwner` default `10`; records are in-memory and "die with the harness process" (`dsh-jobs-local/README.md:12`, `:38`).

**(c) `ctx.effect(fn, label)` / `agent.ctx.effect(fn, label)`** — fiber-scoped lifecycle work that is neither a job nor a maintenance task; used by `dsh-schedule/lib/index.js:1459-1483` to own per-agent runtimes. Suitable for a compressor that is a long-lived per-agent worker with its own abort controller.

### 10.2 Whether results can be surfaced later

Yes. `onJobDone` is the delivery seam — `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-jobs/lib/types/index.d.ts:103-111`:

> "Register an effect-scoped completion listener. It receives the settlements of the owners its registering context's scope covers; each listener is contained; **returned promises are observed but not awaited**. No listener runs after service disposal."

`JobDoneListener = (snapshot: JobSnapshot, owner: Agent | undefined) => void | PromiseLike<void>` — `types.d.ts:135`. Ordering guarantee: "Completion is announced last, after the record is committed and every other observer of the settlement has seen it, **because a reporter may open a model turn synchronously**." — `index.d.ts:33-36`.

The shipped reporter is the exact recipe to copy — `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-tool-jobs/lib/index.js:206-227`:

```js
ctx.jobs.onJobDone((snapshot, owner) => {
    if (snapshot.reported || owner === void 0) return;
    const message = createUserMessage({
        content: [{ type: "text", text: fitCompletionNotice(snapshot) }],
        source: { kind: "plugin", plugin: "tool-jobs", form: "notice", summary: completionSummary(snapshot) }
    });
    const spent = spentWakes.get(owner) ?? 0;
    if (delivery === "wakeup" && owner.status === "idle" && spent < wakeBudget) {
        spentWakes.set(owner, spent + 1);
        owner.followup(message);          // opens a turn
        return;
    }
    owner.inject(message);                // queues for the next pre-step, no wake
});
```

So: **wake the model with `owner.followup(message)` only under an explicit budget; otherwise `owner.inject(message)`.** Relevant signatures — `followup(message: UserMessage): void` at `runtime-types.d.ts:187-192`; `inject(message: UserMessage): void` at `:201-209`. `owner.status` is `'idle' | 'running'` (`runtime-types.d.ts:90`).

### 10.3 Direct model call

`/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-llm/lib/types/index.d.ts:392-406`:

```ts
/**
 * Stream one model call as raw chunks (token-level deltas). ...
 * @param options - the full request; `options.provider` selects the adapter.
 * @returns the chunk stream, possibly wrapped by `llm/stream` listeners.
 */
stream(options: GenerateOptions): AsyncIterable<StreamChunk>;
```

Abstract adapter face: `abstract stream(options: GenerateOptions): AsyncIterable<StreamChunk>;` — `index.d.ts:182`. **There is no `generate()`**; the only call verb is `stream`. Assemble with `BlockAssembler` — `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-llm/lib/types/assembler.d.ts:22-73`: `push(chunk)` `:32`, `blocks()` `:49`, `interruptedBlocks()` `:57`, `usage` `:59`, `finish` `:61`, `replayState` `:67`, `message(source?)` `:73`.

`GenerateOptions` — `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-llm/lib/types/types.d.ts:403-444`:

```ts
export interface GenerateOptions {
    provider: string;
    model: string;
    reasoningEffort?: ReasoningEffortId;
    messages: Message[];
    system?: string;
    tools?: ToolSchema[];
    temperature?: number;
    maxTokens?: number;
    stop?: string[];
    signal?: AbortSignal;
    sessionId?: Branded<'SessionId'>;
    purpose?: 'compaction' | 'session-title';
}
```

- `signal` — `types.d.ts:432`; "implementations must honor `options.signal`" (`index.d.ts:179-182`). Forward your maintenance/job abort signal so a cancelled job cancels the provider request.
- `purpose` — `types.d.ts:438-443`: "Provider-neutral classification for an auxiliary model call. Adapters may map the purpose to model-hidden transport metadata or purpose-specific generation policy. Ordinary conversation requests leave it unset." It is a **closed two-literal union**, not merge-extensible; a memory compressor must use `'compaction'` or omit it.
- `sessionId` — `types.d.ts:433-437`: "Session identity stamped by the loop for request routing. Replay uses it to separate cursors; adapters may map it to model-hidden transport metadata." `dsh-compaction-basic` passes `agent.session.id` (`lib/index.js:298`).
- `system` — for one-shot callers; the loop leaves it undefined and carries the prompt as a leading system-role message (`types.d.ts:417-421`).

Middleware and failure shape: `ctx.llm.stream` is a `@mode waterfall` event, `'llm/stream'(this: LlmRuntime, options: GenerateOptions, next: () => AsyncIterable<StreamChunk>): AsyncIterable<StreamChunk>` — `index.d.ts:44-46`; "Adapter selection, dispatch, and iteration failures become terminal `error` or `aborted` finish chunks; middleware, nested-call, cleanup, and consumer failures remain thrown." — `index.d.ts:392-399`. So a direct caller must (i) wrap in `try/catch` for thrown middleware errors and (ii) inspect `assembler.finish` for a terminal failure — exactly as `dsh-compaction-basic/lib/index.js:303-307` does via `finishError(assembler.finish)`.

Route resolution for a target model: `resolveModelInfo(provider, model, signal?): Promise<LlmResolvedModelInfo>` — `index.d.ts:354`; `prepareCall(config: LlmCallConfig, signal?): Promise<PreparedLlmCall>` — `index.d.ts:380`.

### 10.4 Reconstructed — background compression

```js
// RECONSTRUCTED FROM TYPES — not copied from any shipped source file.
// Mirrors dsh-jobs/lib/types/{index,types}.d.ts and
// dsh-compaction-basic/lib/index.js:269-317 + dsh-tool-jobs/lib/index.js:206-227.
import { BlockAssembler, createUserMessage } from '@deepseek-ai/dsh-llm';
import { delegationDepthOf } from '@deepseek-ai/dsh-subagent';

// Merge-extend the job-kind namespace (dsh-jobs/lib/types/types.d.ts:19-22).
declare module '@deepseek-ai/dsh-jobs' {
  interface JobKindMap { 'optmem:compress': 'optmem:compress' }
}

function startCompression(agent) {
  if (delegationDepthOf(agent) > 0) return;          // item 9
  const controller = new AbortController();

  ctx.jobs.start({                                   // jobs/index.d.ts:56
    kind: 'optmem:compress',
    label: 'compress memory document',
    outputLimitBytes: 4096,
    owner: agent,                                    // fenced by the owner's session id
    run() {
      const done = (async () => {
        const assembler = new BlockAssembler();
        try {
          for await (const chunk of ctx.llm.stream({   // llm/index.d.ts:406
            provider: route.provider,
            model: route.model,
            messages: [...replayPrefix, createUserMessage({
              content: [{ type: 'text', text: COMPRESS_INSTRUCTION }],
              source: { kind: 'plugin', plugin: 'optmem' },
            })],
            maxTokens: cfg.maxTokens,
            sessionId: agent.session.id,
            purpose: 'compaction',                     // types.d.ts:443 — the only fitting literal
            signal: controller.signal,                 // types.d.ts:432
          })) assembler.push(chunk);
        } catch (error) {
          return { status: 'failed', detail: String(error) };
        }
        if (assembler.finish.kind === 'error' || assembler.finish.kind === 'aborted') {
          return { status: 'failed', detail: assembler.finish.failure.message };
        }
        writeCompressedMemory(assembler.blocks());     // your durable store
        return { status: 'completed', output: assembler.blocks().map((b) => b.text ?? '').join('') };
      })();
      return {
        cancel: (reason) => controller.abort(new Error(reason ?? 'cancelled')),
        done,                                          // must resolve with JobOutcome, must not reject
      };
    },
  });
}

// Surface the result without spending a turn unless explicitly budgeted.
ctx.jobs.onJobDone((snapshot, owner) => {              // jobs/index.d.ts:111
  if (snapshot.reported || owner === undefined) return;
  if (snapshot.kind !== 'optmem:compress') return;
  const message = createUserMessage({
    content: [{ type: 'text', text: compressionNotice(snapshot) }],
    source: { kind: 'plugin', plugin: 'optmem', form: 'notice', summary: boundContextSummary(...) },
  });
  if (owner.status === 'idle' && wakeBudgetLeft(owner)) owner.followup(message);
  else owner.inject(message);
});
```

Note: `dsh-tool-call-timeout-policy` is **not** a background-work seam. It wraps `tools/execute` with a cooperative deadline derived from the tool's own `ToolDefinition.timeoutMs`, swapping a fused signal onto `exec` for dispatch and restoring it in a `finally`; a timed-out call returns `isError: true` with `Error: tool call timed out after <ms>ms` and `{ name: 'ToolTimeoutError', code: 'TOOL_TIMEOUT' }` — `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-tool-call-timeout-policy/README.md:44-56`. It has no configuration and no scheduler; it does not run work outside a turn. Its timeout is read from the tool registry (`ctx.tools.get(exec.name, exec.agent)?.timeoutMs`) — `README.md:66`.

---

## 11. Invariants

Package root: `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-invariants/`.

### The `ctx.invariants` API

`/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-invariants/lib/types/index.d.ts:20-80`:

```ts
export type InvariantFailure = (message: string) => never;

export interface InvariantInstaller {
    (ctx: Context, fail: InvariantFailure): void | Promise<void>;
    /** Services the child installer fiber may access. */
    readonly inject?: Inject;
}

export declare class InvariantError extends Error {
    readonly code: "INVARIANT";
    readonly packageName: string;
    constructor(packageName: string, message: string);
}

declare module '@deepseek-ai/cordis' {
    interface Context { invariants: InvariantRegistry; }
}

export declare class InvariantRegistry extends Service {
    static Config: Schema<Config>;
    register(packageName: string, installer: InvariantInstaller): () => void;   // :80
}
```

`Config` — `index.d.ts:11-19`: `{ enabled?: boolean /* default true */; package_allowlist?: string[]; package_blocklist?: string[] }`, where the two lists are "Case-sensitive JavaScript regex sources" (`:15-18`).

Registration semantics — `index.d.ts:72-80`: "Register one package's invariant installer. The package name is reserved even when filtering disables its checks. Enabled installers run in a child fiber; failure disposes that fiber and releases the reservation." Implementation: `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-invariants/lib/index.js:80-96` — the registry merges `installer.inject` onto a wrapper that binds `fail` to the registering package name and mounts it via `ctx.plugin(...)` in a child fiber.

### What a minimal companion looks like

The companion is a **separate module exported at `./invariant`** from the package (see `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-agent/package.json` `exports["./invariant"] → { types: "./lib/types/invariant.d.ts", default: "./lib/invariant.js" }`). It is a normal Cordis plugin exporting `name`, `inject`, and `apply`.

The shipped `dsh-agent` companion is the smallest complete example — `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-agent/lib/invariant.js:1-23`, reproduced verbatim (23 lines):

```js
/** Package-owned agent lifecycle invariants. @module @deepseek-ai/dsh-agent/invariant */
const PACKAGE_NAME = "@deepseek-ai/dsh-agent";
/** Cordis companion plugin name. */
const name = "agent-invariant";
/** Services required before the companion can register. */
const inject = ["invariants"];
/** Install the agent contribution into its child registration fiber. */
const install = (ctx, fail) => {
	const lastStatus = /* @__PURE__ */ new WeakMap();
	ctx.on("agent/status", ({ agent, status }) => {
		if (lastStatus.get(agent) === status) fail(`agent/status repeated ${status} (no-op transition)`);
		lastStatus.set(agent, status);
	}, { global: true });
};
/**
* Register the agent invariant companion.
* @param ctx - Cordis context carrying the invariant service.
* @returns the installed registration's disposer after setup succeeds.
*/
const apply = (ctx) => Promise.resolve(ctx.invariants.register(PACKAGE_NAME, install));
export { apply, inject, name };
```

Its declaration — `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-agent/lib/types/invariant.d.ts:1-12`:

```ts
export declare const name = "agent-invariant";
export declare const inject: string[];
export declare const apply: (ctx: Context) => Promise<() => void>;
```

A richer companion that validates a plugin's own durable injected messages — `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-time-context/lib/invariant.js:90-207`:

```js
const PACKAGE_NAME = "@deepseek-ai/dsh-time-context";          // 92
const SOURCE_NAME = "time-context";
const READING = /* @__PURE__ */ new RegExp("^Time sampled while preparing turn ...");
const name = "time-context-invariant";
const inject = ["invariants"];
const install = Object.assign((ctx, fail) => {                  // 191
	for (const session of ctx.sessions.list()) validateSession(session, fail);
	ctx.on("session/created", (session) => { validateSession(session, fail); }, { global: true });   // 192
	ctx.on("internal/dispatch", (_mode, eventName, args) => {   // 195
		if (eventName !== "session/event") return;
		const [session, event] = args;
		if (event.type !== "user/message" || event.data.source.kind !== "plugin" || event.data.source.plugin !== SOURCE_NAME) return;
		validateReading(session.snapshotEvents(), event, fail);
	}, { global: true });
}, { inject: ["sessions"] });                                   // 205
const apply = (ctx) => Promise.resolve(ctx.invariants.register(PACKAGE_NAME, install));  // 207
export { apply, inject, name };
```

Note three reusable techniques there: `ctx.sessions.list()` / `session.snapshotEvents()` for a full-log re-validation of already-loaded sessions; `session/created` for newly loaded ones; and `internal/dispatch` filtered to `session/event` for newly appended ones. `{ global: true }` bypasses scope filtering.

Mounting, from `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-invariants/README.md:74-88`:

```ts
import type { Context } from '@deepseek-ai/cordis'
import InvariantRegistry from '@deepseek-ai/dsh-invariants'
import * as SessionInvariant from '@deepseek-ai/dsh-session/invariant'

declare const ctx: Context

ctx.plugin(InvariantRegistry, { enabled: true })
ctx.plugin(SessionInvariant)
```

Failure shape — `README.md:90`: "A violation throws an `InvariantError` from the context that reported it: it carries the stable code `INVARIANT`, the full npm `packageName` of the owning package, and a message prefixed `invariant violated by "<package>": …`."

Design rule — `README.md:105`: "**Real relationships, not synthetic assertions.** A companion checks an event-stream or mutable-data relationship its package owns; confirming a method, plugin name, injection, or fixed pure result is a type, load, or unit-test concern, never a runtime invariant." "Companion wiring is mechanically enforced" by `pnpm run verify-package-invariants` (`README.md:107`), which "rejects empty installers, installers that omit or ignore the reporter, wrong registration names, incomplete publication wiring, and stale wiring for omitted companions".

Note: `dsh-base` deliberately ships **no** runtime diagnostics; the registry is mounted by `dsh-sdk-minimal` with the four core companions — `README.md:30`. A custom composition must mount the registry explicitly.

---

## Gaps / could not determine

Stated plainly; none of these are guessed at above.

1. **`SessionStartSource` value `'compact'` has no shipped emitter.** Declared at `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-agent/lib/types/runtime-types.d.ts:105`; the only emit site is the `source` parameter of `setupAndPublish` (`dsh-agent-loop/lib/index.js:1720`, `:1840`), and grep over every shipped package found only `"startup"` (`:1763`, `:1834`) and `"resume"` (`:1925`). `'clear'` is likewise unemitted. I could not determine what would produce `'compact'`; it is plausible that only a composition driving `setupAndPublish` directly (or a future/removed plugin) does. **Do not make "session-start fires with `source === 'compact'` after every compaction" a load-bearing assumption.** The verified substitutes are `agent/pre-step` (runs before every request) and `compaction/end` on `session/event`.
2. **No `ctx.llm.generate()`.** Only `stream(): AsyncIterable<StreamChunk>` (`dsh-llm/lib/types/index.d.ts:406`). Any non-streaming convenience API would have to be written on top of `BlockAssembler`.
3. **`GenerateOptions.purpose` is a closed literal union** `'compaction' | 'session-title'` (`dsh-llm/lib/types/types.d.ts:443`). Unlike `MessageSourceMap`, `JobKindMap`, and `SessionEventMap` it is not declared as a merge-extensible interface, so a plugin cannot add a purpose without patching the package. Whether TypeScript module augmentation of a type alias is possible here: **no**, and I did not find any widening mechanism.
4. **No Claude Code `PreCompact` / `PostCompact`.** Explicitly listed as unsupported — `dsh-hooks-claude-code/README.md:174`. This seam does not exist as described in the question's framing.
5. **No Cordis event for compaction.** `dsh-compaction` and `dsh-compaction-basic` declare no `ctx.emit`/`ctx.on("compaction…")`; `compaction/start|summary|end|prune` are **session event types** (`dsh-compaction/lib/types/types.d.ts:14-99`). Observation is limited to `session/event`, `agent/pre-step`, and `surface.replaceGeneration`.
6. **No string token-counting API in `ctx.tokenMeter`.** No `countTokens(string)` exists. The only string route is `estimateContent([{ type: 'text', text }])` (`dsh-token-meter/lib/types/estimate.d.ts:25`), which is the fixed 4-chars-per-token heuristic (`README.md:85`), explicitly approximate and known to underprice CJK and JSON (`README.md:64`). Exact counts would require a provider tokenizer, which the package states it is not (`README.md:135`).
7. **Pre-step message role.** `PreStepDecision.messages` is typed `UserMessage[]` (`runtime-types.d.ts:96`). I found no shipped plugin that injects an `assistant`- or `system`-role message through pre-step; `system/message` events come from the system-prompt projection at `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-agent-loop/lib/index.js:1023-1027`, and `createSystemMessage(text, plugin)` (`dsh-llm/lib/types/message.d.ts:200`) is not routed through pre-step. Whether a plugin could inject a system-role message some other way is not determined.
8. **`compactRegion` from a non-backend plugin is unverified in practice.** It is a public abstract method (`dsh-compaction/lib/types/index.d.ts:130`) and any holder of `ctx.compaction` can call it, but the only shipped caller of anything is `dsh-command-compact` calling `compactNow` (`dsh-command-compact/lib/index.js:54`). `compactRegion` additionally requires balanced edges (`toolPairingBalancedBefore/After`, `dsh-compaction/lib/types/tool-pairing.d.ts:15-25`) and mutates the live surface. No shipped example exists.
9. **`ctx.jobs.start` requires an attached controller for the owner.** `dsh-jobs/lib/types/index.d.ts:37-43`. The shipped controller comes from `dsh-tool-jobs` (`dsh-tool-jobs/lib/index.js:205`). I did not find a controller-agnostic way to start background work, nor a list of which compositions attach one; a memory plugin must either require `dsh-tool-jobs` in its composition or call `ctx.jobs.attachController(<name>)` itself (which the contract permits — `dsh-jobs/lib/types/index.d.ts:135-142` — but I found no shipped plugin other than `dsh-tool-jobs` doing it).
10. **Jobs are in-process and non-durable.** `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-jobs-local/README.md:12`: "jobs die with the harness process and are not durable across restarts"; `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-jobs/README.md:120`: "**The contract is in-process** — `JobStart.run()` passes callbacks and exact `Agent` objects; a durable or cross-process backend must reshape identity, restart, ownership, and observation semantics before it can implement this seam." A compression job interrupted by process exit leaves no record. Whether the plugin should instead persist a "compression pending" fact in the session log (the only durable channel) is a design question this research cannot answer.
11. **Scope routing for an unscoped plugin listener is inferred, not runtime-verified.** The type doc says scope-filtered dispatch gives agent-scoped listeners only their agent (`dsh-session/lib/types/index.d.ts:57-59`), which implies a plugin registering on its own (unscoped) `ctx` receives events for every session/agent. I did not execute anything to confirm which layer wins for a plugin loaded at the host composition root.
12. **`agent-instructions` does not expose the escape/bounding helpers.** `lib/index.js:1311` exports only `{ Config, apply, discoverBaselineInstructionFiles, inject, loadBaselineInstructions, name, renderWorkspaceContext }`. `escapeInstructionFrameBody`, `truncateUtf8`, `buildInstructionText`, and `workspaceBaselineIdentity` are module-private, so a memory plugin cannot import them; the reconstructed code in item 5 reimplements them.
13. **Compiled-line drift risk.** Every line number here is from this install's `lib/*.js` / `lib/types/*.d.ts`. The install ships no `src/`, so README links such as `src/index.ts` (`dsh-agent-instructions/README.md:72`) cannot be resolved, and line numbers will not correspond to the upstream TypeScript sources. Version-specific: package manifests pin `^0.1.5-rc.2` peer ranges (e.g. `/home/igor/.local/lib/node_modules/@deepseek-ai/dsh/node_modules/@deepseek-ai/dsh-agent/package.json`).
14. **`summarize()` override narrows its agent parameter.** The base declares `CompactionAgentContext` (`dsh-compaction/lib/types/index.d.ts:89`, `:110`, `:130`) while `BasicCompactionEngine` declares `Agent` (`dsh-compaction-basic/lib/types/index.d.ts:60`, `:70`, `:79`). TypeScript accepts this by method bivariance, but a subclass written with `strictFunctionTypes` semantics awareness should mirror the base signature rather than the shipped override. I did not verify which the compiler prefers under `strict`.
