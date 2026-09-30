---
title: "custo: medição com o medidor de tokens do harness e relatório ao usuário"
labels: [area:cover, area:audit, type:feature]
milestone: "M3 — Inteligência"
---

## Contexto

O orçamento de contexto é a decisão mais consequente do sistema, e o OptMem o
fazia em **linhas** — o que obrigava a adivinhar limites de harness e a paginar o
documento para não ser truncado. O harness expõe um medidor de tokens real, então
o orçamento passa a ser medido, não estimado.

Além disso, um plugin de memória que esconde o custo em tokens não é honesto: o
usuário precisa ver o que a memória custa sem instrumentar nada.

## Escopo

- Usar o medidor de tokens do harness para (a) confirmar e corrigir o documento
  após a escolha da cobertura e (b) reportar o custo real.
- Corrigir para baixo quando estourar (fundir irmãos mais antigos) e para cima
  quando sobrar (dividir os mais recentes).
- A linha de custo no rodapé do documento, refletindo a medição, não a estimativa.
- Acumular o custo de compressão por store e expor em `memory_config`.
- Um teto duro de bytes (`injection.maxBytes`) independente de tokens, como rede
  de segurança para o caso em que a tokenização divirja.

## Fora de escopo

Estimar custo em dinheiro: o plugin reporta tokens, não preços. Preço muda e é
específico do provedor do usuário.

## Critérios de aceitação

- [ ] O documento nunca excede `wake.budgetTokens` **medidos**, em 100% de um
      teste com `T` de 1 a 100.000 e orçamentos de 500 a 32.000.
- [ ] `memory_config.lastTokens` é igual ao valor medido na última injeção.
- [ ] O rodapé do documento mostra o custo medido, e um teste verifica que o valor
      bate com o do `memory_config`.
- [ ] `injection.maxBytes` é respeitado mesmo quando o orçamento de tokens
      permitiria um documento maior.
- [ ] O custo acumulado de compressão (chamadas, tokens de entrada, tokens de
      saída) é reportado por namespace.
- [ ] Dobrar o orçamento não altera nenhum arquivo em disco (verificado por hash
      e mtime do diretório do store inteiro).

## Dependências

- item 04 (render), item 13 (compressão, para os contadores de custo).

## Referências

- [spec 03 — wake e cover](../blob/main/docs/spec/03-wake-e-cover.md)
- [spec 12 — observabilidade](../blob/main/docs/spec/12-observabilidade.md)
