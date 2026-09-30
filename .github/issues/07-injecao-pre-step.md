---
title: "injection: documento de memória em agent/pre-step, com dedup e falha aberta"
labels: [area:injection, type:feature]
milestone: "M2 — Contexto"
---

## Contexto

É o item que faz o sistema existir. O OptMem dependia de o modelo obedecer a uma
instrução ("rode `memo wake` antes de qualquer outra tool call"); aqui a memória é
injetada programaticamente, então o modelo não pode esquecer de acordar (ADR-0003).

O seam é o waterfall `agent/pre-step`, que decide com que mensagens o loop entra no
passo — o mesmo que `dsh-agent-instructions` usa para injetar `AGENTS.md`.

## Escopo

- Ouvinte em `agent/pre-step` que injeta o documento no primeiro passo elegível.
- Mensagem **durável** com **fonte atribuída ao plugin** (nunca texto anônimo no
  histórico).
- Decisão por passo, na ordem: `disabled` → `subagent` → `store-error` →
  `already-visible` → injeta. A verificação de subagente vem **antes** de qualquer
  acesso ao store.
- Deduplicação: no máximo uma injeção por namespace enquanto a anterior continua
  visível na superfície derivada; reinjeção quando deixa de estar visível.
- Em `resume`, não reinjetar se a anterior continua visível.
- Anexar ao lote **depois** das mensagens do usuário: o pedido atual vem primeiro.
- Falha aberta: store inacessível ⇒ uma linha de aviso, sessão prossegue.
- Emissão de `optmem/inject` / `optmem/skip` para toda decisão.

## Fora de escopo

O texto do documento (item 04), a re-verificação de visibilidade a cada passo e a
reação à compactação (item 14), e o escopo por subagente (item 09).

## Critérios de aceitação

- [ ] O primeiro passo de uma sessão nova contém exatamente uma mensagem com a
      fonte do plugin, por namespace ativo.
- [ ] O segundo passo não contém uma segunda, enquanto a primeira está visível.
- [ ] Em `resume` com a injeção anterior visível, nenhuma injeção nova ocorre.
- [ ] Com profundidade de delegação > 0, nenhuma mensagem é injetada e o store
      **não é aberto** (verificado por instrumentação de I/O).
- [ ] Com o store inacessível, a sessão prossegue, o aviso tem uma linha, e
      `optmem/store-error` é registrado.
- [ ] A mensagem é durável e reconstruível no replay da sessão.
- [ ] Nenhum caminho lança para o loop do agente: um teste com store que lança em
      toda operação não produz erro não tratado.

## Dependências

- item 04 (render), item 02 (store).

## Referências

- [spec 04 — injeção](../blob/main/docs/spec/04-injecao.md)
- [ADR-0003](../blob/main/docs/adr/0003-injecao-programatica.md)
