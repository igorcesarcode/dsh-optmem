# ADR-0005 — O plugin é o único escritor; a CLI `memo` opera em somente-leitura

- **Status:** aceito
- **Data:** 2026-09-30
- **Contexto da decisão:** especificação 02 (store)

## Contexto

O ADR-0001 adota o formato de arquivo do OptMem para permitir que a CLI `memo`
continue útil. Isso cria imediatamente um risco: **dois escritores no mesmo log**.

Ambos os escritores usam o mesmo mecanismo de segurança — lock de arquivo e
`repair` de cauda parcial — mas com semânticas diferentes:

- A CLI assume que **ela** atribui ids e que a árvore é construída por ela, com
  `pending()` derivado de `count()` por nível.
- O plugin (ADR-0002) comprime em background, o que significa que ele constrói
  níveis da árvore **sem** que o agente tenha pedido.

Se os dois rodarem `nap` no mesmo diretório, o resultado é trabalho duplicado,
`tree_put` recusando escritas (`if count(p, TREE_REC) != lo // size: return False`)
e, no limite, divergência entre o que cada um acha que está pendente. Nenhum dado
é perdido — o log é append-only — mas o estado fica confuso e o custo de token é
pago duas vezes.

## Decisão

**Um diretório, um escritor.** O plugin é o dono do diretório de memória.

- O diretório padrão é `$DSH_HOME/storages/optmem/` — fora de `~/.optmem/`, para
  que a CLI e o plugin não compartilhem diretório por acidente.
- Apontar `MEMORY_DIR` do plugin para `~/.optmem/memory` é **explicitamente
  suportado**, mas apenas com `store.role = 'reader'`. Nesse modo o plugin:
  - lê normalmente (wake, recall, zoom);
  - **não** grava notas;
  - **não** comprime;
  - e a tool `memory_note` responde com um erro explícito que ensina o usuário a
    escolher entre "usar a CLI" ou "migrar o diretório para o plugin".
- A migração é uma operação explícita e documentada (`dsh-optmem migrate <dir>`),
  que copia o log preservando ids, copia a árvore como cache e **deixa o
  diretório de origem intacto**, para que a volta seja possível.
- Um arquivo-sentinela no diretório (`OWNER`) registra quem escreve ali. Se o
  plugin encontrar um diretório sem sentinela e com árvore construída, assume
  `reader` e avisa — nunca assume posse de um store que não criou.

## Consequências

- A CLI continua sendo uma ferramenta de inspeção de primeira classe: `memo
  recall`, `memo zoom` e `memo wake` funcionam contra o diretório do plugin.
  Isso é valioso o bastante para justificar a compatibilidade de formato.
- Usuários que já têm memória no OptMem não perdem nada: apontam o `MEMORY_DIR`
  e continuam em modo leitura até decidir migrar.
- O plugin não pode contar com a CLI para nada. Nenhum caminho de código invoca
  `python3`, nem como fallback. Um subprocesso de Python no caminho crítico de
  toda sessão seria inaceitável (ADR-0003).
- O `config` de tamanhos deixa de ser um arquivo compartilhado: o plugin usa o
  schema do cordis, e ignora o arquivo `config` da CLI — exceto para **avisar**
  quando os valores divergirem, porque uma divergência de `ENTRY_CHARS` entre os
  dois produtores faria a CLI rejeitar notas que o plugin aceita.

## Alternativas descartadas

- **Coexistência com lock compartilhado.** Tecnicamente possível, já que ambos os
  lados usam lock de arquivo. Descartado porque o problema não é corrupção, é
  **intenção**: dois planejadores de árvore com políticas diferentes no mesmo
  diretório não têm como concordar sobre o que está pendente.
- **Plugin delega toda escrita à CLI.** Reintroduz o subprocesso e a dependência
  de `python3` no caminho crítico. Descartado.
- **Formato próprio, sem compatibilidade.** Perde a ferramenta de inspeção
  independente e a possibilidade de auditar a memória sem o DSH instalado —
  metade do valor de ter memória em arquivo plano.

## Evidência

- Semântica de posse e de ids: `memo` do OptMem (`log_append` atribui ids dentro
  do lock; `tree_put` recusa escrita fora de ordem).
- Diretórios gerenciados do DSH: `~/.dsh/storages` (observado no ambiente) e
  `@deepseek-ai/dsh-storage` / `@deepseek-ai/dsh-storage-json`.
