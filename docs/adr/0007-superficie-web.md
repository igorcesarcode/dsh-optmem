# ADR-0007 — Superfície Web: pacote de duas metades com uma aba nativa

- **Status:** aceito
- **Data:** 2026-09-30
- **Contexto da decisão:** especificação 11 (web)

## Contexto

O requisito é uma **aba nativa** na GUI Web, ao lado de "Chat" e "Trajectory", onde
memórias e compactações aparecem em tempo real.

O harness oferece três caminhos para pôr UI no browser, e a escolha entre eles não
é de gosto — cada um tem um custo e um limite diferentes:

1. **Pacote de duas metades estático** (`dsh.client` + `platform: 'web'` + export
   `./client`). É o que todos os `dsh-client-ui-*` publicados fazem.
2. **Pacote dinâmico** (`cordis_run`), avaliado como closure no browser após
   aprovação humana.
3. **Painel global** no slot `main` de escopo raiz, selecionável por
   `ctx.layout.selectPanel(id)`.

A pergunta de viabilidade — "dá para fazer isso fora do monorepo?" — foi respondida
por leitura do pacote publicado: **sim**, a descoberta é Loader-driven e relativa ao
pacote, sem lista de permissão nem caminho que assuma o layout do monorepo
([research/02](../research/02-client-web-kit.md) §6, [research/04](../research/04-superficie-cliente-e-aba.md)).

## Decisão

**Pacote de duas metades, registrando uma entrada no slot `conversation.view`.**

| Caminho | Veredito | Motivo |
|---|---|---|
| Duas metades estático | **escolhido** | é o mecanismo do próprio Trajectory; a aba é irmã de Chat/Trajectory por construção |
| Pacote dinâmico | descartado | exige aprovação humana por carga e **nada é restaurado após um refresh**: uma aba de memória que some quando a página recarrega é inútil |
| Painel global | descartado | obrigaria o usuário a escolher *entre* a conversa e a memória, em vez de alternar entre elas |

Regras derivadas:

- **R1.** A aba é uma entrada de slot com `id` estável, `order` configurável e
  `label` vindo do serviço de locale. O registro usa o wrapper de efeito do serviço
  de slots, para que o unload do plugin remova a aba.
- **R2.** O plugin é distribuído como **um pacote que declara as duas faces**
  (`dsh.bundle.patch` para ser montado como camada de perfil, e `dsh.client` para
  ter a metade browser). A convenção do harness é **dois** pacotes separados — o
  `dsh-tool-todo` e o `dsh-client-ui-tool` não têm aresta de dependência entre si e
  se encontram só por string e por evento de sessão —, mas isso existe para
  permitir que a UI de uma tool seja trocada sem trocar a tool. Aqui as duas metades
  são a mesma funcionalidade e não faz sentido versioná-las em separado.
  
  A descoberta de cliente é por `package.json`, então as duas faces no mesmo pacote
  são legítimas em princípio; **o protótipo (issue 19) decide**, porque não existe
  exemplo publicado de pacote com as duas. Se falhar, cai para o padrão de dois
  pacotes sem mudar mais nada do desenho.
- **R3.** A metade browser não contém lógica de memória. Ela projeta eventos e
  chama a metade host. Duas implementações da mesma regra divergem.
- **R4.** O bundle de cliente é **construído e commitado como artefato de build**
  (não versionado em fonte) e o host nunca o constrói. Bundle ausente é falha dura
  de ativação, então isso entra na verificação de release.
- **R5.** O formato do bundle é provado por **protótipo antes** de o painel virar
  compromisso: o preset de build que o harness usa não é publicado, e não existe
  exemplo conhecido de bundle construído fora do repositório.

## Consequências

- A aba herda o comportamento de sessão da conversa: ela é por sessão, e uma sessão
  retomada reconstrói o ledger do log de sessão em vez de abrir vazio.
- O tempo real sai de graça para **esta sessão**: os eventos `optmem/*` e
  `compaction/*` já são eventos de sessão, e o Trajectory já consome esse canal. Não
  inventamos transporte.
- Atividade de **outra** sessão paralela no mesmo store não aparece ao vivo no v1 —
  exigiria um canal de push da metade host. É limite declarado, não bug.
- Passamos a ter uma superfície de build que não existe em nenhum outro lugar do
  projeto: o front-end. Isso traz dependência de ferramenta de bundle, um artefato
  gerado e um shim de tipos escrito à mão, porque os pacotes de tipo de slot não são
  publicados.
- O plugin deixa de ser puramente servidor. Um bug na metade browser pode quebrar a
  GUI, então o contrato inclui "não quebrar a GUI quando o store falha".

## Alternativas descartadas

- **Só host, sem superfície.** O usuário continua podendo inspecionar via
  `memory_recall` e o `LOG.txt`. Insuficiente: a spec 10 (P6) exige que o usuário
  consiga ver o que o agente sabe sem ler um log, e a aba é o instrumento.
- **CLI separada de inspeção.** Reintroduziria uma segunda ferramenta para o mesmo
  store e não resolve "em tempo real".
- **Aba dentro do Trajectory** (como uma definição de evento, no padrão
  `registerTrajectoryCompactionDefinitions`). Seria menos trabalho, mas enterra a
  memória dentro de outra ferramenta e não dá espaço para busca e correção. O
  Trajectory é um ledger de execução; memória é um ativo, e misturar os dois
  confunde os dois.
- **Exportar o store como arquivos para o painel de arquivos.** Transformaria
  memória em navegação de arquivos e perderia busca, marcações e custo.

## Evidência

- Aba como entrada de slot e projeção em `ViewTab`:
  `dsh-client-ui-conversation/lib/types/client/contract/views.d.ts` e
  `view-selection.d.ts`; registro real em
  `dsh-client-ui-trajectory/lib/client.js`.
- Pacotes de duas metades, descoberta e serviço em `/plugins`:
  `dsh-client-modules/README.md`.
- Pacote dinâmico: aprovação por carga e **nada restaurado após refresh**:
  `dsh-cordis-client-runner/README.md`.
- Painel global e `ctx.layout.selectPanel`: `dsh-client-ui-layout/README.md`.
- Configuração de terceiro na GUI por namespace: `dsh-client-ui-settings-plugins/lib/types/client/slot-contract.d.ts`.
