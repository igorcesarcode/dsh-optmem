# Documentação — dsh-optmem

Este diretório é a fonte de verdade do projeto. O código é consequência dele.

## Ordem de leitura

1. [`spec/00-overview.md`](spec/00-overview.md) — problema, metas, não-metas, arquitetura e fluxos.
2. [`spec/`](spec/) — uma especificação por área, numeradas na ordem de dependência.
3. [`adr/`](adr/) — decisões de arquitetura e o que foi descartado, com o motivo.
4. [`research/`](research/) — levantamento do harness, feito por leitura do pacote
   publicado do DSH. São **anexos de evidência**: descrevem o harness, não o plugin.
   Quando o harness mudar, é aqui que se confere o que mudou.

## Especificações

| # | Arquivo | Área | Depende de |
|---|---|---|---|
| 00 | [overview](spec/00-overview.md) | visão, metas, fluxos | — |
| 01 | [pacote-e-build](spec/01-pacote-e-build.md) | empacotamento, build, CI | 00 |
| 02 | [store](spec/02-store.md) | log append-only, lock, interop com a CLI `memo` | 01 |
| 03 | [wake-e-cover](spec/03-wake-e-cover.md) | cobertura, orçamento, render do documento | 02 |
| 04 | [injecao](spec/04-injecao.md) | `agent/pre-step`, `agent/session-start`, dedup | 03 |
| 05 | [tools](spec/05-tools.md) | tools nativas de memória | 02, 03 |
| 06 | [compressao](spec/06-compressao.md) | compressão em background via LLM | 02, 03 |
| 07 | [compaction](spec/07-compaction.md) | sobrevivência à compactação | 04, 06 |
| 08 | [escopo](spec/08-escopo-e-subagentes.md) | workspaces, sessões, subagentes | 04 |
| 09 | [seguranca](spec/09-seguranca.md) | threat model, escaping, aprovação | 04, 05 |
| 10 | [privacidade](spec/10-privacidade.md) | retenção, redação, repouso | 09 |
| 11 | [web](spec/11-web.md) | painel e configuração na GUI | 05, 09 |
| 12 | [observabilidade](spec/12-observabilidade.md) | eventos, invariantes, diagnóstico | 02, 06 |
| 13 | [testes](spec/13-testes.md) | testkit, loader-smoke, e2e | 01–12 |
| 14 | [release](spec/14-release.md) | versionamento, publicação, compatibilidade | 13 |

## Decisões

| ADR | Decisão |
|---|---|
| [0001](adr/0001-log-append-only-de-largura-fixa.md) | log append-only de largura fixa, formato compatível com a CLI `memo` |
| [0002](adr/0002-compressao-server-side.md) | compressão server-side em background, não em turno do agente |
| [0003](adr/0003-injecao-programatica.md) | injeção programática em `agent/pre-step`, não por obediência do modelo |
| [0004](adr/0004-proveniencia-obrigatoria.md) | toda memória carrega proveniência obrigatória |
| [0005](adr/0005-plugin-e-o-unico-escritor.md) | o plugin é o único escritor; a CLI opera em somente-leitura |
| [0006](adr/0006-sem-embeddings-no-v1.md) | sem busca vetorial no v1; recall exato + navegação por árvore |
| [0007](adr/0007-superficie-web.md) | superfície web: pacote de duas faces com entrada no slot `conversation.view` |
| [0008](adr/0008-rota-e-erros-da-compressao.md) | a compressão tem rota própria, e o tratamento de erro é nosso |

## Convenções

- Toda afirmação sobre o harness cita caminho verificável sob o pacote publicado.
- Toda especificação termina em **Critérios de aceitação** verificáveis.
- Divergência entre spec e código é bug de um dos dois; registre no ADR
  correspondente em vez de deixar a spec envelhecer em silêncio.
