# dsh-optmem

**Memória permanente para agentes do DeepSeek Harness.** Um plugin nativo — servidor
e Web — que faz o agente lembrar do que aprendeu entre sessões, com custo de
contexto explícito e proveniência obrigatória.

> **Estado: especificação.** Este repositório contém o projeto, as especificações e
> o plano de trabalho. Não há implementação ainda. O que existe aqui é a resposta a
> "o que exatamente vamos construir, e por quê" — com cada afirmação sobre o harness
> citando caminho verificável em [`docs/research/`](docs/research/).

---

## O problema

Um agente esquece tudo ao fim da sessão. O que ele aprendeu sobre o projeto, sobre
o usuário e sobre tentativas que falharam vive apenas naquele histórico e morre na
compactação ou no fechamento.

Escrever tudo em `AGENTS.md` cresce sem limite e é relido inteiro a cada
requisição. Confiar no histórico de sessões dá busca, não memória: o agente não
*sabe* nada no início. Bancos de memória com pipeline de LLM resolvem a recuperação
semântica, mas trazem servidor, índice que diverge e um custo por escrita que o
usuário não vê.

O [OptMem](https://github.com/VictorTaelin/OptMem) mostrou uma quarta via,
minimalista: **log append-only + árvore de resumos + orçamento de leitura que decai
com a idade**. Armazenamento ilimitado, leitura limitada e barata, a inteligência é
do agente e a ferramenta é burra e auditável.

Este projeto parte dessa ideia e ataca os quatro pontos que ela deixou em aberto.

## O que muda em relação ao OptMem

| Problema no OptMem | Como este projeto resolve |
|---|---|
| A memória só existe se o modelo obedecer ("rode `memo wake` como primeira tool call"), e falha em silêncio | injeção programática em `agent/pre-step`: o modelo não pode esquecer de acordar |
| A compressão custa **~1 turno do agente por memória** | compressão própria, chamando o modelo direto e rodando fora do turno — o custo sai de turnos e vira tokens, medidos |
| Texto livre entra em todo contexto futuro, para sempre: injeção de prompt vira **permanente** | proveniência obrigatória por memória, autoridade por origem, escape de frame e aprovação para origem não confiável |
| Paginação e orçamento eram adivinhações sobre limites de harness | orçamento explícito em tokens, com a estimativa e a medição real reportadas |
| A memória some quando a conversa é compactada | re-injeção verificada a cada passo — cobre compactação automática, `/compact` e poda |

## A aba OptMem

A GUI Web tem hoje duas abas: **Chat** e **Trajectory**. Este plugin acrescenta uma
terceira, nativa:

```
┌ Chat ─┬─ Trajectory ─┬─ OptMem ─────────────────────────────┐
│                                                             │
│   [ Ao vivo ]   [ Memórias ]   [ Custos ]                   │
│                                                             │
│   ● memória #1284 gravada        (user, agent-inference)    │
│   ● #0-15 comprimido             1.4k → 96 tokens, 820 ms   │
│   ● memória injetada             61 linhas, 7.842 tokens    │
│   ● compactação                  faixa 0-412, 38k liberados │
│   ● memória re-injetada após compactação                    │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

- **Ao vivo** — o ledger de memórias **e compactações** em tempo real, sem polling.
  Não é transporte novo: os eventos de memória já são eventos de sessão, e
  `compaction/*` já é evento de sessão do harness. É o mesmo canal que o Trajectory
  consome.
- **Memórias** — lista, busca, `zoom` na árvore, marcar como privada, descartar
  resumo, apagar de verdade.
- **Custos** — orçamento, tokens da última injeção, chamadas e tokens de
  compressão, pendentes, degradados, saúde do store.

Verificado viável sem fork do harness: a descoberta de plugins de cliente é
Loader-driven e relativa ao pacote, e as abas são entradas no slot
`conversation.view` — "Chat" é apenas a entrada padrão
([evidência](docs/research/04-superficie-cliente-e-aba.md)).

### Instalado não é o mesmo que ativo

Manter a memória no disco e não querer que o agente a receba agora são coisas
diferentes — durante um trabalho sob confidencialidade diferente, um debug, ou um
ajuste de configuração. O plugin tem uma **chave de ativação** na GUI, separada da
instalação:

- **inativo** = sem injeção, sem compressão, sem chamada de modelo, tools avisando
  como ativar — e **o store intocado**, nada apagado nem recomputado;
- a aba continua acessível e diz "inativo", em vez de parecer vazia.

A chave é configuração do plugin, não mutação do Loader: a projeção de inventário do
harness é explicitamente somente-leitura.

### Qual modelo comprime a memória

A compressão tem **rota própria**, independente da conversa, porque é o único lugar
do sistema que gasta dinheiro em escala e o que menos exige do modelo. O padrão é
**herdar a rota da sessão**; a configuração permite escolher outro provedor, modelo e
nível de raciocínio.

A UI é a mesma do subagente: lista agrupada por provedor, descrições vindas do
catálogo vivo, e **effort derivado do modelo** — sem entrada de texto livre, porque o
harness rejeita effort não suportado sem clamp nem alias. Rotas salvas que sumiram do
catálogo aparecem no fim e continuam removíveis.

E o tratamento de erro das APIs é **nosso**: o harness não retenta chamadas diretas a
`ctx.llm.stream()`, e declara isso. Então a compressão classifica o erro em
transitório (retenta com backoff e jitter) e permanente (não retenta), trata contexto
estourado dividindo o bloco em vez de repetir o pedido, e tem disjuntor — porque
retentar uma credencial errada é queimar dinheiro sozinho
([ADR-0008](docs/adr/0008-rota-e-erros-da-compressao.md)).

## Como funciona

```
primeiro passo da sessão
        │
        ├─ é subagente?           → não injeta (garantido em código)
        ├─ já injetei e ainda vejo? → não repete
        └─ senão                  → injeta o documento de memória
                                     (orçado, emoldurado, escapado)
        │
   agente trabalha ──► memory_note ──► log append-only
        │                                   │
        │                              job de compressão
        │                                   │
        └─ memory_recall / memory_zoom ◄── árvore de resumos
```

A memória é entregue como **mensagem durável** com fonte do plugin — não como
resultado de tool que o modelo precisa pedir. O documento apresenta as memórias
recentes cruas e as antigas como resumos, com o detalhe decaindo com a idade, e
cabe em um orçamento que o usuário escolhe.

## Custo

O custo é a decisão de projeto mais consequente, então ele é declarado em números.

| Item | Ordem de grandeza | Observação |
|---|---|---|
| Injeção | ~8k tokens por sessão (orçamento padrão) | durável até a próxima compactação; **escolhido**, não acidental |
| Compressão | ~1,5k tokens de entrada por bloco | **linear** no número de memórias; mitigado por compressão preguiçosa |
| Armazenamento | ~600 bytes por memória | irrelevante em dinheiro |
| Latência | leitura em processo | sem subprocesso, no caminho do primeiro passo |
| Efeito colateral | a janela ocupada antecipa a compactação | e compactação é uma chamada cara |

Dez mil memórias custam da ordem de 15M tokens de entrada em compressão; um milhão,
1,5B. É o único componente que cresce de forma relevante — e é por isso que a
compressão preguiçosa é requisito, não otimização.

O rodapé do documento injetado mostra o custo real, e a aba **Custos** mostra o
acumulado. Um plugin de memória que esconde o custo em tokens não é honesto.

## Segurança e privacidade

Memória de longa duração é um alvo diferente do habitual: uma injeção de prompt que
persiste entre sessões, compactações e modelos.

- **Proveniência obrigatória.** Toda memória registra sessão, turno, profundidade,
  origem, workspace e modelo. `tool-output` nunca é apresentado como fato neutro.
- **Escape de frame.** `</system-reminder>` literal em uma memória não fecha o
  enquadramento.
- **Aprovação** antes de gravar memória de origem não confiável — o alvo do atacante
  passa a ser convencer o usuário, não o modelo.
- **Subagentes não escrevem nem recebem memória**, garantido por profundidade de
  delegação, não por convenção de prompt.
- **Nada é apagado automaticamente, nunca.** Retenção esconde do documento; apagar
  de verdade é um ato explícito e confirmado.
- A memória vai para o provedor do modelo em toda requisição — não há como ter
  memória sem isso. O que existe é controle: padrões de negação, redação na
  injeção, memória privada que só aparece em busca deliberada.

Modelo de ameaça completo em [`docs/spec/09-seguranca.md`](docs/spec/09-seguranca.md).
Política de reporte em [`SECURITY.md`](SECURITY.md).

## O que este projeto não é

- **Não** substitui o histórico de sessão do harness. Ele acrescenta memória; não
  poda, não resume e não gerencia a conversa.
- **Não** faz busca semântica no v1: `recall` é exato e a aproximação vem de
  navegar pela árvore de resumos ([ADR-0006](docs/adr/0006-sem-embeddings-no-v1.md)).
- **Não** sincroniza entre máquinas nem compartilha memória entre usuários.
- **Não** promete que dados sensíveis não cheguem ao provedor se forem registrados
  como memória comum. Promete que não vão por acidente, e dá o instrumento.

## Limites declarados

Limites que **não** têm solução no desenho atual, e que estão aqui para não serem
descobertos depois:

- **Resumo não é determinístico.** A árvore é reconstruível, mas reconstruí-la
  produz outro texto — quem resume é um modelo. O log é a verdade; a árvore é cache.
- **Sem busca semântica.** Encontrar "aquela conversa sobre performance" depende de
  a palavra estar na memória ou no resumo.
- **Sem detecção de adulteração.** Quem tem escrita no sistema de arquivos controla
  a memória. O desenho de uma cadeia de hash está registrado como trabalho futuro.

## Instalação (planejada)

```sh
dsh plugin --profile web add dsh-optmem
```

E a linha de configuração no patch do perfil. O pacote declara `dsh.bundle.patch`,
sem o qual a instalação seria silenciosamente inerte.

## Estrutura do repositório

```
docs/
  index.md                 mapa da documentação
  spec/                    uma especificação por área (00–14)
  adr/                     decisões de arquitetura e o que foi descartado
  research/                levantamento do harness, com citação de caminho e linha
.github/issues/            fonte de verdade das issues do repositório
scripts/create-issues.sh   cria labels, milestones e issues a partir dos arquivos
```

O código **não** existe ainda. Quando existir, ele segue as specs — e uma mudança de
comportamento começa em `docs/`, não em `src/`
([CONTRIBUTING.md](CONTRIBUTING.md)).

## Roadmap

| Fase | Entrega | Valor |
|---|---|---|
| **M1 Fundação** | pacote, build, store, cobertura, render | memória legível e testável, ainda sem harness |
| **M2 Contexto** | injeção, escopo, tools | **o sistema funciona**: o agente lembra |
| **M3 Inteligência** | compressão em background, compactação | escala e sobrevive à compactação |
| **M4 Superfície** | a aba OptMem, ledger ao vivo, configuração na GUI | o usuário vê e controla |
| **M5 Endurecimento** | proveniência, aprovação, privacidade | seguro para uso continuado |
| **M6 Release** | matriz de compatibilidade, documentação, npm | instalável por terceiros |

O plano detalhado, com critérios de aceitação por item, está nas
[issues](../../issues). O épico é a
[#1](../../issues/1).

## Compatibilidade

O harness está em `0.1.5-rc.*`, e os próprios pacotes dele aparecem em versões
diferentes na mesma instalação. O plugin isola toda a superfície de acoplamento em
um módulo (`src/harness/`) e degrada bem: uma mudança de seam quebra um módulo, não
o sistema, e a sessão nunca é derrubada por falha de memória. A matriz de
compatibilidade verificada em CI é publicada na release
([spec 14](docs/spec/14-release.md)).

## Licença

[MIT](LICENSE).
