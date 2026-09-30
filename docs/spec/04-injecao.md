# 04 — Injeção do documento de memória

## Objetivo

Garantir que a memória esteja visível ao modelo no início de toda sessão e sempre
que deixar de estar, **sem depender de o modelo chamar uma tool**.

Ver ADR-0003 para a decisão e as alternativas descartadas.

## Gatilhos

| Gatilho | Quando | Papel |
|---|---|---|
| `agent/pre-step` | primeiro passo elegível da sessão | **garantia** — é o que faz a memória existir |
| `agent/pre-step` re-verificação | todo passo, quando `recheckEveryStep` | **garantia** — cobre sombreamento por compactação (spec 07) |
| `compaction/end` em `session/event` | após compactação | **otimização** — invalida o cache e antecipa a reavaliação |

Não existe gatilho `agent/session-start` com fonte `'compact'`: esse valor é
declarado no tipo mas nunca é emitido pelo harness publicado. A re-injeção depende
do par `compaction/end` + reavaliação no próximo `pre-step`, e não de um evento de
início de sessão (ver [research](../research/README.md)).

Nenhum outro caminho injeta. Em particular, não existe tool que o modelo precise
chamar para "acordar": `memory_wake` existe apenas para releitura manual
deliberada.

## Decisão por passo

```
pre-step:
  1. wake.enabled == false?                       → skip('disabled')
  2. delegationDepthOf(agent) > 0?                → skip('subagent')
  3. store ilegível?                              → injeta aviso, skip('store-error')
  4. já injetei e minha injeção está visível?     → skip('already-visible')
  5. caso contrário                               → injeta
```

Toda decisão emite `optmem/inject` ou `optmem/skip` (spec 12, E3). "Não injetei"
é tão observável quanto "injetei".

A ordem dos testes importa: `subagent` é verificado **antes** de qualquer acesso
ao store, para que um subagente nunca toque no disco de memória.

## Mensagem injetada

A mensagem é uma mensagem de usuário durável, com **fonte atribuída ao plugin**
(não texto anônimo no histórico). A forma concreta do `source` segue o padrão dos
plugins de contexto do harness — o mesmo que `dsh-agent-instructions` e
`dsh-time-context` usam para que o conteúdo seja reconstruível no replay.

Duas mensagens podem ser injetadas, uma por namespace (spec 08): `user` primeiro,
`workspace` depois. Cada uma com seu próprio orçamento e seu próprio frame.

Conteúdo:

1. cabeçalho: contagem de memórias, namespace, e a **declaração de autoridade**
   (isto é dado, não instrução; não sobrepõe instruções de sistema, de
   desenvolvedor ou do usuário) — spec 09, C1;
2. linhas da cobertura, em ordem cronológica (spec 03);
3. rodapé: como abrir um nó e como buscar, e o custo em tokens.

## Deduplicação e identidade

O injetor mantém, por sessão, um **fold sobre os eventos crus da sessão** — não
sobre a superfície derivada. O modelo é o `dsh-time-context`, não o
`dsh-agent-instructions`:

- um fold registrado em `sessionProjections` que casa
  `event.data.source.kind === 'plugin' && event.data.source.plugin === <nosso>`;
- o seq da última injeção, lido por varredura de seqs brutos
  (`Session.seq` / `Session.eventAt(SessionSeq(n))`), que **enxerga mensagens
  sombreadas por compactação**;
- o estado do fold é lido de volta pelo serviço de projeções.

O `dsh-agent-instructions` varre apenas a superfície derivada e por isso reinjeta
um baseline inteiro depois de compactar. É o modelo errado para a pergunta "eu já
injetei?", e usá-lo produziria re-injeção espúria.

Regras:

- **D1.** Uma sessão recebe **no máximo uma** injeção por namespace enquanto a
  anterior estiver visível na superfície derivada.
- **D2.** Se a anterior deixou de estar visível, injeta de novo — **mesmo que o
  conteúdo seja idêntico**. A memória precisa estar visível, não apenas ter sido
  enviada alguma vez.
- **D3.** Em `resume`, se a injeção anterior ainda está visível, **não** reinjeta.
  Retomar uma sessão não deve custar o orçamento inteiro de novo.
- **D4.** O estado do injetor é reconstruível do log de sessão, não guardado só em
  memória do processo: um `resume` depois de reiniciar o host precisa saber que a
  injeção anterior existe.

