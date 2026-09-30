---
title: "scaffold: pacote, build, exports e CI"
labels: [area:release, type:infra]
milestone: "M1 — Fundação"
---

## Contexto

Primeiro tijolo: um pacote publicável que o DSH consegue carregar. Sem isso nada
mais pode ser testado dentro do harness.

Quatro fatos do levantamento definem este item
([research/01](https://github.com/igorcesarcode/dsh-optmem/blob/main/docs/research/01-server-plugin-kit.md)):

1. **`dsh.bundle.patch` é obrigatório para montar.** O campo `dsh` não é necessário
   para o loader importar o pacote, mas `dsh plugin add` só promove o pacote a
   camada de perfil se ele declarar `dsh.bundle.patch`. Sem isso a instalação
   imprime *"declares no dsh.bundle — installed as a plain dependency, not a profile
   layer"* e **nada monta** — o modo de falha mais caro de diagnosticar.
2. **`unwrapExports` é `exports.default ?? exports`.** Um `export default` junto de
   `inject`/`Config` como named exports faz o loader descartar os metadados em
   silêncio. Só duas formas valem: named exports completos, ou classe de serviço
   default-exportada com `static inject`/`static Config`.
3. **`link:` quebra imports bare.** Com instalação por link, o Node resolve o
   symlink e os imports `@deepseek-ai/*` não alcançam o espelho em
   `$DSH_HOME/profiles/node_modules`. O workaround verificado é `createRequire`
   ancorado no `package.json` do CLI.
4. **O toolchain não é recuperável do pacote publicado.** Zero tsconfig e zero
   config de bundler nos 240 pacotes; 12 pacotes de plugin amostrados não têm campo
   `scripts`. Só o **contrato de saída** é provável: ESM, `lib/index.js`, tipos em
   `lib/types/**` (nunca `lib/index.d.ts`), e todo subpath de `exports` com a
   condição `types`.

## Escopo

- `package.json` publicável: `type: module`, `main`, `exports` (entry point,
  `./invariant`, `./client`, `./package.json`), `files`, `license: MIT`,
  `repository`, `engines`, `peerDependencies` para o harness e o cordis.
- Campo `dsh` com `bundle.patch` e, para a metade browser, `client` com
  `platform: "web"` e a lista de `inject`.
- TypeScript próprio compilando para `lib/`, com o contrato de saída acima.
- Lint, formatação e uma regra que proíbe import bare do harness fora de
  `src/harness/`.
- `src/harness/` com o `createRequire` ancorado, para desenvolvimento com `link:`.
- CI que roda build, lint e testes em cada push.
- `.github/pull_request_template.md` ligando PR a issue e a spec.

## Fora de escopo

Qualquer lógica de memória, e o bundle de cliente (item 19).

## Critérios de aceitação

- [ ] `dsh plugin --profile <perfil> add <este-pacote>` monta o plugin — verifica
      `dsh.bundle.patch` no manifesto.
- [ ] Um teste monta o plugin e verifica que `inject` e `Config` foram aplicados
      (prova que `unwrapExports` não descartou metadados).
- [ ] Todo subpath de `exports` resolve `types` e `default`, verificado por um teste
      que faz os imports.
- [ ] `lib/index.d.ts` **não** existe; os tipos estão sob `lib/types/`.
- [ ] `dependencies` não contém nenhum `@deepseek-ai/*` nem o cordis.
- [ ] Regra de lint falha se um arquivo fora de `src/harness/` importar um pacote do
      harness.
- [ ] Instalação por `link:` funciona em desenvolvimento, com `src/harness/`
      resolvendo os pacotes do harness via `createRequire`.
- [ ] Importar o pacote não produz efeito colateral: nada é registrado e o disco não
      é tocado.
- [ ] CI verde em push e em PR.
- [ ] Nenhum `postinstall` nem script que execute código na instalação.

## Dependências

Nenhuma. É a base de todas as outras.

## Referências

- [spec 01 — pacote e build](https://github.com/igorcesarcode/dsh-optmem/blob/main/docs/spec/01-pacote-e-build.md)
- [spec 14 — release](https://github.com/igorcesarcode/dsh-optmem/blob/main/docs/spec/14-release.md)
