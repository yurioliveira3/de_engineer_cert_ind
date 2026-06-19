"""
F2-04 - Teste de integridade da DAG (dag integrity test).

Verifica que banvic_elt importa sem erros e tem a estrutura esperada:
topologia, retries, catchup, max_active_runs, tags, on_failure_callback.
Sem subir Airflow completo - usa DagBag + SQLite em memória (conftest.py).
"""

from __future__ import annotations

from datetime import timedelta

from airflow.models import DagBag

DAG_ID = "banvic_elt"


# -- Importação ------------------------------------------------------


def test_no_import_errors(dagbag: DagBag) -> None:
    assert dagbag.import_errors == {}, f"Import errors: {dagbag.import_errors}"


def test_dag_exists(dagbag: DagBag) -> None:
    assert DAG_ID in dagbag.dags, f"DAG '{DAG_ID}' não encontrada no DagBag"


# -- Configuração geral ----------------------------------------------


def test_catchup_false(dag) -> None:
    assert dag.catchup is False, "catchup=False evita backfill acidental de datas passadas"


def test_max_active_runs_one(dag) -> None:
    assert dag.max_active_runs == 1, "max_active_runs=1 previne lock concorrente no Meltano"


def test_tags_present(dag) -> None:
    assert dag.tags, "DAG deve ter ao menos uma tag para categorização na UI"


def test_schedule_is_none(dag) -> None:
    # schedule=None: projeto educacional — runs disparadas manualmente para demonstração.
    # Em produção seria "35 4 * * *" (04:35 BRT).
    assert dag.schedule_interval is None, (
        f"schedule esperado None (manual), obtido '{dag.schedule_interval}'"
    )


def test_start_date_timezone_sao_paulo(dag) -> None:
    # dag.start_date é normalizado para UTC pelo Airflow; dag.timezone preserva o tz original.
    tz_name = str(dag.timezone)
    assert "Sao_Paulo" in tz_name, f"DAG deve usar timezone America/Sao_Paulo, obtido: {tz_name}"


def test_all_tasks_have_execution_timeout(dag) -> None:
    for task in dag.tasks:
        assert task.execution_timeout is not None, (
            f"Task '{task.task_id}' sem execution_timeout - risco de hang infinito"
        )


def test_retry_delay_is_five_minutes(dag) -> None:
    for task in dag.tasks:
        assert task.retry_delay == timedelta(minutes=5), (
            f"Task '{task.task_id}': retry_delay inesperado ({task.retry_delay})"
        )


# -- Tasks: retries e callbacks --------------------------------------


def test_all_tasks_have_retries(dag) -> None:
    for task in dag.tasks:
        assert task.retries >= 1, (
            f"Task '{task.task_id}' tem retries={task.retries} - mínimo esperado: 1"
        )


def test_all_tasks_have_failure_callback(dag) -> None:
    for task in dag.tasks:
        assert task.on_failure_callback is not None, (
            f"Task '{task.task_id}' sem on_failure_callback - falhas silenciosas não aceitáveis"
        )


# -- Topologia -------------------------------------------------------


def test_expected_task_ids(dag) -> None:
    expected = {
        "wait_transacoes_csv",
        "el_extract_load_sql",
        "el_extract_load_csv",
        "validate_raw_load",
        "dbt_run",
        "dbt_test",
    }
    actual = {t.task_id for t in dag.tasks}
    assert expected == actual, f"Diferença nas tasks: {expected.symmetric_difference(actual)}"


def test_topology_sensor_is_root(dag) -> None:
    sensor = dag.get_task("wait_transacoes_csv")
    assert sensor.upstream_list == [], "FileSensor deve ser a task raiz (sem upstream)"


def test_topology_el_tasks_depend_on_sensor(dag) -> None:
    for task_id in ("el_extract_load_sql", "el_extract_load_csv"):
        upstream = {t.task_id for t in dag.get_task(task_id).upstream_list}
        assert "wait_transacoes_csv" in upstream, f"{task_id} deve depender de wait_transacoes_csv"


def test_topology_el_tasks_are_parallel(dag) -> None:
    """el_sql e el_csv não têm dependência entre si - rodam em paralelo."""
    el_sql_upstream = {t.task_id for t in dag.get_task("el_extract_load_sql").upstream_list}
    el_csv_upstream = {t.task_id for t in dag.get_task("el_extract_load_csv").upstream_list}
    assert "el_extract_load_csv" not in el_sql_upstream
    assert "el_extract_load_sql" not in el_csv_upstream


def test_topology_validate_raw_after_both_el(dag) -> None:
    """validate_raw_load é o gate entre EL e dbt - garante early-fail antes de transformar."""
    upstream = {t.task_id for t in dag.get_task("validate_raw_load").upstream_list}
    assert upstream == {"el_extract_load_sql", "el_extract_load_csv"}


def test_topology_dbt_run_after_validate(dag) -> None:
    upstream = {t.task_id for t in dag.get_task("dbt_run").upstream_list}
    assert "validate_raw_load" in upstream


def test_topology_dbt_test_is_leaf(dag) -> None:
    dbt_test = dag.get_task("dbt_test")
    assert dbt_test.downstream_list == [], "dbt_test deve ser a task folha"
    upstream = {t.task_id for t in dbt_test.upstream_list}
    assert "dbt_run" in upstream
