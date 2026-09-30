---
title: "compaction: verificação de visibilidade e re-injeção após compactação"
labels: [area:compaction, area:injection, type:feature]
milestone: "M3 — Inteligência"
---

## Contexto

Quando o DSH compacta, o documento de memória injetado no início da sessão é
apenas mais uma mensagem no histórico: se a compactação escolher uma faixa que o
inclui, ele sai da superfície derivada e o modelo para de vê-lo. O modo de falha é
particularmente ruim — a memória some exatamente quando a conversa está longa o
bastante para precisar dela.

**Correção vinda do levantamento:** a re-injeção **não** pode depender de
`agent/session-start` com fonte `'compact'`. Esse valor é declarado em
`SessionStartSource` mas **não tem emissor** no harness publicado — os únicos call
sites passam `'startup'` e `'resume'`. Também não existe evento cordis em volta da
compactação: `compaction/*` são eventos de sessão. Ver
[research/README](../blob/main/docs/research/README.md), "achados que mudaram
decisões".

## Escopo

- **Garantia:** a cada passo, verificar se a última injeção ainda está visível na
  superfície derivada; se não, injetar de novo. Cobre compactação automática,
  `/compact` manual e poda de resultados de ferramenta.
- **Otimização:** observar `compaction/end` em `session/event` para invalidar o
  cache de visibilidade e antecipar a reavaliação. Não é o mecanismo de correção.
- Dedup sobre eventos **crus** da sessão, não sobre a superfície derivada: varredura
  de seqs (`Session.eventAt`) e fold em `sessionProjections` casando a fonte de
  plugin — o modelo do `dsh-time-context`. O `dsh-agent-instructions` varre só a
  superfície derivada e por isso reinjeta um baseline inteiro depois de compactar;
  é o modelo errado para "eu já injetei?".
- Cache de visibilidade por revisão da superfície, para não custar uma varredura
  por passo.
- Nunca reinjetar quando a anterior continua visível — inclusive no caso de
  compactação parcial que preservou a primeira.
- (Opcional, `compaction.harvest`) colher candidatos a memória da faixa sombreada,
  lendo a sessão **bruta**, com aprovação e `origin = agent-inference`.

## Fora de escopo

Implementar um backend de compactação próprio. O plugin **observa** a compactação,
não a substitui.

## Critérios de aceitação

- [ ] Após compactação automática que sombreia o documento, o próximo passo contém
      um documento novo e o anterior não está na superfície derivada.
- [ ] Após `/compact` manual, o mesmo vale.
- [ ] Duas compactações consecutivas produzem exatamente duas injeções no total,
      não três.
- [ ] Uma compactação que **não** sombreia o documento não produz re-injeção.
- [ ] Com `injection.recheckEveryStep = false`, a re-injeção depende só do gatilho
      `compaction/end` — e existe um teste que documenta o caso em que isso falha,
      deixando claro por que o padrão é `true`.
- [ ] A verificação de visibilidade adiciona menos de 1 ms por passo em uma sessão
      com 500 mensagens.
- [ ] Com `compaction.harvest = true`, uma decisão registrada explicitamente e
      depois descartada produz um candidato que a contém, e nenhum candidato é
      gravado sem passar pela política de escrita.

## Dependências

- item 07 (injeção), item 13 (compressão).

## Referências

- [spec 07 — compactação](../blob/main/docs/spec/07-compaction.md)
- [research/03 — lifecycle, injeção e compactação](../blob/main/docs/research/03-lifecycle-injection-compaction.md)
