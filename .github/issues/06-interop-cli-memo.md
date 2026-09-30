---
title: "interop: contrato verificado com a CLI memo do OptMem"
labels: [area:store, area:tests, type:test]
milestone: "M1 — Fundação"
---

## Contexto

A compatibilidade de formato com a CLI `memo` é metade do valor de ter um store em
arquivo plano: permite inspecionar e auditar a memória **sem o DSH instalado**. É
também o contrato mais fácil de quebrar em silêncio, porque nada no nosso código
depende dele.

Um teste de contrato contra o binário real é a única forma de saber que ele
continua valendo. É o único teste do projeto que depende de código de terceiros.

## Escopo

- Baixar o `memo` do OptMem em CI, **fixado por hash**, e falhar se o hash mudar
  sem uma atualização deliberada do pin.
- Gerar um store com o plugin e apontar `MEMORY_DIR` da CLI para ele.
- Verificar:
  - `memo wake` lê o log e a árvore produzidos pelo plugin;
  - `memo recall` encontra memórias gravadas pelo plugin;
  - `memo zoom` abre um nó da árvore do plugin;
  - `note` e `nap` **não** são oferecidos no modo leitor (ADR-0005).
- Documentar o que fazer quando o contrato quebrar: ou o nosso formato mudou (bug
  nosso) ou o formato do OptMem mudou (decisão sobre migrar).

## Fora de escopo

Invocar a CLI em runtime. O plugin **nunca** executa `python3` (ADR-0005).

## Critérios de aceitação

- [ ] O teste roda em CI, com o `memo` obtido de URL fixa e verificado por hash.
- [ ] `wake`, `recall` e `zoom` da CLI produzem saída consistente com o conteúdo
      gravado pelo plugin, para um store de pelo menos 1.000 memórias com árvore
      parcialmente construída.
- [ ] Um store cuja árvore está vazia permanece legível pela CLI.
- [ ] O teste falha se o hash do binário pinado mudar, com mensagem explicando que
      é preciso revisar a compatibilidade antes de atualizar o pin.
- [ ] Nenhum caminho de produção importa, invoca ou depende da CLI — verificado
      por um teste que falha se `python3` aparecer no bundle.

## Dependências

- item 02 (store).

## Referências

- [spec 02 — store](../blob/main/docs/spec/02-store.md)
- [ADR-0005](../blob/main/docs/adr/0005-plugin-e-o-unico-escritor.md)
