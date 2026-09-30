# 08 — Escopo: usuário, workspace, sessão e subagentes

## Objetivo

Definir **de quem** é cada memória e **quem** pode lê-la ou escrevê-la. Sem isso,
memória de um projeto vaza para outro, e um subagente escreve lixo que ninguém
sabe de onde veio.

## Dimensões

| Dimensão | Valores | Efeito |
|---|---|---|
| Namespace | `user` \| `workspace` | onde a memória vive; decide qual store a contém |
| Sessão | id da sessão | proveniência apenas; memória não é escopada por sessão |
| Profundidade | `0` (principal) \| `>0` (subagente) | decide se injeta e se escreve |
| Workspace | caminho canônico | qual store de workspace |

## Namespaces: dois stores, não um filtro

A memória tem duas naturezas distintas:

- **Sobre o usuário** — preferências, jeito de trabalhar, fatos pessoais. Vale em
  todo projeto.
- **Sobre o projeto** — decisões, restrições, o que foi tentado. Vale naquele
  workspace.

A tentação é ter um log único e filtrar por tag na leitura. **Isso está
descartado**, porque a cobertura (spec 03) opera sobre faixas contíguas
`[0, T)` e uma tag de workspace quebraria o alinhamento em potências de dois —
isto é, destruiria a árvore, que é o mecanismo inteiro.

Decisão: **um store por namespace**.

```
$DSH_HOME/storages/optmem/
  user/                 LOG.txt  PROV.txt  TREE/  OWNER
  ws/<hash-do-path>/    LOG.txt  PROV.txt  TREE/  OWNER
```

- `wake` renderiza **dois documentos**, cada um com seu próprio orçamento:
  `user` primeiro (fatos duráveis sobre a pessoa), depois `workspace`.
- O orçamento total `wake.budgetTokens` é dividido por `wake.userShare`
  (padrão `0.25`). Se um namespace não tem memórias, o outro herda o orçamento
  inteiro — não se desperdiça orçamento com um store vazio.
- Cada store tem sua própria árvore, seu próprio lock e sua própria numeração de
  ids. Ids não são globalmente únicos; são qualificados pelo namespace.

| Config | Padrão | Significado |
|---|---|---|
| `scope.mode` | `'both'` | `both` \| `user` \| `workspace` |
| `scope.workspaceHash` | `sha256(caminho)`[:16] | diretório do store de workspace |
| `wake.userShare` | `0.25` | fração do orçamento para o namespace `user` |

## Sessão

Memória **não** é escopada por sessão. A sessão aparece apenas na proveniência
(ADR-0004), o que permite responder "de onde veio isso" sem fragmentar a memória
em pedaços que nunca se acumulam.

Consequência: uma sessão nova já nasce com todo o passado. É o ponto do sistema.

## Subagentes

**Regra dura: profundidade > 0 não injeta e não escreve.**

- Sem injeção: um subagente recebe o contexto que o pai decidiu passar, e nada
  mais. Injetar memória em um subagente gasta orçamento de um contexto que já é
  apertado, e o subagente não tem como julgar relevância para a tarefa delegada.
- Sem escrita: o subagente não sabe o que já é conhecido, então suas notas chegam
  duplicadas e mal classificadas — exatamente o modo de falha que o OptMem
  original tentou evitar por convenção de prompt.
- As tools de memória, quando chamadas em profundidade > 0, respondem com um erro
  explícito e ensinam a alternativa: *"subagentes não gravam memória; devolva este
  fato ao agente principal para que ele registre"*.
- A detecção é por `delegationDepthOf(agent)`, não por heurística de prompt.

O que **é** permitido a um subagente: nada de memória. O que o pai deve fazer:
incluir no prompt de delegação os fatos que importam, extraídos da própria
memória do pai — que ele tem.

## Critérios de aceitação

- **CA1.** Um subagente (profundidade ≥ 1) iniciado por `subagent` ou
  `subagent_fork` não recebe nenhuma mensagem do plugin no seu histórico.
- **CA2.** `memory_note` chamada em profundidade ≥ 1 falha com mensagem explícita
  e **não** escreve nada em disco (verificar por hash do store).
- **CA3.** Duas sessões em workspaces diferentes não veem memória de projeto uma
  da outra, e ambas veem as memórias do namespace `user`.
- **CA4.** Um store de workspace vazio faz o namespace `user` receber os
  `wake.budgetTokens` completos.
- **CA5.** Renomear o diretório do workspace cria um namespace novo (hash
  diferente) e a memória antiga continua acessível pelo caminho antigo — o plugin
  avisa quando detecta memória órfã de um workspace que não existe mais.
- **CA6.** A árvore de cada namespace é construída apenas sobre as memórias
  daquele namespace: nenhum bloco mistura ids de stores diferentes.
