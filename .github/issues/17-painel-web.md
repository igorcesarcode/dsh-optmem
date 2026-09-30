---
title: "web: aba nativa OptMem no slot conversation.view"
labels: [area:web, type:feature]
milestone: "M4 — Superfície"
---

## Contexto

A GUI Web tem hoje duas abas: **Chat** e **Trajectory**. O requisito é uma terceira,
nativa, onde o usuário vê e corrige o que o agente sabe.

Isto **não** é conveniência: a spec 10 (P6) exige que o usuário consiga ver o que o
agente sabe sobre ele sem ler um log, e uma memória que o usuário não vê é uma
memória que ele não corrige.

O mecanismo está decidido e verificado: as abas são entradas no slot
`conversation.view`, e "Chat" é apenas a entrada padrão resolvida por
`resolveActiveView`. O Trajectory registra a dele exatamente assim
(`dsh-client-ui-trajectory/lib/client.js`). Ver ADR-0007 e
[research/04](https://github.com/igorcesarcode/dsh-optmem/blob/main/docs/research/04-superficie-cliente-e-aba.md).

**Este item é bloqueado por [#20](https://github.com/igorcesarcode/dsh-optmem/issues/20)** enquanto o formato de
bundle de cliente não estiver provado: o host só serve bundle já construído, e o
preset de build do harness não é publicado.

## Escopo

- Pacote de duas metades: `dsh.client` com `platform: "web"` e export `./client`.
- Registro no slot `conversation.view` com `id` estável (`optmem`), `order`
  configurável e `label` vindo do serviço de locale.
- Três seções internas: **Ao vivo**, **Memórias** e **Custos** (spec 11).
- **Memórias**: lista por namespace, busca, indicadores (privada, `tool-output`,
  resumo vs. crua, pendente, `degraded`) e ações (alternar privado, descartar
  resumo, apagar de verdade com confirmação textual, `zoom`).
- **Custos**: orçamento, tokens da última injeção, chamadas e tokens de compressão,
  pendentes, degradados, saúde do store.
- Consultas ao store por chamada da metade browser para a metade host.
- A metade browser **não** contém lógica de memória: ela projeta e consulta.

## Fora de escopo

O ledger ao vivo (item 27), a configuração na GUI (item 18) e o protótipo de bundle
(item 19).

## Critérios de aceitação

- [ ] A aba **OptMem** aparece ao lado de **Chat** e **Trajectory**, e desaparece ao
      desinstalar o plugin, sem reiniciar o host.
- [ ] Uma sessão retomada reconstrói o estado da aba, não abre vazia.
- [ ] Uma memória com string sentinela **não** aparece com o texto completo na
      listagem — só ao abrir a memória.
- [ ] A busca encontra uma memória de uma sessão anterior e `zoom` abre o nó.
- [ ] Marcar como privada remove a memória do próximo wake injetado, verificado em
      sessão nova.
- [ ] Apagar de verdade exige confirmação textual e reporta a contagem removida.
- [ ] Em modo `reader`, nenhuma ação de escrita é oferecida, e a razão é exibida.
- [ ] Store inacessível não quebra a GUI: mostra o erro e as outras abas seguem
      funcionando.
- [ ] O registro usa o wrapper de efeito do serviço de slots (unload remove a aba).

## Dependências

- item 19 (protótipo de bundle) — bloqueia.
- itens 10, 11 (tools), item 20 (eventos de sessão).

## Referências

- [spec 11 — web](https://github.com/igorcesarcode/dsh-optmem/blob/main/docs/spec/11-web.md)
- [ADR-0007](https://github.com/igorcesarcode/dsh-optmem/blob/main/docs/adr/0007-superficie-web.md)
