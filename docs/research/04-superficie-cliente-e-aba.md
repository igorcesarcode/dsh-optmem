# 04 — Superfície de cliente e a aba nativa

Levantamento feito por leitura direta do pacote publicado
(`@deepseek-ai/dsh@0.1.5-rc.1` e pacotes `0.1.5-rc.2` em `node_modules/`), em
2026-09-30. Complementa [02-client-web-kit.md](02-client-web-kit.md), que chegou
às mesmas conclusões por outro caminho.

## A pergunta

É possível um plugin de terceiro acrescentar uma **aba nativa** ao lado de "Chat" e
"Trajectory" na GUI Web, sem fork do monorepo?

## Resposta

**Sim.** Em duas partes: o registro da aba é um slot do cliente, e a entrega do
código de cliente é um pacote de duas metades.

### 1. A aba é uma entrada no slot `conversation.view`

O contrato está declarado em
`dsh-client-ui-conversation/lib/types/client/contract/views.d.ts`:

```ts
/** One conversation view tab, projected from a 'conversation.view' slot
 *  entry's registration options (label falls back to the entry id). */
export interface ViewTab {
  id: string
  label: string
}
```

E `view-selection.d.ts` documenta a resolução:
*"Resolve a preferred registered View, then Chat, without choosing another View"* —
ou seja, a aba "Chat" é apenas a entrada padrão, e qualquer entrada registrada no
slot vira uma aba irmã.

O registro real, extraído de `dsh-client-ui-trajectory/lib/client.js`:

```js
ctx.slots.inject("conversation.view", () => ctx.slots.register({
  name: "conversation.view",
  id: "trajectory",
  order: 10,
  locale: NS,
  label: () => t("view.trajectory"),
  children: { "conversation.trajectory.images": { kind: "single", scope: "session" } },
  inject: (sessionId) => { /* props do componente */ },
}))
```

Pontos verificados:

- `ctx.slots.inject(key, fn)` + `ctx.slots.register({ name, id, order, locale, label, children, inject })`.
- `label` vem do serviço de locale; o `id` é o fallback.
- O registro **"rides the slot service's effect wrapper, so plugin unload removes
  the tab"** (`dsh-client-ui-trajectory/lib/types/client/index.d.ts`).
- O tab do Trajectory é descrito como *"pure-consumer plugin registering into the
  conversation ViewMap (no service)"* — ele não define serviço nenhum, só consome.

### 2. O código de cliente é entregue por um pacote de duas metades

De `dsh-client-modules/README.md`:

> "`dsh-client-modules` turns a plugin package's `dsh.client` declaration into a
> loadable browser bundle: **the host half scans enabled Loader entries and composes
> the boot graph**, an available Web carrier serves each bundle over `/plugins`."

> "A browser plugin package declares `dsh.client` in its `package.json` with
> `platform: 'web'`, exports a `./client` bundle, and lists any non-baseline module
> requests under `dsh.client.external`."

E o manifesto real de um pacote de cliente
(`dsh-client-ui-trajectory/package.json`):

```json
"exports": {
  ".":        { "types": "./lib/types/index.d.ts", "default": "./lib/index.js" },
  "./client": { "types": "./lib/types/client/index.d.ts", "default": "./lib/client.js" }
},
"dsh": {
  "client": {
    "inject": ["@deepseek-ai/dsh-api-session-controller", "@deepseek-ai/dsh-client-locale",
               "@deepseek-ai/dsh-client-ui-conversation", "@deepseek-ai/dsh-client-ui-renderer",
               "@deepseek-ai/dsh-client-ui-session"],
    "platform": "web"
  }
},
"scripts": { "bundle": "tsdown", "watch": "tsdown --watch" }
```

A descoberta é **Loader-driven e relativa ao pacote**: `dsh-client-modules/lib/index.js`
escaneia as entradas habilitadas do Loader e resolve cada `dsh.client` contra o
`package.json` do próprio pacote. Não há lista de permissão nem caminho que assuma
o layout do monorepo (`02-client-web-kit.md` §6.3–6.4).

