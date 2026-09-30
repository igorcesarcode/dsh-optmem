# Issues — fonte de verdade

Os arquivos deste diretório são a **fonte de verdade** das issues do repositório.
Cada um é criado no GitHub por [`scripts/create-issues.sh`](../../scripts/create-issues.sh),
que lê o cabeçalho de cada arquivo e é idempotente (não duplica issue existente
pelo título).

Editar a issue no GitHub sem refletir aqui faz os dois divergirem. A regra é:
**edite o arquivo, rode o script** — ou aceite que o arquivo é o histórico e o
GitHub é o estado vivo.

## Cabeçalho

```markdown
---
title: "store: log append-only de largura fixa"
labels: [area:store, type:feature]
milestone: "M1 — Fundação"
---
```

- `title` — obrigatório, único, com prefixo de área.
- `labels` — lista; precisam existir (o script as cria).
- `milestone` — opcional; precisa existir (o script o cria).

## Índice

| # | Arquivo | Fase |
|---|---|---|
| 00 | [epic](00-epic.md) | — |
| 01 | [scaffold-do-pacote](01-scaffold-do-pacote.md) | M1 |
| 02 | [store-append-only](02-store-append-only.md) | M1 |
| 03 | [cobertura-orcada-em-tokens](03-cobertura-orcada-em-tokens.md) | M1 |
| 04 | [render-do-wake](04-render-do-wake.md) | M1 |
| 05 | [propriedades-da-cobertura](05-propriedades-da-cobertura.md) | M1 |
| 06 | [interop-cli-memo](06-interop-cli-memo.md) | M1 |
| 07 | [injecao-pre-step](07-injecao-pre-step.md) | M2 |
| 08 | [escopo-namespaces](08-escopo-namespaces.md) | M2 |
| 09 | [exclusao-de-subagentes](09-exclusao-de-subagentes.md) | M2 |
| 10 | [tools-nucleo](10-tools-nucleo.md) | M2 |
| 11 | [tools-descarte-e-config](11-tools-descarte-e-config.md) | M2 |
| 12 | [testes-de-integracao](12-testes-de-integracao.md) | M2 |
| 13 | [compressao-em-background](13-compressao-em-background.md) | M3 |
| 14 | [sobrevivencia-a-compactacao](14-sobrevivencia-a-compactacao.md) | M3 |
| 15 | [orcamento-com-token-meter](15-orcamento-com-token-meter.md) | M3 |
| 16 | [colheita-na-compactacao](16-colheita-na-compactacao.md) | M3 |
| 17 | [aba-nativa](17-painel-web.md) | M4 |
| 18 | [config-e-i18n-na-gui](18-config-e-i18n-na-gui.md) | M4 |
| 19 | [prototipo-do-bundle-de-cliente](19-spike-client-plugin.md) | M4 |
| 20 | [proveniencia-e-invariantes](20-proveniencia-e-invariantes.md) | M5 |
| 21 | [aprovacao-na-escrita](21-aprovacao-na-escrita.md) | M5 |
| 22 | [privacidade-e-redacao](22-privacidade-e-redacao.md) | M5 |
| 23 | [endurecimento-do-diretorio](23-endurecimento-do-diretorio.md) | M5 |
| 24 | [matriz-e-camada-de-adaptacao](24-matriz-e-camada-de-adaptacao.md) | M6 |
| 25 | [documentacao-de-release](25-documentacao-de-release.md) | M6 |
| 26 | [publicacao-no-npm](26-publicacao-no-npm.md) | M6 |
| 27 | [ledger-ao-vivo](27-ledger-ao-vivo.md) | M4 |

## Milestones

| Milestone | Entrega |
|---|---|
| M1 — Fundação | pacote, store e cobertura: memória legível e testável, ainda sem harness |
| M2 — Contexto | **o sistema funciona**: o agente lembra |
| M3 — Inteligência | escala e sobrevive à compactação |
| M4 — Superfície | o usuário vê e controla |
| M5 — Endurecimento | seguro para uso continuado |
| M6 — Release | instalável por terceiros |

## Labels

`area:store` `area:cover` `area:injection` `area:tools` `area:compression`
`area:compaction` `area:scope` `area:security` `area:privacy` `area:web`
`area:audit` `area:tests` `area:release` `area:docs`
`type:feature` `type:test` `type:infra` `type:docs` `type:spike`
`spec` `blocked` `good-first-issue`
