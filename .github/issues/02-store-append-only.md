---
title: "store: log append-only de largura fixa, ids, lock e repair"
labels: [area:store, type:feature]
milestone: "M1 — Fundação"
---

## Contexto

O store é o ativo de longo prazo: é o único componente cujo formato não pode ser
trocado sem perda. Um crash no momento errado não pode custar a memória inteira —
é isso que o `repair` de cauda existe para impedir.

Formato adotado (ADR-0001): registros de **320 bytes**, `#<id> <YYYY-MM-DD> <texto>`
com padding de espaços, anexados sob lock exclusivo.

## Escopo

- Escrita de registros de largura fixa; teto de 280 bytes por memória.
- Atribuição de id **dentro do lock** e `fsync` antes de liberar.
- `repair()` de cauda parcial, executado antes de qualquer append.
- Leitura: `get(id)` em um seek, `slice(lo,hi)` em uma leitura, `scan()` em
  streaming (nunca materializa o log inteiro).
- Verificação do invariante "o id na posição `i` é `i`"; violação coloca o store
  em `corrupt` e recusa escrita.
- Criação do diretório com permissão `0700` e arquivos `0600`.
- `OWNER` com `format=1` e o namespace.

## Fora de escopo

Árvore de resumos (item 03), proveniência (item 20), criptografia (spec 10, P5).

## Critérios de aceitação

- [ ] `get(id)` lê exatamente 320 bytes no offset `id × 320`, com um único read
      (verificado por instrumentação de I/O no teste).
- [ ] Truncar o log em cada offset de 0 a `2 × 320` e depois anexar: o log
      resultante é válido e todas as memórias anteriores continuam legíveis por id.
- [ ] 8 processos gravando 200 memórias cada produzem exatamente 1600 memórias,
      com ids únicos e sem registro fora de ordem.
- [ ] Texto com `\n`, `\r`, vazio ou 281 bytes é rejeitado com mensagem que nomeia
      o limite e ensina a corrigir.
- [ ] UTF-8 multi-byte no limite exato de 280 bytes é aceito; o corte é feito em
      bytes, nunca sobre texto já decodificado.
- [ ] `scan()` percorre 1.000.000 de registros sintéticos sem materializar mais de
      um lote por vez (medido por memória residente no teste).
- [ ] Um id que não bate com a posição coloca o store em `corrupt` e nenhuma
      escrita é aceita nesse estado.

## Dependências

- item 01 (scaffold).

## Referências

- [spec 02 — store](https://github.com/igorcesarcode/dsh-optmem/blob/main/docs/spec/02-store.md)
- [ADR-0001](https://github.com/igorcesarcode/dsh-optmem/blob/main/docs/adr/0001-log-append-only-de-largura-fixa.md)
