---
title: "tools: memory_forget e memory_config"
labels: [area:tools, type:feature]
milestone: "M2 — Contexto"
---

## Contexto

Duas tools de controle. `memory_forget` corrige um resumo ruim — e a diferença
entre as duas formas dele é a diferença entre uma operação segura e uma
irreversível. `memory_config` responde, sem instrumentar nada, as três perguntas
que o usuário realmente faz: quanto custa, o que está pendente, está saudável.

## Escopo

- `memory_forget` (soft, padrão): descarta o resumo do bloco e tudo construído
  sobre ele; o próximo job recomputa. **O log não é tocado.**
- `memory_forget` (hard): reescreve o log, **renumera todos os ids**, invalida a
  árvore e as referências antigas. Exige `confirm: "APAGAR"` literal. Reporta
  contagens, nunca conteúdo.
- Recusa `hard` em modo leitor.
- `memory_config`: instantâneo de namespaces, wake, compressão e saúde do store.
- Variante opcional `set` que muda **apenas** `wake.budgetTokens` — a única
  configuração que faz sentido ajustar em conversa, porque é a única cujo efeito o
  usuário sente imediatamente.

## Fora de escopo

Edição de conteúdo de memória. Corrigir uma memória é `forget` (soft) e gravar de
novo.

## Critérios de aceitação

- [ ] `forget` soft de um bloco com resumo existente remove o resumo e os
      ascendentes, e o próximo job os reconstrói; o `LOG.txt` fica byte-idêntico.
- [ ] `forget` soft de bloco sem resumo falha com mensagem explícita.
- [ ] `forget` hard sem confirmação textual não faz nada.
- [ ] `forget` hard com confirmação reescreve o log, renumera os ids, descarta a
      árvore, e reporta a contagem de removidas.
- [ ] `forget` hard em modo leitor é recusado.
- [ ] `memory_config` reporta `lastTokens` igual ao valor medido na última injeção.
- [ ] `memory_config` distingue `pending` de `degraded` e reporta `calls`,
      `tokensIn` e `tokensOut` acumulados.
- [ ] Um store em estado `corrupt` aparece como `corrupt: true` **antes** de
      qualquer tentativa de escrita.

## Dependências

- item 10 (tools núcleo), item 03 (cover) para o descarte de ascendentes.

## Referências

- [spec 05 — tools](../blob/main/docs/spec/05-tools.md)
- [spec 12 — observabilidade](../blob/main/docs/spec/12-observabilidade.md)
