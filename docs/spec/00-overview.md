# 00 — Visão geral

## O problema

Um agente de DSH esquece tudo ao fim da sessão. O que ele aprendeu sobre o
projeto, sobre o usuário e sobre tentativas que falharam vive apenas no histórico
daquela sessão, e morre na compactação ou no fechamento.

As saídas conhecidas são insatisfatórias:

- **Escrever tudo em `AGENTS.md`.** Cresce sem limite e é relido inteiro em toda
  requisição. Vira caro antes de virar útil.
- **Confiar no histórico de sessões.** O DSH já persiste sessões e permite
  consultá-las, mas consultar é uma busca, não uma memória: o agente não *sabe*
  nada no início da sessão.
- **Bancos de memória com pipeline de LLM (vetoriais, "memory servers").** Fazem
  a recuperação semântica bem, mas introduzem servidor, dependências, índice que
  diverge e um custo por escrita que o usuário não vê.

O OptMem demonstrou uma quarta via, minimalista: **log append-only + árvore de
resumos + orçamento de leitura que decai com a idade**. O armazenamento é
ilimitado; a leitura é limitada e barata. A inteligência é do agente, a
ferramenta é burra e auditável.

O que o OptMem deixou em aberto, e que este projeto ataca, são quatro coisas:

1. **Depende de obediência do modelo.** A memória só existe se o modelo rodar
   `memo wake` como primeira chamada de toda sessão. Falha em silêncio.
2. **A compressão custa turnos.** ~1 compressão por memória, cada uma um turno
   completo do agente.
3. **Sem proveniência.** Texto livre entra em todo contexto futuro, para sempre.
   Uma injeção de prompt vira persistente e auto-replicante.
4. **Retrabalho de transporte.** Paginação, orçamento e formatação são
   adivinhações sobre limites de harness.

## O que este projeto é

`dsh-optmem` é um **plugin nativo de DSH** que implementa memória permanente,
usando os seams do harness em vez de convenções de prompt:

| Necessidade | Seam do DSH | Ganho sobre o OptMem |
|---|---|---|
| Entregar a memória ao agente | `agent/pre-step` (waterfall, mensagem durável) | o modelo não pode esquecer de acordar |
| Voltar após compactação | `agent/session-start` fonte `'compact'` | memória sobrevive à compactação |
| Comprimir | `ctx.llm.stream()` + `ctx.jobs` | custo em tokens, não em turnos |
| Orçamento de contexto | `ctx.tokenMeter` | medido, não estimado |
| Não rodar em subagente | `delegationDepthOf(agent)` | garantido em código |
| Auditoria | eventos de sessão + `ctx.invariants` | proveniência verificável |
| Persistência | `ctx.storage` / diretório próprio | atômica e gerenciada |
| Interface e configuração | plugin client / settings | memória visível e editável na GUI |

## Metas

- **M1.** A memória está visível ao agente no primeiro passo de toda sessão, sem
  ação do modelo.
- **M2.** O custo de contexto é um número explícito, medido, e configurável pelo
  usuário.
- **M3.** O ativo (o log) é um arquivo legível, portátil, inspecionável sem o DSH
  instalado, compatível em formato com a CLI `memo`.
- **M4.** Nenhuma memória existe sem proveniência, e conteúdo de origem não
  confiável não entra no contexto com autoridade de instrução.
- **M5.** Nenhum caminho de código bloqueia a sessão: falha de memória é falha
  aberta e **visível**.
- **M6.** A compressão não consome turnos do agente e seu custo é observável.

## Não-metas (v1)

- **Busca vetorial.** Ver ADR-0006. `recall` é exato; a aproximação vem da árvore.
- **Sincronização entre máquinas.** O diretório pode estar em pasta sincronizada,
  mas o plugin não coordena conflito entre réplicas. Um store por máquina.
- **Memória compartilhada entre usuários.** Escopo é usuário + workspace.
- **Substituir o histórico de sessão do DSH.** O plugin não poda, não resume e não
  gerencia o histórico da conversa. Ele só acrescenta memória.
- **Interface de edição rica.** O painel web é de inspeção e correção, não um
  editor de texto com versionamento.

## Arquitetura

```
                    ┌─────────────────────────────────────┐
   agente  ─────────┤  agent/pre-step   (injeção)         │
                    │  agent/session-start ('compact')    │
                    └──────────────┬──────────────────────┘
                                   │ documento de wake (orçado)
                    ┌──────────────▼──────────────────────┐
                    │  cover(T, budget)  ← ctx.tokenMeter │
                    └──────────────┬──────────────────────┘
                        lê         │         lê
              ┌─────────────────┐  │  ┌──────────────────┐
              │ LOG.txt         │◄─┴─►│ TREE/<size>      │
              │ largura fixa    │      │ cache de resumos │
              │ append-only     │      │ descartável      │
              └────────┬────────┘      └────────▲─────────┘
                       │ append                 │ append
              ┌────────▼────────────────────────┴─────────┐
              │  store (lock, repair, ids, proveniência)  │
              └────────▲──────────────────────▲───────────┘
                       │                      │
          ┌────────────┴───────┐   ┌──────────┴──────────────┐
          │ tools              │   │ job de compressão       │
          │ memory_note …      │   │ ctx.llm.stream() + jobs │
          └────────────────────┘   └─────────────────────────┘
```

