# ADR-0006 — Sem busca vetorial no v1; recall exato e navegação por árvore

- **Status:** aceito
- **Data:** 2026-09-30
- **Contexto da decisão:** especificações 03 (wake) e 05 (tools)

## Contexto

A pergunta "como o agente encontra uma memória antiga?" tem duas respostas
conhecidas: busca por similaridade (embeddings + índice vetorial) ou busca exata
(regex / full-text) combinada com navegação hierárquica.

O OptMem escolhe a segunda e delega a inteligência ao agente: `recall <regex>`
varre o log palavra por palavra, e `zoom a-b` abre um nó da árvore nas duas
metades, deixando o agente decidir para onde descer.

Em um plugin de DSH a primeira opção é tecnicamente fácil — o plugin já tem
acesso a provedor de modelo e pode gerar embeddings, e o padrão SQLite já é usado
no projeto (`@deepseek-ai/dsh-session-query-sqlite`).

## Decisão

**v1 não tem busca vetorial.** `recall` é exato (regex, case-insensitive, sobre o
log inteiro), e a busca semântica é responsabilidade do agente navegando pelos
resumos com `zoom`.

Justificativa:

1. **Embeddings criam um segundo índice que pode divergir do log.** O ADR-0001
   escolheu largura fixa exatamente para não ter índice dessincronizável. Um
   índice vetorial reintroduz o problema, e agora com um vetor por memória.
2. **Embeddings exigem um provedor com API de embedding**, que nem toda
   configuração de DSH tem. O plugin deve funcionar com o modelo que o usuário
   já escolheu para conversar, e nem todo provedor expõe embeddings.
3. **O custo é recorrente e invisível.** Cada nota nova precisa de um vetor, e
   cada mudança de modelo de embedding invalida o índice inteiro. É exatamente o
   tipo de custo que o ADR-0002 tenta tornar explícito.
4. **`zoom` funciona bem o suficiente.** O documento de wake já entrega os
   resumos em granularidade decrescente com a idade; navegar é uma ou duas
   chamadas para o caso comum.

O que entra no v1 no lugar disso:

- `recall` com regex e um teto de saída, sempre reportando quantos resultados
  ficaram de fora.
- **FTS derivado opcional** (SQLite FTS5 sobre o log), reconstruível e
  descartável, atrás de `search.mode = 'fts'`. É índice derivado, nunca store
  primário: pode ser apagado a qualquer momento e o sistema continua correto.
- Um gancho documentado para um backend vetorial futuro, **desde que** ele seja
  derivado, reconstruível e opcional pela mesma regra.

## Consequências

- Nenhuma dependência de embedding no v1: o plugin funciona com qualquer
  provedor de chat, inclusive um modelo local.
- O usuário precisa saber **o que** procurar. Isso é uma limitação real: "aquela
  conversa sobre o problema de performance" não é encontrável por regex se a
  palavra "performance" não estiver na memória. Mitigação: os resumos da árvore
  são escritos para conter os termos que identificam o bloco, e a spec 06 define
  o contrato de compressão com esse requisito explícito.
- A licença de complexidade fica baixa: um arquivo, uma regex, um teto. É a parte
  do sistema com menor risco de bug.
- Se o backend vetorial for adicionado depois, o ADR-0001 já garante que ele pode
  ser descartado e reconstruído a partir do log, sem migração.

## Alternativas descartadas

- **Embeddings desde o v1.** Melhor recuperação, custo e acoplamento piores, e
  contraria a decisão de não ter índice que possa divergir. Adiado, não rejeitado.
- **Só regex, sem árvore.** Simplifica muito, mas o wake passaria a mostrar
  apenas as N memórias mais recentes, e memória antiga ficaria inalcançável sem
  saber a palavra exata. A árvore é o que dá recuperação aproximada sem vetores.
- **Deixar o agente resumir sob demanda, sem árvore persistida.** Pagaria o custo
  de compressão em toda sessão. Descartado.

## Evidência

- `recall` como varredura completa com teto de saída, e `zoom` como navegação:
  `memo` do OptMem (`cmd_recall`, `cmd_zoom`).
- Padrão de índice descartável já existente no harness:
  `@deepseek-ai/dsh-session-query` e `@deepseek-ai/dsh-session-query-sqlite`.
