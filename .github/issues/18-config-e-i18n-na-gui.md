---
title: "web: configuração do plugin na GUI e internacionalização"
labels: [area:web, type:feature]
milestone: "M4 — Superfície"
---

## Contexto

Duas necessidades distintas: o usuário precisa ajustar o orçamento de memória sem
editar YAML, e o projeto precisa falar português, inglês e chinês como os demais
pacotes do harness.

Sobre a configuração: a única opção que faz sentido editar em conversa é
`wake.budgetTokens`, porque é a única cujo efeito o usuário sente imediatamente.
As demais são decisões de instalação e pertencem ao arquivo de perfil.

## Escopo

- Expor o schema de configuração do plugin na tela de configurações, com descrição
  e valor padrão de cada campo.
- Slider numérico para `wake.budgetTokens`, com **estimativa de tokens viva** para
  o store atual, para que o usuário veja a consequência antes de aplicar.
- Indicador de compressão: modo, pendentes, degradados, custo acumulado.
- i18n: strings do painel e das mensagens de erro visíveis ao usuário em pt-BR,
  en e zh.
- `README.md`, `README.zh.md` e o arquivo de tradução, seguindo a convenção dos
  pacotes do harness.

## Fora de escopo

Traduzir as mensagens que o **modelo** vê. Elas ficam em inglês, como as demais
mensagens de ferramenta do harness — o modelo é multilíngue, mas o histórico é
mais fácil de auditar com uma língua só para metadados.

## Critérios de aceitação

- [ ] O plugin aparece na lista de plugins com o nome, a versão e o estado.
- [ ] Todos os campos de configuração aparecem com descrição e padrão vindos do
      schema, sem lista duplicada escrita à mão.
- [ ] Mudar o orçamento pela GUI tem efeito na próxima sessão, sem reiniciar o host.
- [ ] A estimativa de tokens mostrada bate com o valor realmente medido na próxima
      injeção (tolerância de 10%).
- [ ] As strings existem em pt-BR, en e zh; nenhuma aparece hardcoded.
- [ ] A README em chinês existe e cobre instalação, configuração e limites.

## Dependências

- item 17 (painel), item 19 (spike de viabilidade do client plugin).

## Referências

- [spec 11 — web](../blob/main/docs/spec/11-web.md)
