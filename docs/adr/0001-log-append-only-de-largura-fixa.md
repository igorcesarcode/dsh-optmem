# ADR-0001 — Log append-only de largura fixa, em formato compatível com a CLI `memo`

- **Status:** aceito
- **Data:** 2026-09-30
- **Contexto da decisão:** especificação 02 (store)

## Contexto

A memória precisa ser durável, auditável e independente do harness. Três formatos
eram candidatos: (a) registros de largura fixa em arquivo plano, como o OptMem
original; (b) JSONL append-only; (c) tabelas no SQLite que o DSH já usa para
consultar sessões.

O requisito que domina a escolha não é desempenho, é **sobrevivência**: a memória
tem de continuar legível quando o DSH mudar de versão, quando o plugin for
desinstalado, e quando o usuário quiser inspecionar o arquivo com `grep` ou com a
CLI `memo` do projeto original. Memória de agente é um ativo de longo prazo; o
formato é o único componente que não pode ser trocado sem perda.

## Decisão

O store é um arquivo `LOG.txt` de **registros de largura fixa de 320 bytes**, um
por memória, com o layout do OptMem:

```
#<id> <YYYY-MM-DD> <texto>\n<padding de espaços até 320 bytes>
```

Consequências diretas do formato:

- **Posição é identidade.** A memória `i` começa no offset `i * 320`. Não existe
  arquivo de índice, e portanto não existe índice dessincronizado.
- **Leitura O(1) por seek**, sem varrer o log.
- **Anexar é a única mutação.** Nenhum caminho de código reescreve um registro.
- **Desperdício deliberado de espaço** (~2× para memórias curtas). Aceito: 1M de
  memórias ocupa ~320 MB de log, o que é irrelevante para o custo real do
  sistema, que é token.
- **Reparo de cauda.** Um registro parcial deixado por crash é truncado no
  próximo open, antes de qualquer append (`repair`). Sem isso, um único crash
  desalinha todos os registros seguintes.
- **Teto por memória:** 280 bytes, herdado do formato. É menor que o registro
  para caber cabeçalho e padding.

O diretório é **do plugin** (`$DSH_HOME/storages/optmem/` por padrão), não o
`~/.optmem/memory` da CLI. O *formato* é compatível; a *posse* é do plugin
(ver ADR-0005).

## Consequências

- A CLI `memo` do OptMem consegue ler o arquivo apontando `MEMORY_DIR` para o
  diretório do plugin: `memo recall`, `memo zoom` e `memo wake` funcionam em modo
  leitura. `memo note` e `memo nap` passam a ser proibidos nesse diretório para
  não haver dois escritores.
- A árvore de resumos (`TREE/<size>`) é **cache**: pode ser apagada e reconstruída
  a partir do log. O log nunca depende dela.
- Migrar de JSONL ou SQLite para este formato exigiria reescrita completa; por
  isso a decisão é tomada antes de existir dado real em produção.
- O limite de 280 bytes obriga compressão na escrita, que é o que dá densidade ao
  documento de wake. É uma restrição de projeto, não um acidente.

## Alternativas descartadas

- **JSONL.** Mais legível e sem padding, mas o acesso a uma memória antiga exige
  varrer o arquivo, e não há compatibilidade com a CLI `memo`. A legibilidade já é
  atendida por `recall`.
- **SQLite (`dsh-session-query-sqlite` já usa o padrão).** Daria busca e índice de
  graça, mas amarra a memória a um schema e a uma ferramenta, e transforma um
  arquivo inspecionável em um binário. Fica como índice **derivado** opcional no
  futuro, nunca como store primário.
- **Armazenar como eventos de sessão do DSH.** Daria proveniência e replay de
  graça, mas amarra a memória ao formato de sessão do harness — exatamente o que
  "sobrevive à troca de fornecedor" quer evitar. Ver ADR-0004 para como a
  proveniência é preservada sem essa amarra.

## Evidência

- Formato e constantes: `memo` do OptMem (`LOG_REC = 320`, `ENTRY_CHARS = 280`,
  `repair`, `pad`, `log_append`).
- O `EntryChars` do formato é validado contra o tamanho do registro em
  `size()`: `top = min(TREE_REC - 8, LOG_REC - 40)`.
