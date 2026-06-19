"""
Governanca de modelos dbt: garante que todo modelo SQL esta documentado e
testado nos arquivos _*.yml. Sao testes unitarios - leem os arquivos do
projeto, sem banco. Pegam regressoes de cobertura (modelo novo sem teste).
"""

from __future__ import annotations

from pathlib import Path

import pytest
import yaml

PROJECT_ROOT = Path(__file__).parents[2]
MODELS_DIR = PROJECT_ROOT / "dbt_project" / "models"

YML_BY_LAYER = {
    "staging": MODELS_DIR / "staging" / "_stg_models.yml",
    "marts": MODELS_DIR / "marts" / "_marts_models.yml",
}


def _yml_models(yml_path: Path) -> dict:
    data = yaml.safe_load(yml_path.read_text())
    return {m["name"]: m for m in data["models"]}


def _sql_model_names(layer_dir: Path) -> set[str]:
    return {p.stem for p in layer_dir.glob("*.sql")}


def _model_has_test(model: dict) -> bool:
    if model.get("tests"):
        return True
    return any(col.get("tests") for col in model.get("columns", []))


@pytest.mark.parametrize("layer", ["staging", "marts"])
def test_all_sql_models_have_yml_entry(layer: str) -> None:
    documented = set(_yml_models(YML_BY_LAYER[layer]))
    on_disk = _sql_model_names(MODELS_DIR / layer)
    missing = on_disk - documented
    assert not missing, f"Modelos {layer} sem entrada no _*.yml: {sorted(missing)}"


@pytest.mark.parametrize("layer", ["staging", "marts"])
def test_all_models_have_description(layer: str) -> None:
    models = _yml_models(YML_BY_LAYER[layer])
    no_desc = [n for n, m in models.items() if not str(m.get("description", "")).strip()]
    assert not no_desc, f"Modelos {layer} sem description: {sorted(no_desc)}"


@pytest.mark.parametrize("layer", ["staging", "marts"])
def test_all_models_have_at_least_one_test(layer: str) -> None:
    models = _yml_models(YML_BY_LAYER[layer])
    untested = [n for n, m in models.items() if not _model_has_test(m)]
    assert not untested, f"Modelos {layer} sem nenhum teste declarado: {sorted(untested)}"


def test_business_marts_present_and_tested() -> None:
    """Os marts de narrativa (Camila + CEO) existem, estao no yml e tem testes."""
    marts = _yml_models(YML_BY_LAYER["marts"])
    on_disk = _sql_model_names(MODELS_DIR / "marts")
    for required in (
        "mart_engajamento_cliente",
        "mart_kpi_comercial",
        "mart_ranking_alavancas",
    ):
        assert required in on_disk, f"Modelo SQL ausente: {required}.sql"
        assert required in marts, f"Mart sem entrada no yml: {required}"
        assert _model_has_test(marts[required]), f"Mart sem testes: {required}"
