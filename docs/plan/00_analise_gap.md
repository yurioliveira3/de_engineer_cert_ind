# 00 - Análise de Gap: Estado Atual × Exigências da Certificação

> Objetivo deste documento: **revisar o que falta**. Mapeia cada exigência do desafio
> (etapas + critérios de avaliação) contra o que existe hoje no repositório, com nível
> de severidade para priorização.

## 1. O que a certificação exige

Extraído de `Instruções.docx`.

**Etapas obrigatórias:**
1. **IaC, Conteinerização e Kubernetes** - preparar execução (Airflow) e armazenamento
   (Postgres/MinIO) em **Kubernetes local (Minikube/Kind)**.
2. **Pipeline de Ingestão (ELT)** - usar `banvic_data.zip` como fonte e **Meltano ou Embulk**
   para Extract + Load no destino. Configurar **Extractors (Taps)** e **Loaders (Targets)**.
3. **Orquestração** - **DAGs no Airflow**, tasks com dependências, **Sensores** para
   checar disponibilidade dos arquivos.
4. **Monitoramento e Falhas** - **retries** e **idempotência**.
5. **Documentação Técnica** - arquitetura, escolhas, como rodar localmente.
6. **Apresentação + vídeo (3-5 min)**.

**Critérios de avaliação:**
- Domínio de Infraestrutura (Docker, IaC, Kubernetes).
- Implementação de Ingestão (conexões fonte/destino, movimentação eficiente).
- Orquestração e boas práticas de Airflow.
- Qualidade e resiliência do código.
- **Segurança e gerenciamento de segredos** (não expor credenciais).
- Apresentação da solução.

**Entregáveis:**
- Repositório Git (IaC + config de ingestão + `dags/`).
- `README.md` com **diagrama de arquitetura**, passo a passo e **estratégia de ingestão**.
- Vídeo 3-5 min (deploy + DAG executando + dados chegando no destino).
- **Modelo Conceitual** do projeto.

## 2. O que existe hoje no repositório

| Componente | Local | Estado |
|---|---|---|
| `docker-compose.yml` | raiz | Postgres + dbt + Metabase. Funcional, mas **sem Airflow, sem source DB, sem Meltano**. |
| Carga raw | `postgres/init/0*.sql` | `COPY` direto dos 7 CSVs no schema `raw`. Funciona, mas **não é Meltano/Embulk** - é seed de init. |
| dbt | `dbt_project/` | Maduro: 7 staging (views), 8 marts (facts/marts/metadata), testes de schema, macros, `dbt_utils`. **Bom.** |
| DAG de exemplo | `Dados - Banvic/banvic/dags/banvic_etl.py` | Template fornecido pela Indicium. 3 tasks (`extract_sql`, `extract_csv`, `load_dw`) em Python puro. **Isolada do projeto real, sem Meltano, sem sensores, sem retries.** |
| Compose Airflow exemplo | `Dados - Banvic/banvic/docker/*.yml` | Template. **Senhas hardcoded** (`airflow/airflow`, `dw_admin/dw_admin`). Conflito de portas com o compose da raiz. |
| Queries | `queries/*.sql` | Insights e KPIs de crédito para BI. |
| README | raiz | Descreve **apenas** a stack dbt/Metabase. Não menciona Airflow, Meltano nem Kubernetes. |
| Segredos | `.env` / `.env.example` | `.env` para a stack da raiz (parcial). Compose do template tem credenciais em texto. |
| Dados-fonte | `data/source/` | **Vazio** (gitignored). Os 7 CSVs vêm do Google Drive (ver `Descrição dos dados`). |

## 3. Matriz de Gap (exigência -> status -> ação)

Legenda de severidade: CRITICO Crítico (bloqueia aprovação) · IMPORT Importante · POLISH Polimento.

