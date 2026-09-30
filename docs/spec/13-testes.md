# 13 — Testes

## Princípio

O sistema tem duas metades com naturezas diferentes, e cada uma pede um tipo de
teste:

- **A metade determinística** — store, cobertura, render, escape, escopo. É
  função pura de bytes: testa-se por propriedade, com oráculo independente.
- **A metade de harness** — injeção, tools, compactação, jobs. Só existe dentro do
  DSH: testa-se pelo testkit do próprio harness.

O erro a evitar é testar a metade determinística *através* do harness (lento e
frágil) ou testar a metade de harness *por unidade* (não prova nada, porque o seam
é justamente o que pode estar errado).

## Camada 1 — Propriedades da cobertura

A cobertura é o coração do sistema e a parte com mais chance de bug sutil. Testes
de propriedade, com gerador aleatório de `T`, tamanhos de resumo e orçamentos:

| Propriedade | Enunciado |
|---|---|
| Cobertura | a união dos blocos é exatamente `[0, T)`, sem sobreposição |
| Alinhamento | todo bloco tem `size` potência de dois e `lo % size == 0` |
| Ordem | os blocos saem em ordem crescente de `lo` |
| Orçamento | o custo medido ≤ `wake.budgetTokens` |
| Monotonicidade | aumentar o orçamento nunca produz um documento com menos detalhe nos blocos recentes |
| Estabilidade | `T` e configuração iguais produzem documento byte-idêntico |
| Sem falha | nenhuma entrada produz exceção; lacunas são marcadas, nunca lançadas |

O oráculo é uma implementação de referência independente e ingênua (força bruta
sobre todas as coberturas válidas para `T` pequeno), não uma reimplementação da
mesma lógica.

## Camada 2 — Store

- **Crash:** truncar o log em cada offset de `0` a `2 × 320` e verificar que o
  store se recupera e que as memórias anteriores continuam legíveis por id.
- **Concorrência:** N processos gravando em paralelo; contagem final exata, ids
  únicos, ordem preservada. Repetir com N = 8 (o caso documentado pelo OptMem).
- **Corrupção:** injetar um id errado em um registro e verificar que o store entra
  em `corrupt` e recusa escrita.
- **Fuzz de entrada:** texto com `\n`, `\r`, UTF-8 multi-byte no limite exato de
  280 bytes, surrogates, string vazia.

Atenção ao limite multi-byte: o teto é em **bytes**, não em caracteres, e o corte
precisa ser feito em bytes antes do decode — fatiar texto já decodificado desloca
todas as fronteiras depois do primeiro caractere multi-byte.

## Camada 3 — Integração com o harness

**Aviso de dependência:** os pacotes de testkit do harness (`dsh-loader-smoke`,
`dsh-agent-loop-testkit`) **não estão instalados** e aparecem apenas como
`devDependencies` em manifestos do próprio monorepo — não há contrato publicado que
possamos assumir. O único utilitário de teste verificado como embarcado é
`defineContentToolFixture`, importável da **entrada principal** de
`@deepseek-ai/dsh-tools` (não existe subpath `./testing`).

Consequência: a camada de integração é construída sobre a **API pública** do
harness, com um profile de teste e uma sessão real, e não sobre testkit de
terceiro. Se um testkit publicável aparecer, ele é adotado depois — não é
pré-requisito.

- O plugin monta em um profile de teste sem erro e sem serviço faltante.
- O primeiro passo de uma sessão contém exatamente uma mensagem com a fonte do
  plugin.
- O segundo passo **não** contém uma segunda.
- Após compactação, contém uma nova (spec 07).
- Em subagente, contém zero (spec 08).
- `store.dir` inválido faz o plugin montar e falhar aberto com aviso, em vez de
  derrubar o boot.

## Camada 4 — Segurança

Testes que falham se o controle for removido — não testes que confirmam o código:

- `</system-reminder>` no conteúdo: frame íntegro, exatamente um fechamento.
- Payload adversarial em memória (instruções, tentativa de escalar autoridade):
  o texto aparece como dado e o cabeçalho de autoridade permanece.
- `origin = tool-output` sem aprovação: store inalterado (hash antes/depois).
- `store.dir` com symlink, com `/etc`, com caminho relativo: rejeitados.
- 21 notas em um turno: a 21ª rejeitada.

## Camada 5 — Interoperabilidade

O contrato mais fácil de quebrar em silêncio é a compatibilidade com a CLI do
OptMem. Teste de contrato:

1. Gerar um store com o plugin.
2. Rodar a CLI `memo` real (Python, fixada por commit) com `MEMORY_DIR` apontado
   para o diretório do plugin.
3. Verificar `wake`, `recall` e `zoom` produzem saída consistente com o conteúdo.
4. Verificar que `note`/`nap` **não** são oferecidos (modo leitor).

Este é o único teste que depende de código de terceiros. Ele roda em CI com o
`memo` baixado e verificado por hash, e a CI **falha** se o hash mudar sem uma
atualização deliberada do pin.

## Camada 6 — Custo

Não é teste de correção, é teste de orçamento — roda em CI, com valores fixos:

- Com a fila de compressão cheia e provedor simulado lento, a injeção não espera
  (spec 06 CA1).
- Com `lazy = true` e `T = 100.000` sintético, a contagem de chamadas de
  compressão fica abaixo do teto declarado (spec 06 CA7).
- O documento de wake para `T = 100.000` é produzido em menos de 50 ms.

## O que não se testa

- **Não** se testa a qualidade do resumo gerado pelo modelo. É não determinístico
  por natureza (ADR-0006 e spec 06 aceitam isso explicitamente). Testa-se o
  **contrato**: uma linha, dentro do teto, não vazia, e o custo registrado.
- **Não** se testa o comportamento do modelo diante da memória. Um teste que
  verifica "o modelo lembrou" é um teste que mede o modelo, não o plugin.

## Critérios de aceitação

- **CA1.** As sete propriedades da camada 1 rodam com pelo menos 10.000 casos
  gerados e passam.
- **CA2.** A camada 2 roda em CI em menos de 30 s.
- **CA3.** A camada 3 tem um teste por item listado, e cada um falha se a
  funcionalidade correspondente for removida (verificado por mutação manual em
  pelo menos um caso por item).
- **CA4.** A camada 4 tem um teste por controle C1–C6 da spec 09.
- **CA5.** A camada 5 roda em CI e falha se o hash do `memo` pinado mudar.
- **CA6.** A suíte inteira roda em CI em menos de 5 minutos no caminho rápido, e
  existe um alvo separado para a camada 6 (custo), que não bloqueia PR de rotina.
