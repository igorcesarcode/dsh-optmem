---
title: "security: endurecimento do diretório e da posse do store"
labels: [area:security, type:feature]
milestone: "M5 — Endurecimento"
---

## Contexto

O store vive fora do workspace, o que significa que a política de sandbox de
arquivos do harness — que protege o workspace — não o cobre. Duas consequências:
escrever nele é escrever no futuro do agente, e uma configuração descuidada de
`store.dir` pode apontar para um alvo sensível.

Além disso, a compatibilidade com a CLI `memo` (ADR-0005) cria o risco de dois
escritores no mesmo diretório.

## Escopo

- `realpath` em `store.dir` antes do uso.
- Allowlist de diretórios permitidos (`$DSH_HOME/storages/` por padrão, ampliável
  explicitamente).
- Rejeição de componentes de caminho que sejam symlink, em vez de segui-los.
- Abertura de `LOG.txt`, `PROV.txt` e `.lock` sem seguir symlink, quando a
  plataforma suportar.
- Arquivo `OWNER` com `format=1` e namespace.
- Store sem `OWNER` mas com árvore construída ⇒ modo `reader` automático, com
  aviso e explicação (veio da CLI).
- Em modo `reader`: escrita recusada com mensagem que ensina a migrar.
- Comando `dsh-optmem migrate <dir>`: copia log e árvore preservando ids, cria
  `PROV.txt` com `import`, escreve `OWNER`, e **deixa a origem intacta**.
- `fsync` no diretório após criação de arquivo, para que a criação sobreviva a um
  crash.

## Fora de escopo

Detecção de adulteração do log (spec 09, C7) e criptografia em repouso (spec 10, P5).

## Critérios de aceitação

- [ ] `store.dir = /etc` é rejeitado na configuração, com mensagem que diz qual é
      o diretório permitido.
- [ ] `store.dir` apontando para um symlink é recusado, e o alvo não é tocado.
- [ ] Um store sem `OWNER` com `TREE/` populado entra em `reader`; uma tentativa de
      `memory_note` falha e o store não muda.
- [ ] Um store sem `OWNER` e sem árvore é tratado como novo e o `OWNER` é criado.
- [ ] `OWNER` com `format=2` (desconhecido) é recusado em modo leitor, nunca
      escrito.
- [ ] `migrate` preserva os ids exatamente e deixa o diretório de origem intacto
      (hash antes/depois).
- [ ] A criação do diretório e dos arquivos sobrevive a um kill entre a criação e
      a primeira escrita (teste com ponto de falha injetado).

## Dependências

- item 02 (store).

## Referências

- [ADR-0005](https://github.com/igorcesarcode/dsh-optmem/blob/main/docs/adr/0005-plugin-e-o-unico-escritor.md)
- [spec 02 — store](https://github.com/igorcesarcode/dsh-optmem/blob/main/docs/spec/02-store.md)
- [spec 09 — segurança](https://github.com/igorcesarcode/dsh-optmem/blob/main/docs/spec/09-seguranca.md)
