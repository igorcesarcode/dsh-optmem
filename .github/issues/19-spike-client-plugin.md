---
title: "web: protótipo do formato de bundle de cliente fora do monorepo"
labels: [area:web, type:spike]
milestone: "M4 — Superfície"
---

## Contexto

A pergunta de **arquitetura** já está respondida: um plugin de terceiro **pode**
contribuir superfície de cliente sem fork do monorepo. A descoberta é Loader-driven
e relativa ao pacote — `dsh-client-modules` escaneia as entradas habilitadas e
resolve cada `dsh.client` contra o `package.json` do próprio pacote, sem lista de
permissão nem caminho que assuma o layout do monorepo.

O que **não** está respondido é o **esforço**. Três fatos verificados:

1. O preset que emite o bundle no formato lazy-CJS vive em
   `packages/client/tsdown.client.ts` no monorepo e **não é publicado**. O texto
   publicado diz explicitamente que um plugin fora do repositório *"has to
   reproduce that build itself"*.
2. O host **nunca** constrói: bundle ausente é falha dura de ativação
   (*"client bundle not found; run `pnpm run build` before launch"*).
3. `@deepseek-ai/dsh-client-ui-slots` **não é publicado**, embora as augmentations
   de `SlotMap` apontem para ele — integração de tipos exige shim escrito à mão.

Não existe exemplo conhecido de bundle construído fora do repositório. A conclusão
honesta do levantamento é: decidível no nível de arquitetura, **não** decidível no
nível de "escreva estas 30 linhas de config e funciona".

Este item existe para transformar isso em uma resposta provada, **antes** de o
painel virar compromisso de entrega.

## Escopo

- Reproduzir o formato lazy-CJS: wrapper de fábrica, externos emitidos como
  chamadas `require()`, `id` igual ao nome do pacote, convenção de tag de CSS,
  trailer de sourcemap.
- Produzir um bundle mínimo que **carregue na GUI** e registre uma aba vazia no
  slot `conversation.view` — nada além de aparecer.
- Documentar a receita de build no repositório, de forma reproduzível.
- Escrever o shim de tipos para o contrato de slot.
- Escrever o watch de desenvolvimento (o `pnpm run dev:web` do harness é script de
  raiz do workspace e **não existe** no install publicado; o receptor de HMR
  observa o `lib/client.js` do próprio plugin).

## Fora de escopo

Qualquer conteúdo real na aba (item 17).

## Critérios de aceitação

- [ ] Uma aba vazia registrada por um bundle construído **fora** do monorepo do
      harness aparece na GUI.
- [ ] A receita de build está no repositório e outra pessoa a reproduz do zero.
- [ ] O shim de tipos compila e cobre o contrato de slot usado.
- [ ] O watch de desenvolvimento recarrega a aba sem refresh da página.
- [ ] O documento registra o que **não** foi possível determinar, se for o caso, em
      vez de supor.
- [ ] Se o formato se mostrar irreprodutível fora do repositório, o item 17 é
      reescrito com as alternativas restantes e a decisão vai para o ADR-0007.

## Dependências

- Nenhuma. Pode rodar em paralelo com M1 — e **bloqueia** o item 17.

## Referências

- [ADR-0007](../blob/main/docs/adr/0007-superficie-web.md)
- [research/02 — §6](../blob/main/docs/research/02-client-web-kit.md)
- [research/04](../blob/main/docs/research/04-superficie-cliente-e-aba.md)
