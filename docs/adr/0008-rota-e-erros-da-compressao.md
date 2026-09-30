# ADR-0008 — A compressão tem rota própria, e o tratamento de erro é nosso

- **Status:** aceito
- **Data:** 2026-09-30
- **Contexto da decisão:** especificações 06 (compressão) e 11 (web)

## Contexto

Duas descobertas do levantamento forçam esta decisão.

**Primeira.** O harness **não** dá retry para chamadas diretas a `ctx.llm.stream()`.
O `dsh-llm-retry` retenta no limite do passo durável do agente, e o próprio README
diz por quê: *"Skip it when calls go through `ctx.llm.stream()` directly without the
agent loop: those consumers remain single-attempt because a raw stream cannot
separate already-emitted chunks durably."* Como o ADR-0002 decidiu que a compressão
chama o modelo direto, **nós** somos os donos do retry, do backoff e da taxonomia de
erro. Isso não é um detalhe de implementação; é uma responsabilidade herdada.

**Segunda.** A compressão é o único lugar do sistema que gasta dinheiro em escala —
uma chamada por bloco, para sempre. É também o lugar onde a qualidade do modelo
importa **menos** que na conversa: o trabalho é condensar uma linha a partir de
texto que já está no contexto, com um contrato explícito. Usar o mesmo modelo caro
da sessão para isso é desperdício; usar um modelo barato é a otimização óbvia.

Ao mesmo tempo, o usuário precisa poder escolher — inclusive escolher o modelo caro,
se a memória dele vale isso.

## Decisão

A compressão tem **rota própria**, configurável, independente da rota da sessão, e o
**tratamento de erro é implementado por nós**.

### Rota

- `compression.route.provider`, `compression.route.model`,
  `compression.route.reasoning_effort`.
- **Vazio significa herdar a rota da sessão.** É o padrão, porque é o comportamento
  que não surpreende e não exige configuração.
- A forma é a mesma que o subagente usa (`AllowedModelRoute { provider, model }` mais
  `reasoning_effort`), para que o usuário reconheça a interface e para que a
  validação seja a mesma: **provider e model andam juntos**, e trocar a rota sem
  informar effort limpa o effort pertencente à rota anterior.
- O effort é **validado contra o modelo**, não aceito como texto livre: o harness
  rejeita effort não suportado antes de qualquer I/O de provedor, sem clamp e sem
  alias. Um adapter sem metadado de raciocínio simplesmente não oferece a linha de
  effort.

### Tratamento de erro

Taxonomia própria, derivada do `code` compartilhado do `LlmError`
(`AUTH`, `RATE_LIMIT`, `NO_ADAPTER`, …), com duas classes:

| Classe | Códigos | Ação |
|---|---|---|
| **Transitório** | `RATE_LIMIT`, `TIMEOUT`, `TRANSPORT`, `SERVER`, `EMPTY_RESPONSE` | retenta com backoff exponencial e jitter |
| **Permanente** | `AUTH`, `NO_ADAPTER`, effort/modelo inválido, `CONTEXT_WINDOW_EXCEEDED`, conteúdo não suportado | **não retenta** — a tentativa seguinte falharia igual |

Regras:

1. **Permanente é permanente.** Retentar `AUTH` mil vezes com credencial errada é
   queimar dinheiro e encher o log. Erro permanente marca o bloco e **desliga a
   compressão** após N falhas consecutivas, com aviso visível (disjuntor).
2. **Bloco grande demais é reduzido, não retentado.** `CONTEXT_WINDOW_EXCEEDED` é
   permanente *para aquela entrada*, então a resposta é dividir o bloco em dois
   filhos e enfileirá-los — não repetir o mesmo pedido.
3. **Retry é seguro por construção.** A gravação do resumo é append-only e o job
   desiste se o bloco já foi comprimido. Um retry que chega depois de um sucesso
   alheio não duplica nada.
4. **Backoff com os mesmos nomes do harness** (`initialDelayMs`, `maxDelayMs`,
   `jitterRatio`, `maxAttempts`), porque é o vocabulário que o usuário já viu na
   configuração do provedor.
5. **Nada disso chega ao loop do agente.** Falha de compressão é assunto do plugin;
   o agente nunca vê um erro de API por causa da memória.
6. **Custo de retry é custo real.** Cada tentativa é uma requisição faturada. O
   contador de tokens conta tentativas fracassadas também — esconder isso seria
   esconder o custo que o ADR-0002 prometeu tornar visível.

## Consequências

- O plugin passa a ter uma superfície de configuração maior que "os tamanhos":
  rota, effort, retry e o liga/desliga. Isso é o preço de a compressão ser
  server-side, e é um preço honesto — a alternativa (delegar ao agente) tem um custo
  maior e invisível.
- A interface de escolha de modelo é **a mesma do subagente**: lista agrupada por
  provedor, com descrições vindas do diretório vivo, effort derivado do modelo, e
  rotas salvas que sumiram do catálogo aparecendo no fim e continuando removíveis.
  Reusar o padrão é melhor que inventar um segundo jeito de escolher modelo na mesma
  GUI.
- Um erro de configuração de rota (credencial errada, adapter ausente) agora tem um
  modo de falha explícito e visível, em vez de silenciosamente degradar para lacunas.
- O disjuntor introduz estado entre jobs. Ele é derivado (contadores por store) e
  zerado por uma ação explícita do usuário, nunca por tempo — religar sozinho depois
  de uma credencial errada só repete o erro.

## Alternativas descartadas

- **Usar sempre a rota da sessão.** Zero configuração, mas amarra o custo da memória
  ao modelo mais caro que o usuário escolheu para conversar. Descartado como
  **único** comportamento; mantido como **padrão**.
- **Deixar o `dsh-llm-retry` cuidar disso.** Não é possível: ele não cobre
  `ctx.llm.stream()` direto. Descartado por inviabilidade, não por preferência.
- **Retry infinito em qualquer erro.** Transforma uma credencial errada em um laço
  que gasta dinheiro sozinho. Descartado.
- **Escolher o modelo por heurística (o mais barato disponível).** O plugin não sabe
  o preço dos modelos, e adivinhar por nome de modelo é frágil. O usuário escolhe.

## Evidência

- Retry do harness não cobre stream direto: `@deepseek-ai/dsh-llm-retry/README.md`
  ("direct `ctx.llm.stream()` calls remain single-attempt"), com a taxonomia de
  códigos elegíveis (`EMPTY_RESPONSE`, `RATE_LIMIT`, `SERVER`, `TIMEOUT`,
  `TRANSPORT`) e a forma do `retryPolicy`
  (`initialDelayMs`/`maxDelayMs`/`jitterRatio`).
- Catálogo e effort: `ctx.llm.listModels(provider)` e
  `ctx.llm.resolveModelInfo(provider, model, signal)` — "exact model identity plus
  available context and reasoning metadata"
  (`@deepseek-ai/dsh-llm/lib/types/index.d.ts:345`, `:355`); effort não suportado
  rejeita antes do I/O, sem clamp nem alias (`:361`).
- Taxonomia compartilhada de erro: `LlmError` com `code`
  (`@deepseek-ai/dsh-llm/lib/types/index.d.ts:59`, `:69`).
- Forma da rota e do effort no subagente:
  `@deepseek-ai/dsh-tool-subagent/lib/types/model-selection.d.ts`
  (`AllowedModelRoute`, `DelegationModelRequest.reasoning_effort`).
