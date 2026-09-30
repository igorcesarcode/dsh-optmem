---
title: "release: publicação no npm e verificação de instalação limpa"
labels: [area:release, type:infra]
milestone: "M6 — Release"
---

## Contexto

O plugin só tem valor se outra pessoa conseguir instalar. Publicar é o último
passo, e o mais fácil de fazer errado: um `peerDependencies` mal declarado produz
duas cópias do cordis e um modo de falha difícil de diagnosticar; um `files` mal
declarado publica menos do que o necessário.

## Escopo

- Pacote público no npm, com `repository`, `license: MIT`, `engines` e
  `peerDependencies` corretos (nunca `dependencies` para pacotes do harness).
- `files` enxuto: apenas o necessário para carregar o plugin e o companion de
  invariantes.
- Nenhum `postinstall` nem script que execute código na instalação.
- Verificação de instalação limpa: máquina/container sem o repositório, instalando
  pelo comando documentado, montando em um perfil e produzindo uma injeção.
- CHANGELOG com a primeira versão e a convenção de versionamento do projeto.
- Tag anotada e release no GitHub, com link para a matriz de compatibilidade.

## Fora de escopo

Publicação automática em cada merge. Releases são atos deliberados enquanto o
projeto estiver em `0.x`.

## Critérios de aceitação

- [ ] `dsh plugin --profile <nome> add dsh-optmem` instala a versão publicada em um
      ambiente limpo, e o plugin **monta** — o que exige `dsh.bundle.patch` no
      manifesto. Sem ele o pacote instala como dependência simples e nada é montado.
- [ ] O tarball publicado contém o bundle de cliente já construído: o host nunca
      constrói, e bundle ausente é falha dura de ativação.
- [ ] A instalação limpa produz uma injeção de memória visível na primeira sessão.
- [ ] `npm ls <pacote-do-harness>` no perfil instalado mostra **uma** cópia dos
      pacotes compartilhados do harness, não duas.
- [ ] O tarball publicado não contém fonte de teste, fixtures nem segredos.
- [ ] Nenhum script do `package.json` executa na instalação.
- [ ] O CHANGELOG declara a política de versionamento e o que constitui major
      enquanto o projeto está em `0.x`.
- [ ] A release no GitHub linka a matriz de compatibilidade vigente.

## Dependências

- itens 24, 25.

## Referências

- [spec 14 — release](https://github.com/igorcesarcode/dsh-optmem/blob/main/docs/spec/14-release.md)
