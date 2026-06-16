# Fase 2 - Revisão & Construção de Testes

> **Meta da fase:** revisar criticamente o núcleo construído na Fase 1 e cobri-lo com
> **testes automatizados** que comprovam o que o rubric chama de "qualidade e resiliência
> do código": integridade da ingestão, idempotência, integridade da DAG, comportamento sob
> falha e validação fim-a-fim. Fecha com **CI**.

**Critério de saída da fase:** suíte de testes verde localmente e no CI; idempotência e
resiliência **demonstradas por teste** (não só por afirmação); checklist E2E reproduzível.

---

## F2-01 - Code review da ingestão (Meltano) e da DAG

**Descrição.** Revisão guiada antes de testar, para corrigir problemas estruturais.

**Checklist de revisão.**
- `meltano.yml`: streams selecionados corretos (7 entidades), tipos mapeados sem perda,
  `replication-method` coerente, **zero segredos** no arquivo.
- Nomes/tipos das tabelas `raw.*` batem com o que o dbt `_sources.yml` espera.
- DAG: dependências corretas, `retries`/`retry_delay` presentes, sensor no lugar certo,
  sem caminhos absolutos frágeis, sem credenciais.
- Idempotência: a estratégia (truncate/replace) está realmente aplicada no target.
- Separação de responsabilidades (EL no Meltano, T no dbt - sem lógica de transformação
  vazando para a ingestão).

**Critério de aceite.** Lista de achados registrada e resolvida; pode usar `/code-review`
sobre o diff da Fase 1.

**Dependências.** Fase 1 completa.

---

## F2-02 - Testes de integridade da ingestão (fonte × destino)

**Descrição.** Garantir que os dados chegam completos e corretos ao `raw`.

**Ações.**
- Para cada uma das 7 tabelas: comparar **contagem de linhas** fonte × `raw.*`.
- Checar **presença de colunas** e **não-nulidade de chaves** (`cod_cliente`,
  `num_conta`, `cod_proposta`, etc.).
- Checar **tipos**/parsing de datas e numéricos do `transacoes.csv`.
- Implementar como teste `pytest` (consulta SQL via `psycopg`) ou como
  **dbt source freshness/tests** no schema `raw`.

**Arquivos afetados.** `tests/ingestion/test_row_counts.py` (ou `dbt` source tests),
fixtures de conexão.

**Critério de aceite.** Teste falha se qualquer tabela tiver contagem divergente ou PK nula.

**Dependências.** F1-04.

---

## F2-03 - Testes de idempotência

**Descrição.** Comprovar que reexecutar a ingestão **não duplica** nem corrompe dados.

**Ações.**
- Rodar o EL duas vezes para o mesmo `logical_date`; afirmar que `count(raw.*)` é igual
  após a 2ª execução.
- Testar `--full-refresh` vs execução normal.
- Caso de borda: execução parcial interrompida + re-trigger -> estado consistente.

**Arquivos afetados.** `tests/ingestion/test_idempotency.py`.

**Critério de aceite.** Duas execuções consecutivas produzem contagens idênticas; sem
linhas duplicadas (validar por PK).

**Dependências.** F1-05.

---

## F2-04 - Teste de integridade da DAG (DAG integrity test)

**Descrição.** Garantir que a DAG importa e está bem-formada - padrão de boas práticas de
Airflow.

**Ações.**
- `pytest` que faz `DagBag` load e afirma: **0 import errors**, ausência de ciclos,
  `retries >= 1` em todas as tasks, `catchup=False`, `tags` presentes,
  `on_failure_callback` setado.
- Afirmar a topologia esperada (sensor -> EL paralelo -> validate_raw_load -> dbt_run -> dbt_test).

**Arquivos afetados.** `tests/dags/test_dag_integrity.py`.

**Critério de aceite.** Teste verde; quebra se alguém introduzir erro de import ou remover
retries.

**Dependências.** F1-05.

---

## F2-05 - Testes de resiliência / tratamento de falhas

**Descrição.** Demonstrar o comportamento sob falha exigido pelo rubric (retries, sensores).

**Ações.**
- **Arquivo ausente**: remover `transacoes.csv` -> o `FileSensor` deve aguardar/expirar
  (não prosseguir) - testar via `poke`/timeout curto.
- **Falha no load**: derrubar o DW no meio do load -> a task deve **falhar e re-tentar**
  conforme `retries`; após o DW voltar, completar.
- **Callback de falha**: verificar que `on_failure_callback` é disparado (log/Slack/no-op
  testável).

