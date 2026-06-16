"""
DAG: banvic_elt
Orquestra o pipeline ELT completo do case BanVic:
  FileSensor -> [EL SQL || EL CSV] -> validate_raw_load -> dbt run -> dbt test

Ingestão via Meltano (Singer):
 - tap-postgres -> 6 tabelas ERP (source-postgres) -> target-postgres (raw.*)
 - tap-csv -> transacoes.csv -> target-postgres (raw.transacoes)

Transformação via dbt Core (staging -> marts).
"""

from __future__ import annotations

import logging
from datetime import timedelta

import pendulum
from airflow import DAG
from airflow.operators.bash import BashOperator
from airflow.operators.python import PythonOperator
from airflow.providers.postgres.hooks.postgres import PostgresHook
from airflow.sensors.filesystem import FileSensor

from callbacks import on_task_failure

log = logging.getLogger(__name__)

TZ = pendulum.timezone("America/Sao_Paulo")
MELTANO_ROOT = "/opt/airflow/meltano"
DBT_ROOT = "/opt/airflow/dbt_project"
LANDING_CSV = "/opt/airflow/data/landing/transacoes.csv"
_DBT_ARGS = f"--profiles-dir {DBT_ROOT} --project-dir {DBT_ROOT}"

EXPECTED_RAW_TABLES = [
    "agencias",
    "clientes",
    "colaboradores",
    "colaborador_agencia",
    "contas",
    "propostas_credito",
    "transacoes",
]

DOC_MD = """\
## Pipeline ELT - BanVic

| Etapa | Ferramenta | Detalhes |
|---|---|---|
| Extract + Load SQL | Meltano tap-postgres | 6 tabelas ERP -> raw.* |
| Extract + Load CSV | Meltano tap-csv | transacoes.csv -> raw.transacoes |
| Transform | dbt Core | raw -> staging -> marts |
| Validação | PythonOperator | row count > 0 em todas as 7 tabelas |

**Idempotência:** Meltano usa FULL_TABLE (recria raw.*); dbt usa `table` (DROP+CREATE).
Re-execuções do mesmo `logical_date` produzem o mesmo estado sem duplicação.
"""

default_args = {
    "retries": 2,
    "retry_delay": timedelta(minutes=5),
    "retry_exponential_backoff": True,
    "execution_timeout": timedelta(hours=1),
    "on_failure_callback": on_task_failure,
}


def _validate_load() -> None:
    hook = PostgresHook(postgres_conn_id="dw_postgres")
    missing = []
    for table in EXPECTED_RAW_TABLES:
        count = hook.get_first(f'SELECT COUNT(*) FROM raw."{table}"')[0]
        log.info("raw.%s -> %d linhas", table, count)
        if count == 0:
            missing.append(table)
    if missing:
        raise ValueError(f"Tabelas com 0 linhas após ingestão: {missing}")
    log.info("Validação concluída - todas as %d tabelas populadas.", len(EXPECTED_RAW_TABLES))


with DAG(
    dag_id="banvic_elt",
    description="Pipeline ELT BanVic: Meltano (EL) + dbt (T)",
    start_date=pendulum.datetime(2025, 1, 1, tz=TZ),
    # Em produção seria "35 4 * * *" (04:35 BRT). schedule=None aqui porque o projeto
    # é entregável de certificação — as runs são disparadas manualmente para demonstração.
    schedule=None,
    catchup=False,
    max_active_runs=1,
    default_args=default_args,
    tags=["banvic", "elt"],
    doc_md=DOC_MD,
) as dag:

    wait_transacoes = FileSensor(
        task_id="wait_transacoes_csv",
        filepath=LANDING_CSV,
        poke_interval=30,
        timeout=300,
        mode="reschedule",
    )

    el_sql = BashOperator(
        task_id="el_extract_load_sql",
        bash_command=f"cd {MELTANO_ROOT} && meltano run el-sql",
    )

    el_csv = BashOperator(
        task_id="el_extract_load_csv",
        bash_command=f"cd {MELTANO_ROOT} && meltano run el-csv",
    )

    validate_raw = PythonOperator(
        task_id="validate_raw_load",
        python_callable=_validate_load,
    )

    dbt_run = BashOperator(
        task_id="dbt_run",
        bash_command=f"cd {DBT_ROOT} && dbt deps {_DBT_ARGS} && dbt run {_DBT_ARGS}",
    )

    dbt_test = BashOperator(
        task_id="dbt_test",
        bash_command=f"cd {DBT_ROOT} && dbt test {_DBT_ARGS}",
    )

    wait_transacoes >> [el_sql, el_csv] >> validate_raw >> dbt_run >> dbt_test
