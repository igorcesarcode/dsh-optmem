---
title: "compression: rota própria (provider/model/effort) e tratamento de erro de API"
labels: [area:compression, type:feature]
milestone: "M3 — Inteligência"
---

## Contexto

Duas descobertas do levantamento forçam este item.

**O harness não retenta chamadas diretas a `ctx.llm.stream()`.** O `dsh-llm-retry`
retenta no limite do passo durável do agente, e o README dele diz por quê: *"those
consumers remain single-attempt because a raw stream cannot separate already-emitted
chunks durably"*. Como o ADR-0002 decidiu que a compressão chama o modelo direto,
**nós** somos donos do retry, do backoff e da taxonomia de erro.

**A compressão é o único lugar que gasta dinheiro em escala** — uma chamada por
bloco, para sempre — e é onde a qualidade do modelo importa **menos**: o trabalho é
condensar uma linha a partir de texto que já está no contexto, sob contrato
explícito. Amarrar isso ao modelo caro da conversa é desperdício.

Ver [ADR-0008](https://github.com/igorcesarcode/dsh-optmem/blob/main/docs/adr/0008-rota-e-erros-da-compressao.md).

## Escopo

### Rota

- `compression.route.{provider,model,reasoning_effort}`, **vazio = herda a rota da
  sessão** (padrão).
- Provider e model andam juntos: um sem o outro é configuração inválida, rejeitada
  na leitura, não em runtime.
- Trocar a rota sem informar effort **limpa** o effort da rota anterior.
- Effort validado contra o modelo via `ctx.llm.resolveModelInfo`, nunca texto livre.
  Effort não suportado rejeita **antes** de qualquer I/O de provedor, sem clamp nem
  alias. Modelo sem metadado de raciocínio não oferece effort.
- Catálogo é **consultivo**: um modelo servido mas não anunciado continua
  configurável.

### Erro de API

Taxonomia derivada do `code` compartilhado do `LlmError`:

| Classe | Códigos | Ação |
|---|---|---|
| Transitório | `RATE_LIMIT`, `TIMEOUT`, `TRANSPORT`, `SERVER`, `EMPTY_RESPONSE` | retenta com backoff exponencial e jitter |
| Permanente | `AUTH`, `NO_ADAPTER`, modelo/effort inválido, conteúdo não suportado | não retenta |
| Entrada grande demais | `CONTEXT_WINDOW_EXCEEDED` | **divide o bloco** nos dois filhos e enfileira |

- **Disjuntor**: após N falhas permanentes consecutivas, desliga a compressão e
  avisa. Religar é **explícito**, nunca automático por tempo.
- Retry **seguro por construção**: gravação append-only + desistência se o bloco já
  foi comprimido ⇒ tentativa tardia não duplica.
- Vocabulário do harness: `initialDelayMs`, `maxDelayMs`, `jitterRatio`,
  `maxAttempts`.
- **Tentativa fracassada conta no custo** (tokens e chamadas).
- Nada chega ao loop do agente.

## Fora de escopo

A UI de escolha (item 18) e a mecânica da fila e do job (item 13).

## Critérios de aceitação

- [ ] Com rota vazia, o evento `optmem/compress` registra o mesmo provider/model da
  sessão.
- [ ] Com rota explícita, o evento registra a rota configurada e o effort.
- [ ] `provider` sem `model` (e vice-versa) é rejeitado na leitura da configuração.
- [ ] Trocar a rota sem effort limpa o effort anterior, verificado na configuração
  gravada.
- [ ] Effort não suportado pelo modelo é rejeitado **antes** de qualquer chamada ao
  provedor (verificado por contagem de chamadas zero).
- [ ] Um erro `RATE_LIMIT` simulado é retentado com backoff crescente e jitter, e
  sucede na segunda tentativa.
- [ ] Um erro `AUTH` **não** é retentado, e após `breakerAfter` falhas consecutivas a
  compressão fica desligada e reporta o disjuntor armado.
- [ ] Religar o disjuntor exige ação explícita; nenhum caminho o religa por tempo.
- [ ] `CONTEXT_WINDOW_EXCEEDED` divide o bloco em dois filhos em vez de repetir o
  mesmo pedido.
- [ ] Uma tentativa que chega depois de o bloco já ter sido comprimido **não**
  duplica o registro (verificar contagem no nível da árvore).
- [ ] Tokens de tentativas fracassadas entram no acumulado reportado.
- [ ] Nenhuma falha de API produz erro no loop do agente: um teste com provedor que
  sempre falha produz sessão funcional e memória com lacunas.

## Dependências

- item 13 (mecânica do job de compressão).

## Referências

- [spec 06 — compressão](https://github.com/igorcesarcode/dsh-optmem/blob/main/docs/spec/06-compressao.md)
- [ADR-0008](https://github.com/igorcesarcode/dsh-optmem/blob/main/docs/adr/0008-rota-e-erros-da-compressao.md)
