from __future__ import annotations

import logging
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from airflow.models import TaskInstance

log = logging.getLogger(__name__)


def on_task_failure(context: dict) -> None:
    ti: TaskInstance = context["task_instance"]
    log.error(
        "[banvic_elt] FALHA | dag=%s task=%s run_id=%s tentativa=%s",
        ti.dag_id,
        ti.task_id,
        ti.run_id,
        ti.try_number,
    )
    log.error("Exceção: %s", context.get("exception"))
