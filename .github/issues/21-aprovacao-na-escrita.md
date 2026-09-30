---
title: "security: aprovação antes de gravar memória de origem não confiável"
labels: [area:security, type:feature]
milestone: "M5 — Endurecimento"
---

## Contexto

O vetor mais provável de envenenamento persistente: o agente lê conteúdo hostil
(README de repositório clonado, saída de ferramenta, página web) e o grava como
memória. A partir daí, aquele texto volta ao contexto em toda sessão futura.

A defesa mais eficaz não é detectar conteúdo malicioso — é exigir uma decisão
humana quando a origem é não confiável. Isso move o alvo do atacante de "escrever
texto livre no store" para "convencer o usuário a aprovar", que é uma barreira de
natureza diferente.

## Escopo

- Ponto de decisão antes de gravar quando `origin = 'tool-output'`.
- Notas com `origin = user` ou `agent-inference` **não** pedem confirmação: o custo
  de fricção precisa recair só sobre o caso de risco.
- A aprovação mostra o **texto** que será gravado e a origem concreta (qual tool,
  qual referência), não um resumo.
- Negado ⇒ o store fica byte-idêntico.
- Memórias `tool-output` são marcadas no documento de wake (spec 09, C1) para que
  o modelo e o humano vejam que aquilo veio de fora.
- Configuração para o usuário relaxar a política (`requireApprovalFor: []`), com o
  padrão seguro.

## Fora de escopo

Classificação automática de conteúdo por heurística ou por modelo. A classificação
é do plugin, a partir do **caminho** pelo qual o texto chegou, nunca do conteúdo —
o conteúdo é justamente a parte que pode ser enganosa.

## Critérios de aceitação

- [ ] `memory_note` com `origin = tool-output` não grava sem aprovação; com
      aprovação negada, o store fica byte-idêntico (hash antes/depois).
- [ ] Com aprovação concedida, a memória é gravada com a origem correta e as
      referências.
- [ ] `memory_note` com `origin = user` não dispara aprovação.
- [ ] O prompt de aprovação exibe o texto exato e a origem concreta.
- [ ] Memórias `tool-output` aparecem marcadas no documento de wake.
- [ ] Um resumo que contém memória `tool-output` também aparece marcado.
- [ ] Com `requireApprovalFor: []`, a aprovação não é pedida — e existe um teste
      que documenta explicitamente que isso reduz a proteção.

## Dependências

- item 20 (proveniência), item 10 (tools).

## Referências

- [spec 09 — segurança](https://github.com/igorcesarcode/dsh-optmem/blob/main/docs/spec/09-seguranca.md)
- [ADR-0004](https://github.com/igorcesarcode/dsh-optmem/blob/main/docs/adr/0004-proveniencia-obrigatoria.md)
