# 01 — Pacote, build e carregamento

## Objetivo

Publicar um pacote que o harness consegue instalar, montar e — no caso da metade
browser — servir. Sem isso nada mais existe.

O levantamento completo está em
[research/01-server-plugin-kit.md](../research/01-server-plugin-kit.md). Esta spec
fixa as decisões.

## O que o harness exige (verificado)

| Requisito | Consequência |
|---|---|
| ESM, `main: lib/index.js` | não há `lib/index.d.ts`; tipos vivem em `lib/types/**` |
| Todo subpath de `exports` carrega a condição `types` | sem ela o consumidor não enxerga os tipos |
| O loader importa apenas `options.name` da entrada | o campo `dsh` **não** é necessário para montar |
| `dsh plugin add` só promove o pacote a camada de perfil se ele declarar `dsh.bundle.patch` | sem isso a instalação diz *"declares no dsh.bundle — installed as a plain dependency, not a profile layer"* e **nada monta** |
| O host **nunca** constrói o bundle de cliente | bundle ausente é falha dura de ativação |

### Duas armadilhas que definem o desenho

**1. `unwrapExports` é `exports.default ?? exports`.** Um `export default` junto de
`inject`/`Config` como named exports faz o loader **descartar os metadados em
silêncio**. Só existem duas formas válidas:

```ts
// Forma A — named exports (é a que usamos na metade host)
export const name = 'optmem'
export const inject = ['tools', 'llm', 'jobs']
export const Config = z.object({ /* … */ })
export function apply(ctx, config) { /* … */ }

// Forma B — classe de serviço default-exportada, com static inject/static Config
```

**2. `link:` quebra imports bare.** Para um pacote instalado por link, o Node
resolve o symlink para o realpath, e os imports `@deepseek-ai/*` **não** alcançam o
espelho em `$DSH_HOME/profiles/node_modules`. Quem instala por caminho local precisa
de um `createRequire` ancorado no `package.json` do CLI.

Decisão: **`peerDependencies` para tudo que é do harness**, e nenhum import bare do
harness fora de `src/harness/`. Em desenvolvimento com `link:`, o `src/harness/`
resolve via `createRequire` ancorado; em publicação, resolve normalmente. O
detalhe fica em um módulo só — que é a camada de adaptação do item 24.

## Manifesto

```jsonc
{
  "name": "dsh-optmem",
  "version": "0.1.0",
  "type": "module",
  "main": "lib/index.js",
  "types": "lib/types/index.d.ts",
  "exports": {
    ".":          { "types": "./lib/types/index.d.ts", "default": "./lib/index.js" },
    "./invariant":{ "types": "./lib/types/invariant.d.ts", "default": "./lib/invariant.js" },
    "./client":   { "types": "./lib/types/client/index.d.ts", "default": "./lib/client.js" },
    "./package.json": "./package.json"
  },
  "files": ["lib/**/*.js", "lib/types/**/*.d.ts", "README.md", "LICENSE"],
  "dsh": {
    "bundle": { "patch": "cordis.patch.yml" },
    "client": {
      "inject": ["@deepseek-ai/dsh-api-session-controller", "@deepseek-ai/dsh-client-locale",
                 "@deepseek-ai/dsh-client-ui-conversation", "@deepseek-ai/dsh-client-ui-renderer"],
      "platform": "web"
    }
  },
  "license": "MIT",
  "peerDependencies": {
    "@deepseek-ai/cordis": "^4.0.2",
    "@deepseek-ai/dsh-agent": "*", "@deepseek-ai/dsh-llm": "*",
    "@deepseek-ai/dsh-session": "*", "@deepseek-ai/dsh-tools": "*",
    "@deepseek-ai/dsh-jobs": "*", "@deepseek-ai/dsh-invariants": "*"
  }
}
```

- **`dsh.bundle.patch`** é o que faz `dsh plugin add` montar o plugin. Sem ele, a
  instalação é silenciosamente inerte — o modo de falha mais caro de diagnosticar.
