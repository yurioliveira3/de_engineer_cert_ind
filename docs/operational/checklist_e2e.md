# Checklist E2E - BanVic ELT Pipeline

> **Objetivo**: roteiro reproduzível para validar o pipeline do zero ao dado no destino.
> Serve como guia de demonstração para o vídeo de entrega.

---

## Pré-requisitos

```bash
# Ferramentas necessárias
docker --version        # >= 24.0
docker compose version  # >= 2.24
kind version            # >= 0.23 (para modo K8s)
helm version            # >= 3.14 (para modo K8s)
kubectl version         # >= 1.29 (para modo K8s)
```

Arquivo `.env` preenchido a partir do `.env.example`:

```bash
cp .env.example .env
# Edite .env com as senhas desejadas
```

---

## Modo 1 - Docker Compose (desenvolvimento)

### 1. Subir o ambiente

```bash
make up
# Aguardar: "OK  Ambiente subindo. Airflow: http://localhost:8080  Metabase: http://localhost:3000"
```

**Resultado esperado**: todos os serviços healthy.

```bash
docker compose ps
# NAME                    STATUS
# source-postgres         healthy
# dw-postgres             healthy
# airflow-db              healthy
# airflow-webserver       healthy
# airflow-scheduler       healthy
# dbt                     running
# metabase                running
```

### 2. Verificar carga inicial do source-postgres

```bash
docker compose exec source-postgres \
  psql -U banvic -d banvic -c "
    SELECT schemaname, tablename, n_live_tup AS rows
    FROM pg_stat_user_tables ORDER BY tablename;"
```

**Resultado esperado**:

| tablename | rows |
|---|---|
| agencias | 10 |
| clientes | 998 |
| colaborador_agencia | 100 |
| colaboradores | 100 |
| contas | 999 |
| propostas_credito | 2000 |

### 3. Trigger manual da DAG

Acesse http://localhost:8080 -> login `admin` / senha do `.env` -> DAG `banvic_elt` -> "Trigger DAG".

Ou via CLI:

```bash
docker compose exec airflow-scheduler \
  airflow dags trigger banvic_elt
```

### 4. Acompanhar execução

```bash
# Logs do scheduler em tempo real
make logs-airflow

# Ou verificar status via CLI
docker compose exec airflow-scheduler \
  airflow dags list-runs -d banvic_elt --limit 3
```

**Resultado esperado**: todos os 6 tasks com estado `success`.

```
wait_transacoes_csv     -> success
el_extract_load_sql     -> success
el_extract_load_csv     -> success
dbt_run                 -> success
dbt_test                -> success  (45 PASS, 2 WARN - client_id=528, documentado)
validate_load           -> success
```

### 5. Verificar raw.* no DW

```bash
docker compose exec dw-postgres \
  psql -U analytics -d analytics_dw -c "
    SELECT schemaname, tablename, n_live_tup AS rows
    FROM pg_stat_user_tables
    WHERE schemaname = 'raw'
    ORDER BY tablename;"
```

**Resultado esperado**:

| tablename | rows |
|---|---|
| agencias | 10 |
| clientes | 998 |
| colaborador_agencia | 100 |
| colaboradores | 100 |
| contas | 999 |
| propostas_credito | 2000 |
| transacoes | 71999 |

### 6. Verificar marts

```bash
docker compose exec dw-postgres \
  psql -U analytics -d analytics_dw -c "
    SELECT table_name, (
      SELECT COUNT(*) FROM analytics_dw.marts.\"\" || table_name || \"\"
    ) AS rows
    FROM information_schema.tables
    WHERE table_schema = 'marts'
    ORDER BY table_name;" 2>/dev/null || \
docker compose exec dw-postgres \
  psql -U analytics -d analytics_dw -c "
    SELECT 'fct_atividade_contas' AS mart, COUNT(*) FROM marts.fct_atividade_contas
    UNION ALL
    SELECT 'fct_funil_credito', COUNT(*) FROM marts.fct_funil_credito
    UNION ALL
    SELECT 'fct_performance_agencia', COUNT(*) FROM marts.fct_performance_agencia
    UNION ALL
    SELECT 'fct_volume_diario_transacoes', COUNT(*) FROM marts.fct_volume_diario_transacoes
    UNION ALL
    SELECT 'mart_kpi_resumo_credito', COUNT(*) FROM marts.mart_kpi_resumo_credito
    UNION ALL
    SELECT 'mart_oportunidade_crosssell', COUNT(*) FROM marts.mart_oportunidade_crosssell;"
```

### 7. Teste de idempotência manual

```bash
# Acionar a DAG novamente com a mesma data
docker compose exec airflow-scheduler \
  airflow dags trigger banvic_elt

# Aguardar conclusão, depois verificar que contagens são idênticas
docker compose exec dw-postgres \
  psql -U analytics -d analytics_dw -c "SELECT COUNT(*) FROM raw.transacoes;"
# Deve retornar 71999 - sem duplicação
```

### 8. Teardown

