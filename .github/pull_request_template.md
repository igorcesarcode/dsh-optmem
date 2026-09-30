## O que muda

<!-- Uma frase. Se não couber em uma frase, provavelmente são dois PRs. -->

## Rastreabilidade

- Issue: #
- Spec: `docs/spec/NN-*.md`
- ADR (se mudou uma decisão): `docs/adr/NNNN-*.md`

## Verificação

<!-- O que foi executado, e o resultado. -->

- [ ] `npm run build`
- [ ] `npm run lint`
- [ ] `npm test`

## Checklist

- [ ] Comportamento novo tem spec ou ADR **antes** do código.
- [ ] Testes na camada correta ([spec 13](docs/spec/13-testes.md)): propriedade para
      a cobertura, integração para os seams, contrato para interoperabilidade.
- [ ] Nenhum teste tautológico, detector de mudança, ou que mede o modelo em vez do
      plugin.
- [ ] Nenhum caminho novo lança para o loop do agente: falha de memória é falha
      aberta **e visível**.
- [ ] Se tocou em `LOG.txt`, `PROV.txt` ou `TREE/`: compatibilidade de formato
      declarada, e o que acontece com stores existentes.
- [ ] Se tocou em segurança: qual controle da [spec 09](docs/spec/09-seguranca.md)
      foi afetado, e qual teste prova que continua valendo.
- [ ] Se tocou na superfície web: a GUI não quebra quando o store falha.
- [ ] Se um seam do harness mudou: a alteração ficou contida em `src/harness/`.

## O que **não** foi feito

<!-- Limitações conhecidas, trabalho adiado, e o que ficou sem teste. Honestidade
     aqui vale mais do que uma lista de checks cheia. -->
