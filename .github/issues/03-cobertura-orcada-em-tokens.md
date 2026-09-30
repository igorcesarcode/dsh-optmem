---
title: "cover: cobertura com decaimento por idade e orçamento em tokens"
labels: [area:cover, type:feature]
milestone: "M1 — Fundação"
---

## Contexto

É o coração do sistema e a decisão que determina todo o custo de contexto: dado
`T` memórias e um orçamento, escolher uma cobertura `[0,T)` em blocos alinhados de
potência de dois, onde o detalhe decai com a distância até o presente.

Diferença central em relação ao OptMem: o orçamento é em **tokens**, não em
linhas, e a cobertura é **restrita por disponibilidade** — um resumo que não
existe não invalida o documento, ele é substituído pelos filhos ou marcado como
lacuna. O OptMem recusa acordar quando falta um resumo; aqui isso é inaceitável,
porque a injeção está no caminho de toda sessão (ADR-0003).

## Escopo

- Blocos: `[lo,hi)` alinhados, potência de dois, `lo % size == 0`.
- Regra de decaimento: manter inteiro sse `size ≤ alpha × (T - lo)`.
- Busca binária em `alpha` para caber no orçamento (estimativa por linhas).
- Refinamento por disponibilidade: descer para os filhos quando o resumo falta.
- Medição exata e correção: fundir irmãos mais antigos se estourar; dividir os
  mais recentes se sobrar.
- Lacuna explícita para bloco sem resumo em `size == 1`, com enfileiramento de
  compressão.
- Caminho rápido: abaixo do piso, todas as memórias cruas e **nenhuma** compressão
  enfileirada.

## Fora de escopo

O render do texto (item 04) e o job que produz os resumos (item 13). Este item
entrega a função de cobertura e a de enfileiramento como interface.

## Critérios de aceitação

- [ ] A união dos blocos é exatamente `[0,T)`, sem sobreposição, para `T` de 0 a
      100.000 em teste de propriedade.
- [ ] O custo medido do documento fica dentro do orçamento em 100% dos casos de
      um teste com `T` de 1 a 100.000 e orçamentos de 500 a 32.000 tokens.
- [ ] Com `T` abaixo do piso, nenhuma compressão é enfileirada.
- [ ] Com a árvore vazia e `T` grande, o documento é produzido com lacunas
      marcadas, e o número de blocos enfileirados é igual ao número de lacunas.
- [ ] Nenhuma entrada produz exceção: lacuna é marcada, nunca lançada.
- [ ] `T` e configuração iguais produzem cobertura byte-idêntica (determinismo).
- [ ] A função de cobertura é pura: não faz I/O e não depende de estado global,
      verificado por um teste que a chama sem nenhum store montado.

## Dependências

- item 02 (store) para a leitura de memórias e resumos.

## Referências

- [spec 03 — wake e cover](../blob/main/docs/spec/03-wake-e-cover.md)
- [ADR-0006](../blob/main/docs/adr/0006-sem-embeddings-no-v1.md)
