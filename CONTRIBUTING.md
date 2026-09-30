# Contribuindo

## A regra que organiza tudo

**Especificação primeiro.** Este projeto tem um ativo que não pode ser refeito: o
formato do store e a memória que os usuários acumulam nele. Por isso, mudanças de
comportamento começam em `docs/spec/` ou `docs/adr/`, não em código.

Um PR que muda comportamento sem uma spec ou ADR correspondente é fechado com um
pedido para abrir a discussão antes. Não é burocracia: é o único mecanismo que
temos para não descobrir uma incompatibilidade depois que já existem dez mil
memórias gravadas no formato antigo.

## Fluxo

1. **Issue primeiro.** Toda mudança não trivial tem issue, com critério de
   aceitação verificável. Se não dá para escrever o critério, o problema ainda não
   está entendido.
2. **Spec ou ADR.** Comportamento novo → spec. Decisão de arquitetura (ou
   reversão de uma) → ADR. Um ADR novo nunca apaga um antigo: ele o marca como
   substituído e diz o que mudou de evidência.
3. **Implementação.** Com testes que falham se o comportamento for removido.
4. **Verificação.** PR descreve o que foi executado e o que **não** foi.

## O que um PR precisa conter

- Referência à issue e à spec/ADR.
- Testes na camada correta (ver [spec 13](docs/spec/13-testes.md)): propriedade
  para a cobertura, integração para os seams, contrato para a interoperabilidade.
- Se tocar em `LOG.txt`, `PROV.txt` ou `TREE/`: uma nota explícita sobre
  compatibilidade de formato e o que acontece com stores existentes.
- Se tocar em segurança: qual controle da [spec 09](docs/spec/09-seguranca.md) foi
  afetado e qual teste prova que ele continua valendo.

## Testes proibidos

- **Tautológico** — confere a implementação contra ela mesma, ou verifica o mock
  que o próprio teste configurou.
- **Detector de mudança** — congela detalhe interno (ordem de chamadas, campo
  privado, texto de log) e quebra em toda refatoração correta.
- **Teste de modelo** — "o modelo lembrou" mede o modelo, não o plugin.

## Convenções

- Português nas specs e ADRs; inglês no código, nos nomes de API e nas mensagens
  voltadas ao modelo.
- Toda afirmação sobre o harness cita caminho verificável sob o pacote publicado.
  Se a citação não existe mais, o ADR precisa ser reaberto — não reescrito em
  silêncio.
- Commits no imperativo, com escopo: `store: rejeita texto com quebra de linha`.

## Licença

Contribuições entram sob MIT. Ver [LICENSE](LICENSE).
