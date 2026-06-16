# Decisões Técnicas - BanVic ELT Pipeline

> Documento de registro das principais escolhas de arquitetura, com motivação e trade-offs.
> Cada decisão segue o formato: **Contexto -> Decisão -> Justificativa -> Trade-offs aceitos**.

---

## 1. Orquestração: Apache Airflow

**Contexto**  
O pipeline precisa ser executado diariamente, monitorar a chegada de um arquivo CSV externo,
disparar etapas sequenciais e paralelas, e garantir reexecução em caso de falha.

**Decisão**  
Apache Airflow 2.9.2 com `LocalExecutor`.

**Justificativa**  
- Exigência explícita da certificação (Airflow como orquestrador).
- `LocalExecutor` é suficiente para um case com DAG única e volume controlado - sem overhead
  de CeleryExecutor (Redis/MQ) ou KubernetesExecutor.
- `FileSensor` nativo resolve o problema de dependência do CSV externo sem código customizado.
- `max_active_runs=1` previne execuções concorrentes no mesmo banco sem transações distribuídas.

**Trade-offs aceitos**  
- `LocalExecutor` não escala horizontalmente. Para produção com múltiplas DAGs ou alto paralelismo,
  `CeleryExecutor` seria preferível.
- O arquivo `.env` injeta conexões via variável de ambiente (`AIRFLOW_CONN_*`) - uma conexão
  definida via UI seria mais auditável, mas introduz estado fora do versionamento.

---

## 2. Ingestão: Meltano com Singer Protocol

**Contexto**  
Precisamos extrair 6 tabelas de um banco PostgreSQL (ERP simulado) e um arquivo CSV,
carregando tudo em um Data Warehouse PostgreSQL. A solução deve ser declarativa,
versionável e idempotente.

**Decisão**  
Meltano 3.9.3 com `tap-postgres` + `tap-csv` -> `target-postgres`.

**Justificativa**  
- Exigência da certificação (Meltano ou Embulk para EL).
- O protocolo Singer separa extração e carga de forma padronizada - qualquer tap pode ser
  substituído sem alterar o loader.
- `meltano.yml` é versionável e descreve toda a configuração de ingestão em um único arquivo.
- `meltano run <job>` é chamado via `BashOperator` no Airflow, mantendo o acoplamento mínimo.

**Trade-offs aceitos**  
- Meltano e Airflow compartilham o mesmo container mas com instalações Python separadas
  (`tool-venv`) para evitar conflitos de dependência (SQLAlchemy 1.x vs 2.x).
- O `tap-csv` é instalado via Git (`pip_url: git+https://...`) pois o release oficial não
  suporta todos os campos necessários.

---

## 3. Replicação: FULL_TABLE (sem incremental)

**Contexto**  
As tabelas fonte (ERP simulado) são pequenas (10-2.000 linhas) e não possuem coluna de
`updated_at` confiável que permita replicação incremental segura.

**Decisão**  
`default_replication_method: FULL_TABLE` no `tap-postgres`.  
`activate_version: false` e `add_record_metadata: false` no `target-postgres`.

**Justificativa**  
- Para volumes pequenos, FULL_TABLE é mais simples, mais previsível e igualmente rápido.
- `activate_version: false` evita que o Singer gerencie versões de tabela - o `target-postgres`
  já substitui o conteúdo da tabela a cada execução.
- `add_record_metadata: false` evita colunas `_sdc_*` que complicariam os modelos dbt
  downstream sem agregar valor neste case.
- Resultado: idempotência garantida na camada de ingestão - reexecutar a DAG no mesmo dia
  produz exatamente o mesmo estado em `raw.*`.

**Trade-offs aceitos**  
- Em produção com tabelas de milhões de linhas, FULL_TABLE seria inviável. A migração para
  `INCREMENTAL` exigiria a adição de colunas `updated_at` no fonte e lógica de merge no target.
- A ausência de `add_record_metadata` inviabiliza freshness checks no dbt (`loaded_at` não existe).
  Isso foi documentado em `_sources.yml` como limitação aceita.

---

## 4. Transformação: dbt Core

**Contexto**  
Os dados brutos precisam ser limpos, renomeados (de português para inglês), tipados
corretamente e agregados em modelos analíticos para consumo pelo Metabase.

**Decisão**  
dbt Core 1.9 com `dbt-postgres` adapter. Duas camadas: `staging` (views) e `marts` (tables).

**Justificativa**  
- dbt é o padrão de mercado para transformação SQL declarativa, com versionamento, testes
  integrados e geração automática de documentação.
- A separação staging/marts segue a arquitetura Medallion: a camada `staging` é a verdade
  limpa sobre a fonte; os `marts` são os modelos orientados a decisão de negócio.
- O profile dbt lê credenciais de variáveis de ambiente - sem segredos em `profiles.yml`.

