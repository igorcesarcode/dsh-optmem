# ADR-0002 — Compressão server-side em background, não em turno do agente

- **Status:** aceito
- **Data:** 2026-09-30
- **Contexto da decisão:** especificação 06 (compressão)

## Contexto

A memória cresce. Para caber em um orçamento de leitura fixo, memórias antigas
precisam ser comprimidas em resumos, e resumos de resumos formam uma árvore.

O OptMem original resolve isso **delegando ao agente**: `memo note` imprime um
pedido de compressão e o agente responde com `memo nap`. É elegante — a
ferramenta não precisa de LLM — mas tem um custo que só aparece em escala:
**~1 compressão por memória registrada**, e cada compressão é um turno completo
do agente. Em 10 mil memórias, são 10 mil turnos extras. Em 1 milhão, é
inviável por construção.

O DSH oferece o que faltava ao OptMem: acesso direto ao modelo
(`ctx.llm.stream()`) e execução fora do turno (`ctx.jobs`).

## Decisão

A compressão é feita **pelo plugin**, chamando o modelo diretamente, em um job de
background, com `GenerateOptions.purpose` próprio. O agente nunca é interrompido
para comprimir.

- Modo padrão: `compression.mode = 'background'`.
- Modo `'agent'`: preserva o comportamento do OptMem (o prompt pede a compressão
  na próxima ação). Existe como **compatibilidade e diagnóstico**, não como
  padrão.
- Modo `'off'`: o store cresce e `wake` degrada para as memórias mais recentes
  que couberem no orçamento. Nunca falha.

Regras que a implementação deve respeitar:

1. **Nunca no caminho crítico.** A injeção de contexto não espera compressão.
   Se um resumo necessário não existe, `wake` renderiza o que existe e marca a
   lacuna, em vez de bloquear a sessão. (O OptMem faz o oposto: recusa acordar.
   Aqui isso é inaceitável, porque a memória entra no caminho de toda sessão.)
2. **Lazy primeiro.** Só comprime o que a cobertura atual precisa. Não constrói a
   árvore inteira "para depois".
3. **Idempotente e retomável.** Um bloco comprimido é um registro append-only;
   refazer produz outro texto, então o resultado é gravado uma vez e nunca
   sobrescrito. `forget` é o único caminho de descarte.
4. **Custo observável.** Cada job registra tokens de entrada, tokens de saída,
   modelo e duração. O usuário precisa ver quanto a memória custa por mês.
5. **Um job por vez por store.** Compressões concorrentes do mesmo bloco são
   desperdício puro.

## Consequências

- O custo deixa de ser **turnos** e passa a ser **tokens**. É uma troca
  deliberada: turnos são o recurso escasso do agente; tokens são dinheiro e são
  medíveis.
- O custo é **linear no número de memórias** e é o único componente que cresce de
  forma relevante. O modo *lazy* é o que mantém isso sob controle.
- O plugin passa a depender de um provedor de LLM configurado. Sem provedor, cai
  para `'agent'` automaticamente, com aviso, em vez de falhar.
- Existe uma janela em que o resumo está sendo escrito: leituras veem a versão
  anterior ou a lacuna, nunca um registro pela metade (a escrita é atômica e
  append-only).

## Alternativas descartadas

- **Só modo agente (como o OptMem).** Mantém o plugin sem dependência de LLM, mas
  transfere ao usuário um custo quadrático de paciência. Descartado como padrão,
  mantido como modo.
- **Compressão determinística por template extrativo.** Zero custo de token e
  reprodutível, mas a qualidade do resumo cai muito — e a qualidade do resumo é o
  que determina se a memória antiga ainda é útil. Descartado para o v1; anotado
  como possível backend alternativo, já que o DSH expõe `summarize()` como único
  ponto de override do backend de compactação.
- **Compressão síncrona no `wake`.** Bloquearia a primeira requisição de toda
  sessão. Descartado.

## Evidência

- Chamada direta ao modelo por plugin: `@deepseek-ai/dsh-compaction-basic` usa
  `ctx.llm.stream()` com `GenerateOptions.purpose = 'compaction'`.
- Trabalho fora do turno: `@deepseek-ai/dsh-jobs` / `@deepseek-ai/dsh-jobs-local`.
- Ponto de override do resumo: `summarize()` é declarado como o único hook de
  subclasse em `@deepseek-ai/dsh-compaction-basic/README.md`.
