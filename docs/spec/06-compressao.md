# 06 — Compressão em background

## Objetivo

Manter a árvore de resumos em dia **sem consumir turnos do agente** e sem entrar
no caminho crítico de nenhuma requisição, com custo observável e limitado.

Ver ADR-0002 para a decisão e o motivo.

## Unidade de trabalho

A unidade é um **bloco** `[lo, hi)` alinhado, potência de dois, `size ≥ 2`.

- `size ≤ rawWindow` (padrão 16): o prompt contém as **memórias cruas** do bloco.
- `size > rawWindow`: o prompt contém os **dois resumos filhos** `[lo,mid)` e
  `[mid,hi)`, que já existem por construção.

Essa é a diferença entre comprimir 16 memórias de uma vez e comprimir um resumo de
resumo: o custo por bloco é limitado, e a profundidade cresce logaritmicamente.

## Quando um bloco entra na fila

Três origens, em ordem de prioridade:

1. **Demanda do wake.** Um bloco que a cobertura atual precisa e que não tem
   resumo. Prioridade máxima: é o único caso em que a falta degrada a experiência.
2. **Fechamento de nível.** Quando a memória `k × size - 1` é gravada, o bloco
   `[(k-1) × size, k × size)` torna-se comprimível. É o trabalho de manutenção.
3. **Reparo.** Um `forget` explícito, ou um bloco marcado `degraded` após falhas.

A fila é ordenada por `(prioridade, lo)`. O compressor pega blocos **pequenos
primeiro** dentro da mesma prioridade: baratos, e destravam níveis maiores.

## Lazy por padrão

`compression.lazy = true` (padrão) significa: **só comprime o que a cobertura
precisa**, mais uma janela de manutenção à frente do presente.

Justificativa de custo: comprimir a árvore inteira de `T` memórias custa Θ(T)
chamadas — exatamente o custo que inviabiliza o OptMem em escala. Com lazy, o
custo passa a acompanhar o **crescimento do orçamento**, que é logarítmico em `T`.
A árvore profunda só é construída quando (e se) a memória antiga for realmente
lida.

`compression.lazy = false` constrói a árvore completa em background, para quem
prefere previsibilidade de custo a custo mínimo.

## Contrato do prompt de compressão

```
Comprima as memórias #<lo>-#<hi> em UMA linha de no máximo <entryChars> bytes.

Regras:
- Guarde o que tem efeito duradouro: decisões, fatos sobre o usuário, restrições,
  nomes, caminhos, o que foi tentado e falhou.
- Descarte o que não tem: estados transitórios, passos intermediários, repetições.
- Não invente. Se algo é incerto, omita em vez de supor.
- Inclua os termos pelos quais este bloco seria procurado depois: nomes de
  arquivos, tecnologias, sintomas de erro. O resumo é um índice, não uma prosa.
- Escreva na mesma língua das memórias de origem.

<corpo: memórias cruas ou os dois resumos filhos>

Responda apenas com a linha.
```

O requisito "inclua os termos pelos quais este bloco seria procurado" existe
porque `recall` é exato (ADR-0006): sem os termos, o resumo é inencontrável e a
memória antiga fica inacessível na prática.

A chamada usa `purpose` próprio, para que o custo de memória seja distinguível do
custo de conversa em qualquer relatório de uso.

## Execução

- Roda **fora do turno**, por um de dois seams, escolhidos por disponibilidade:
  - `Agent.runMaintenance(task)` — trabalho serializado pelo agente, sem turno, quando o agente está disponível;
  - `ctx.jobs.start(spec)` — job do serviço de jobs. Atenção: `ctx.jobs.start` exige um **controller anexado** ao dono, e o controller do harness vem de `dsh-tool-jobs`. Sem esse pacote montado, este caminho não existe e o compressor cai para o primeiro.
- Resultado de job é entregue por `ctx.jobs.onJobDone` e, quando há algo a dizer ao agente, por `owner.followup(msg)` se o agente estiver ocioso e dentro do orçamento, ou `owner.inject(msg)` caso contrário. A compressão **não** usa esse canal para pedir ação: só para reportar.
- A chamada ao modelo é `ctx.llm.stream(...)` — **não existe `generate()`** nesta versão — com `GenerateOptions.purpose` (união fechada de dois literais, não extensível), `signal` propagado do job, e o texto montado por `BlockAssembler`. Falhas do adaptador chegam como chunk terminal de erro ou abortado, então o caminho de sucesso **verifica `assembler.finish`**; não basta o stream ter terminado.
- **Um job por store.** Compressões concorrentes do mesmo bloco são desperdício.
- Resultado é gravado como registro **append-only** no nível correspondente. Nunca
  sobrescreve: se o resumo do bloco já existe, o job desiste (alguém chegou
  primeiro).
