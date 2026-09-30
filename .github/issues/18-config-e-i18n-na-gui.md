---
title: "web: cartão de configuração — ativação, rota da compressão e i18n"
labels: [area:web, type:feature]
milestone: "M4 — Superfície"
---

## Contexto

Três necessidades no mesmo cartão: o usuário precisa poder **desligar** o plugin sem
desinstalá-lo, escolher **qual modelo comprime a memória**, e ler tudo isso na sua
língua.

**Correção vinda do levantamento:** a configuração **não** é renderizada
automaticamente do schema. A aba de plugins despacha um slot por namespace, e um
namespace que nenhum cartão reivindica **não renderiza nada** — os controles dos
pacotes publicados são escritos à mão. O plugin precisa entregar o próprio cartão. O
que existe a favor é que o `SettingsDescriptor.schema` está no fio e há API de
schema, então um formulário **dirigido pelo schema** é possível — só não é gratuito.

**Referência de UI:** o cartão `subagent-model-selection`. Adotamos os
comportamentos dele porque cada um resolve um problema real: chave e modelos
**estagiados juntos**; salvar em **uma** mutação cercada pela revisão do rascunho;
**desativar preserva** as rotas; modelos **agrupados por provedor**; rotas salvas
ausentes do catálogo vão para o fim e continuam removíveis; descrições são
**metadado vivo**, não armazenado; effort **derivado do modelo**, sem entrada livre.

## Escopo

### 1. Instalado ≠ ativo

- Chave de ativação, **configuração do plugin** e não mutação do Loader (a projeção
  do inventário de plugins do harness é somente-leitura e não habilita nada).
- Inativo significa: sem injeção (`optmem/skip` com `reason = 'disabled'`), sem
  compressão, sem chamada de LLM, tools respondendo com instrução de como ativar, e
  **store intocado**.
- A aba continua acessível e mostra "inativo", em vez de parecer vazia.

### 2. Rota da compressão

- Lista de modelos **agrupada por provedor**, com **"herdar da sessão"** como
  primeiro item e padrão.
- Effort derivado do modelo escolhido; modelo sem metadado de raciocínio não mostra
  a linha e não aceita texto livre.
- Provider e model andam juntos; trocar a rota sem effort limpa o effort anterior.
- Rotas salvas ausentes do catálogo aparecem no fim e permanecem removíveis.

### 3. Orçamento, saúde e i18n

- Slider para `wake.budgetTokens` com **estimativa viva** para o store atual.
- Indicador de compressão: modo, pendentes, degradados, **disjuntor armado**,
  chamadas e tokens (incluindo tentativas fracassadas).
- Chaves obrigatórias em `en` e `zh`; `pt-BR` como pacote adicional (`addLanguage`).
  Nenhuma chave pode ter `pt-BR` como única fonte.
- `README.md` e `README.zh.md` na convenção dos pacotes.

## Fora de escopo

A implementação do retry e da taxonomia de erro (item 28) e o ledger ao vivo
(item 27).

## Critérios de aceitação

- [ ] O cartão é **do plugin**: sem ele, o namespace não renderiza nada — e um teste
      falha se o cartão for removido.
- [ ] Todos os campos aparecem com descrição e padrão vindos do schema, sem lista
      duplicada escrita à mão.
- [ ] Desativar pela GUI: a próxima sessão não recebe injeção, nenhuma chamada de
      LLM acontece, e **nenhum** arquivo do store muda (hash e mtime do diretório).
- [ ] Reativar devolve o comportamento anterior sem recompressão.
- [ ] Desativado, uma tool de memória explica que o plugin está inativo e como
      ativá-lo.
- [ ] Chave e rota são gravadas em **uma** mutação; uma revisão nova do host no meio
      marca o rascunho como falho.
- [ ] Desativar preserva as rotas escolhidas.
- [ ] A lista é agrupada por provedor; o effort acompanha o modelo; modelo sem
      metadado de raciocínio não oferece effort.
- [ ] Rota ausente do catálogo aparece no fim e continua removível.
- [ ] "Herdar da sessão" é o padrão e o evento `optmem/compress` confirma o uso da
      rota da sessão.
- [ ] O cartão mostra o disjuntor armado, e religar é ação explícita.
- [ ] Estimativa de tokens bate com a medição da próxima injeção (tolerância 10%).
- [ ] Chaves em `en` e `zh` completas; nenhuma string hardcoded.

## Dependências

- item 19 (protótipo de bundle) — bloqueia.
- item 28 (rota e erros da compressão) — o cartão configura o que aquele item
  implementa.

## Referências

- [spec 11 — web](https://github.com/igorcesarcode/dsh-optmem/blob/main/docs/spec/11-web.md)
- [ADR-0008](https://github.com/igorcesarcode/dsh-optmem/blob/main/docs/adr/0008-rota-e-erros-da-compressao.md)
