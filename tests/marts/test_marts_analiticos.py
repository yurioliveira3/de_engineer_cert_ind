"""
Testes de integracao dos marts analiticos de negocio (Camila + CEO).
Marca: @pytest.mark.integration - requerem ambiente no ar (Docker Compose ou Kind)
+ DAG executada (marts construidos).
Execute: pytest -m integration tests/marts/test_marts_analiticos.py
"""

from __future__ import annotations

import pytest

VALID_ENGAGEMENT = {"active", "at_risk", "churned", "never_used"}
EXPECTED_DRIVERS = {
    "saldo_total",
    "tempo_relacionamento",
    "posse_credito_aprovado",
}


@pytest.mark.integration
def test_engajamento_client_id_unique(dw_conn) -> None:
    """mart_engajamento_cliente: client_id e PK (sem duplicatas)."""
    with dw_conn.cursor() as cur:
        cur.execute(
            "SELECT count(*) - count(distinct client_id) FROM marts.mart_engajamento_cliente"
        )
        assert cur.fetchone()[0] == 0


@pytest.mark.integration
def test_engajamento_status_values_valid(dw_conn) -> None:
    """Todos os engagement_status estao no dominio esperado."""
    with dw_conn.cursor() as cur:
        cur.execute("SELECT distinct engagement_status FROM marts.mart_engajamento_cliente")
        found = {row[0] for row in cur.fetchall()}
    invalid = found - VALID_ENGAGEMENT
    assert not invalid, f"engagement_status invalido(s): {invalid}"


@pytest.mark.integration
def test_engajamento_no_negative_counts(dw_conn) -> None:
    """transaction_count e account_count nunca negativos."""
    with dw_conn.cursor() as cur:
        cur.execute(
            "SELECT count(*) FROM marts.mart_engajamento_cliente "
            "WHERE transaction_count < 0 OR account_count < 1"
        )
        assert cur.fetchone()[0] == 0


@pytest.mark.integration
def test_kpi_comercial_single_row(dw_conn) -> None:
    """mart_kpi_comercial e um resumo single-row."""
    with dw_conn.cursor() as cur:
        cur.execute("SELECT count(*) FROM marts.mart_kpi_comercial")
        assert cur.fetchone()[0] == 1


@pytest.mark.integration
def test_kpi_comercial_rates_bounded(dw_conn) -> None:
    """Taxas percentuais ficam no intervalo [0, 100]."""
    with dw_conn.cursor() as cur:
        cur.execute(
            "SELECT count(*) FROM marts.mart_kpi_comercial "
            "WHERE taxa_ativos_pct NOT BETWEEN 0 AND 100 "
            "OR taxa_inativos_pct NOT BETWEEN 0 AND 100"
        )
        assert cur.fetchone()[0] == 0


@pytest.mark.integration
def test_kpi_comercial_status_partition(dw_conn) -> None:
    """total_clientes = soma das 4 categorias de engajamento (particao completa)."""
    with dw_conn.cursor() as cur:
        cur.execute(
            "SELECT count(*) FROM marts.mart_kpi_comercial "
            "WHERE total_clientes != clientes_ativos + clientes_em_risco "
            "+ clientes_churned + clientes_sem_uso"
        )
        assert cur.fetchone()[0] == 0


@pytest.mark.integration
def test_ranking_has_expected_drivers(dw_conn) -> None:
    """mart_ranking_alavancas retorna os drivers com correlacao nao-nula.

    O SQL avalia 4 drivers, mas 'quantidade_contas' tem variância zero no dataset
    (todos os 998 clientes possuem exatamente 1 conta), fazendo corr() retornar NULL.
    O WHERE correlation IS NOT NULL do mart filtra essa linha corretamente.
    """
    with dw_conn.cursor() as cur:
        cur.execute("SELECT driver FROM marts.mart_ranking_alavancas")
        found = {row[0] for row in cur.fetchall()}
    assert found == EXPECTED_DRIVERS, f"Drivers divergentes: {found}"


@pytest.mark.integration
def test_ranking_is_dense_and_ordered(dw_conn) -> None:
    """impact_rank e denso de 1..N sem lacunas nem repeticao."""
    with dw_conn.cursor() as cur:
        cur.execute(
            "SELECT min(impact_rank), max(impact_rank), "
            "count(*), count(distinct impact_rank) "
            "FROM marts.mart_ranking_alavancas"
        )
        min_rank, max_rank, total, distinct_ranks = cur.fetchone()
    assert min_rank == 1
    assert max_rank == total
    assert distinct_ranks == total


@pytest.mark.integration
def test_ranking_correlation_within_bounds(dw_conn) -> None:
    """Coeficiente de correlacao de Pearson sempre em [-1, 1]."""
    with dw_conn.cursor() as cur:
        cur.execute(
            "SELECT count(*) FROM marts.mart_ranking_alavancas "
            "WHERE correlation IS NOT NULL AND correlation NOT BETWEEN -1 AND 1"
        )
        assert cur.fetchone()[0] == 0