- `forget` é o único caminho de descarte, e é explícito.
- Retomável: o estado é derivado do store (quais níveis existem e até onde), nunca
  de estado em memória do processo. Reiniciar o host não perde trabalho, apenas
  reenfileira.

## Rota da compressão

A compressão **não** usa necessariamente o modelo da conversa. Ela tem rota própria
(ADR-0008), porque é o único lugar do sistema que gasta dinheiro em escala e porque
o trabalho — condensar uma linha a partir de texto já no contexto, sob contrato
explícito — exige menos do modelo que a conversa.

```jsonc
{
  "provider": "deepseek",        // vazio = herda a rota da sessão
  "model": "deepseek-chat",      // vazio = herda
  "reasoning_effort": "low"      // vazio = o padrão do modelo escolhido
}
```

Regras:

- **Vazio herda a sessão.** Sem configuração, o comportamento é o que não
  surpreende: a memória é comprimida pelo mesmo modelo que está conversando.
- **Provider e model andam juntos.** Um sem o outro é configuração inválida,
  rejeitada na leitura, não em runtime.
- **Trocar a rota sem informar effort limpa o effort da rota anterior** — o effort
  pertence à rota, não ao plugin. Manter um effort que pertencia a outro modelo
  seria aceitar uma configuração que o harness vai rejeitar depois.
- **Effort é validado contra o modelo**, nunca texto livre: as opções vêm do
  metadado de raciocínio do modelo resolvido. Effort não suportado é rejeitado
  **antes** de qualquer I/O de provedor, sem clamp e sem alias. Modelo sem metadado
  de raciocínio simplesmente não oferece effort.
- **O catálogo é consultivo, não autoritativo.** Um modelo que o adapter serve mas
  não anuncia continua configurável; a lista da GUI apenas o mostra no fim, como as
  rotas salvas que sumiram do catálogo.

## Tratamento de erro de API

**O harness não retenta chamadas diretas a `ctx.llm.stream()`** — o
`dsh-llm-retry` só cobre o limite do passo durável do agente, e declara isso. Como a
compressão chama o stream direto (ADR-0002), retry, backoff e taxonomia são
**nossos**.

| Classe | Códigos | Ação |
|---|---|---|
| **Transitório** | `RATE_LIMIT`, `TIMEOUT`, `TRANSPORT`, `SERVER`, `EMPTY_RESPONSE` | retenta com backoff exponencial e jitter |
| **Permanente** | `AUTH`, `NO_ADAPTER`, modelo/effort inválido, conteúdo não suportado | **não retenta**; marca e reporta |
| **Entrada grande demais** | `CONTEXT_WINDOW_EXCEEDED` | **divide o bloco** nos dois filhos e enfileira, em vez de repetir o mesmo pedido |

- **Disjuntor.** Após N falhas permanentes consecutivas, a compressão **desliga** e
  avisa na GUI. Retentar `AUTH` com credencial errada é queimar dinheiro sozinho. O
  religar é explícito, nunca automático por tempo — religar sozinho depois de uma
  credencial errada só repete o erro.
- **Retry é seguro por construção.** A gravação é append-only e o job desiste se o
  bloco já foi comprimido; uma tentativa que chega depois de um sucesso alheio não
  duplica nada.
- **Vocabulário do harness.** `initialDelayMs`, `maxDelayMs`, `jitterRatio`,
  `maxAttempts` — os mesmos nomes do `retryPolicy` do provedor, porque é o que o
  usuário já viu.
- **Custo de tentativa fracassada conta.** Tokens de chamadas que falharam entram no
  acumulado. Esconder isso seria esconder o custo que o ADR-0002 prometeu tornar
  visível.
- **Nada chega ao loop do agente.** O agente nunca vê um erro de API por causa da
  memória.

Outras falhas, não de API:

| Falha | Comportamento |
|---|---|
| Sem provedor de LLM configurado | cai para `compression.mode = 'agent'` com aviso; `wake` segue com lacunas |
| Resposta longa demais | trunca no teto da linha, registra que truncou |
| Resposta vazia ou só whitespace | transitório: retenta |
| Teto de tentativas atingido | bloco vira `degraded`; não é retentado até um `forget` explícito |
| Custo do job acima de `compression.maxJobTokens` | job aborta **antes** de chamar; bloco fica pendente |

