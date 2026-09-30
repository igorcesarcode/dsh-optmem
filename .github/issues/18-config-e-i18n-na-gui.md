---
title: "web: configuração do plugin na GUI e internacionalização"
labels: [area:web, type:feature]
milestone: "M4 — Superfície"
---

## Contexto

Duas necessidades distintas: o usuário precisa ajustar o orçamento de memória sem
editar YAML, e o projeto precisa falar as línguas do harness.

**Correção vinda do levantamento:** a configuração **não** é renderizada
automaticamente do schema. A aba de plugins despacha um slot por namespace, e um
namespace que nenhum cartão reivindica **não renderiza nada** — os controles dos
pacotes publicados são escritos à mão. O plugin precisa entregar o próprio cartão.
O que existe a favor é que o `SettingsDescriptor.schema` está no fio e há API de
schema (reidratação, validação, acesso por caminho), então um formulário **genérico
dirigido pelo schema** é possível — só não é gratuito.

Sobre os locales: os embutidos são exatamente `zh` e `en`, e `zh` é a fonte de
verdade do conjunto de chaves. pt-BR entra como pacote de idioma externo
(`addLanguage`), e portanto não pode ser a única fonte de nenhuma chave.

Sobre a configuração em si: a única opção que faz sentido editar em conversa é
`wake.budgetTokens`, porque é a única cujo efeito o usuário sente imediatamente. As
demais são decisões de instalação e pertencem ao arquivo de perfil.

## Escopo

- Cartão de configuração próprio do plugin, registrado sob o seu namespace.
- Formulário **dirigido pelo schema**: descrição e padrão vindos do schema, sem
  lista duplicada escrita à mão.
- Slider numérico para `wake.budgetTokens`, com **estimativa de tokens viva** para o
  store atual, para que o usuário veja a consequência antes de aplicar.
- Indicador de compressão: modo, pendentes, degradados, custo acumulado.
- i18n: chaves obrigatórias em `en` e `zh`; `pt-BR` como pacote adicional.
- `README.md` e `README.zh.md` na convenção dos pacotes.

## Fora de escopo

Traduzir as mensagens que o **modelo** vê. Elas ficam em inglês, como as demais
mensagens de ferramenta do harness — o modelo é multilíngue, mas o histórico é
mais fácil de auditar com uma língua só para metadados.

## Critérios de aceitação

- [ ] O plugin aparece na lista de plugins com o nome, a versão e o estado.
- [ ] O cartão é **do plugin**: sem ele, o namespace não renderiza nada — e um teste
      falha se o cartão for removido.
- [ ] Todos os campos de configuração aparecem com descrição e padrão vindos do
      schema, sem lista duplicada escrita à mão.
- [ ] Mudar o orçamento pela GUI tem efeito na próxima sessão, sem reiniciar o host.
- [ ] A estimativa de tokens mostrada bate com o valor realmente medido na próxima
      injeção (tolerância de 10%).
- [ ] As chaves existem em `en` e `zh` (obrigatórias) e em `pt-BR` (adicional);
      nenhuma string aparece hardcoded, e nenhuma chave tem `pt-BR` como única
      fonte.
- [ ] A README em chinês existe e cobre instalação, configuração e limites.

## Dependências

- item 17 (painel), item 19 (spike de viabilidade do client plugin).

## Referências

- [spec 11 — web](https://github.com/igorcesarcode/dsh-optmem/blob/main/docs/spec/11-web.md)
