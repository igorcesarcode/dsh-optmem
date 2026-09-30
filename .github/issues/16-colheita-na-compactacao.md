---
title: "compaction: colheita opcional de memória na faixa sombreada"
labels: [area:compaction, type:feature]
milestone: "M3 — Inteligência"
---

## Contexto

A compactação é o momento em que contexto valioso está prestes a ser perdido. Uma
segunda função do plugin pode ler a faixa que foi sombreada — da sessão **bruta**,
não da superfície derivada — e extrair candidatos a memória durável.

Fica **desligada por padrão**: acrescenta uma chamada de LLM por compactação, um
modo de falha novo, e memória gerada por inferência é de qualidade inferior à
memória que o agente decidiu registrar deliberadamente.

Nota: o bridge de hooks do Claude Code não suporta `PreCompact`/`PostCompact`,
então este caminho só é possível como plugin nativo.

## Escopo

- Observar a compactação pelos eventos de sessão.
- Ler a faixa sombreada da sessão bruta.
- Pedir candidatos ao modelo, no mesmo contrato de linha única da compressão.
- Gravar com `origin = 'agent-inference'` e `refs = [id-da-compactação]`,
  sujeitos à política de escrita de qualquer memória.
- Teto de candidatos por compactação.

## Fora de escopo

Substituir a decisão do agente sobre o que vale registrar. A colheita é uma rede
de segurança, não o mecanismo principal.

## Critérios de aceitação

- [ ] Com a opção desligada, nenhuma chamada de LLM extra acontece em uma
      compactação (verificado por contagem de chamadas).
- [ ] Com a opção ligada, uma decisão registrada explicitamente e depois descartada
      produz um candidato que a contém.
- [ ] Nenhum candidato é gravado sem passar pela política de escrita (aprovação,
      padrões de negação).
- [ ] O teto de candidatos é respeitado.
- [ ] Candidatos carregam `refs` apontando para a compactação que os originou.
- [ ] Uma compactação que não descarta nada durável não produz candidato (teste
      negativo, para evitar colheita indiscriminada).
- [ ] Falha na colheita não afeta a compactação nem a sessão.

## Dependências

- item 14 (sobrevivência à compactação), item 13 (compressão).

## Referências

- [spec 07 — compactação](../blob/main/docs/spec/07-compaction.md)