```bash
make down
# Remove containers E volumes - estado limpo para próximo deploy
```

---

## Modo 2 - Kubernetes / Kind (entrega)

### 1. Criar cluster

```bash
make kind-up
# Cria cluster 'banvic' com 1 control-plane + 2 workers
```

### 2. Construir e carregar imagem

```bash
make build
make kind-load
# Carrega banvic-airflow:latest no registry interno do Kind
```

### 3. Criar secrets K8s

```bash
# Gerar k8s/secrets.yaml a partir do .env
python3 - <<'EOF'
import base64, os
from pathlib import Path
from dotenv import dotenv_values

env = dotenv_values(".env")
keys = [
    "SOURCE_POSTGRES_USER", "SOURCE_POSTGRES_PASSWORD",
    "DW_POSTGRES_USER", "DW_POSTGRES_PASSWORD",
    "AIRFLOW_DB_USER", "AIRFLOW_DB_PASSWORD",
    "AIRFLOW_FERNET_KEY", "AIRFLOW__WEBSERVER__SECRET_KEY",
]
lines = ["apiVersion: v1", "kind: Secret", "metadata:", "  name: banvic-secrets",
         "  namespace: banvic", "type: Opaque", "data:"]
for k in keys:
    v = base64.b64encode(env[k].encode()).decode()
    lines.append(f"  {k}: {v}")

# Airflow metadata connection string
conn = f"postgresql+psycopg2://{env['AIRFLOW_DB_USER']}:{env['AIRFLOW_DB_PASSWORD']}@airflow-db:5432/airflow"
v = base64.b64encode(conn.encode()).decode()
lines.append(f"  connection: {v}")

Path("k8s/secrets.yaml").write_text("\n".join(lines))
print("k8s/secrets.yaml gerado.")
EOF
```

### 4. Deploy

```bash
make kind-deploy

# Helm para Airflow (após kind-deploy)
helm repo add apache-airflow https://airflow.apache.org
helm upgrade --install airflow apache-airflow/airflow \
  --version 1.16.0 \
  -n banvic \
  -f k8s/airflow/values.yaml \
  --wait --timeout 10m
```

### 5. Verificar pods

```bash
kubectl get pods -n banvic
# Esperado: source-postgres-0, dw-postgres-0, airflow-db-0, metabase-xxx
# Airflow: scheduler, webserver, triggerer - todos Running
```

### 6. Acessar Airflow

```bash
kubectl port-forward svc/airflow-webserver 8080:8080 -n banvic &
# Acesse: http://localhost:8080
```

### 7. Destruir cluster

```bash
make kind-down
```

---

## Seção 5 - Resiliência (cenários observados em execução real)

### 5.1 FileSensor aguarda arquivo ausente

**Cenário**: `data/landing/transacoes.csv` removido antes do trigger.

**Comportamento observado**:
- `wait_transacoes_csv` entra em estado `up_for_reschedule`
- Poke a cada 30 segundos; não prossegue para `el_extract_load_csv`
- Após timeout (300s / 5min): task falha com `AirflowSensorTimeout`
- `on_failure_callback` registra o erro no log

**Verificação**: restaurar o CSV e re-trigger -> pipeline completa normalmente.

### 5.2 Retry com backoff exponencial

**Configuração verificada** (via `test_resilience.py`):
- `retries=2` em todas as tasks
- `retry_delay=timedelta(minutes=5)`
- `retry_exponential_backoff=True`

**Comportamento**: 1ª falha aguarda 5min -> 2ª falha aguarda 10min -> após 2 retries falha definitivamente e dispara `on_failure_callback`.

### 5.3 Lock concorrente Meltano

**Cenário original** (corrigido na Fase 1): múltiplos runs simultâneos da DAG
competiam pelo mesmo `tap-postgres-to-target-postgres` lock no Meltano.

**Correção**: `max_active_runs=1` na DAG - apenas um run ativo por vez.

**Verificação** (via `test_dag_integrity.py::test_max_active_runs_one`): garante que a correção permanece.

---

## Seção 6 - dbt tests

```bash
# Dentro do container dbt
make dbt-test

# Resultado esperado:
# Finished running 47 tests
# Completed with 45 passed, 2 warnings, 0 errors.
#
# WARN:
#   relationships_stg_contas_client_id__stg_clientes__client_id (severity: warn)
#   relationships_stg_propostas_credito_client_id__stg_clientes__client_id (severity: warn)
#
# Causa: cod_cliente=528 existe em contas e propostas_credito mas não em clientes
# (defeito intencional no dataset para demonstrar detecção de integridade referencial
# pela camada Silver antes de contaminar a Gold).
```

---

## Referência rápida - comandos de diagnóstico

```bash
# Logs do Airflow scheduler
make logs-airflow

# Checar saúde dos serviços
docker compose ps

# Rodar testes unitários (sem DB)
pytest tests/dags/ tests/ingestion/test_idempotency.py -m "not integration" -v

# Rodar testes de integração (com DB - requer make up)
pytest -m integration -v

# Lint
make lint
```