| # | Exigência | Status atual | Gap | Sev. | Fase |
|---|---|---|---|---|---|
| 1 | Conteinerização (Docker) | compose com Postgres/dbt/Metabase | Falta integrar source DB + Airflow + Meltano num compose coeso | IMPORT | 1 |
| 2 | **Kubernetes local (Kind/Minikube)** | **Ausente** | Criar manifests/Helm + Kind + bootstrap | CRITICO | 1 |
| 3 | Armazenamento (Postgres/MinIO) | Postgres ✓ | OK (Postgres escolhido) | POLISH | - |
| 4 | **Ingestão com Meltano/Embulk** | **Ausente** (init `COPY` + DAG Python) | Implementar projeto Meltano (taps/targets) | CRITICO | 1 |
| 5 | **Extractors (Taps) / Loaders (Targets)** | **Ausente** | `tap-postgres` + `tap-csv` -> `target-postgres` | CRITICO | 1 |
| 6 | Integridade dos dados na carga | parcial (testes dbt) | Reforçar validação fonte->destino | IMPORT | 2 |
| 7 | **DAG real no projeto** | só template isolado | DAG que orquestra Meltano (EL) + dbt (T) | CRITICO | 1 |
| 8 | Tasks com dependências | template tem 3 tasks | Reescrever (sensor -> EL -> T -> validação) | CRITICO | 1 |
| 9 | **Sensores (FileSensor)** | **Ausente** | Sensor de disponibilidade do `transacoes.csv` / fonte | CRITICO | 1 |
| 10 | **Retries** | **Ausente** na DAG | `default_args` com `retries` + `retry_delay` | CRITICO | 1 |
| 11 | **Idempotência** | parcial (DROP/CREATE + partição por data) | Garantir e **testar** re-execução sem duplicar | CRITICO | 1/2 |
| 12 | Monitoramento básico | Ausente | `on_failure_callback`, logs, (SLA) | IMPORT | 1/3 |
| 13 | **Segurança / segredos** | `.env` parcial; **senhas hardcoded no template** | Remover hardcoded; `.env` + k8s Secrets; Airflow Connections via env | CRITICO | 1 |
| 14 | Cobertura de testes (resiliência) | só testes dbt | Testes de ingestão, idempotência, DAG integrity, falha | IMPORT | 2 |
| 15 | CI | Ausente | GitHub Actions (lint + dbt parse + DAG test) | POLISH | 2 |
| 16 | README (diagrama + passo a passo + estratégia) | descreve só dbt/Metabase | Reescrever para arquitetura completa | CRITICO | 1/3 |
| 17 | **Modelo Conceitual** (entregável) | **Ausente** | Diagrama ER/conceitual do BanVic | CRITICO | 3 |
| 18 | Vídeo 3-5 min | Ausente | Roteiro + gravação (deploy -> DAG -> dados) | CRITICO | 3 |
| 19 | Higiene do repositório | logs/`__pycache__` commitados no template | Limpar e consolidar estrutura canônica | IMPORT | 1 |
| 20 | Dashboard comercial + ranking CEO | queries soltas | Materializar dashboard + análise estatística | POLISH | 3 |

## 4. Conflitos e inconsistências a resolver (dívida técnica)

1. **Duas arquiteturas paralelas**: a stack da raiz (dbt/Metabase) e o template
   `Dados - Banvic/banvic` (Airflow/DW) **não conversam**. Precisam ser unificadas num
   único projeto coeso.
2. **Conflito de portas**: raiz mapeia Postgres em `5433`; template mapeia DW em `5433`,
   Airflow-DB em `5434`, e o outro compose usa `55432/55433`. Padronizar.
3. **Credenciais hardcoded** nos compose do template (`airflow/airflow`, `dw_admin`,
   `transpass`, `dwpass`) - viola o critério de segurança. **Remover.**
4. **A DAG-fonte cobre só 3 tabelas** (`clientes`, `contas`, `propostas_credito`); o case
   tem **7 tabelas**. A ingestão Meltano precisa cobrir todas.
