---
title: "scope: namespaces user/workspace com stores separados"
labels: [area:scope, area:store, type:feature]
milestone: "M2 — Contexto"
---

## Contexto

Memória tem duas naturezas: fatos sobre o **usuário** (valem em todo projeto) e
fatos sobre o **projeto** (valem naquele workspace). A tentação é um log único com
tag de workspace — e isso está descartado, porque a cobertura opera sobre faixas
contíguas `[0,T)` e uma tag quebraria o alinhamento em potências de dois, isto é,
destruiria a árvore.

Decisão: **um store por namespace** (spec 08).

## Escopo

- Layout `storages/optmem/user/` e `storages/optmem/ws/<hash-do-caminho>/`.
- Hash do caminho canônico do workspace, estável entre sessões.
- `wake` renderiza dois documentos, `user` primeiro, cada um com seu frame e sua
  linha de custo.
- Divisão do orçamento por `wake.userShare` (padrão 0.25); namespace vazio devolve
  o orçamento ao outro.
- `scope.mode`: `both` | `user` | `workspace`.
- Detecção e aviso de memória órfã de workspace que não existe mais.

## Fora de escopo

Sincronização entre máquinas (não-meta do v1) e memória compartilhada entre
usuários.

## Critérios de aceitação

- [ ] Duas sessões em workspaces diferentes não veem memória de projeto uma da
      outra, e ambas veem o namespace `user`.
- [ ] Um store de workspace vazio faz o namespace `user` receber os
      `wake.budgetTokens` completos.
- [ ] Renomear o diretório do workspace cria um namespace novo, e o plugin avisa
      sobre a memória órfã do caminho antigo.
- [ ] Cada store tem numeração de ids própria e independente; ids de stores
      diferentes nunca são misturados em um mesmo bloco.
- [ ] Nenhum bloco da árvore de um namespace contém memória de outro (verificado
      por propriedade sobre o store sintético).
- [ ] O hash do caminho é estável entre execuções e entre plataformas para o mesmo
      caminho canônico.

## Dependências

- item 02 (store), item 07 (injeção).

## Referências

- [spec 08 — escopo](https://github.com/igorcesarcode/dsh-optmem/blob/main/docs/spec/08-escopo-e-subagentes.md)
