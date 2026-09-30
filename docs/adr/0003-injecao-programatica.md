# ADR-0003 — Injeção programática em `agent/pre-step`, não por obediência do modelo

- **Status:** aceito
- **Data:** 2026-09-30
- **Contexto da decisão:** especificação 04 (injeção)

## Contexto

O OptMem depende de o modelo obedecer a uma instrução: "run `memo wake` before any
other tool call, in every session". Toda a memória do sistema repousa sobre essa
frase. Um modelo mais fraco, um turno interrompido ou uma compactação no momento
errado bastam para a sessão começar sem passado — e o modo de falha é **silencioso**:
o agente simplesmente não sabe nada e não avisa.

O DSH tem um seam que existe exatamente para isso: `agent/pre-step` é um waterfall
que decide **com que mensagens o loop entra no passo**, e
`@deepseek-ai/dsh-agent-instructions` já o usa para injetar `AGENTS.md`.

## Decisão

O documento de memória é injetado como **mensagem durável do próprio plugin**,
em `agent/pre-step`, sem passar por decisão do modelo.

Regras:

1. **Uma vez por sessão**, no primeiro passo elegível. Não a cada passo.
2. **Fonte tipada.** A mensagem carrega `source` de plugin, com nome do plugin e
   as seções que a compõem — nunca texto anônimo no histórico.
3. **Autoridade limitada, declarada no enquadramento.** O texto entra emoldurado
   como contexto de memória que **não sobrepõe** instruções de sistema, de
   desenvolvedor ou do usuário. Memória é dado, não instrução.
4. **Escape obrigatório.** Qualquer `</system-reminder>` literal no conteúdo da
   memória é escapado antes de entrar no frame. Sem isso, uma memória fecha o
   frame do plugin e injeta texto com autoridade que não tem. Isto é requisito de
   segurança, não de formatação (ver ADR-0004 e spec 09).
5. **Falha é aberta e visível.** Se o store não puder ser lido, a sessão começa
   sem memória e **com um aviso no contexto**, nunca em silêncio.
6. **Re-injeção após compactação**, observando `compaction/end` no fluxo de eventos
   de sessão e reavaliando a visibilidade no próximo `agent/pre-step`. **Não** por
   `agent/session-start` com fonte `'compact'`: esse valor é declarado no tipo, mas
   nenhum emissor existe no harness publicado — só `'startup'` e `'resume'` são
   passados. Fazer a re-injeção depender dele seria construir sobre um seam que não
   dispara (ver [research](../research/README.md), achados que mudaram decisões).
7. **Nunca em subagente** (ver ADR/spec 08).

## Consequências

- O modelo não pode "esquecer de acordar". O pior caso passa a ser falta de
  memória **reportada**, não falta de memória silenciosa.
- O documento de memória ocupa a janela de contexto de forma permanente até a
  próxima compactação. Por isso o orçamento é explícito e configurável
  (spec 03): o custo é conhecido e escolhido, não acidental.
- A injeção está no caminho crítico do primeiro passo: precisa ser leitura em
  processo com cache, nunca subprocesso. Um `python3` por passo seria inaceitável.
- Como a mensagem é durável e participa do replay, a sessão continua
  reconstruível a partir do log — a memória não é estado oculto.

## Alternativas descartadas

- **Só prompt + tool call (OptMem).** É o que estamos tentando consertar.
- **Injetar em todo passo.** Mantém a memória fresca, mas paga o custo em toda
  requisição e destrói o cache de prefixo. Descartado.
- **Colocar o texto no system prompt via configuração de perfil.** Funcionaria
  para um bloco estático, mas não para conteúdo que muda a cada sessão, e
  misturaria memória com instruções — exatamente o que o item 3 proíbe.
- **Injetar só em `agent/session-start`.** O hook equivalente (`SessionStart`)
  roda *detached* no bridge de hooks do Claude Code e "context can miss the first
  request"; e a fonte `'compact'` nunca é emitida. `agent/pre-step` é o único seam
  verificado que roda antes de **toda** requisição.

## Evidência

- `agent/pre-step` e `PreStepDecision`: `@deepseek-ai/dsh-agent/lib/types/runtime-types.d.ts:302-319` e `:92`.
- `SessionStartSource` declara `'startup' | 'resume' | 'clear' | 'compact'`
  (`runtime-types.d.ts:105`), mas só `'startup'` e `'resume'` têm emissor: o único
  ponto de emissão é o parâmetro `source` de `setupAndPublish`/`publish`
  (`@deepseek-ai/dsh-agent-loop/lib/index.js:1720`, `:1840`), com call sites em
  `:1763`, `:1834` (`"startup"`) e `:1925` (`"resume"`).
- Observação da compactação por evento de sessão, não por evento cordis:
  `compaction/start|summary|end` são tipos de evento de sessão
  (`@deepseek-ai/dsh-compaction/lib/types/types.d.ts:14-99`), observáveis em
  `ctx.on('session/event', …)` (`@deepseek-ai/dsh-session/lib/types/index.d.ts:52-62`).
- Dedup contra histórico sombreado: varredura de seqs brutos com
  `Session.seq` / `Session.eventAt(SessionSeq(n))` e fold em
  `ctx.sessionProjections.register({ key, stateVersion, stateSchema, init, apply })`
  (`@deepseek-ai/dsh-time-context/lib/index.js:135-143`, `:181-219`). O
  `dsh-agent-instructions` varre apenas `session.surface.nodes` e por isso **não**
  serve de modelo para "eu já injetei?".
