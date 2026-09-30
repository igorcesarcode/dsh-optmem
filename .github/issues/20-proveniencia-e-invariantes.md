---
title: "audit: proveniência obrigatória e companion de invariantes"
labels: [area:audit, area:security, type:feature]
milestone: "M5 — Endurecimento"
---

## Contexto

Toda memória precisa poder responder "de onde você veio". Sem isso, não há como
distinguir "o usuário me disse" de "eu li num README de repositório clonado" — e
essa distinção é o que impede uma injeção de prompt de se tornar permanente.
Ver ADR-0004.

## Escopo

- Arquivo `PROV.txt` de largura fixa (240 bytes), alinhado por id: sessão, turno,
  passo, profundidade, origem, workspace, modelo, referências.
- `origin` ∈ `user` | `agent-inference` | `tool-output` | `import`.
- Migração de store sem proveniência: tudo vira `import`.
- `PROV.txt` perdido não é corrupção fatal: tudo vira `import` e o plugin avisa.
- Resumos herdam o **conjunto** de origens dos filhos, para que `tool-output` não
  se dilua em resumo aparentemente inócuo.
- Eventos de sessão tipados (`optmem/note`, `optmem/inject`, `optmem/compress`,
  `optmem/compress-failed`, `optmem/skip`, `optmem/store-error`).
- Companion de invariantes com as sete invariantes da spec 12.
- **Payload de evento nunca contém o texto de uma memória** (spec 12, E2).

## Fora de escopo

A aprovação na escrita (item 21) e a detecção de adulteração (C7 da spec 09, fora
do v1).

## Critérios de aceitação

- [ ] Todo id do log tem registro de proveniência; um teste verifica o alinhamento
      após 1.000 gravações intercaladas.
- [ ] Apagar `PROV.txt` não impede `wake`; todas as memórias passam a `import` e um
      aviso é emitido.
- [ ] `origin` é sempre um dos quatro valores; um valor fora do conjunto é
      rejeitado na escrita.
- [ ] Um resumo de bloco que contém ao menos uma memória `tool-output` carrega
      `tool-output` no seu conjunto de origens.
- [ ] Os seis eventos são emitidos nos caminhos correspondentes, com payload
      tipado.
- [ ] O companion rejeita, em teste, uma violação de cada uma das sete invariantes.
- [ ] Um teste grava uma memória com uma string sentinela e verifica que ela **não**
      aparece em nenhum evento do log de sessão.

## Dependências

- item 02 (store), item 10 (tools).

## Referências

- [ADR-0004](https://github.com/igorcesarcode/dsh-optmem/blob/main/docs/adr/0004-proveniencia-obrigatoria.md)
- [spec 12 — observabilidade](https://github.com/igorcesarcode/dsh-optmem/blob/main/docs/spec/12-observabilidade.md)