Nenhuma dessas falhas lança no loop do agente. Todas são registradas.

## Custo

- Entrada por bloco: ~`rawWindow × 70` tokens (16 × ~70) no caso cru, ou dois
  resumos no caso agregado. Ordem de grandeza: **~1,5k tokens de entrada**.
- Saída por bloco: uma linha, ≤ 280 bytes ⇒ ~100 tokens.
- Total por memória registrada, com lazy: **sublinear**, porque o número de
  chamadas passa a acompanhar o crescimento do orçamento, não o crescimento de `T`.

O compressor mantém um contador acumulado (`tokensIn`, `tokensOut`, `calls`) por
store, exposto em `memory_config` e no painel web. O usuário precisa ver o custo
sem instrumentar nada (M6).

## Configuração

| Config | Padrão | Significado |
|---|---|---|
| `compression.enabled` | `true` | liga a compressão (chave de ativação, ver spec 11) |
| `compression.mode` | `'background'` | `background` \| `agent` \| `off` |
| `compression.lazy` | `true` | só o que a cobertura precisa |
| `compression.rawWindow` | `16` | acima disso, comprime de resumos |
| `compression.route.provider` | `''` | vazio = herda a rota da sessão |
| `compression.route.model` | `''` | vazio = herda a rota da sessão |
| `compression.route.reasoning_effort` | `''` | vazio = padrão do modelo escolhido |
| `compression.retry.initialDelayMs` | `1000` | primeiro atraso do backoff |
| `compression.retry.maxDelayMs` | `30000` | teto do atraso |
| `compression.retry.jitterRatio` | `0.2` | fração de jitter |
| `compression.retry.maxAttempts` | `3` | tentativas antes de `degraded` |
| `compression.retry.breakerAfter` | `5` | falhas permanentes consecutivas antes de desligar |
| `compression.maxJobTokens` | `4000` | teto de entrada por job |
| `compression.maxBlocksPerRun` | `8` | teto de blocos por execução do job |

## Evidência

- Chamada direta ao modelo com `purpose` em união fechada e `signal`:
  `@deepseek-ai/dsh-llm/lib/types/index.d.ts:406` (só `stream`, sem `generate`).
- Backend de compactação usando `ctx.llm.stream()` e `summarize()` como único hook
  de subclasse: `@deepseek-ai/dsh-compaction-basic/README.md`.
- Trabalho fora do turno: `Agent.runMaintenance(task)`
  (`@deepseek-ai/dsh-agent/lib/types/runtime-types.d.ts:165-174`) e
  `ctx.jobs.start(spec)` com controller anexado
  (`@deepseek-ai/dsh-jobs/lib/types/index.d.ts:37-43`, `:56`);
  `onJobDone` e a receita de entrega em `@deepseek-ai/dsh-tool-jobs/lib/index.js:205-227`.
- `dsh-tool-call-timeout-policy` **não** é um seam de trabalho em background: ele
  apenas envolve `tools/execute` com um prazo cooperativo.

## Critérios de aceitação

- **CA1.** Nenhum caminho de `wake` espera compressão. Medir: com a fila cheia e o
  provedor de LLM artificialmente lento, a injeção do primeiro passo completa no
  mesmo tempo que com a fila vazia (diferença < 50 ms).
- **CA2.** Com `compression.mode = 'off'`, nenhuma chamada de LLM é feita e o
  sistema continua produzindo documentos de wake com lacunas.
- **CA3.** Dois jobs concorrentes no mesmo store comprimem blocos distintos; o
  total de registros gravados é igual ao número de blocos pendentes, sem
  duplicata.
- **CA4.** Matar o processo no meio de uma compressão não deixa registro parcial
  (o `repair` de nível remove a cauda) e o bloco volta a ficar pendente.
- **CA5.** Um resumo que excede `entryChars` é truncado e o evento registra o
  truncamento.
- **CA6.** Após `maxAttempts` falhas, o bloco não é retentado automaticamente, e
  aparece como `degraded` no `memory_config`.
- **CA7.** Com `lazy = true` e `T = 100.000`, o número de chamadas de compressão
  após a primeira sessão é ≤ 2× o número de blocos presentes na cobertura, e não
  Θ(T).