### 3. Tempo real: de onde vêm os dados

Dois canais, com papéis distintos:

| Canal | Mecanismo | O que serve |
|---|---|---|
| **Fluxo ao vivo** | eventos de sessão, os mesmos que o Trajectory consome via `dsh-api-session-controller` | memória gravada, compressão concluída, injeção, skip, compactação — tudo que acontece **nesta sessão**, sem polling |
| **Consulta sob demanda** | `host.call(method, args)` da metade browser para a metade host | lista completa, busca, `zoom`, contagens, saúde do store |

O primeiro canal é gratuito em termos de desenho: a spec 12 já declara os eventos
`optmem/*` como eventos de sessão, e `compaction/*` **já é** evento de sessão
(`dsh-compaction/lib/types/types.d.ts`). Ou seja, "memórias e compactações em
tempo real" sai do mesmo mecanismo que o Trajectory usa para desenhar o ledger.

Limite honesto: o canal ao vivo cobre **a sessão aberta**. Atividade de outra
sessão paralela no mesmo store não passa por este log de sessão. Para isso é
preciso um canal de push da metade host — desenho a confirmar no protótipo.

### 4. Custos verificados (todos do lado do build)

1. **O preset de build não é publicado.** O `clientBundle` preset que emite o
   formato lazy-CJS vive em `packages/client/tsdown.client.ts` no monorepo, e o
   texto publicado diz isso explicitamente
   (`dsh-client-ui-settings-plugins/README.md`): *"a plugin outside this repository
   has to reproduce that build itself"*.
2. **O bundle é shipado pronto.** O host nunca builda; bundle ausente é falha dura
   de ativação: *"client-modules: client bundle not found; run `pnpm run build`
   before launch"*.
3. **Os tipos de slot não são publicados.** `@deepseek-ai/dsh-client-ui-slots` não
   existe no install, embora as augmentations de `SlotMap` apontem para ele —
   integração de tipos exige um shim de declaração escrito à mão.
4. **`pnpm run dev:web` não existe no install publicado.** É script de raiz do
   workspace; para um plugin de terceiro o watch é o próprio `tsdown --watch`
   escrevendo `lib/client.js`, que é o que o receptor de HMR observa.

O que isso significa na prática: a pergunta de **arquitetura** está decidida
(sim), a de **esforço** não. Não existe exemplo publicado de bundle construído fora
do repositório. O formato exato — externos emitidos como chamadas `require()`,
`id` igual ao nome do pacote, wrapper de fábrica lazy-CJS, convenção de tag de CSS,
trailer de sourcemap — precisa ser reproduzido e provado por um protótipo **antes**
de o painel virar compromisso de entrega.

## Ajuste de rota

O settings de terceiro **é** suportado por desenho declarado: *"Keying on the
namespace is what lets a plugin distributed outside this repository contribute a
card: it registers its own settings namespace on the Host and its own card under
that key in the browser"* (`dsh-client-ui-settings-plugins/lib/types/client/slot-contract.d.ts`).
Isso confirma a spec 11 §configuração.

O item que era um *spike* de viabilidade (issue 19) passa a ser um **protótipo de
formato de bundle**: a resposta arquitetural já existe, falta provar que o formato
é reprodutível fora do repositório.

## Fontes

- `dsh-client-ui-conversation/lib/types/client/contract/views.d.ts`
- `dsh-client-ui-conversation/lib/types/client/view-selection.d.ts`
- `dsh-client-ui-trajectory/lib/client.js`, `lib/types/client/index.d.ts`, `package.json`
- `dsh-client-modules/README.md`, `lib/index.js`
- `dsh-cordis-client-runner/README.md`
- `dsh-client-ui-layout/README.md`
- `dsh-client-ui-settings-plugins/lib/types/client/slot-contract.d.ts`
- [02-client-web-kit.md](02-client-web-kit.md) — levantamento completo, §6
