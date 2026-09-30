---
title: "web: ledger ao vivo de memórias e compactações"
labels: [area:web, type:feature]
milestone: "M4 — Superfície"
---

## Contexto

É a metade "em tempo real" do requisito: ver a memória **acontecendo**, e ver a
compactação acontecer.

O ponto que torna isto barato: não há transporte novo a inventar. Os eventos
`optmem/*` (spec 12) já são eventos de sessão, e `compaction/*` **já é** evento de
sessão do harness (`dsh-compaction/lib/types/types.d.ts`). É o mesmo canal que o
Trajectory consome para desenhar o ledger dele. A aba OptMem apenas projeta.

## Escopo

Ledger append-only, sem polling e sem botão de atualizar, com uma linha por evento:

| Linha | Origem |
|---|---|
| memória gravada | `optmem/note` |
| compressão concluída | `optmem/compress` |
| compressão falhou | `optmem/compress-failed` |
| injeção | `optmem/inject` |
| não injetado (com motivo) | `optmem/skip` |
| **compactação** | `compaction/start` / `compaction/end` |
| **re-injeção pós-compactação** | `optmem/inject` após `compaction/end` |

Regras:

- **Sem polling.** Alimentado pelo fluxo de eventos de sessão.
- **Sem texto completo.** A linha mostra o suficiente para reconhecer a memória; o
  texto completo é a seção "Memórias", sob demanda.
- **Reconstruível.** Uma sessão retomada mostra o ledger derivado do log, não
  vazio.
- **Ausência é informação.** "Nenhuma compressão pendente" precisa ser visível: o
  usuário tem de saber que a memória está em dia.

## Fora de escopo

Atividade de **outras** sessões no mesmo store. O canal de eventos é por sessão;
um canal de push da metade host é trabalho de v2, registrado como limite declarado
na spec 11, não como bug.

## Critérios de aceitação

- [ ] Gravar uma memória faz uma linha aparecer **sem recarregar a página**.
- [ ] Uma compactação que sombreia a memória produz **duas** linhas: a compactação e
      a re-injeção.
- [ ] Uma sessão retomada mostra o ledger reconstruído do log de sessão.
- [ ] Nenhuma requisição periódica é feita com a aba aberta e o agente parado
      (verificado contando requisições, não por inspeção visual).
- [ ] Uma memória com string sentinela não aparece com o texto completo no ledger.
- [ ] O estado "nada pendente" é distinguível de "sem dados".
- [ ] Um evento desconhecido (de uma versão futura do plugin) não quebra o ledger:
      é ignorado ou mostrado como desconhecido.

## Dependências

- item 19 (protótipo de bundle) — bloqueia.
- item 20 (proveniência e invariantes) — os eventos precisam existir.

## Referências

- [spec 11 — web](../blob/main/docs/spec/11-web.md)
- [spec 12 — observabilidade](../blob/main/docs/spec/12-observabilidade.md)
