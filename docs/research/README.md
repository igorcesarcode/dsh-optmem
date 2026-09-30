# Levantamento do harness — anexos de evidência

Estes documentos descrevem o **DeepSeek Harness**, não o plugin. Foram produzidos
por leitura do pacote publicado (`@deepseek-ai/dsh@0.1.5-rc.1` e os pacotes
`@deepseek-ai/dsh-*@0.1.5-rc.2` que ele traz em `node_modules/`), com citação de
caminho e linha para cada afirmação.

Servem para três coisas:

1. **Sustentar as decisões.** Cada ADR e cada spec cita evidência daqui.
2. **Detectar deriva.** Quando o harness mudar, é aqui que se confere o que mudou
   — e quais das nossas decisões dependiam daquilo.
3. **Não repetir o trabalho.** A próxima pessoa que precisar saber como um seam
   funciona lê isto em vez de reler o bundle.

## Regra

Um anexo registra o que foi **verificado**, e separa isso do que foi **inferido**.
Onde não foi possível determinar, ele diz que não foi possível, em vez de supor.
Isso é o que torna o documento útil: uma suposição disfarçada de fato é pior do
que uma lacuna declarada.

## Índice

| Arquivo | Assunto | Estado |
|---|---|---|
| [01-server-plugin-kit.md](01-server-plugin-kit.md) | empacotamento, config, tools, invariantes, storage, testes | pendente |
| [02-client-web-kit.md](02-client-web-kit.md) | superfície de cliente, slots, configuração na GUI | pendente |
| [03-lifecycle-injection-compaction.md](03-lifecycle-injection-compaction.md) | `pre-step`, ciclo de vida, dedup bruto, compactação, jobs, LLM, invariantes | **completo** |
| [04-superficie-cliente-e-aba.md](04-superficie-cliente-e-aba.md) | como registrar uma aba nativa ao lado de Chat e Trajectory | **completo** |

## Achados que mudaram decisões

Registro do que o levantamento **corrigiu** no desenho, porque um anexo que só
confirma não está fazendo o trabalho dele:

| Achado | Consequência |
|---|---|
| `SessionStartSource` declara `'compact'`, mas **nenhum emissor existe** no harness publicado — só `'startup'` e `'resume'` são passados | a re-injeção pós-compactação **não** pode depender desse gatilho. Passa a observar `compaction/end` em `session/event` e verificar a superfície no próximo `pre-step` (spec 07, ADR-0003) |
| `PreCompact`/`PostCompact` são explicitamente não suportados pelo bridge de hooks do Claude Code | o caminho de reação à compactação só existe como plugin nativo — reforça o ADR-0003 |
| Não existe evento cordis em volta da compactação; `compaction/*` são apenas eventos de sessão | a observação é por `ctx.on('session/event', …)` |
| Não existe `ctx.llm.generate()`, só `stream()` | a compressão usa `stream()` com `purpose` (spec 06) |
| `ctx.tokenMeter` não conta tokens de uma string arbitrária; expõe `estimateContent([…])`, heurística de 4 caracteres por token | o orçamento do documento usa a estimativa como gate barato e a medição da requisição como confirmação (spec 03, spec 15) |
| `dsh-agent-instructions` deduplica apenas contra a superfície derivada | é **modelo errado** para "eu já injetei?". O modelo correto é `dsh-time-context`: varredura de seqs brutos + fold em `sessionProjections` (spec 07) |
| Pacotes de **duas metades** (`dsh.client` + `platform: 'web'` + export `./client`) são escaneados do Loader e servidos em `/plugins` | uma aba nativa de terceiro é viável sem fork do monorepo (ADR-0007) |
