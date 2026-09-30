# 07 — Sobrevivência à compactação

## Objetivo

Garantir que a memória continue visível ao modelo **depois** que o DSH compactar a
conversa — e, opcionalmente, colher memória do trecho que está prestes a ser
sombreado.

## O problema

O DSH condensa histórico antigo em uma mensagem de resumo e continua a conversa
como se o resumo sempre tivesse existido. O documento de memória injetado no
início da sessão é apenas mais uma mensagem no histórico: quando a compactação
escolhe uma faixa que o inclui, ele **sai da superfície derivada** e o modelo para
de vê-lo.

O modo de falha é silencioso e particularmente ruim: o agente perde a memória
justamente no momento em que a conversa está longa o bastante para precisar dela.

## Solução v1 — verificação de visibilidade

Não confiar em um evento único. A cada passo elegível, o injetor verifica se a sua
última injeção ainda está visível na superfície derivada:

```
pre-step:
  se nunca injetei nesta sessão:            injeta
  senão se a última injeção não está mais
        na superfície derivada:             injeta de novo
  senão:                                    não faz nada
```

- O identificador da última injeção é guardado por sessão, em memória.
- A verificação de visibilidade usa a projeção da sessão, com cache por revisão
  da superfície, para não custar uma varredura por passo.
- Isto cobre **todas** as causas de sombreamento — compactação automática,
  compactação manual (`/compact`), poda de resultados de ferramenta — e não só a
  compactação que dispara `session-start` com fonte `'compact'`.

O gatilho barato é `compaction/end`, observado no fluxo de eventos de sessão
(`ctx.on('session/event', …)`): ele invalida o cache de visibilidade para que a
próxima verificação aconteça imediatamente, em vez de esperar o resultado de uma
checagem que talvez já esteja em cache.

**Não** existe gatilho por `agent/session-start` com fonte `'compact'`. Esse valor
é declarado em `SessionStartSource`, mas o harness publicado nunca o emite: o
único ponto de emissão passa apenas `'startup'` e `'resume'`. Construir a
re-injeção sobre ele seria construir sobre um seam que não dispara — e o modo de
falha seria a memória sumir em silêncio depois da primeira compactação.

Também não existe evento cordis em volta da compactação: `compaction/*` são
**eventos de sessão**, não eventos de plugin. É por isso que a observação é por
`session/event`.

## Solução v2 — colheita na compactação (opcional, desligada por padrão)

A compactação é o momento em que contexto valioso está prestes a ser perdido.
Uma segunda função, atrás de `compaction.harvest = true`:

1. Observar a compactação (eventos de sessão `compaction/start`, `compaction/summary`,
   `compaction/end`).
2. Ler da sessão bruta — não da superfície — a faixa que foi sombreada.
3. Pedir ao modelo que extraia candidatos a memória durável daquela faixa, no
   mesmo contrato de linha única da spec 06.
4. Gravar os candidatos com `origin = 'agent-inference'` e
   `refs = [compactionId]`, **sujeitos à mesma política de aprovação** de qualquer
   escrita (spec 09).

Por que desligado por padrão: acrescenta uma chamada de LLM por compactação, um
novo modo de falha, e memória gerada por inferência é de qualidade inferior à
memória que o agente decidiu registrar deliberadamente. É um recurso para quem
quer captura automática, não o comportamento padrão.

Nota de implementação: o bridge de hooks do Claude Code **não** suporta
`PreCompact`/`PostCompact`, então este caminho só existe como plugin nativo — o
que é mais um argumento para o plugin nativo existir.

## Interação com o orçamento

Depois de uma re-injeção, o orçamento é o mesmo `wake.budgetTokens`: não há
acúmulo. A re-injeção substitui a anterior na prática, porque a anterior já não
está visível. Se por algum motivo as duas estiverem visíveis (compactação parcial
que preservou a primeira), o injetor **não** injeta de novo — a verificação de
visibilidade impede duplicação, e isso é testado.

## Configuração

| Config | Padrão | Significado |
|---|---|---|
| `injection.recheckEveryStep` | `true` | verificar visibilidade a cada passo |
| `injection.recheckOnCompactionEnd` | `true` | invalidar o cache ao ver `compaction/end` |
| `compaction.harvest` | `false` | colher memória da faixa sombreada |
| `compaction.harvestMaxCandidates` | `5` | teto de candidatos por compactação |

## Critérios de aceitação

- **CA1.** Após uma compactação automática que sombreia o documento de memória, o
  próximo passo do agente contém um documento novo, e o documento anterior não
  está na superfície derivada.
- **CA2.** Após `/compact` manual, o mesmo vale.
- **CA3.** Duas compactações consecutivas produzem exatamente duas injeções no
  total, e não três.
- **CA4.** Uma compactação que **não** sombreia o documento não produz
  re-injeção (verificar por contagem de mensagens com fonte do plugin).
- **CA5.** Com `injection.recheckEveryStep = false`, a re-injeção depende apenas do
  gatilho `compaction/end` — e o teste documenta o caso em que isso falha (uma
  compactação que não emite o evento observável, ou uma poda que sombreia sem
  compactar), para deixar claro por que o padrão é `true`.
- **CA6.** Com `compaction.harvest = true`, uma compactação que descarta uma
  decisão registrada explicitamente produz um candidato a memória que a contém, e
  nenhum candidato é gravado sem passar pela política de escrita.
- **CA7.** A verificação de visibilidade não adiciona mais de 1 ms por passo em
  uma sessão com 500 mensagens (medido com o medidor de tokens do harness como
  referência de instrumentação).

## Evidência

- Compactação substitui uma faixa por uma mensagem de resumo; a faixa sombreada
  permanece no log bruto e sai da superfície derivada: `@deepseek-ai/dsh-compaction/README.md`.
- Ler a sessão **bruta** em vez da superfície derivada, incluindo mensagens
  sombreadas por compactação, é o que `@deepseek-ai/dsh-time-context` faz: varredura
  de seqs brutos com `Session.eventAt(SessionSeq(n))` e fold em
  `ctx.sessionProjections.register(...)` que casa
  `event.data.source.kind === 'plugin' && event.data.source.plugin === …`
  (`dsh-time-context/lib/index.js:135-143`, `:181-219`).
- `compaction/start|summary|end` são tipos de evento de sessão, sem evento cordis
  correspondente: `@deepseek-ai/dsh-compaction/lib/types/types.d.ts:14-99`.
- `PreCompact`/`PostCompact` **não** são suportados pelo bridge de hooks do Claude
  Code: `@deepseek-ai/dsh-hooks-claude-code/README.md:174`.
- `'compact'` em `SessionStartSource` não tem emissor:
  `@deepseek-ai/dsh-agent/lib/types/runtime-types.d.ts:105` declara, e os call sites
  de `setupAndPublish`/`publish` em `@deepseek-ai/dsh-agent-loop/lib/index.js:1763`,
  `:1834` e `:1925` passam apenas `"startup"` e `"resume"`.