**Trade-offs aceitos**  
- dbt Core não tem scheduler próprio - depende do Airflow para orquestração, o que é
  desejável neste contexto (separação de responsabilidades).
- O container `dbt` no Docker Compose existe apenas como ambiente de execução; em produção,
  o dbt rodaria dentro do container do Airflow (mesma abordagem do `BashOperator`).

---

## 5. Materialização: `view` para staging, `table` para marts

**Contexto**  
Precisamos definir como cada camada dbt é materializada no banco.

**Decisão**  
- `staging/*`: `materialized=view`
- `marts/*`: `materialized=table`

**Justificativa**  
- **Views de staging** são leves, não armazenam dados duplicados e refletem sempre o estado
  atual do `raw.*`. Se os dados brutos mudam, a staging atualiza automaticamente.
- **Tables de marts** são necessárias porque o Metabase consulta os marts diretamente -
  queries sobre views aninhadas em views seriam mais lentas e menos previsíveis.
- `materialized=table` no dbt executa `DROP TABLE IF EXISTS` + `CREATE TABLE AS SELECT`,
  garantindo idempotência total: reexecutar `dbt run` nunca gera duplicação.

**Trade-offs aceitos**  
- Tables consomem espaço em disco. Para um case pequeno, irrelevante. Em escala, seria
  avaliado `materialized=incremental` para modelos de fato com alto volume de inserções diárias.

---

## 6. Gate de Validação: `validate_raw_load` antes do dbt

**Contexto**  
Se o Meltano falhar silenciosamente (e.g. conectar mas não extrair nenhuma linha), o dbt
executaria sobre tabelas vazias, criando marts vazios sem erro explícito. O pipeline
sinalizaria sucesso com dados incorretos.

**Decisão**  
`PythonOperator validate_raw_load` posicionado **entre** os tasks de EL e o `dbt_run`.
Falha se qualquer tabela `raw.*` tiver `COUNT(*) = 0`.

**Justificativa**  
- **Early-fail**: detecta o problema na camada mais barata de computar (COUNT simples)
  antes de disparar todo o processamento dbt.
- **Clareza de erro**: o operador lança `ValueError` com a lista exata das tabelas vazias,
  facilitando o diagnóstico.
- **Idempotência protegida**: impede que uma execução com EL vazio sobrescreva marts
  previamente populados por uma execução bem-sucedida anterior.

**Trade-offs aceitos**  
- Adiciona uma task ao DAG e um round-trip ao banco. O custo é desprezível dado o volume.
- Apenas verifica `COUNT > 0`, não valida conteúdo. Testes dbt mais granulares (not_null,
  relationships) completam a cobertura na etapa `dbt_test`.

---

## 7. Topologia da DAG: EL paralelo com gate centralizado

**Contexto**  
Temos duas fontes independentes: o banco PostgreSQL (ERP) e o CSV de transações. Ambas
precisam ser ingeridas antes que o dbt possa rodar.

**Decisão**  
```
FileSensor -> [el_sql ∥ el_csv] -> validate_raw_load -> dbt_run -> dbt_test
```
Os dois tasks de EL rodam **em paralelo** e convergem no gate de validação.

**Justificativa**  
- O EL do CSV e o EL SQL são independentes - nenhum precisa aguardar o outro.
- Paralelismo reduz o tempo total de execução (ambos rodam simultâneos, limitados por I/O
  do banco de destino).
- O `validate_raw_load` como ponto de convergência garante que **ambas** as cargas
  completaram com sucesso antes do dbt iniciar.

**Trade-offs aceitos**  
- `LocalExecutor` com `max_active_runs=1` limita o paralelismo real ao número de workers
  configurados. Para este case, 1 worker é suficiente e o paralelismo é lógico,
  não necessariamente físico.

---

## 8. Arquitetura Medallion (raw -> staging -> marts)

**Contexto**  
Os dados transitam de uma fonte operacional (ERP) até um destino analítico (Metabase).
Precisamos de separação clara entre dados brutos, dados limpos e dados orientados a negócio.

**Decisão**  
Três schemas no `analytics_dw`:
- `raw` (Bronze): dados brutos, estrutura da fonte, gerenciado pelo Meltano.
- `staging` (Silver): dados limpos, renomeados, tipados - gerenciado pelo dbt.
- `marts` (Gold): modelos analíticos agregados - gerenciado pelo dbt.

**Justificativa**  
- **Isolamento de responsabilidade**: Meltano não precisa saber nada sobre a lógica de negócio;
  dbt não precisa lidar com dados brutos inconsistentes.
- **Rastreabilidade**: qualquer anomalia pode ser investigada camada a camada (`raw -> staging -> mart`).
- **Reprocessamento seguro**: `dbt run` pode ser reexecutado sem afetar `raw.*`, e vice-versa.
- **Padrão de mercado**: Medallion (bronze/silver/gold) é amplamente adotado em Databricks,
  Snowflake, BigQuery e plataformas open-source.

