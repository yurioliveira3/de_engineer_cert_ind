"""Configuração global de testes - env vars Airflow e fixtures compartilhadas."""
from __future__ import annotations

import os
import sys
from pathlib import Path
from typing import TYPE_CHECKING

import psycopg2
import pytest

if TYPE_CHECKING:
    import pytest as _pytest


def pytest_configure(config: "_pytest.config.Config") -> None:
    config.addinivalue_line(
        "markers",
        "integration: testes que requerem docker compose up e dados carregados",
    )

# Airflow precisa de uma string de conexão válida mesmo em modo teste
os.environ.setdefault("AIRFLOW__DATABASE__SQL_ALCHEMY_CONN", "sqlite:////tmp/airflow_test.db")
os.environ.setdefault("AIRFLOW__CORE__UNIT_TEST_MODE", "True")
os.environ.setdefault("AIRFLOW__CORE__LOAD_EXAMPLES", "False")
os.environ.setdefault(
    "AIRFLOW__CORE__FERNET_KEY",
    "zTfpnAh-4m0zNe9q87RkRr3vXG6dNnKw0fPQWpHjmY0=",
)

PROJECT_ROOT = Path(__file__).parent.parent
# dags/ no sys.path para que `from callbacks import on_task_failure` funcione no DagBag
sys.path.insert(0, str(PROJECT_ROOT / "dags"))


@pytest.fixture(scope="module")
def dw_conn():
    conn = psycopg2.connect(
        host=os.getenv("DW_POSTGRES_HOST", "localhost"),
        port=int(os.getenv("DW_POSTGRES_PORT", "5433")),
        user=os.getenv("DW_POSTGRES_USER", "analytics"),
        password=os.getenv("DW_POSTGRES_PASSWORD", ""),
        dbname=os.getenv("DW_POSTGRES_DB", "analytics_dw"),
    )
    yield conn
    conn.close()