**Arquivos afetados.** `tests/dags/test_resilience.py`, `dags/callbacks.py`.

**Critério de aceite.** Sensor bloqueia sem o arquivo; task falha->retry->sucesso após
recuperação da fonte; callback registrado.

**Dependências.** F1-05.

> **Nota de implementação (2026-06-14):** O teste de "DW cai no meio do load -> retry ->
> sucesso" não foi implementado como teste automatizado - simular container start/stop
> dentro de pytest exigiria `pytest-docker` ou `testcontainers`, adicionando
> complexidade desproporcional ao escopo. Em vez disso:
> - A configuração de retry (`retries=2`, `retry_exponential_backoff=True`) é verificada
>   em `tests/dags/test_resilience.py` (unit tests, sem DB).
> - O comportamento do `FileSensor` sob arquivo ausente é testado com mock de `FSHook`.
> - O comportamento real de retry durante o desenvolvimento está documentado em
>   `docs/operational/checklist_e2e.md §5` com os cenários observados.

---

## F2-06 - Revisão e expansão dos testes dbt

**Descrição.** A suíte dbt já existe (inclui 2 falhas *by design* de integridade
referencial). Revisar e ampliar a cobertura de data quality na camada de transformação.

**Ações.**
- Confirmar os 2 testes que falham por design (cliente órfão 528) e **documentar** que são
  esperados - ou convertê-los em `warn` para o pipeline ficar verde sem mascarar o achado.
- Adicionar testes onde faltam: `not_null`/`unique`/`relationships` nas PKs/FKs de staging;
  `accepted_values` em status; `dbt_utils` para chaves compostas.
- Garantir que `dbt test` roda **dentro da DAG** (F1-05) e o resultado é observável.

**Arquivos afetados.** `dbt_project/models/**/_*.yml`, possíveis `tests/` singulares.

**Critério de aceite.** `dbt test` com resultado determinístico e documentado; cobertura de
PK/FK nas 7 entidades.

**Dependências.** F1-05.

---

## F2-07 - Validação fim-a-fim (E2E) e checklist de reprodutibilidade

**Descrição.** Provar que um deploy limpo funciona - exatamente o que o vídeo precisará
mostrar.

**Ações.**
- **Compose**: `make down -v && make up` -> trigger da DAG -> DAG verde -> `SELECT count(*)`
  nas 7 `raw.*` + amostras nas marts.
- **Kind**: `make kind-down && make kind-up && make kind-deploy` -> mesmo roteiro no cluster.
- Registrar um **checklist E2E** (`docs/operational/checklist_e2e.md`) com os comandos e os resultados
  esperados - vira roteiro de demonstração.

**Arquivos afetados.** `docs/operational/checklist_e2e.md`, `Makefile` (alvos de verificação).

**Critério de aceite.** Ambos os modos passam do zero ao dado no destino seguindo só o
checklist.

**Dependências.** F1-07.

---

## F2-08 - CI (GitHub Actions)

**Descrição.** Automatizar as verificações para garantir que o repositório entregue está
saudável.

**Ações (jobs).**
- **Lint**: `ruff` (Python/DAGs) + `sqlfluff` (dbt) + `yamllint`.
- **DAG integrity test** (F2-04) - sem subir Airflow completo.
- **dbt parse** / `dbt build` contra um Postgres de serviço (container do CI).
- **meltano config validate** / `meltano lock`.
- **Secret scan** (ex.: `gitleaks`) - reforça F1-06.

**Arquivos afetados.** `.github/workflows/ci.yml`, `pyproject.toml`/`.sqlfluff`/`.ruff.toml`.

**Critério de aceite.** Pipeline de CI verde em PR; falha se DAG quebrar, segredo vazar ou
dbt não parsear.

**Dependências.** F2-02..F2-06.

---

## Resumo da Fase 2

| ID | Task | Tipo | Depende de |
|---|---|---|---|
| F2-01 | Code review ingestão + DAG | Revisão | Fase 1 |
| F2-02 | Testes de integridade da ingestão | Teste | F1-04 |
| F2-03 | Testes de idempotência | Teste | F1-05 |
| F2-04 | DAG integrity test | Teste | F1-05 |
| F2-05 | Testes de resiliência/falha | Teste | F1-05 |
| F2-06 | Revisão/expansão testes dbt | Teste | F1-05 |
| F2-07 | Validação E2E + checklist | Verificação | F1-07 |
| F2-08 | CI (GitHub Actions) | Automação | F2-02..F2-06 |

Próximo passo: [`03_fase3_melhorias.md`](03_fase3_melhorias.md).
