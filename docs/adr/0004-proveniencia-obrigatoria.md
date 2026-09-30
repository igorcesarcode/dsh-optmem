# ADR-0004 — Toda memória carrega proveniência obrigatória

- **Status:** aceito
- **Data:** 2026-09-30
- **Contexto da decisão:** especificações 09 (segurança) e 12 (observabilidade)

## Contexto

Memória é dado de longa duração que volta ao contexto em toda sessão futura.
Uma memória envenenada — texto que instrui o agente a fazer algo, escrito por
conteúdo não confiável que o agente leu — sobrevive à sessão, à compactação e à
troca de modelo. É a diferença entre uma injeção de prompt efêmera e uma
injeção de prompt **persistente e auto-replicante**.

O OptMem não tem defesa estrutural contra isso: `memo note "<texto>"` grava texto
livre sem autor, sem origem e sem distinção entre "o usuário me disse" e "eu li
num README de repositório clonado".

## Decisão

Nenhuma memória existe sem proveniência. O plugin grava, junto de cada memória, um
registro de origem com:

| Campo | Obrigatório | Por quê |
|---|---|---|
| `sessionId` | sim | qual sessão gravou |
| `turn` / `step` | sim | onde no turno |
| `agentDepth` | sim | 0 = principal; >0 nunca grava (spec 08) |
| `origin` | sim | `user` \| `agent-inference` \| `tool-output` \| `import` |
| `workspace` | sim | a que projeto a memória pertence |
| `sourceRefs` | não | ids de tool calls / mensagens que a originaram |
| `model` | não | modelo que redigiu, quando aplicável |
| `revisedBy` | não | id de compressão posterior, quando for resumo |

Regras derivadas:

1. **`origin` decide a autoridade.** Conteúdo classificado como `tool-output`
   **nunca** entra no contexto com autoridade de instrução; ele é citado como
   dado e permanece emoldurado.
2. **Gravação com origem não confiável exige aprovação.** Uma memória cuja origem
   é saída de ferramenta sobre conteúdo externo passa pelo ponto de decisão
   `ask` antes de persistir. O agente pode propor; o usuário confirma.
3. **Gravação é auditável.** Cada nota produz um evento de sessão log-only, com
   payload tipado, e um companion de invariantes valida a forma do que foi
   gravado. Nada entra no store sem deixar rastro verificável.
4. **Resumos herdam o conjunto de origens** dos filhos que comprimem, para que
   `origin: tool-output` não se dilua em resumo aparentemente inócuo.
5. **Proveniência é barata em bytes e cara de falsificar** — o vetor de ataque
   passa a ser "convencer o agente a classificar como `user`", o que é um alvo
   muito menor do que "escrever texto livre".

## Consequências

- O store deixa de ser um arquivo de texto puro: cada memória tem um sidecar de
  proveniência. O log continua legível e continua sendo a verdade do conteúdo;
  a proveniência é um segundo arquivo append-only, alinhado por id.
- O formato continua compatível com a CLI `memo` para **leitura**: a CLI ignora a
  proveniência e vê o texto. Escrever pelo plugin e ler pela CLI funciona;
  escrever pela CLI e ler pelo plugin produz memórias com origem `import`
  (desconhecida), o que é a classificação correta.
- Requer uma decisão de UX: quanta fricção a aprovação introduz. O padrão deve ser
  aprovar **apenas** o que vem de `tool-output`; notas do próprio usuário não
  pedem confirmação.
- Custo de armazenamento cresce, mas continua irrelevante frente ao custo em
  tokens.

## Alternativas descartadas

- **Sem proveniência (como o OptMem).** Mais simples e mais rápido de usar; deixa
  o vetor de injeção persistente completamente aberto. Inaceitável para memória
  de longa duração.
- **Confiar em heurística de classificação pelo modelo.** O modelo é justamente a
  parte que pode ser enganada. A classificação é do plugin, a partir do caminho
  pelo qual o texto chegou, não do conteúdo.
- **Guardar a memória dentro dos eventos de sessão do DSH.** Daria proveniência
  de graça, mas amarra o ativo de longo prazo ao formato do harness. Descartado
  por isso, não por incapacidade técnica.

## Evidência

- Eventos de sessão log-only com declaração mesclada e companion de invariantes:
  `@deepseek-ai/dsh-compaction/README.md` (eventos `compaction/*`) e
  `@deepseek-ai/dsh-hook-protocol/README.md` (eventos `hook/*`).
- Ponto de decisão `ask` antes de uma tool rodar:
  `@deepseek-ai/dsh-tools/lib/types/index.d.ts` (`tools/pre-execute`).
- Escape de frame e fronteira de confiança em conteúdo de repositório:
  `@deepseek-ai/dsh-agent-instructions/README.md`.
