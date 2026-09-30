# 09 — Segurança: modelo de ameaça e controles

## Objetivo

Impedir que a memória se torne um vetor de ataque **persistente**. Uma injeção de
prompt comum morre com a sessão; uma memória envenenada sobrevive à sessão, à
compactação e à troca de modelo. É uma diferença de categoria, não de grau.

## Ativos

| Ativo | Por que importa |
|---|---|
| O conteúdo do log | volta ao contexto em toda sessão futura; envenená-lo é persistente |
| O diretório do store | fora do workspace; escrever nele é escrever no futuro do agente |
| O documento de wake | é o canal de entrega; é onde o escape acontece |
| O espaço de contexto | enchê-lo é negar serviço ao agente |
| Dados pessoais do usuário | o prompt original do OptMem manda registrar a vida do usuário |

## Modelo de ameaça

| # | Ameaça | Vetor | Severidade |
|---|---|---|---|
| T1 | **Envenenamento persistente** | agente lê conteúdo hostil (README de repo clonado, saída de ferramenta, página web) e grava como memória | alta |
| T2 | **Escape de frame** | memória contém `</system-reminder>` e escreve fora do frame, com autoridade que não tem | alta |
| T3 | **Exfiltração** | memória instrui o agente a revelar segredos ou a gravá-los, que então vão a todo provedor futuro | alta |
| T4 | **Negação de serviço por contexto** | memória gigante ou muitas memórias consomem o orçamento e deslocam o trabalho real | média |
| T5 | **Escrita por terceiro** | outro processo (ou a CLI `memo`) escreve no diretório do plugin | média |
| T6 | **Path traversal na configuração** | `store.dir` apontando para um alvo sensível, ou symlink no diretório | média |
| T7 | **Adulteração do log** | edição manual para plantar ou apagar memória | baixa (local, exige acesso ao FS) |

## Controles

### C1 — Autoridade por origem (T1, T3)

Toda memória carrega `origin` (ADR-0004). O documento de wake declara, no
cabeçalho, que o conteúdo é **dado, não instrução**, e não sobrepõe instruções de
sistema, de desenvolvedor ou do usuário.

Memória com `origin = tool-output` nunca é apresentada como fato neutro: o render
a prefixa com uma marca de origem para que o modelo — e o humano que lê o
histórico — vejam que aquilo veio de conteúdo externo.

### C2 — Escape de frame (T2)

Antes de entrar no frame, **todo** conteúdo de memória passa por escape:

- `</system-reminder>` literal → escapado.
- O mesmo para qualquer fechamento de tag que o plugin use no frame.

Isto é invariante de render, verificado por teste dedicado (spec 03 CA4 e spec 13).
É o controle mais barato e o de maior impacto.

### C3 — Aprovação na escrita de origem não confiável (T1)

Gravar com `origin = tool-output` passa pelo ponto de decisão `ask` antes de
persistir. O agente pode propor a memória; o usuário confirma. Notas de
`origin = user` e `agent-inference` não pedem confirmação.

Isso move o alvo do atacante de "escrever texto livre" para "convencer o usuário a
aprovar", que é uma barreira humana em vez de uma barreira de modelo.

### C4 — Limites duros (T4)

- `entryChars` (280 bytes) por memória — teto do formato.
- `wake.budgetTokens` — teto do documento injetado.
- `wake.maxLines` — teto independente de tokens.
- `note.maxPerTurn` (padrão 20) — teto de notas por turno, para impedir que um
  loop do agente encha o log.
- `note.maxPerDay` (padrão 2000) — teto diário, com aviso ao atingir.

### C5 — Posse e modo leitor (T5)

O diretório carrega um arquivo `OWNER` (ADR-0005). Um store sem `OWNER` que já
tenha árvore construída é tratado como vindo da CLI e o plugin entra em
`role = 'reader'`: não escreve, não comprime, e diz por quê. O plugin é
**fail-closed na escrita** e **fail-open na leitura**.

### C6 — Validação do diretório (T6)

- `store.dir` é resolvido com `realpath` antes do uso.
- O caminho resolvido precisa estar sob um diretório permitido
  (`$DSH_HOME/storages/` por padrão, ou uma allowlist explícita em configuração).
- Componentes de caminho com symlink são rejeitados, não seguidos.
- O arquivo `.lock`, `LOG.txt` e `PROV.txt` são abertos com `O_NOFOLLOW` quando a
  plataforma suporta.

### C7 — Integridade (T7) — fora do escopo do v1

Adulteração local do log **não** é detectada no v1. O desenho proposto, para uma
fase posterior, é uma cadeia de hash em `PROV.txt` (cada registro contém o hash
do anterior), o que dá evidência de adulteração sem tocar em `LOG.txt` e sem
quebrar a compatibilidade com a CLI. Enquanto isso não existe, o risco residual
está documentado na README e o plugin não afirma integridade que não tem.

## O que este modelo não promete

- **Não impede** que o modelo seja convencido por uma memória legítima. Memória é
  conteúdo, e conteúdo influencia o modelo. O que se impede é a memória entrar
  com autoridade de instrução e a passagem por canais não monitorados.
- **Não impede** o usuário de aprovar algo ruim. A aprovação é uma barreira, não
  uma prova.
- **Não protege** contra um adversário com acesso de escrita ao sistema de
  arquivos do usuário (C7).

## Critérios de aceitação

- **CA1.** Uma memória contendo `</system-reminder>` e texto de instrução não
  altera a autoridade do frame: teste de render verifica que o frame tem exatamente
  um fechamento, no fim, e que o conteúdo aparece escapado.
- **CA2.** `memory_note` com `origin = tool-output` não grava sem aprovação; com
  aprovação negada, o store fica byte-idêntico.
- **CA3.** 21 chamadas de `memory_note` em um turno: as 20 primeiras gravam, a 21ª
  falha com mensagem explícita, e nenhum registro extra é escrito.
- **CA4.** `store.dir = /etc` é rejeitado na configuração, com mensagem que diz
  qual é o diretório permitido.
- **CA5.** Um store sem `OWNER` mas com `TREE/` populado entra em `reader`; uma
  tentativa de `memory_note` falha e o store não muda.
- **CA6.** Com o store apontando para um symlink, o plugin recusa e não segue.
- **CA7.** O documento de wake de um store com memórias `tool-output` contém a
  marca de origem correspondente em cada uma.
