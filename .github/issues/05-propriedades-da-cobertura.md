---
title: "testes: propriedades da cobertura com oráculo independente"
labels: [area:cover, area:tests, type:test]
milestone: "M1 — Fundação"
---

## Contexto

A cobertura é a parte com maior densidade de lógica sutil do sistema e a mais
difícil de revisar por leitura. Um erro aqui não quebra nada visivelmente: ele
produz um documento que parece plausível e custa o dobro do orçamento, ou que
esquece silenciosamente uma faixa de memórias.

Por isso ela é testada por **propriedade**, com um oráculo independente — não com
exemplos escolhidos a dedo, e não com uma reimplementação da mesma lógica (isso
seria tautológico).

## Escopo

- Gerador aleatório de `T`, tamanhos de resumo, disponibilidade de nós da árvore e
  orçamento.
- Oráculo ingênuo e independente: para `T` pequeno, força bruta sobre todas as
  coberturas válidas, escolhendo a de menor custo que respeita o decaimento.
- As sete propriedades da spec 13: cobertura, alinhamento, ordem, orçamento,
  monotonicidade, estabilidade, ausência de exceção.
- Casos de borda explícitos: `T = 0`, `T = 1`, `T = 2^k`, `T = 2^k - 1`,
  `T = 2^k + 1`, orçamento mínimo, orçamento absurdo.

## Fora de escopo

Testes de integração com o harness (item 12). Este item é puramente determinístico.

## Critérios de aceitação

- [ ] As sete propriedades rodam com pelo menos 10.000 casos gerados e passam.
- [ ] O oráculo é independente: um teste verifica que ele **discorda** de uma
      implementação deliberadamente errada (prova de que o oráculo tem poder de
      detecção, e não que sempre concorda).
- [ ] Os seis casos de borda têm teste nomeado.
- [ ] Um `seed` fixo reproduz exatamente a mesma execução; nenhum teste depende de
      aleatoriedade não semeada.
- [ ] A suíte roda em menos de 30 s.

## Dependências

- item 03 (cover).

## Referências

- [spec 13 — testes](../blob/main/docs/spec/13-testes.md)
