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
- chamadas de compressão, tokens de entrada e de saída acumulados, **incluindo
  tentativas fracassadas** — esconder o custo do retry seria esconder custo real;
- a rota em uso (herdada da sessão ou explícita) e o effort;
- pendentes e degradados, e o **estado do disjuntor** quando armado;
- estado de saúde do store: `writer`/`reader`, `corrupt`, lacunas.

## Ativação: instalado ≠ ativo

São duas coisas diferentes, e a GUI precisa deixar isso explícito:

| Estado | Onde vive | Quem controla | O que significa |
|---|---|---|---|
| **instalado e montado** | perfil (patch do Loader) | o usuário, no arquivo de perfil | o código carrega no host |
| **ativo** | configuração do plugin | uma **chave na GUI** | a memória funciona |

Um plugin pode estar montado e inativo: o usuário quer manter a memória no disco,
mas não quer que o agente receba contexto dela agora — durante um trabalho sob
confidencialidade diferente, durante um debug, ou enquanto ajusta a configuração.

**Inativo significa, concretamente:**

- nenhuma injeção em `agent/pre-step`, e `optmem/skip` com `reason = 'disabled'`;
- nenhuma compressão, nenhuma chamada de LLM;
- as tools respondem que o plugin está inativo, com a instrução de como ativar;
- **o store não é tocado**: nada é apagado, nada é recomputado, nada é reescrito;
- a aba continua acessível e mostra "inativo", em vez de parecer vazia.

A chave de ativação é uma **configuração do plugin**, não uma mutação do Loader: a
projeção do inventário de plugins do harness é explicitamente somente-leitura e não
habilita nem desabilita nada. O que a GUI mostra do Loader é o estado de montagem; o
que ela **controla** é a nossa chave.

O padrão de interação é o do cartão de subagente (ver abaixo): a chave e as rotas
são **estagiadas juntas** e gravadas em uma única mutação, cercada pela revisão em
que o rascunho começou. Desativar **preserva** as rotas escolhidas para reuso.

## Configuração na GUI

**A configuração não é renderizada automaticamente a partir do schema.** A aba de
plugins despacha um slot por namespace, e um namespace que nenhum cartão reivindica
**não renderiza nada** — os controles dos pacotes publicados são escritos à mão
([research/02](../research/02-client-web-kit.md) §4).

O que existe a favor: o `SettingsDescriptor.schema` **está no fio**, e há API de
schema (reidratação, validação, acesso por caminho). Então o desenho é: o plugin
**entrega o próprio cartão**, e o formulário é **dirigido pelo schema** — cada campo
com descrição e padrão vindos do schema, sem lista duplicada escrita à mão, que é o
modo de falha real (schema e formulário divergindo).

### Referência: o cartão de subagente

O cartão `subagent-model-selection` é a referência de UI para a parte de modelo, e
adotamos os comportamentos dele porque são a resposta para problemas que já
apareceram:

| Comportamento do cartão de subagente | Por que adotamos |
|---|---|
| Chave de permissão + modelos, **estagiados juntos** | evita o estado intermediário "ligado sem modelo" |
| Salvar submete `enabled` e rotas em **uma** mutação, cercada pela revisão do rascunho | uma revisão nova do host marca o rascunho como falho em vez de restaurar uma rota revogada |
| **Desativar preserva** as rotas | reativar não obriga a reconfigurar |
| Modelos **agrupados por provedor** | o catálogo já vem assim |
| Rotas salvas **ausentes do catálogo** aparecem no fim e continuam removíveis | o catálogo é consultivo; sumir da lista não invalida a escolha |
| Nomes de adapter e descrições de modelo são **metadado vivo**, não armazenado; o cartão atualiza após mudanças de adapter, commits de settings e reconexões | descrição de modelo envelhece mal no disco |
| Effort **derivado do modelo**; modelo sem metadado de raciocínio não mostra a linha; sem entrada livre | o harness rejeita effort não suportado sem clamp nem alias — oferecer texto livre seria oferecer uma configuração inválida |

### O nosso cartão

1. **Chave de ativação** (o "instalado ≠ ativo" acima).
2. **Rota da compressão**: lista de modelos agrupada por provedor, com a opção
   explícita **"herdar da sessão"** como primeiro item e padrão; effort derivado do
   modelo escolhido. Ver [ADR-0008](../adr/0008-rota-e-erros-da-compressao.md).
3. **Orçamento**: slider para `wake.budgetTokens` com **estimativa viva** para o
   store atual, para que o usuário veja a consequência antes de aplicar.
4. **Saúde e custo**: modo da compressão, pendentes, degradados, disjuntor armado ou
   não, chamadas e tokens acumulados (incluindo tentativas fracassadas).
5. As demais opções aparecem, mas marcadas como "de instalação": mudá-las é decisão
   de perfil, não de conversa.

## i18n

- Os locales embutidos do harness são exatamente **`zh` e `en`**; `zh` é a fonte de
  verdade do conjunto de chaves. O harness suporta pacotes de idioma externos
  (`addLanguage`), e é por aí que **pt-BR** entra, se disponível.
- Consequência de projeto: as chaves de `en` e `zh` são obrigatórias; `pt-BR` é
  adicional e não pode ser a única fonte de uma chave.
- Cada registro de slot carrega o seu namespace de locale; sem a face de locale o
  harness falha na montagem do slot.
- As mensagens que o **modelo** vê ficam em inglês, como as demais mensagens de
  ferramenta do harness. O histórico é mais fácil de auditar com uma língua só
  para metadados.
- `README.md` e `README.zh.md` na convenção dos pacotes. O `README.i18n.yaml` é
  registro de hash de blob para ferramenta de documentação — **não** é bundle de
  strings e não é lido em runtime.

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
- **CA13.** Desativar pela GUI faz a próxima sessão não receber injeção (verificado
  em sessão nova) e **nenhum** arquivo do store mudar (hash e mtime do diretório
  inteiro).
- **CA14.** Desativar não apaga memória e não invalida resumo: reativar devolve o
  comportamento anterior sem recompressão.
- **CA15.** Desativado, uma tool de memória responde que o plugin está inativo e
  como ativá-lo — não um erro genérico.
- **CA16.** Desativar pela GUI interrompe a compressão em andamento e nenhuma
  chamada de LLM nova acontece depois disso (verificado por contagem de chamadas).
- **CA17.** A chave de ativação e a rota são gravadas em **uma** mutação: uma
  revisão nova do host no meio marca o rascunho como falho, e não restaura uma rota
  revogada.
- **CA18.** A lista de modelos é agrupada por provedor, o effort muda quando o
  modelo muda, e um modelo sem metadado de raciocínio **não** mostra a linha de
  effort e **não** aceita effort por texto livre.
- **CA19.** Uma rota salva que sumiu do catálogo aparece no fim da lista e continua
  removível.
- **CA20.** Com a rota herdada (padrão), a compressão usa o mesmo provider/model da
  sessão — verificado no evento `optmem/compress`.
- **CA21.** O cartão mostra o disjuntor armado quando a compressão foi desligada por
  falhas permanentes, e o religar é uma ação explícita.

## Dependências de pesquisa

O protótipo de formato de bundle (issue 19) bloqueia CA1 e CA12. Todo o resto
pode ser especificado e implementado antes dele.
