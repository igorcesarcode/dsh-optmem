# 12 — Observabilidade, eventos e invariantes

## Objetivo

Tornar o comportamento do plugin verificável **depois** do fato. Memória é um
sistema cujo estado é difícil de inspecionar (o que o agente "sabe" é difuso) e
cujo custo é invisível (tokens). Sem observabilidade, os dois viram fé.

## Eventos de sessão

O plugin declara eventos próprios no mapa de eventos de sessão (log-only, sem
`surfaceOp`, no mesmo padrão dos eventos `compaction/*` e `hook/*` do harness).
Eles nunca aparecem na superfície derivada — são registro, não conversa.

| Evento | Quando | Payload |
|---|---|---|
| `optmem/note` | uma memória é gravada | `id`, `namespace`, `origin`, `bytes`, `sessionId`, `turn` |
| `optmem/inject` | o documento é injetado | `namespace`, `memories`, `blocks`, `tokens`, `lines`, `reason` |
| `optmem/compress` | um bloco é comprimido | `lo`, `hi`, `size`, `tokensIn`, `tokensOut`, `model`, `durationMs`, `truncated` |
| `optmem/compress-failed` | compressão falha | `lo`, `hi`, `attempt`, `error`, `degraded` |
| `optmem/skip` | uma decisão de não injetar | `reason` (`subagent` \| `already-visible` \| `disabled` \| `store-error`) |
| `optmem/store-error` | leitura ou escrita falha | `op`, `path`, `error` |

Regras:

- **E1.** Todo evento é tipado e validado por um companion de invariantes.
- **E2.** Payload nunca contém o **texto** de uma memória. Contém ids e contagens.
  O conteúdo já está em `LOG.txt`; duplicá-lo no log de sessão multiplicaria o
  vazamento de dados pessoais sem ganho de auditoria.
- **E3.** `optmem/inject` é obrigatório mesmo quando nada é injetado (com
  `reason`): "não injetei" precisa ser tão observável quanto "injetei".
- **E4.** Eventos ficam dentro de um turno quando o turno existe; os de boot não.

## Companion de invariantes

O companion é um export separado no subpath `./invariant` do próprio pacote, com
`name`, `inject` e `apply`. A forma verificada no harness é:

```ts
export const name = 'optmem-invariant'
export const inject = ['invariants']
export const apply = (ctx) => ctx.invariants.register(PACKAGE_NAME, (ctx, fail) => {
  // ctx.on('session/event', …) e `fail(...)` na violação
})
```

Ele verifica, sobre o log de sessão:

| # | Invariante |
|---|---|
| I1 | Todo `optmem/compress` referencia um bloco `[lo,hi)` alinhado, potência de dois, `size ≥ 2` |
| I2 | Nunca existem dois `optmem/compress` para o mesmo bloco e namespace |
| I3 | `tokensIn`/`tokensOut` são finitos, positivos e ≤ `compression.maxJobTokens` |
| I4 | `optmem/note` tem `origin` no conjunto fechado e `depth == 0` |
| I5 | `optmem/inject` tem `tokens ≤ wake.budgetTokens` |
| I6 | Nenhum payload contém campo com o texto da memória |
| I7 | `optmem/skip` com `reason = 'subagent'` nunca é seguido de `optmem/inject` na mesma sessão |

I7 é a que mais importa na prática: ela transforma "o subagente não recebe
memória" de uma intenção de código em uma propriedade verificável do histórico.

## Diagnóstico

`memory_config` (tool) e o painel web expõem o mesmo instantâneo:

```jsonc
{
  "namespaces": [
    { "name": "user",      "memories": 412,  "bytes": 131840, "summaries": 38 },
    { "name": "workspace", "memories": 1284, "bytes": 410880, "summaries": 140 }
  ],
  "wake": { "budgetTokens": 8000, "lastTokens": 7842, "lastLines": 61 },
  "compression": {
    "mode": "background", "lazy": true,
    "pending": 3, "degraded": 1,
    "calls": 178, "tokensIn": 267000, "tokensOut": 17800
  },
  "store": { "dir": "…", "role": "writer", "format": 1, "corrupt": false }
}
```

Este instantâneo responde, sem instrumentar nada, as três perguntas que o usuário
realmente faz: **quanto custa**, **o que está pendente**, e **está saudável**.

## Registro de diagnóstico (log de arquivo)

Além dos eventos de sessão, o plugin escreve um log de arquivo enxuto por
namespace, com rotação por tamanho:

- decisões de cobertura (orçamento pedido vs. obtido, número de lacunas);
- custo por job de compressão;
- falhas de store e de provedor.

Nunca contém texto de memória, pela mesma razão de E2.

## Critérios de aceitação

- **CA1.** Cada um dos sete eventos é emitido no caminho correspondente, e um
  teste verifica a presença e o payload de cada um.
- **CA2.** O companion de invariantes rejeita, em teste, uma violação de cada uma
  das sete invariantes.
- **CA3.** Nenhum payload de evento contém o texto de uma memória: teste que
  grava uma memória com uma string sentinela e verifica que ela não aparece em
  nenhum evento do log de sessão.
- **CA4.** `memory_config` reporta `lastTokens` igual ao valor realmente medido na
  última injeção (comparado com o medidor do harness).
- **CA5.** `optmem/skip` é emitido para cada uma das quatro razões, em teste.
- **CA6.** Um store em estado `corrupt` aparece como `corrupt: true` antes de
  qualquer tentativa de escrita.
- **CA7.** O log de diagnóstico rotaciona e nunca excede `diagnostics.maxBytes`
  (padrão 1 MiB) por namespace.