**Trade-offs aceitos**  
- Três schemas significam três vezes o custo de armazenamento para os mesmos dados.
  Aceitável neste case; em produção seria mitigado com `materialized=view` em staging.

---

## 9. Qualidade de Dados: testes dbt + meta_data_quality

**Contexto**  
A certificação exige evidência de que o pipeline detecta e reporta problemas de qualidade.
O dado fonte possui uma inconsistência conhecida: `cod_cliente=528` existe em `contas` e
`propostas_credito` mas não na tabela `clientes`.

**Decisão**  
Dois mecanismos complementares:
1. **Testes dbt** declarados em YAML (`unique`, `not_null`, `relationships`, `accepted_values`,
   `dbt_utils`) - executados no step `dbt_test`.
2. **`meta_data_quality` view** - dashboard SQL que agrega PASS/FAIL dos testes diretamente
   no banco, consultável via Metabase ou psql.
3. **`metadata.test_results` table** - populada pela macro `populate_test_results()` no
   `on-run-end` do dbt, persiste histórico de execuções.

**Justificativa**  
- O teste de `relationships` com `severity: warn` captura a inconsistência do `cod_cliente=528`
  sem interromper o pipeline - demonstra que a camada Silver detecta defeitos antes de
  contaminar a Gold.
- `meta_data_quality` torna os resultados observáveis para stakeholders não-técnicos via
  Metabase, sem necessidade de acesso ao terminal.

**Trade-offs aceitos**  
- A macro `populate_test_results()` usa `run_query()` (SQL executado no banco durante
  a compilação dbt), que não é transacional. Uma falha parcial pode deixar resultados
  incompletos em `metadata.test_results`. Mitigação: o campo `executed_at DEFAULT NOW()`
  permite filtrar execuções incompletas.

---

## 10. Infraestrutura: Docker Compose (dev) + Kind (prod)

**Contexto**  
O ambiente precisa rodar localmente para desenvolvimento e ser demonstrável em modo
Kubernetes para atender à exigência de IaC + K8s da certificação.

**Decisão**  
Dois modos de execução:
- **Docker Compose**: ambiente de desenvolvimento completo (`make up`), 7 serviços.
- **Kind + Helm**: cluster Kubernetes local simulando produção (`make kind-up` + `make kind-deploy`).

**Justificativa**  
- Docker Compose é o caminho mais rápido para desenvolvimento e demonstração local.
- Kind permite validar os manifests Kubernetes sem custo de cloud.
- A separação entre modos garante que o mesmo código funciona nos dois ambientes -
  a imagem Docker é a mesma, apenas o orquestrador muda.
- Secrets são gerenciados via `.env` (Compose) e `k8s/secrets.yaml` (Kind) - ambos
  gitignored; apenas exemplos versionados.

**Trade-offs aceitos**  
- Kind não é produção real. Limitações de rede, storage e scheduling do Kind não refletem
  um cluster gerenciado (EKS/GKE/AKS). Para produção real, o Helm chart do Airflow
  (`k8s/airflow/values.yaml`) precisaria de ajustes de recursos e persistent volumes.

---

## 11. Testes: pytest com separação unit / integration

**Contexto**  
O pipeline usa Airflow, que tem dependências pesadas. Rodar todos os testes contra um
banco real a cada push tornaria o CI lento e frágil.

**Decisão**  
72 testes pytest divididos em duas categorias via `pytest.mark`:
- **Unit** (`not integration`): 41 testes - rodam sem banco
  (18 de integridade de DAG + 10 de resiliência + 6 de configuração Meltano
  + 7 de governança/cobertura dos modelos dbt).
  Usados no CI (GitHub Actions job de testes unitários).
- **Integration** (`-m integration`): 31 testes - requerem `docker compose up`
  (2 de idempotência + 20 de contagem fonte vs destino + 9 dos marts analíticos),
  vários expandidos por `parametrize`. Rodam via `make test-integration`.

Além dos testes pytest, o dbt declara 69 data tests (`unique`, `not_null`,
`relationships`, `accepted_values`, `accepted_range`, `expression_is_true`)
executados na etapa `dbt_test`.

**Justificativa**  
- Testes unitários de DAG (topologia, configuração, callbacks) são determinísticos e rápidos.
  Não há motivo para um banco real nessa camada.
- Testes de integração (row counts, PKs) precisam do banco real pois verificam dados, não código.
- A separação permite CI rápido sem abrir mão de cobertura de integração no ambiente local.

**Trade-offs aceitos**  
- O Meltano não pode ser invocado nos testes de integração dentro do container Airflow por
  conflito de SQLAlchemy (1.x no Airflow vs 2.x no Meltano). O `test_el_sql_idempotent_counts`
  usa skip gracioso (`pytest.skip`) quando o subprocess Meltano falha, preservando a validação
  de Layer 1 (counts estruturais).
