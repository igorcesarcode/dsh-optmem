# 11 — Superfície Web: a aba nativa OptMem

## Objetivo

Dar à memória uma superfície **nativa** na GUI Web: uma terceira aba, ao lado de
**Chat** e **Trajectory**, onde memórias e compactações aparecem **em tempo real**
— e onde o usuário pode inspecionar, buscar, marcar como privado e remover.

Isto é requisito, não conveniência. Uma memória que o usuário não consegue ver é
uma memória que ele não consegue corrigir (spec 10, P6); e uma memória cujo custo
ele não consegue ver é um custo que ele não escolheu.

## Decisão de mecanismo

A aba é uma **entrada no slot `conversation.view`** do pacote de conversa, e o
código de cliente é entregue por um **pacote de duas metades** (`dsh.client` com
`platform: 'web'` e export `./client`).

Isso não é uma escolha entre alternativas: é o mecanismo que o próprio Trajectory
usa. As abas "Chat" e "Trajectory" são entradas irmãs nesse slot, e
`resolveActiveView` trata "Chat" apenas como a entrada padrão.

Evidência completa em
[research/04-superficie-cliente-e-aba.md](../research/04-superficie-cliente-e-aba.md).

### Por que não um painel global

O layout também oferece um slot `main` de escopo raiz para painéis globais
(`ctx.layout.selectPanel(id)`). **Descartado** porque o requisito é uma aba irmã de
Chat e Trajectory, com a mesma natureza de superfície de sessão — não algo que
substitui a conversa. O painel global faria o usuário escolher *entre* ver a
conversa e ver a memória; a aba deixa ele alternar sem perder nada.

## Anatomia da aba

```
┌ Chat ─┬─ Trajectory ─┬─ OptMem ────────────────────────────────────┐
│                                                                ▲ │
│  [ Ao vivo ]  [ Memórias ]  [ Custos ]                          │ │
│                                                                  │ │
│  ── seções internas da aba ──────────────────────────────────────┘ │
└────────────────────────────────────────────────────────────────────┘
```

Três seções internas, por razões distintas:

| Seção | Pergunta que responde | Fonte de dados |
|---|---|---|
| **Ao vivo** | o que a memória está fazendo agora? | fluxo de eventos de sessão |
| **Memórias** | o que o agente sabe? | consulta sob demanda ao store |
| **Custos** | quanto isso me custa? | eventos + contagens do store |

### Seção "Ao vivo" — o requisito de tempo real

Um ledger append-only que cresce conforme os eventos chegam, na ordem em que
chegam, sem polling e sem botão de atualizar:

| Linha | Evento de origem | O que mostra |
|---|---|---|
| memória gravada | `optmem/note` | id, namespace, origem, primeiros bytes do texto |
| compressão concluída | `optmem/compress` | bloco `#lo-hi`, tokens de entrada e saída, duração |
| compressão falhou | `optmem/compress-failed` | bloco, tentativa, motivo, se virou `degraded` |
| injeção | `optmem/inject` | namespace, memórias, blocos, tokens, linhas |
| não injetado | `optmem/skip` | motivo (subagente, já visível, desligado, erro de store) |
| **compactação** | `compaction/*` | faixa sombreada, tokens liberados |
| **re-injeção pós-compactação** | `optmem/inject` após `compaction/end` | que a memória voltou a ficar visível |

As duas últimas linhas são o outro pedido explícito: **compactações em tempo
real**. Elas não exigem trabalho novo de coleta — `compaction/*` já é evento de
sessão, e a re-injeção já é um `optmem/inject` (spec 07). O que a aba faz é
projetá-los.

Regras:

- **L1.** O ledger é alimentado pelo fluxo de eventos de sessão, o mesmo canal que
  o Trajectory consome. Nenhum polling.
- **L2.** O ledger nunca mostra o **texto** de uma memória recém-gravada além dos
  primeiros bytes necessários para reconhecê-la — a aba é uma janela sobre o
  store, e o store é onde o texto mora. Texto completo é a seção "Memórias".
- **L3.** Uma sessão retomada mostra o ledger reconstruído do log de sessão, não
  vazio: o histórico é derivado, como tudo o mais no harness.
- **L4.** O ledger indica a **ausência** de eventos tanto quanto a presença:
  "nenhuma compressão pendente" é informação, e o usuário precisa saber que a
  memória está em dia.

### Seção "Memórias"

Navegação e correção do store:

- lista por namespace, ordenada por id decrescente, com data, origem e marcações;
- busca (mesmo motor do `memory_recall`);
- indicadores visuais: privada, origem `tool-output`, resumo vs. crua, bloco
  pendente, bloco `degraded`;
