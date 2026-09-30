---
title: "render: documento de wake com enquadramento, escape e rodapé de custo"
labels: [area:cover, area:security, type:feature]
milestone: "M1 — Fundação"
---

## Contexto

O documento de wake é o canal pelo qual a memória entra no contexto. Duas coisas
precisam estar certas aqui, e ambas são de segurança, não de formatação:

1. **Autoridade declarada.** O cabeçalho diz que aquilo é dado, não instrução, e
   não sobrepõe instruções de sistema, de desenvolvedor ou do usuário.
2. **Escape.** Um `</system-reminder>` literal dentro de uma memória fecharia o
   frame do plugin e escreveria com autoridade que não tem (spec 09, C2).

## Escopo

- Enquadramento com cabeçalho de autoridade e contagem de memórias.
- Escape de qualquer fechamento de tag usado no frame, em memória crua e em resumo.
- Linhas no formato `#id data texto` (crua) e `#lo-hi resumo` (bloco), em ordem
  cronológica crescente.
- Marca explícita de lacuna (`[resumo pendente]`) — silêncio pareceria "nada
  aconteceu".
- Marca de origem para memórias `tool-output` (spec 09, C1).
- Rodapé com as duas tools de recuperação e o custo em tokens.
- Substituição por uma linha de aviso quando o store falha (falha aberta e visível).

## Fora de escopo

A escolha de quais blocos entram (item 03) e a injeção no histórico (item 07).

## Critérios de aceitação

- [ ] Uma memória contendo `</system-reminder>` e texto de instrução produz um
      documento com **exatamente um** fechamento de frame, no fim, e o conteúdo
      escapado.
- [ ] O documento nunca passa de `injection.maxBytes`, mesmo com resumos de 280
      bytes em todas as linhas.
- [ ] Memórias `tool-output` aparecem com marca de origem distinguível.
- [ ] Blocos sem resumo aparecem como lacuna explícita, nunca omitidos.
- [ ] O rodapé mostra o custo medido em tokens e as duas tools de recuperação.
- [ ] Com o store inacessível, o documento tem exatamente uma linha, nomeia o
      caminho e o erro, e não contém stack trace.
- [ ] O render é puro: mesma cobertura + mesmas memórias ⇒ mesmo texto.

## Dependências

- item 03 (cover).

## Referências

- [spec 03 — wake e cover](../blob/main/docs/spec/03-wake-e-cover.md)
- [spec 09 — segurança](../blob/main/docs/spec/09-seguranca.md)