5. **Artefatos commitados**: `__pycache__`, `logs/`, dados de execução do template. Devem
   sair do versionamento.
6. **Dados-fonte ausentes**: os 7 CSVs (origem da ingestão) precisam ser obtidos do Drive
   e há que definir o mecanismo de seed (source Postgres + arquivo CSV).
7. **`.env` inconsistente**: `POSTGRES_DB=postgres` enquanto os init criam `analytics_dw`
   e `metabase_app`. Revisar variáveis para a nova topologia (source + DW + airflow meta).

## 5. Diagnóstico em uma frase

> A **camada analítica (dbt + Metabase) está pronta e é um diferencial**, mas o **núcleo
> que o rubric realmente avalia - Kubernetes, ingestão com Meltano e orquestração Airflow
> com sensores/retries/idempotência/segredos - está praticamente ausente** (existe apenas
> um template isolado). O esforço deve concentrar-se em construir esse núcleo e amarrá-lo
> à camada analítica existente.

Próximo passo: [`01_fase1_core_foundation.md`](01_fase1_core_foundation.md).

---

## 6. Status Final - gaps resolvidos

> Este documento registra o **estado inicial** do repositório antes da implementação.
> A tabela abaixo cruza cada gap com o que foi entregue.

| # | Sev. | Resolvido? | Como |
|---|---|---|---|
| 2 | CRITICO | OK | `k8s/` + `make kind-up` + `make kind-deploy` (Helm Airflow) |
| 4 | CRITICO | OK | `meltano/meltano.yml` com `tap-postgres` + `tap-csv` -> `target-postgres` |
| 5 | CRITICO | OK | Jobs Meltano `el-sql` / `el-csv` configurados em `meltano.yml` |
| 7 | CRITICO | OK | `dags/banvic_elt.py` - DAG real integrada ao Meltano e dbt |
| 8 | CRITICO | OK | Topologia: `FileSensor -> [el_sql || el_csv] -> validate_raw_load -> dbt_run -> dbt_test` |
| 9 | CRITICO | OK | `FileSensor` monitorando `transacoes.csv` com `mode=reschedule` |
| 10 | CRITICO | OK | `default_args` com `retries=2`, `retry_exponential_backoff=True` |
| 11 | CRITICO | OK | Meltano FULL_TABLE + dbt `DROP+CREATE TABLE` + `max_active_runs=1` |
| 13 | CRITICO | OK | Credenciais em `.env` e `k8s/secrets.yaml`; `AIRFLOW_CONN_*` via env |
| 16 | CRITICO | OK | README reescrito: diagrama ASCII + Mermaid + passo a passo compose e Kind |
| 17 | CRITICO | OK | `docs/architectures/modelo_conceitual.drawio` + `arquitetura_dados.drawio` |
| 1 | IMPORT | OK | `docker-compose.yml` coeso: source-postgres + dw-postgres + airflow + meltano + dbt + metabase |
| 6 | IMPORT | OK | `validate_raw_load` (gate COUNT > 0) + testes dbt (not_null, relationships, unique) |
| 12 | IMPORT | OK | `on_failure_callback` em `dags/callbacks.py`; log estruturado |
| 14 | IMPORT | OK | 72 testes pytest: 41 unit no CI (18 DAG + 10 resiliência + 6 config Meltano + 7 cobertura dbt) + 31 integração (2 idempotência + 20 contagem + 9 marts analíticos); + 69 data tests dbt |
| 15 | POLISH | OK | GitHub Actions: `dag-tests` + `dbt-parse` + `lint` |
| 19 | IMPORT | OK | `postgres/init/` orphan removido; `.gitignore` cobre `__pycache__`, `logs/`, `data/` |
| 18 | CRITICO | PEND | Vídeo 3-5 min - pendente (F3-06) |
| 20 | POLISH | - | Dashboard Camila + ranking CEO - opcional, não implementado |