- ações: alternar privado, descartar resumo (soft), apagar de verdade (hard, com
  confirmação textual);
- abrir um nó da árvore nas duas metades (`zoom`).

Os dados vêm por **consulta sob demanda** à metade host (`host.call`), não pelo
fluxo de eventos: a lista completa de 100.000 memórias não pertence a um fluxo.

### Seção "Custos"

- orçamento configurado (`wake.budgetTokens`) e tokens da última injeção;
- chamadas de compressão, tokens de entrada e de saída acumulados;
- pendentes e degradados;
- estado de saúde do store: `writer`/`reader`, `corrupt`, lacunas.

## Configuração na GUI

O plugin registra seu namespace de configuração no host e seu cartão sob essa
chave no browser. Isso é o caminho declarado para plugins distribuídos fora do
repositório.

- Todos os campos do schema aparecem com descrição e padrão, gerados do schema —
  sem lista duplicada escrita à mão.
- Um controle deslizante para `wake.budgetTokens` com **estimativa viva** para o
  store atual: o usuário vê a consequência antes de aplicar.
- As demais opções são editáveis mas marcadas como "de instalação": mudá-las é uma
  decisão de perfil, não de conversa.

## i18n

- Strings da aba e das mensagens visíveis ao usuário em **pt-BR, en e zh**.
- As mensagens que o **modelo** vê ficam em inglês, como as demais mensagens de
  ferramenta do harness. O histórico é mais fácil de auditar com uma língua só
  para metadados.
- `README.md`, `README.zh.md` e o arquivo de tradução, na convenção dos pacotes.

## O que a aba não é

- **Não** substitui a conversa nem o Trajectory. É uma terceira visão.
- **Não** é um editor de texto: corrigir uma memória é descartar e regravar. Edição
  in-place exigiria reescrever o log, o que colide com o ADR-0001.
- **Não** é um grafo visual da árvore. `zoom` cobre o caso de uso sem o custo de um
  layout de grafo.
- **Não** mostra atividade de **outras** sessões no v1 (ver Limites).

## Limites declarados

| Limite | Motivo | Consequência |
|---|---|---|
| O canal ao vivo cobre a sessão aberta | eventos de sessão são por sessão | atividade de outra sessão paralela só aparece ao recarregar a lista |
| O preset de build do cliente não é publicado | vive no monorepo | temos de reproduzir o formato lazy-CJS e provar por protótipo |
| Os tipos de slot não são publicados | `dsh-client-ui-slots` fora do install | shim de declaração escrito à mão |
| `pnpm run dev:web` não existe no install publicado | é script de raiz do workspace | o watch é o nosso próprio `tsdown --watch` sobre `lib/client.js` |

O primeiro limite é o único que afeta o usuário. A correção — um canal de push da
metade host — é trabalho de v2 e está especificada como tal, não prometida aqui.

## Critérios de aceitação

- **CA1.** A aba **OptMem** aparece ao lado de **Chat** e **Trajectory** quando o
  plugin está instalado, e desaparece quando o plugin é desinstalado — sem
  reiniciar o host.
- **CA2.** Com a aba aberta, gravar uma memória em outra interação faz uma linha
  aparecer no ledger **sem recarregar a página** e sem polling.
- **CA3.** Uma compactação que sombreia a memória produz **duas** linhas no ledger:
  a compactação e a re-injeção.
- **CA4.** Uma sessão retomada mostra o ledger reconstruído, não vazio.
- **CA5.** Uma memória que contém uma string sentinela **não** aparece com o texto
  completo no ledger — só na seção "Memórias", sob demanda.
- **CA6.** A busca encontra uma memória gravada em uma sessão anterior e a lista
  abre o nó correspondente com `zoom`.
- **CA7.** Marcar como privada remove a memória do próximo documento de wake
  injetado, verificado em uma sessão nova, sem recarregar a GUI.
- **CA8.** Apagar de verdade exige confirmação textual na interface e reporta a
  contagem de removidas.
- **CA9.** Em modo `reader`, nenhuma ação de escrita da aba é oferecida, e a razão
  é exibida.
- **CA10.** A aba não quebra a GUI quando o store está inacessível: mostra o erro
  e as demais abas continuam funcionando.
- **CA11.** Nenhuma string aparece hardcoded; as três locales estão completas.
- **CA12.** O bundle de cliente é construído fora do monorepo do harness, e a
  receita está documentada no repositório o suficiente para ser reproduzida.

## Dependências de pesquisa

O protótipo de formato de bundle (issue 19) bloqueia CA1 e CA12. Todo o resto
pode ser especificado e implementado antes dele.
