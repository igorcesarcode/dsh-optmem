# Política de segurança

## O que é um problema de segurança aqui

Memória de agente é um alvo diferente do habitual. O que importa:

1. **Envenenamento persistente.** Conteúdo hostil que entra no store e volta ao
   contexto em toda sessão futura, sobrevivendo a compactação e troca de modelo.
2. **Escape de frame.** Memória que fecha o enquadramento do plugin e escreve com
   autoridade que não tem.
3. **Exfiltração.** Memória que instrui o agente a gravar segredos — que passam a
   viajar para todo provedor usado depois.
4. **Escrita por terceiro.** Outro processo escrevendo no diretório do store.
5. **Negação de serviço por contexto.** Memória que consome o orçamento e desloca
   o trabalho real.

O modelo de ameaça completo, com os controles e o que **não** é prometido, está em
[docs/spec/09-seguranca.md](docs/spec/09-seguranca.md). Leia antes de reportar:
vários comportamentos surpreendentes estão lá declarados como risco aceito.

## Como reportar

Abra um relatório **privado** pelos *Security Advisories* do repositório, não uma
issue pública. Inclua:

- a versão do plugin e a versão do DSH;
- a menor sequência de passos que demonstra o problema;
- o impacto: o que o atacante ganha, e o que ele precisa controlar para isso.

Se o problema só se reproduz com um `store.dir` já comprometido, diga isso
explicitamente — muda a classificação de severidade.

## Fora do escopo

Estes não são tratados como vulnerabilidades, por decisão registrada:

- **Adulteração local do log.** Detecção de integridade não existe no v1
  (spec 09, C7). Quem tem acesso de escrita ao sistema de arquivos do usuário
  controla a memória. O desenho proposto (cadeia de hash em `PROV.txt`) está
  documentado como trabalho futuro.
- **Resumo não determinístico.** O texto de um resumo gerado por LLM não é
  reprodutível. É propriedade aceita do desenho, documentada no ADR-0006 e na
  spec 06.
- **Ausência de busca semântica.** Decisão do ADR-0006, não um bug.
- **Influência do modelo por memória legítima.** Memória é conteúdo, e conteúdo
  influencia o modelo. O que se controla é a **autoridade** com que ele entra, não
  a influência.
- **Dados sensíveis que o agente registrou normalmente.** Existem instrumentos
  (`--private`, `denyPatterns`, escopo por workspace), mas o registro de um fato
  sensível como memória comum é escolha do usuário e do agente.

## Versões suportadas

Enquanto o plugin estiver em `0.x`, apenas a última versão publicada recebe
correção de segurança.