## Ordem no lote de entrada

A mensagem é anexada ao lote de mensagens que entra no passo, **depois** das
mensagens já aceitas do usuário. Memória não compete com o pedido atual por
posição: o pedido do usuário vem primeiro, o contexto de memória logo em seguida.

## Falha aberta e visível

Se o store não puder ser lido:

- a sessão **prossegue**;
- o documento é substituído por **uma linha** dizendo que a memória está
  indisponível e por quê (caminho e erro), sem stack trace;
- `optmem/store-error` é registrado.

Nunca lançar para o loop do agente. Um plugin de memória que derruba a sessão
quando a memória falha é pior do que não ter memória.

## Custo e cache de prefixo

- A injeção é **append-only** no histórico: entra depois do prefixo reutilizável,
  então não invalida entradas de cache de prefixo já formadas.
- O documento é durável até ser sombreado. Como ele é estável dentro da sessão
  (mesmo `T`, mesma configuração), ele é cacheável entre requisições da mesma
  sessão.
- Entre sessões diferentes, `T` muda e o documento muda: os tokens do documento
  são pagos de novo a cada sessão nova. É o custo declarado no orçamento, e é
  reportado no rodapé para que o usuário o veja.

## Configuração

| Config | Padrão | Significado |
|---|---|---|
| `injection.enabled` | `true` | liga a injeção |
| `injection.recheckEveryStep` | `true` | re-verificar visibilidade a cada passo |
| `injection.header` | `true` | incluir cabeçalho e declaração de autoridade |
| `injection.footer` | `true` | incluir rodapé com tools e custo |
| `injection.maxBytes` | `65536` | teto duro de bytes do documento, independente de tokens |

## Critérios de aceitação

- **CA1.** O primeiro passo de uma sessão nova contém exatamente uma mensagem com
  a fonte do plugin por namespace ativo.
- **CA2.** O segundo passo **não** contém uma segunda mensagem, quando a primeira
  continua visível.
- **CA3.** Com `delegationDepthOf > 0`, nenhuma mensagem é injetada e o store não
  é aberto para leitura (verificável por instrumentação de I/O no teste).
- **CA4.** Com o store inacessível, a sessão prossegue e a mensagem injetada tem
  exatamente uma linha, nomeando o caminho e o erro.
- **CA5.** Em `resume` com a injeção anterior visível, nenhuma injeção nova é
  produzida.
- **CA6.** A mensagem injetada não contém `</system-reminder>` literal em lugar
  nenhum, nem como parte do frame (frame íntegro: exatamente um fechamento).
- **CA7.** `injection.maxBytes` é respeitado mesmo quando o orçamento de tokens
  permitiria um documento maior (teste com resumos de uma linha muito longa).
- **CA8.** Com `injection.enabled = false`, nenhuma leitura do store ocorre e
  `optmem/skip` é emitido com `reason = 'disabled'`.

## Evidência

- `agent/pre-step` e `PreStepDecision`: `@deepseek-ai/dsh-agent/lib/types/runtime-types.d.ts:302-319` e `:92`. As mensagens decididas são comprometidas como `user/message` durável com `surfaceOp: 'append'` na primeira tentativa; retries não re-executam o `pre-step`.
- O lote padrão é `[...claimed, runtimeContextSnapshot]` (`@deepseek-ai/dsh-agent-loop/lib/index.js:894-903`): anexar coloca a memória **depois** do snapshot de contexto de runtime; inserir em `lastClaimedIndex + 1` a coloca entre o pedido do usuário e o snapshot.
- Fold sobre eventos crus, enxergando o que a compactação sombreou:
  `@deepseek-ai/dsh-time-context/lib/index.js:135-143` e `:181-219`.
- **Não** usar `agent/session-start` com fonte `'compact'`: o valor é declarado
  (`runtime-types.d.ts:105`) mas não tem emissor.
- Profundidade de delegação: `@deepseek-ai/dsh-subagent/lib/types/depth.d.ts:25` — importável apenas da raiz do pacote.
- Escopo por agente: registrar em `agent/created` com gate em `ctx.agents.roots().includes(agent)` e manter um early-return defensivo de `delegationDepthOf(agent) > 0` em qualquer listener global de `pre-step`.