- **`dsh.client`** só existe porque o requisito inclui a aba nativa (spec 11).
  `platform` tem de ser exatamente `"web"`: qualquer outro valor faz o pacote ser
  ignorado **em silêncio** pela varredura de cliente.
- A metade browser só pode pedir módulos da **tabela semente** (`react`,
  `react/jsx-runtime`, `react-dom`, `react-dom/client`, `@deepseek-ai/cordis`,
  `dsh-client-store`, `dsh-client-ui-slots`, `dsh-client-ui-primitives`,
  `dsh-client-ui-dockkit`) ou de outras linhas do grafo. O resto vai em
  `dsh.client.external` e precisa de um fornecedor — pedido inválido, fornecedor
  ausente, auto-pedido e ciclo síncrono são rejeitados na composição.
- `peerDependencies` usam `*` na fase RC e são apertadas na matriz de release
  (spec 14). `dependencies` não contém nenhum pacote do harness.

## Build

O toolchain **não** é recuperável do pacote publicado: não há um único tsconfig ou
config de bundler nos 240 pacotes, e 12 pacotes de plugin amostrados não têm campo
`scripts`. Só o **contrato de saída** é provável. Portanto o build é nosso:

- TypeScript compilando para ESM em `lib/`, com `lib/types/**/*.d.ts`.
- A metade browser precisa de um bundle no formato **lazy-CJS factory** que os
  plugins de cliente do harness usam, porque o host só serve o que já está
  construído. O preset que o harness usa não é publicado — ver o protótipo de
  formato (item 19), que é pré-requisito de CA1 da spec 11.
- Artefatos de build não são versionados em fonte; são publicados no pacote.

## Config

- Schema declarado e exportado como `Config`, com defaults e descrição por campo.
- Nada de variável de ambiente para configuração: a configuração vem do perfil.
- O schema é a **única** fonte dos campos; o painel de configuração da GUI e o
  catálogo de configuração derivam dele, sem lista duplicada à mão (spec 11).

## Montagem

- O plugin é montado por uma linha no patch do perfil do usuário.
- A montagem **nunca derruba o boot**: se um serviço exigido faltar, o plugin
  registra o que conseguiu e reporta o que não conseguiu (spec 14).
- Nada de trabalho no corpo do módulo: efeitos ficam em `apply`, para que o unload
  e o reload não deixem lixo.

## Critérios de aceitação

- [ ] `dsh plugin --profile <perfil> add <este-pacote>` monta o plugin (verifica
      `dsh.bundle.patch` no manifesto).
- [ ] `unwrapExports` não descarta metadados: um teste monta o plugin e verifica que
      `inject` e `Config` foram aplicados.
- [ ] Todo subpath de `exports` resolve `types` e `default` (teste de import dos
      dois lados).
- [ ] `dependencies` não contém nenhum `@deepseek-ai/*` nem o cordis.
- [ ] `import` bare do harness aparece **apenas** em `src/harness/`, verificado por
      regra de lint.
- [ ] O corpo do módulo não tem efeito colateral: importar o pacote não registra
      nada nem toca o disco.
- [ ] Instalação por `link:` funciona em desenvolvimento, com o `createRequire` de
      `src/harness/` resolvendo os pacotes do harness.
- [ ] `lib/index.d.ts` **não** existe; os tipos estão em `lib/types/`.

## Evidência

- `unwrapExports`, `dsh.bundle.patch` e o aviso de dependência simples:
  [research/01](../research/01-server-plugin-kit.md) §1–2.
- Armadilha do `link:` e o `createRequire` ancorado: [research/01](../research/01-server-plugin-kit.md) §2.7.
- Contrato de saída e ausência de toolchain publicado: [research/01](../research/01-server-plugin-kit.md) §9.
- Manifesto de referência de um pacote de duas metades:
  `dsh-client-ui-trajectory/package.json`.
