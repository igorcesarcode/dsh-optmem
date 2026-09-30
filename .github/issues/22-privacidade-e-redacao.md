---
title: "privacy: padrões de negação, redação na injeção e memória privada"
labels: [area:privacy, type:feature]
milestone: "M5 — Endurecimento"
---

## Contexto

O prompt do OptMem manda registrar "anything you learn about their life (even
indirectly)". Isso produz uma base de dados pessoal em texto plano que é enviada a
todo provedor de modelo usado — em toda requisição, porque o documento de wake faz
parte do contexto.

Não há como ter memória sem que o modelo a veja. O que se pode fazer é dar
controle: nada entra por acidente, o que é sensível pode não viajar, e nada é
apagado em silêncio.

## Escopo

- `privacy.denyPatterns`: avaliados **antes de gravar**; correspondência impede a
  gravação, nomeando o padrão. Defaults: chaves de API, tokens do GitHub, chaves
  AWS, chaves privadas PEM.
- `privacy.redactPatterns`: avaliados **na injeção**; a memória fica íntegra no
  store, o texto injetado sai redigido. Redigir na escrita destruiria informação
  que o usuário pode querer; redigir na injeção protege o canal que importa.
- `memory_note --private`: a memória não entra no wake, mas é encontrável por
  `recall`, que é uma busca deliberada.
- Retenção que **não apaga**: `wakeMaxAgeDays` apenas exclui do documento;
  `maxMemories` apenas avisa.
- Permissões `0700` no diretório e `0600` nos arquivos, aplicadas na criação.
- `memory_config` reporta contagens por namespace e por origem.

## Fora de escopo

Criptografia em repouso (spec 10, P5 — v2) e qualquer promessa de anonimato.

## Critérios de aceitação

- [ ] Memória contendo um padrão de negação não é gravada, e o erro nomeia o
      padrão que correspondeu.
- [ ] Memória contendo um padrão de redação é gravada íntegra (verificado no
      `LOG.txt`) e sai redigida no documento de wake.
- [ ] `--private` não aparece no wake em nenhuma configuração de orçamento, e
      aparece em `memory_recall`.
- [ ] Com `wakeMaxAgeDays = 1` e memórias de 10 dias: nenhuma no wake, todas em
      `recall`, nenhum arquivo do store modificado (verificado por hash e mtime).
- [ ] O diretório do store é criado com `0700` e os arquivos com `0600`, verificado
      em plataforma POSIX.
- [ ] A LISTA de padrões é configurável e substituível, não fixa no código.
- [ ] Um teste verifica que a redação acontece **na injeção e não na escrita**, para
      que a decisão não regrida em silêncio.

## Dependências

- item 10 (tools), item 07 (injeção, para a redação no documento).

## Referências

- [spec 10 — privacidade](https://github.com/igorcesarcode/dsh-optmem/blob/main/docs/spec/10-privacidade.md)
