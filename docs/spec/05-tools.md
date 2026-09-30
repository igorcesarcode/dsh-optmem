# 05 — Tools de memória

## Objetivo

Dar ao agente (e ao usuário) acesso explícito ao store: gravar, reler, buscar,
navegar, descartar e inspecionar. As tools são a interface **deliberada**; a
injeção (spec 04) é a interface **automática**.

## Catálogo

| Tool | Papel | Frequência esperada |
|---|---|---|
| `memory_note` | grava uma memória | alta |
| `memory_recall` | busca exata no log | média |
| `memory_wake` | relê o documento de memória | baixa (manual) |
| `memory_zoom` | abre um nó da árvore nas duas metades | média |
| `memory_forget` | descarta um resumo ruim, ou apaga de verdade | rara |
| `memory_config` | mostra o instantâneo de saúde e custo | rara |

Nomes em `snake_case`, seguindo a convenção das tools do harness. Nomes com
prefixo `memory_` para não colidir com tools de terceiros e para que o agente
identifique a família.

## `memory_note`

```jsonc
{
  "text": "string, obrigatório, uma linha, ≤ 280 bytes",
  "namespace": "user | workspace",   // padrão: derivado da config
  "origin": "user | agent-inference | tool-output",  // padrão: agent-inference
  "private": false,                  // true → não entra no wake
  "refs": ["tool-call-id"]           // opcional
}
```

Contrato:

- **N1.** Rejeita texto vazio, com `\n` ou `\r`, ou acima do teto — com mensagem
  que diz o limite e ensina a corrigir ("comprima mais" / "registre em duas
  memórias"), nunca apenas "inválido".
- **N2.** Rejeita se um `privacy.denyPatterns` corresponder, nomeando o padrão.
- **N3.** Com `origin = tool-output`, passa pelo ponto de decisão `ask` do harness
  **antes** de gravar (spec 09, C3). Negado → nada é escrito.
- **N4.** Em profundidade > 0, falha com a mensagem: *"subagentes não gravam
  memória; devolva este fato ao agente principal para que ele registre"*.
- **N5.** Em `store.role = 'reader'`, falha explicando o modo leitor e como
  migrar.
- **N6.** Respeita `note.maxPerTurn` e `note.maxPerDay` (spec 09, C4).
- **N7.** Responde com o id atribuído, o namespace e a contagem atual.
- **N8.** **Não** bloqueia para comprimir. Enfileira o trabalho e retorna. O
  agente nunca espera a compressão (ADR-0002).

A saída apresenta o id e, quando há trabalho de compressão pendente, uma linha
informativa — nunca uma exigência de ação imediata.

## `memory_recall`

```jsonc
{
  "pattern": "string, regex, case-insensitive",
  "namespace": "user | workspace | both",  // padrão: both
  "limit": 50,                             // teto de resultados
  "includePrivate": false
}
```

- **R1.** Varredura completa do log, em streaming, sem materializar tudo em
  memória. O teto de saída é respeitado **descartando os mais antigos**, e a saída
  diz quantos ficaram de fora — nunca trunca em silêncio.
- **R2.** Regex inválida produz erro que mostra o problema na regex, não stack
  trace.
- **R3.** Resultados são formatados como `#id data texto`, uma linha cada, o mesmo
  formato do documento de wake, para que o id possa ser usado em `zoom`/`forget`.
- **R4.** `includePrivate = false` (padrão) inclui memórias privadas — a busca é
  deliberada, então o padrão é encontrá-las (spec 10, P2). O parâmetro existe para
  excluí-las explicitamente.

## `memory_zoom`

```jsonc
{ "block": "lo-hi", "namespace": "user | workspace | both" }
```

- **Z1.** `lo-hi` é validado como bloco real: alinhado, potência de dois,
  `size ≥ 2`. `4-5` e `5-6` não podem ser aceitos como o mesmo registro — sem a
  checagem de forma, um id ambíguo é um bug de leitura silencioso.
- **Z2.** Abre o nó nas duas metades, cada uma renderizada como o wake a
  renderizaria: resumo, se existir; memória crua, se `size == 1`; marca explícita
  se o resumo ainda não existe.
- **Z3.** Nunca dispara compressão sincronamente: se o resumo falta, a tool
  enfileira e diz que está pendente.

## `memory_wake`

```jsonc
{ "namespace": "user | workspace | both", "force": false }
```

- **W1.** Relê o documento. É para releitura manual deliberada — a injeção
  automática (spec 04) já cobre o caso normal.
- **W2.** Não reinjeta no histórico por chamar esta tool: a tool devolve o texto
  como resultado de tool, que é diferente de mensagem durável injetada. Isso é
  documentado para não confundir "eu vi" com "está no contexto".

## `memory_forget`

```jsonc
{
  "block": "lo-hi",           // descarta um resumo (soft)
  "namespace": "...",
  "hard": false,              // true → operação destrutiva, exige confirm
  "confirm": "APAGAR"         // literal, só para hard = true
}
```

- **F1.** Soft (padrão): descarta o resumo e tudo construído sobre ele; o próximo
  job recomputa. O log **não** é tocado. É a operação segura e a mais comum.
- **F2.** Hard: reescreve o log, **renumera todos os ids**, invalida a árvore e as
  referências antigas. Exige `confirm: "APAGAR"` literal e reporta quantas
  memórias foram removidas (contagens, nunca conteúdo).
- **F3.** `hard` em `store.role = 'reader'` é recusado.

## `memory_config`

```jsonc
{ "namespace": "..." }   // opcional; ausente → todos
```

Devolve o instantâneo da spec 12. É somente leitura, exceto por uma variante
opcional `set` que muda **apenas** o orçamento de wake — a única configuração que
faz sentido ajustar em conversa, porque é a única cujo efeito o usuário sente
imediatamente.

## Apresentação

Cada tool declara sua projeção de apresentação, para que o resultado apareça
legível na GUI (spec 11) em vez de JSON cru: notas como uma linha com id, recall
como lista, zoom como duas seções, config como tabela.

## Critérios de aceitação

- **CA1.** As seis tools são registradas e aparecem no conjunto de tools da
  sessão; cada uma tem schema de argumentos e schema de saída válidos.
- **CA2.** Uma tool chamada em profundidade > 0 responde com um erro que contém a
  palavra "subagente" e **não** toca no store (hash antes/depois).
- **CA3.** `memory_note` com 281 bytes falha nomeando o limite; com 280 bytes
  succeeds.
- **CA4.** `memory_note` com `origin = tool-output` sem aprovação deixa o store
  byte-idêntico.
- **CA5.** `memory_recall` com padrão que casa 10.000 memórias devolve no máximo
  `limit` resultados, os mais recentes, e informa quantos ficaram de fora.
- **CA6.** `memory_zoom 4-5` é rejeitado com mensagem sobre a forma de bloco;
  `memory_zoom 4-7` é aceito.
- **CA7.** `memory_forget` com `hard = true` e `confirm` errado não faz nada.
- **CA8.** Nenhuma tool bloqueia esperando compressão: com a fila cheia e provedor
  lento, `memory_note` retorna em menos de 100 ms.
- **CA9.** Toda mensagem de erro de tool é acionável: nomeia o que está errado e
  o que fazer. Verificado por revisão, com um caso de teste por tool.