### Componentes

| Componente | Responsabilidade | Spec |
|---|---|---|
| `store` | log append-only, ids, lock, repair, proveniência | 02 |
| `cover` | escolher blocos para o orçamento; render do documento | 03 |
| `injector` | injetar em pre-step/session-start, dedup, escape | 04 |
| `tools` | `memory_note`, `memory_wake`, `memory_recall`, `memory_zoom`, `memory_forget`, `memory_config` | 05 |
| `compressor` | job de background, prompt de compressão, custo | 06 |
| `compaction-bridge` | observar/reagir à compactação | 07 |
| `scope` | workspace, sessão, profundidade de delegação | 08 |
| `audit` | eventos de sessão, invariantes, proveniência | 12 |
| `web` | painel e settings | 11 |

## Fluxos

### 1. Início de sessão

1. O primeiro passo elegível dispara `agent/pre-step`.
2. O injetor verifica: é subagente? (não injeta, spec 08) Já injetou nesta
   sessão? (não repete)
3. `cover(T, budget)` escolhe os blocos; `tokenMeter` confirma o tamanho.
4. O documento é emoldurado, escapado e anexado como mensagem durável com fonte
   de plugin.
5. Se o store falhar, injeta um aviso de uma linha e segue (falha aberta).

### 2. Durante o trabalho

O agente chama `memory_note` quando aprende algo. A tool grava com proveniência,
responde com o id, e — **sem bloquear** — enfileira o trabalho de compressão que a
nova memória tornou possível. O agente nunca é interrompido para comprimir.

### 3. Compressão

O job de background pega os blocos pendentes **que a cobertura atual precisa**,
chama o modelo com o prompt de compressão, grava o resumo como registro
append-only, e registra tokens e custo. Falha: retenta com backoff, e após N
tentativas marca o bloco como `degraded` e segue.

### 4. Compactação da conversa

Quando o DSH compacta, o documento de memória pode ficar sombreado. Na próxima
sessão com fonte `'compact'`, o injetor re-injeta. A memória nunca depende de
sobreviver dentro do histórico compactado.

### 5. Recuperação de uma memória antiga

`memory_recall <regex>` varre o log; ou o agente navega: `memory_zoom a-b` abre um
nó nas duas metades, até chegar na memória crua.

## Custos

| Item | Ordem de grandeza | Observação |
|---|---|---|
| Injeção | orçamento padrão de ~8k tokens por sessão, durável até a compactar | é o custo dominante e é **escolhido**, não acidental |
| Compressão | 1 chamada por memória, ~1,5k tokens de entrada cada | **linear**; mitigado por compressão lazy |
| Armazenamento | ~600 B por memória (log + árvore) | irrelevante em dinheiro |
| Latência | leitura em processo, sem subprocesso | no caminho crítico do 1º passo |
| Efeito colateral | janela ocupada antecipa a compactação da conversa | compactação é uma chamada caríssima |

O custo de compressão merece um número: 10 mil memórias ≈ 15M tokens de entrada;
1 milhão ≈ 1,5B. É o único componente que cresce de forma relevante, e é por isso
que a compressão lazy (spec 06) é requisito, não otimização.

## Riscos

| Risco | Severidade | Mitigação |
|---|---|---|
| Memória envenenada persiste e se replica | alta | ADR-0004: proveniência, autoridade por origem, escape, aprovação |
| Custo de contexto surpreende o usuário | média | orçamento explícito + contador de tokens no `wake` |
| Custo de compressão cresce sem limite | média | lazy, teto por job, custo registrado e reportado |
| Plugin vira dependência dura da sessão | média | falha aberta com aviso; nunca lança no loop |
| API do DSH muda (está em RC) | média | spec 14: matriz de compatibilidade e camada de adaptação |
| Vazamento de dados pessoais ao provedor | média | spec 10: redação, escopo, retenção configurável |
| Store corrompido por crash | baixa | ADR-0001: repair de cauda + append-only |

## Estado

Este repositório contém **especificação e planejamento**, não implementação. O
trabalho está fatiado nas issues do repositório, com milestones por fase. Ver
[`../index.md`](../index.md) para o mapa e [`14-release.md`](14-release.md) para a
ordem de entrega.
