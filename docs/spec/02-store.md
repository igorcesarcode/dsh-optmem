# 02 — Store: log append-only, ids e proveniência

## Objetivo

Ser a única fonte de verdade do conteúdo da memória, com mutação restrita a
append, leitura O(1) por id, e recuperação automática de cauda parcial causada por
crash.

## Formato do log

`LOG.txt` é uma sequência de registros de **320 bytes**, sem cabeçalho, sem
rodapé, sem índice.

```
offset i*320
┌──────────────────────────────────────────────────────────────┐
│ '#12 2026-09-30 o usuário prefere respostas curtas\n'        │
│ '                                            …padding…     ' │
└──────────────────────────────────────────────────────────────┘
  └── 320 bytes exatos ──────────────────────────────────────┘
```

Layout do conteúdo, antes do padding:

```
#<id> <YYYY-MM-DD> <texto>
```

- `<id>` é decimal, sem padding, atribuído dentro do lock.
- A data é ISO, sem hora — é a data de registro, não de fato.
- `<texto>` é uma linha, UTF-8, até **280 bytes**.
- O padding é espaço (`0x20`) e o registro termina em `\n`.

### Por que largura fixa

Posição é identidade: `id × 320` é o offset. Não existe índice para dessincronizar,
e toda leitura é um seek. O custo é ~2× de espaço para memórias curtas — aceito
deliberadamente (ADR-0001).

### Invariantes do log

| # | Invariante | Consequência de violação |
|---|---|---|
| I1 | `size % 320 == 0` após `repair` | registros desalinhados, todo id subsequente lixo |
| I2 | O id no registro `i` é `i` | identidade posicional quebrada |
| I3 | Registros `[0, n)` são decodificáveis em UTF-8 | leitura falha |
| I4 | O texto nunca contém `\n` nem `\r` | um registro com dois fins de linha desalinha tudo |
| I5 | O arquivo nunca é truncado, exceto por `repair` de cauda parcial | perda de memória |

I2 é verificado na leitura: se o id lido não bate com a posição, o store entra em
modo `corrupt`, serve o que conseguir em modo leitura, e exige intervenção
explícita do usuário. Nunca "conserta" em silêncio.

## Proveniência

Arquivo irmão `PROV.txt`, de largura fixa (**240 bytes**), alinhado por id: o
registro `i` descreve a memória `i`. Campos separados por `\t`:

```
<sessionId>\t<turn>\t<step>\t<depth>\t<origin>\t<workspace>\t<model>\t<refs>
```

- `origin` ∈ `user` | `agent-inference` | `tool-output` | `import`
- `workspace` é o caminho do workspace, ou `-`
- `refs` é uma lista de ids de tool call separada por `,`, ou `-`

Regras:

- **P1.** Um registro de proveniência existe para todo id do log. Na migração de
  um store sem proveniência, todos recebem `import`.
- **P2.** Se `PROV.txt` for perdido, o store continua legível; todas as memórias
  passam a `import` e o plugin avisa. Não é corrupção fatal.
- **P3.** `tool-output` nunca é promovido a outra origem por escrita nova; apenas
  resumos herdam o **conjunto** de origens dos filhos.
- **P4.** Gravar com `origin = tool-output` exige aprovação (spec 09).

## API interna

```ts
interface MemoryRecord {
  id: number
  date: string          // YYYY-MM-DD
  text: string
}

interface Provenance {
  sessionId: string
  turn: number
  step: number
  depth: number
  origin: 'user' | 'agent-inference' | 'tool-output' | 'import'
  workspace?: string
  model?: string
  refs?: string[]
}

interface Store {
  /** número de memórias; size/320, nunca uma varredura */
  length(): number
  /** uma memória, um seek */
  get(id: number): MemoryRecord
  /** faixa [lo,hi) em uma leitura */
  slice(lo: number, hi: number): MemoryRecord[]
  /** varredura em streaming, sem materializar o log */
  scan(): Iterable<MemoryRecord>
  /** única mutação do conteúdo; ids atribuídos dentro do lock */
  append(items: Array<{ date: string; text: string; prov: Provenance }>): number
  /** leitura da proveniência de um id */
  prov(id: number): Provenance
  /** resumos: leitura e append por nível */
  tree: TreeStore
}
```

### Limites

