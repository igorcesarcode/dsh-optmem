---
title: "testes: integração com o harness (montagem, passos, tools)"
labels: [area:tests, type:test]
milestone: "M2 — Contexto"
---

## Contexto

A metade determinística do sistema (store, cobertura, render) é testável por
propriedade. A metade de harness — injeção, tools, escopo — só existe dentro do
DSH, e testá-la por unidade não prova nada: o que pode estar errado é justamente o
seam.

**Aviso de dependência:** os pacotes de testkit do harness (`dsh-loader-smoke`,
`dsh-agent-loop-testkit`) **não estão instalados** — aparecem apenas como
`devDependencies` em manifestos do próprio monorepo, e não há contrato publicado que
possamos assumir. O único utilitário de teste verificado como embarcado é
`defineContentToolFixture`, importável da **entrada principal** de
`@deepseek-ai/dsh-tools` (não existe subpath `./testing`).

Consequência: esta camada é construída sobre a **API pública** do harness, com um
profile de teste e uma sessão real, e não sobre testkit de terceiro.

## Escopo

- Montagem do plugin em um profile de teste, sem erro e sem serviço faltante.
- Primeiro passo de uma sessão: exatamente uma mensagem com a fonte do plugin.
- Segundo passo: nenhuma segunda.
- Após compactação: uma nova (quando o item 14 estiver pronto).
- Subagente: zero.
- `store.dir` inválido: o plugin monta e falha aberto com aviso, sem derrubar o
  boot do profile.
- Ferramenta de diagnóstico que a suíte usa para inspecionar o store durante o
  teste.

## Fora de escopo

Testes de custo (spec 13, camada 6) e testes de segurança (item 20–23).

## Critérios de aceitação

- [ ] Cada item listado acima tem um teste nomeado.
- [ ] Cada teste falha quando a funcionalidade correspondente é removida do
      código (verificado por mutação manual em pelo menos um caso por item).
- [ ] O plugin monta em um profile limpo usando apenas o comando documentado de
      instalação.
- [ ] Nenhum teste depende de rede, exceto o de interoperabilidade (item 06), que
      é marcado como tal.
- [ ] A suíte de integração roda em menos de 3 minutos.

## Dependências

- itens 07, 08, 09, 10.

## Referências

- [spec 13 — testes](https://github.com/igorcesarcode/dsh-optmem/blob/main/docs/spec/13-testes.md)
