---
title: "scope: exclusão de subagentes garantida por profundidade de delegação"
labels: [area:scope, area:security, type:feature]
milestone: "M2 — Contexto"
---

## Contexto

O OptMem tentava resolver isso por convenção de prompt: *"If you're a subagent:
skip everything above"* e *"When you spawn one, write: You are a subagent. Don't
run memo."* Isso depende de dois modelos obedecerem, e falha em silêncio quando não
obedecem — o subagente grava notas duplicadas e mal classificadas, porque não sabe
o que já é conhecido.

O harness expõe a profundidade de delegação, então a regra passa a ser de código.

## Escopo

- Detecção por profundidade de delegação do agente, não por heurística.
- Profundidade > 0: **sem injeção** e **sem escrita**.
- Tools de memória, em profundidade > 0, respondem com erro acionável:
  *"subagentes não gravam memória; devolva este fato ao agente principal para que
  ele registre"*.
- Verificação **antes** de qualquer acesso ao store, para que um subagente nunca
  toque no disco de memória.
- Invariante observável: `optmem/skip` com `reason = 'subagent'` nunca é seguido
  de `optmem/inject` na mesma sessão.

## Fora de escopo

Decidir o que o agente principal passa ao subagente. O contrato é: o pai inclui no
prompt de delegação os fatos que importam, extraídos da própria memória dele.

## Critérios de aceitação

- [ ] Um subagente criado por `subagent` não recebe nenhuma mensagem do plugin.
- [ ] Um subagente criado por `subagent_fork` também não recebe.
- [ ] `memory_note` em profundidade > 0 falha com mensagem que contém
      "subagente" e não escreve nada (hash do store antes/depois).
- [ ] Nenhuma leitura do store acontece em profundidade > 0, verificado por
      instrumentação de I/O no teste de integração.
- [ ] Um neto (profundidade 2) se comporta como profundidade 1.
- [ ] O invariante I7 da spec 12 é verificado pelo companion e tem teste de
      violação.

## Dependências

- item 07 (injeção).

## Referências

- [spec 08 — escopo](../blob/main/docs/spec/08-escopo-e-subagentes.md)
- [spec 12 — observabilidade](../blob/main/docs/spec/12-observabilidade.md)
