---
title: "docs: README de release com custo e limites declarados"
labels: [area:docs, type:docs]
milestone: "M6 — Release"
---

## Contexto

Um plugin de memória que esconde o custo em tokens não é honesto, e um que promete
mais do que entrega contamina a confiança no resto. A README é o contrato com quem
instala.

O critério de conclusão do épico depende dela: uma pessoa que não participou do
desenvolvimento precisa conseguir usar o plugin seguindo apenas a README.

## Escopo

- O que é, em um parágrafo, e o que **não** é.
- Instalação em dois passos: `dsh plugin --profile <nome> add dsh-optmem` e a linha
  de configuração no patch do perfil.
- **Custo declarado em números**: orçamento padrão de injeção em tokens, e ordem de
  grandeza do custo de compressão por mil memórias.
- Configuração: tabela com todos os campos, padrão e efeito.
- Como inspecionar a memória sem o DSH (o arquivo, o formato, a CLI `memo`).
- Como sair: onde ficam os arquivos, o que apagar, e por que desinstalar não perde
  memória.
- **Limites declarados, incluindo os que não têm solução**: resumo não
  determinístico, ausência de busca semântica, ausência de detecção de adulteração.
- Seção de segurança apontando para `SECURITY.md` e para o modelo de ameaça.
- `README.zh.md` e o arquivo de tradução.
- Diagrama da arquitetura.

## Fora de escopo

Documentação de API interna. O código é a documentação das partes internas.

## Critérios de aceitação

- [ ] Uma pessoa que não participou do projeto instala e vê a memória sendo
      formada em duas sessões consecutivas, seguindo apenas a README (verificação
      com um revisor de fora).
- [ ] A README declara o orçamento padrão em tokens e uma estimativa de custo de
      compressão por mil memórias.
- [ ] A seção de limites lista explicitamente os três limites sem solução.
- [ ] Os comandos da README são copiáveis e funcionam como estão.
- [ ] A README explica como ler o `LOG.txt` sem o DSH instalado.
- [ ] Desinstalar e reinstalar continua lendo o mesmo store, e isso está documentado.
- [ ] `README.zh.md` existe e cobre instalação, configuração e limites (não precisa
      ser tradução literal, precisa ser correta).

## Dependências

- itens 01–24 (a README descreve o que existe, não o que se pretende).

## Referências

- [spec 14 — release](../blob/main/docs/spec/14-release.md)
