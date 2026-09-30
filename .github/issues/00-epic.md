---
title: "[EPIC] dsh-optmem — plugin nativo de memória permanente para DSH"
labels: [spec, type:feature]
---

## Objetivo

Entregar um plugin nativo de DSH que dê ao agente memória permanente entre
sessões, com **custo de contexto explícito** e **proveniência obrigatória**,
usando os seams do harness em vez de convenções de prompt.

Baseado na ideia do [OptMem](https://github.com/VictorTaelin/OptMem) — log
append-only + árvore de resumos + orçamento de leitura que decai com a idade —
corrigindo os quatro pontos que o projeto original deixou em aberto:

1. dependia de obediência do modelo (`memo wake` como primeira tool call);
2. a compressão custava turnos do agente (~1 por memória);
3. não havia proveniência: texto livre entrava em todo contexto futuro, para sempre;
4. paginação e orçamento eram adivinhações sobre limites de harness.

## Especificação

- Visão geral: [`docs/spec/00-overview.md`](https://github.com/igorcesarcode/dsh-optmem/blob/main/docs/spec/00-overview.md)
- Decisões: [`docs/adr/`](https://github.com/igorcesarcode/dsh-optmem/tree/main/docs/adr)
- Levantamento do harness: [`docs/research/`](https://github.com/igorcesarcode/dsh-optmem/tree/main/docs/research)

## Resultado esperado

- O agente lembra do que aprendeu, sem precisar ser instruído a lembrar.
- O usuário vê quanto a memória custa em tokens, e escolhe o orçamento.
- A memória é um arquivo legível, portátil e inspecionável sem o DSH.
- Nenhuma memória existe sem proveniência; conteúdo não confiável não entra com
  autoridade de instrução.
- Falha de memória é falha aberta e visível — nunca derruba a sessão.
- **A GUI Web ganha uma aba nativa `OptMem`**, ao lado de Chat e Trajectory, onde
  memórias e compactações aparecem em tempo real (ver abaixo).

## Requisito de superfície

A aba não é conveniência: é o instrumento que torna a memória auditável pelo
usuário. Sem ela, "o que o agente sabe sobre mim?" só se responde lendo um log, e
uma memória que o usuário não vê é uma memória que ele não corrige.

Mecanismo verificado: as abas são entradas no slot `conversation.view` do pacote de
conversa, e o código de cliente é entregue por um pacote de duas metades
(`dsh.client` + `platform: "web"` + export `./client`). A descoberta é
Loader-driven e relativa ao pacote — **sem fork do harness**.
Ver [ADR-0007](https://github.com/igorcesarcode/dsh-optmem/blob/main/docs/adr/0007-superficie-web.md) e
[spec 11](https://github.com/igorcesarcode/dsh-optmem/blob/main/docs/spec/11-web.md).

O custo real é de build: o preset que emite o bundle de cliente não é publicado, e
o host nunca constrói. Por isso o protótipo de formato ([#20](https://github.com/igorcesarcode/dsh-optmem/issues/20))
bloqueia a aba — a viabilidade arquitetural está decidida, o esforço não.

## Fases

| Milestone | Entrega | Estado |
|---|---|---|
| M1 — Fundação | pacote, store, cobertura, render, interop | — |
| M2 — Contexto | injeção, escopo, tools — **o sistema funciona** | — |
| M3 — Inteligência | compressão em background, compactação | — |
| M4 — Superfície | painel web, settings, i18n | — |
| M5 — Endurecimento | proveniência, aprovação, privacidade | — |
| M6 — Release | matriz de compatibilidade, docs, npm | — |

## Não-metas do v1

Busca vetorial (ADR-0006), sincronização entre máquinas, memória compartilhada
entre usuários, substituir o histórico de sessão do DSH, editor de texto rico.

## Riscos de topo

| Risco | Mitigação |
|---|---|
| Custo de compressão cresce sem limite | compressão lazy (spec 06); é o único custo que cresce |
| APIs do DSH em RC mudam | camada de adaptação `src/harness/` (spec 14) |
| Memória envenenada persiste | proveniência + escape + aprovação (spec 09) |
| Custo de contexto surpreende o usuário | orçamento explícito, custo no rodapé do wake |

## Critério de conclusão do épico

Uma pessoa que não participou do desenvolvimento consegue, seguindo apenas a
README: instalar o plugin, ver a memória sendo formada em duas sessões
consecutivas, ver o custo em tokens, inspecionar o `LOG.txt` sem o DSH, e
desinstalar sem perder a memória.
