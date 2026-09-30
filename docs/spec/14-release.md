# 14 — Release, versionamento e compatibilidade

## Objetivo

Publicar e manter um plugin de terceiro contra um harness que ainda está em
*release candidate*, sem quebrar a memória de ninguém — nem o diretório de store,
nem a sessão de quem atualiza.

## A restrição que domina tudo

O DSH está em `0.1.5-rc.*`. As dependências entre pacotes do próprio harness já
aparecem em versões diferentes dentro da mesma instalação (`rc.1` para o CLI,
`rc.2` para pacotes individuais). Um plugin de terceiro que se acopla a APIs
internas vai quebrar em algum RC.

Portanto a estratégia não é "acompanhar rápido", é **isolar a superfície de
acoplamento e degradar bem**.

## Camadas de acoplamento

Do mais estável para o mais volátil, e o que acontece quando cada uma muda:

| Camada | Exemplos | Estabilidade esperada | Se mudar |
|---|---|---|---|
| Formato do store | `LOG.txt`, `PROV.txt`, `TREE/` | **congelado** — é o ativo do usuário | migração obrigatória, com versão de formato |
| Algoritmo de cobertura | `cover`, decaimento, orçamento | estável | muda o documento, não os dados |
| Contrato de tools | nomes, argumentos, saída | estável | deprecação com um ciclo de aviso |
| Seams do harness | `agent/pre-step`, `ctx.tools.register`, `ctx.llm.stream`, `ctx.jobs` | **volátil (RC)** | camada de adaptação |
| Estrutura do pacote | `package.json`, loader, patch de perfil | **volátil (RC)** | correção de empacotamento |

Regra: nada acima da terceira linha pode importar tipos das duas últimas
diretamente. As chamadas ao harness passam por um módulo único
(`src/harness/`), que é o único lugar a mudar quando o RC mudar.

## Versionamento

- **SemVer no plugin.** `0.x` enquanto o harness estiver em RC; `1.0.0` quando o
  DSH estabilizar e o formato do store estiver congelado por uma release.
- **Versão de formato do store** em `OWNER` (`format=1`). O plugin lê formatos
  mais antigos sempre; escrever em formato antigo nunca. Migração só para frente.
- Uma mudança que exija reescrever o store é **major**, mesmo em `0.x`, e vem com
  comando de migração que preserva o diretório original.

## Matriz de compatibilidade

Publicada na README e verificada em CI. Para cada versão do plugin:

```
dsh-optmem  0.1.x   DSH 0.1.5-rc.1 … 0.1.5-rc.2    Node >= ?
dsh-optmem  0.2.x   DSH 0.2.x                      Node >= ?
```

A CI roda a suíte de integração contra **cada** versão de DSH da matriz, não
apenas a última. Um plugin que só testa contra a versão mais nova descobre a
quebra no computador do usuário.

## Degradação por versão

Se o harness mudou e um seam não existe mais:

- **Na montagem:** o plugin registra o que conseguiu registrar e reporta o que
  não conseguiu. Nunca derruba o boot do profile.
- **Na injeção:** se não puder injetar, avisa no contexto que a memória está
  indisponível e por quê. Falha aberta e visível (M5).
- **Nas tools:** as que não puderem funcionar respondem com um erro que nomeia a
  incompatibilidade e a versão esperada.
- **No store:** o acesso ao store nunca depende de um seam do harness. Um store
  legível continua legível mesmo que o plugin não monte.

## Publicação

- Pacote no npm, público, com `repository`, `license` (MIT) e `engines`.
- **`peerDependencies`** para os pacotes `@deepseek-ai/dsh-*` e cordis, nunca
  `dependencies` — o plugin compartilha as instâncias do harness, não traz as suas.
- Instalação documentada como `dsh plugin --profile <nome> add dsh-optmem`, seguida
  da linha de configuração no patch do profile.
- Nenhum passo de instalação roda código arbitrário. Sem `postinstall`.

## Ordem de entrega

Cada fase é utilizável sozinha. Nenhuma fase deixa o sistema pior do que a
anterior.

| Fase | Entrega | Valor | Depende |
|---|---|---|---|
| **M1 Fundação** | pacote, build, CI, store, cobertura | memória legível e testável, ainda sem harness | — |
| **M2 Contexto** | injeção, tools, escopo | **o sistema funciona**: o agente lembra | M1 |
| **M3 Inteligência** | compressão em background, compaction | o sistema escala e sobrevive à compactação | M2 |
| **M4 Superfície** | painel web, settings, i18n | o usuário vê e controla a memória | M2 |
| **M5 Endurecimento** | proveniência, aprovação, privacidade | o sistema é seguro para uso continuado | M2 |
| **M6 Release** | matriz, docs, publicação | o sistema é instalável por terceiros | M1–M5 |

M5 pode andar em paralelo com M3/M4: são arquivos diferentes e nenhum dos dois
bloqueia o outro.

## Documentação obrigatória na release

- `README.md` — o que é, instalação, configuração, custo esperado, limites.
- Custo **declarado em números**: orçamento padrão de injeção e ordem de grandeza
  do custo de compressão. Um plugin de memória que esconde o custo em tokens não
  é honesto.
- Limites declarados, incluindo os que não têm solução: não determinismo do
  resumo, ausência de busca semântica, ausência de detecção de adulteração.
- Como inspecionar e como sair: onde ficam os arquivos, como ler sem o DSH, como
  desinstalar sem perder memória.

## Critérios de aceitação

- **CA1.** `dsh plugin --profile <perfil> add dsh-optmem` instala e o plugin monta
  em um profile limpo, documentado passo a passo e verificado em CI.
- **CA2.** A CI roda a suíte de integração contra cada versão de DSH da matriz.
- **CA3.** Remover o pacote não apaga nem corrompe o store; reinstalar em outra
  versão continua lendo o mesmo store.
- **CA4.** Uma mudança simulada em um seam do harness quebra **um** módulo
  (`src/harness/`), não a suíte inteira.
- **CA5.** `OWNER` contém `format=1`; um store com `format=2` desconhecido é
  recusado em modo leitor com mensagem clara, nunca escrito.
- **CA6.** A README declara o orçamento padrão de injeção em tokens e uma
  estimativa de custo de compressão por mil memórias.