- `ENTRY_CHARS` máximo é `min(TREE_REC - 8, LOG_REC - 40)` = 280. O mesmo teto
  vale para resumos, com o layout do nível.
- A escrita rejeita texto com `\n`, `\r`, vazio, ou acima do teto, com mensagem
  que ensina a corrigir (não apenas "inválido").

## Concorrência

- Um lock de arquivo exclusivo (`.lock`) cobre **toda** atribuição de id e toda
  escrita de árvore. Sem ele, duas sessões paralelas recebem o mesmo id.
- O lock é aberto em modo append (`"a"`), nunca `"w"` — truncar o arquivo de lock
  quebra locks advisory mantidos por outros processos.
- `fsync` após cada lote antes de liberar o lock. O custo é desprezível porque
  lotes são pequenos e raros.
- Toda leitura é livre de lock: o log só cresce, então um leitor sempre vê um
  prefixo consistente.

## Crash e reparo

`repair()` roda **antes** de qualquer append, sob o lock:

1. `n = size(arquivo)`
2. se `n % 320 != 0`, truncar para `n - (n % 320)`

O registro parcial nunca foi confirmado a ninguém, então removê-lo é correto. Sem
isso, o próximo append começa desalinhado e **todos** os registros seguintes ficam
ilegíveis — um único crash destruiria a memória inteira.

O mesmo reparo se aplica a cada arquivo de nível da árvore, com seu próprio
tamanho de registro. A árvore é cache (ADR-0001), então um nível corrompido pode
ser simplesmente truncado e reconstruído.

## Diretório e configuração

```
$DSH_HOME/storages/optmem/
  LOG.txt        memórias
  PROV.txt       proveniência, alinhada por id
  TREE/<size>    resumos por nível (cache)
  OWNER          sentinela: quem escreve aqui
  .lock          lock advisory
```

| Config | Padrão | Significado |
|---|---|---|
| `store.dir` | `$DSH_HOME/storages/optmem` | diretório do store |
| `store.role` | `'writer'` | `writer` \| `reader` |
| `store.entryChars` | `280` | teto por memória, em bytes |
| `store.workspaceScoped` | `false` | se `true`, um store por workspace |

`store.role = 'reader'` é obrigatório (ou forçado, com aviso) quando o diretório
não contém `OWNER` mas contém árvore construída — sinal de que veio do OptMem
original. Ver ADR-0005.

## Interoperabilidade com a CLI `memo`

| Operação | Funciona contra o diretório do plugin? |
|---|---|
| `memo wake` | sim (lê `LOG.txt` e `TREE/`) |
| `memo recall` | sim |
| `memo zoom` | sim |
| `memo note` | **não** — modo leitor; dois escritores proibidos |
| `memo nap` | **não** — mesma razão |

O plugin **nunca** invoca `python3` nem a CLI. A compatibilidade é de formato, não
de processo.

`dsh-optmem migrate <dir>` copia `LOG.txt` e `TREE/` para o diretório do plugin,
preserva ids, cria `PROV.txt` com `origin = import` para tudo, escreve `OWNER`, e
**deixa a origem intacta**.

## Critérios de aceitação

- **CA1.** `get(i)` executa em tempo constante verificável: leitura de exatamente
  320 bytes no offset `i × 320`, com um único `read`.
- **CA2.** Simular crash truncando o log em `n - 7` bytes; o próximo `append`
  produz um log válido, e todas as memórias anteriores continuam legíveis por id.
- **CA3.** 8 processos gravando 200 memórias cada produzem exatamente 1600
  memórias, sem id duplicado e sem registro fora de ordem.
- **CA4.** `LOG.txt` truncado em um limite de registro continua legível pela CLI
  `memo` do OptMem, com `MEMORY_DIR` apontado para o diretório do plugin.
- **CA5.** Apagar `PROV.txt` não impede `wake`; todas as memórias passam a
  `import` e um aviso é emitido.
- **CA6.** Apagar `TREE/` inteiro não perde nenhuma memória; a árvore é
  reconstruída pelos jobs de compressão.
- **CA7.** Texto com `\n`, vazio, ou 281 bytes é rejeitado com mensagem que diz o
  limite e como corrigir.
- **CA8.** Um id lido que não bate com a posição coloca o store em `corrupt`, e
  nenhuma escrita é aceita nesse estado.
