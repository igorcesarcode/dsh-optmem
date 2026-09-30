---
title: "release: camada de adaptação do harness e matriz de compatibilidade"
labels: [area:release, type:infra]
milestone: "M6 — Release"
---

## Contexto

O DSH está em `0.1.5-rc.*`, e os próprios pacotes do harness aparecem em versões
diferentes na mesma instalação (`rc.1` para o CLI, `rc.2` para pacotes
individuais). Um plugin de terceiro que se acopla a APIs internas vai quebrar em
algum RC.

A estratégia não é acompanhar rápido — é **isolar a superfície de acoplamento e
degradar bem**.

## Escopo

- Módulo único `src/harness/` como **único** lugar que toca os seams do harness:
  `agent/pre-step`, `agent/session-start`, registro de tools, chamada ao modelo,
  jobs, medidor de tokens, profundidade de delegação, eventos de sessão,
  invariantes.
- Nenhum outro módulo importa tipos `@deepseek-ai/*` diretamente; verificado por
  regra de lint.
- Matriz de compatibilidade publicada na README e verificada em CI: a suíte de
  integração roda contra **cada** versão de DSH da matriz.
- Degradação por versão: na montagem, registra o que conseguiu e reporta o que não;
  na injeção, avisa que a memória está indisponível e por quê; nas tools, erro que
  nomeia a incompatibilidade.
- **O acesso ao store nunca depende de um seam do harness**: um store legível
  continua legível mesmo que o plugin não monte.

## Fora de escopo

Suportar versões do DSH anteriores à primeira da matriz. O plugin declara o
mínimo suportado e recusa o resto com mensagem clara.

## Critérios de aceitação

- [ ] Uma mudança simulada em um seam quebra **um** módulo (`src/harness/`), não a
      suíte inteira: teste que faz um stub da mudança e verifica que o resto compila.
- [ ] A regra de lint falha se um arquivo fora de `src/harness/` importar um pacote
      do harness.
- [ ] A CI roda a suíte de integração contra cada versão da matriz e falha se
      qualquer uma quebrar.
- [ ] A matriz está publicada na README e é gerada dos resultados da CI, não
      escrita à mão.
- [ ] Com um seam ausente, o plugin monta, reporta o que faltou, e a sessão
      prossegue sem memória e **com aviso**.
- [ ] Um teste lê o store com o plugin desmontado (apenas a camada de store) e
      verifica que todas as memórias continuam acessíveis.

## Dependências

- itens 01–16 (todo o comportamento a proteger).

## Referências

- [spec 14 — release](https://github.com/igorcesarcode/dsh-optmem/blob/main/docs/spec/14-release.md)
