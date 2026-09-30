# 10 — Privacidade e retenção

## Objetivo

Deixar explícito **o que sai da máquina**, **o que fica**, **por quanto tempo**, e
dar ao usuário controle real sobre isso — sem prometer o que o sistema não pode
entregar.

## O que sai da máquina

O documento de wake é injetado no contexto e portanto **é enviado ao provedor do
modelo em toda requisição** da sessão, não apenas uma vez. Não há como ter memória
sem isso: memória que o modelo não vê não é memória.

Consequências que precisam estar ditas:

1. Toda memória acaba, mais cedo ou mais tarde, no provedor do modelo.
2. "Sobrevive à troca de fornecedor" corta nos dois sentidos: os mesmos fatos vão
   para **todos** os fornecedores que o usuário usar.
3. Criptografia em repouso **não** resolve isso. Ela protege o arquivo parado, não
   o conteúdo em trânsito nem o que o provedor retém.

## Controles

### P1 — Nada entra por acidente

Padrões de **negação na escrita** (`privacy.denyPatterns`), avaliados antes de
gravar. Qualquer correspondência impede a gravação, com mensagem explícita.

Padrões de **redação** (`privacy.redactPatterns`), avaliados na **injeção**: a
memória permanece no store íntegra, mas o texto injetado sai redigido. Redigir na
escrita destruiria informação que o usuário pode querer; redigir na injeção
protege o canal que importa.

Defaults conservadores (o usuário pode ampliar):

```
sk-[A-Za-z0-9]{16,}          chaves de API no formato OpenAI/Anthropic
gh[pousr]_[A-Za-z0-9]{20,}   tokens do GitHub
AKIA[0-9A-Z]{16}             chaves AWS
-----BEGIN [A-Z ]*PRIVATE KEY-----
```

### P2 — Memória que nunca é injetada

`memory_note --private` grava a memória com `inject = false`. Ela:

- **não** aparece no documento de wake;
- **é** encontrada por `memory_recall` (que é uma busca explícita e deliberada);
- aparece marcada no painel web.

Uso típico: detalhes sensíveis que precisam ser recuperáveis sob demanda mas não
devem viajar em toda requisição.

### P3 — Escopo por workspace

Memória de projeto vive no store daquele workspace (spec 08). Isso limita o dano
de trabalhar em um projeto sob confidencialidade diferente.

### P4 — Retenção sem perda silenciosa

Duas noções distintas, que não devem ser confundidas:

| Config | Efeito | O dado? |
|---|---|---|
| `privacy.wakeMaxAgeDays` | memória mais antiga que isso não entra no wake | **permanece** no store, recuperável por `recall` |
| `privacy.maxMemories` | acima disso, um aviso é emitido | **permanece**; nada é apagado automaticamente |

**Nada é apagado automaticamente, nunca.** Apagar de verdade é uma operação
explícita (`memory_forget --hard`), que reescreve o log, **renumera todos os ids** e
portanto invalida `zoom` referências antigas e a árvore. Por isso ela exige
confirmação textual e deixa um registro do que foi removido (contagens, não
conteúdo).

Isto é deliberado: memória de agente é um ativo de longo prazo, e uma política de
retenção que apaga em silêncio é indistinguível de um bug de corrupção.

### P5 — Criptografia em repouso — v2

Fora do escopo do v1, com desenho já definido para não ser retrabalho:

- AES-256-GCM por registro, com o registro de 320 bytes contendo nonce + tag +
  ciphertext, preservando a largura fixa.
- Chave vinda do serviço de credenciais do DSH, nunca de variável de ambiente nem
  de arquivo ao lado do store.
- **Incompatível por construção com a CLI `memo`** e com `recall` por `grep`. É
  uma troca explícita, e por isso opt-in: `store.encrypt = 'aes-256-gcm'`.
- Não resolve o problema do trânsito (ver acima), apenas o do arquivo parado.

Enquanto P5 não existe, a proteção em repouso é a permissão de sistema de arquivos
do diretório (`0700`), que o plugin aplica na criação.

### P6 — Visibilidade

O usuário precisa poder responder "o que o agente sabe sobre mim?" sem ler um log.
Isso é o painel web (spec 11): lista, busca, marcação de privado, e remoção
explícita. E `memory_config` reporta contagens por namespace e por origem.

## O que este documento não promete

- Não promete que dados sensíveis não vão ao provedor **se** o agente os registrar
  como memória normal. Promete que não vão por acidente, e dá o instrumento
  (`--private`, `denyPatterns`) para quem quer controlar.
- Não promete anonimato. Memória é, por definição, identificadora.

## Critérios de aceitação

- **CA1.** Uma memória contendo um padrão de `denyPatterns` não é gravada, e a
  mensagem de erro diz qual padrão correspondeu.
- **CA2.** Uma memória contendo um padrão de `redactPatterns` é gravada íntegra
  (verificar o byte no `LOG.txt`) e sai redigida no documento de wake.
- **CA3.** `memory_note --private` não aparece no wake em nenhuma configuração de
  orçamento, e aparece em `memory_recall`.
- **CA4.** `privacy.wakeMaxAgeDays = 1` com memórias de 10 dias: nenhuma delas no
  wake, todas em `recall`, nenhum arquivo do store modificado.
- **CA5.** O diretório do store é criado com permissão `0700` e arquivos `0600`.
- **CA6.** `memory_forget --hard` sem confirmação textual não faz nada; com
  confirmação, o log é reescrito, os ids são renumerados, e a árvore é descartada.
- **CA7.** `memory_config` reporta contagens separadas por namespace e por origem.
