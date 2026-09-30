---
title: "tools: memory_note, memory_recall, memory_wake e memory_zoom"
labels: [area:tools, type:feature]
milestone: "M2 — Contexto"
---

## Contexto

A injeção (item 07) é a interface automática; as tools são a interface deliberada.
Sem elas o agente não tem como registrar o que aprendeu nem recuperar uma memória
específica.

Toda mensagem de erro de tool é acionável: nomeia o que está errado e o que fazer.
Uma tool que responde "invalid input" obriga o agente a adivinhar.

## Escopo

- `memory_note`: grava uma memória (namespace, origin, private, refs). Valida
  tamanho, quebra de linha, padrões de negação. Respeita tetos por turno e por dia.
  **Não bloqueia** para comprimir — enfileira e retorna.
- `memory_recall`: regex case-insensitive sobre todo o log, em streaming, com teto
  de saída que descarta os mais antigos e informa quantos ficaram de fora.
- `memory_wake`: releitura manual do documento.
- `memory_zoom`: abre um nó nas duas metades; valida a **forma** do bloco
  (alinhado, potência de dois) para que `4-5` e `5-6` não sejam ambíguos.
- Schemas de argumentos e de saída válidos, e projeção de apresentação para a GUI.
- `snake_case` com prefixo `memory_` para evitar colisão com tools de terceiros.

## Fora de escopo

`memory_forget` e `memory_config` (item 11), e a aprovação na escrita (item 21).

## Critérios de aceitação

- [ ] As quatro tools são registradas, aparecem no conjunto de tools da sessão, e
      cada uma tem schema de argumentos e de saída válidos.
- [ ] `memory_note` com 281 bytes falha nomeando o limite; com 280 bytes funciona.
- [ ] `memory_note` com `\n` no texto falha explicando que memória é uma linha.
- [ ] `memory_recall` com padrão que casa 10.000 memórias devolve no máximo `limit`
      resultados, os mais recentes, e informa quantos ficaram de fora.
- [ ] `memory_recall` com regex inválida devolve erro que mostra o problema, sem
      stack trace.
- [ ] `memory_zoom 4-5` é rejeitado com mensagem sobre a forma de bloco; `4-7` é
      aceito.
- [ ] Nenhuma tool bloqueia esperando compressão: com fila cheia e provedor lento,
      `memory_note` retorna em menos de 100 ms.
- [ ] Cada tool tem ao menos um teste de erro que verifica a mensagem, não apenas
      o código de falha.

## Dependências

- item 02 (store), item 03 (cover), item 04 (render).

## Referências

- [spec 05 — tools](../blob/main/docs/spec/05-tools.md)
