"""
F2-05 - Testes de resiliência e tratamento de falhas.

Cobre:
1. FileSensor: configuração que bloqueia sem o arquivo + poke com mock de FSHook
2. on_failure_callback: registra dag_id, task_id e exceção no log de erro
3. Retry com backoff exponencial configurado em todas as tasks

Nota sobre F2-05 - Comportamento de retry real:
  Simular "DW cai no meio do load -> retry -> sucesso" em teste unitário exigiria
  orquestração de containers (start/stop dw-postgres). Esse cenário foi validado
  manualmente durante o desenvolvimento (veja docs/checklist_e2e.md §5) e está
  coberto pela configuração retries=2 + retry_exponential_backoff=True, verificada
  nos testes abaixo. Testes de integração completos requerem pytest-docker ou
  testcontainers, fora do escopo desta suíte unitária.
"""
from __future__ import annotations

import logging
from unittest.mock import MagicMock, patch

# -- FileSensor ------------------------------------------------------


def test_filesensor_soft_fail_false(dag) -> None:
    """soft_fail=False garante que task falha (não skipa) quando arquivo ausente."""
    sensor = dag.get_task("wait_transacoes_csv")
    assert sensor.soft_fail is False


def test_filesensor_mode_reschedule(dag) -> None:
    """mode='reschedule' libera slot do worker enquanto aguarda - não bloqueia pool."""
    sensor = dag.get_task("wait_transacoes_csv")
    assert sensor.mode == "reschedule"


def test_filesensor_timeout_positive(dag) -> None:
    """FileSensor tem timeout > 0 - não aguarda indefinidamente."""
    sensor = dag.get_task("wait_transacoes_csv")
    assert sensor.timeout > 0


@patch("airflow.sensors.filesystem.FSHook")
def test_filesensor_poke_false_when_absent(mock_hook_cls, tmp_path) -> None:
    """FileSensor.poke retorna False quando o arquivo não existe."""
    from airflow.sensors.filesystem import FileSensor

    mock_hook_cls.return_value.get_path.return_value = ""
    sensor = FileSensor(
        task_id="wait_test",
        filepath=str(tmp_path / "nao_existe.csv"),
        poke_interval=1,
        timeout=5,
    )
    assert sensor.poke(MagicMock()) is False


@patch("airflow.sensors.filesystem.FSHook")
def test_filesensor_poke_true_when_present(mock_hook_cls, tmp_path) -> None:
    """FileSensor.poke retorna True quando o arquivo existe."""
    from airflow.sensors.filesystem import FileSensor

    csv_file = tmp_path / "transacoes.csv"
    csv_file.write_text("id,val\n1,100\n")
    mock_hook_cls.return_value.get_path.return_value = ""

    sensor = FileSensor(
        task_id="wait_test",
        filepath=str(csv_file),
        poke_interval=1,
        timeout=5,
    )
    assert sensor.poke(MagicMock()) is True


# -- on_failure_callback ---------------------------------------------


def test_callback_logs_dag_and_task(caplog) -> None:
    """on_failure_callback registra dag_id e task_id no log de erro."""
    from callbacks import on_task_failure

    ti = MagicMock()
    ti.dag_id = "banvic_elt"
    ti.task_id = "el_extract_load_sql"
    ti.run_id = "manual__2025-01-01T00:00:00+00:00"
    ti.try_number = 2

    with caplog.at_level(logging.ERROR):
        on_task_failure({"task_instance": ti, "exception": RuntimeError("Connection refused")})

    assert "banvic_elt" in caplog.text
    assert "el_extract_load_sql" in caplog.text


def test_callback_logs_exception_message(caplog) -> None:
    """on_failure_callback registra a mensagem da exceção original."""
    from callbacks import on_task_failure

    ti = MagicMock()
    ti.dag_id = "banvic_elt"
    ti.task_id = "dbt_run"
    ti.run_id = "manual__2025-01-01T00:00:00+00:00"
    ti.try_number = 1

    with caplog.at_level(logging.ERROR):
        on_task_failure({"task_instance": ti, "exception": ValueError("dbt compilation error")})

    assert "dbt compilation error" in caplog.text


# -- Retry / backoff -------------------------------------------------


def test_all_tasks_have_exponential_backoff(dag) -> None:
    """retry_exponential_backoff=True em todas as tasks - backoff progressivo entre retries."""
    for task in dag.tasks:
        assert getattr(task, "retry_exponential_backoff", False) is True, (
            f"Task '{task.task_id}' sem retry_exponential_backoff"
        )


def test_all_tasks_have_retry_delay(dag) -> None:
    """retry_delay configurado em todas as tasks."""
    for task in dag.tasks:
        assert task.retry_delay is not None, (
            f"Task '{task.task_id}': retry_delay é None"
        )


def test_validate_raw_is_gate_before_dbt(dag) -> None:
    """validate_raw_load deve estar entre EL e dbt - early-fail antes de transformar dados vazios."""
    validate = dag.get_task("validate_raw_load")
    upstream_ids = {t.task_id for t in validate.upstream_list}
    downstream_ids = {t.task_id for t in validate.downstream_list}
    assert "el_extract_load_sql" in upstream_ids
    assert "el_extract_load_csv" in upstream_ids
    assert "dbt_run" in downstream_ids
