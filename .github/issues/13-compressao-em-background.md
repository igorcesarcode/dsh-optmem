---
title: "compression: job de background via ctx.llm.stream() e ctx.jobs"
labels: [area:compression, type:feature]
milestone: "M3 — Inteligência"
---

## Contexto

É a correção mais importante em relação ao OptMem. Lá, cada memória registrada
gera ~1 pedido de compressão, e cada pedido é um **turno completo do agente**: 10
mil memórias, 10 mil turnos extras. O harness permite chamar o modelo diretamente
e rodar fora do turno, então o custo sai de turnos e vira tokens (ADR-0002).

## Escopo

- Fila de blocos por namespace, ordenada por `(prioridade, lo)`: demanda do wake
  primeiro, fechamento de nível depois, reparo por último.
- Modo `background` (padrão), `agent` (compatibilidade com o OptMem) e `off`.
- **Lazy por padrão**: só comprime o que a cobertura precisa, mais uma janela de
  manutenção. É o que mantém o custo sublinear em `T`.
- Chamada direta ao modelo com `purpose` próprio, para separar custo de memória de
  custo de conversa.
- Contrato de prompt: uma linha, ≤ `entryChars`, guardar o duradouro, **incluir os
  termos pelos quais o bloco seria procurado depois** (sem isso o resumo é
  inencontrável, já que `recall` é exato).
- Um job por store; resultado gravado como registro append-only; desiste se o
  bloco já foi comprimido por outro.
- Retry com backoff, teto de tentativas, marcação `degraded`.
- Contadores de `calls`, `tokensIn`, `tokensOut` por store.

## Fora de escopo

A cobertura (item 03) e a re-injeção após compactação (item 14).

## Critérios de aceitação

- [ ] Com `mode = 'background'`, nenhum turno do agente é consumido por
      compressão: um teste verifica que o número de passos não aumenta com a fila
      cheia.
- [ ] Com `mode = 'off'`, nenhuma chamada de LLM é feita e o sistema continua
      produzindo documentos de wake com lacunas.
- [ ] Sem provedor configurado, o modo cai para `agent` com aviso, sem falhar.
- [ ] Dois jobs concorrentes no mesmo store comprimem blocos distintos; o total
      de registros gravados é igual ao número de blocos pendentes, sem duplicata.
- [ ] Matar o processo no meio de uma compressão não deixa registro parcial, e o
      bloco volta a ficar pendente.
- [ ] Resposta acima do teto é truncada e o evento registra o truncamento.
- [ ] Após `maxAttempts` falhas, o bloco não é retentado automaticamente e aparece
      como `degraded`.
- [ ] Com `lazy = true` e `T = 100.000` sintético, a contagem de chamadas fica
      abaixo do teto declarado, e **não** é Θ(T).
- [ ] O prompt de compressão é testado por contrato: uma linha, dentro do teto,
      não vazia. A **qualidade** do resumo não é testada — é não determinística.

## Dependências

- item 03 (cover), item 02 (store).

## Referências

- [spec 06 — compressão](../blob/main/docs/spec/06-compressao.md)
- [ADR-0002](../blob/main/docs/adr/0002-compressao-server-side.md)
