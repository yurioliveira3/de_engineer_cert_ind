from __future__ import annotations

from pathlib import Path

import pytest
from airflow.models import DagBag

DAGS_FOLDER = Path(__file__).parents[2] / "dags"


@pytest.fixture(scope="module")
def dagbag() -> DagBag:
    return DagBag(dag_folder=str(DAGS_FOLDER), include_examples=False)


@pytest.fixture(scope="module")
def dag(dagbag: DagBag):
    return dagbag.dags["banvic_elt"]
