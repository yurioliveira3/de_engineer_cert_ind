"""
F2-02 - Testes de integridade da ingestão (contagem fonte × destino).

Marca: @pytest.mark.integration - requer `make up` + DAG executada.
Execute: pytest -m integration tests/ingestion/test_row_counts.py

Variáveis de ambiente (com defaults docker-compose):
  SOURCE_POSTGRES_HOST/PORT/USER/PASSWORD/DB
  DW_POSTGRES_HOST/PORT/USER/PASSWORD/DB
"""
from __future__ import annotations

import csv
import os
from pathlib import Path

import psycopg2
import pytest

PROJECT_ROOT = Path(__file__).parents[2]

SQL_TABLES_EXPECTED = {
    "agencias": 10,
    "clientes": 998,
    "colaboradores": 100,
    "colaborador_agencia": 100,
    "contas": 999,
    "propostas_credito": 2000,
}

SOURCE_PKS = {
    "agencias": "cod_agencia",
    "clientes": "cod_cliente",
    "colaboradores": "cod_colaborador",
    "contas": "num_conta",
    "propostas_credito": "cod_proposta",
}

TRANSACOES_CSV = PROJECT_ROOT / "data" / "landing" / "transacoes.csv"


@pytest.fixture(scope="module")
def source_conn():
    conn = psycopg2.connect(
        host=os.getenv("SOURCE_POSTGRES_HOST", "localhost"),
        port=int(os.getenv("SOURCE_POSTGRES_PORT", "5432")),
        user=os.getenv("SOURCE_POSTGRES_USER", "banvic"),
        password=os.getenv("SOURCE_POSTGRES_PASSWORD", ""),
        dbname=os.getenv("SOURCE_POSTGRES_DB", "banvic"),
    )
    yield conn
    conn.close()


# -- Contagem fonte × destino ----------------------------------------


@pytest.mark.integration
@pytest.mark.parametrize("table,expected", SQL_TABLES_EXPECTED.items())
def test_source_table_has_expected_count(source_conn, table, expected) -> None:
    """Tabela no source-postgres tem a contagem esperada do dataset original."""
    with source_conn.cursor() as cur:
        cur.execute(f'SELECT COUNT(*) FROM public."{table}"')
        count = cur.fetchone()[0]
    assert count == expected, f"source.public.{table}: esperado {expected}, obtido {count}"


@pytest.mark.integration
@pytest.mark.parametrize("table", SQL_TABLES_EXPECTED.keys())
def test_raw_count_matches_source(source_conn, dw_conn, table) -> None:
    """raw.* deve ter o mesmo número de linhas que a tabela no source-postgres."""
    with source_conn.cursor() as cur:
        cur.execute(f'SELECT COUNT(*) FROM public."{table}"')
        source_count = cur.fetchone()[0]

    with dw_conn.cursor() as cur:
        cur.execute(f'SELECT COUNT(*) FROM raw."{table}"')
        raw_count = cur.fetchone()[0]

    assert raw_count == source_count, (
        f"raw.{table}: {raw_count} linhas, source tem {source_count}"
    )


@pytest.mark.integration
def test_raw_transacoes_count_matches_csv(dw_conn) -> None:
    """raw.transacoes deve ter o mesmo número de linhas que transacoes.csv (excl. header)."""
    assert TRANSACOES_CSV.exists(), (
        f"CSV não encontrado: {TRANSACOES_CSV}\n"
        "Certifique-se de que data/landing/transacoes.csv está presente."
    )
    with TRANSACOES_CSV.open() as f:
        csv_count = sum(1 for _ in csv.reader(f)) - 1  # -1 pelo header

    with dw_conn.cursor() as cur:
        cur.execute('SELECT COUNT(*) FROM raw."transacoes"')
        raw_count = cur.fetchone()[0]

    assert raw_count == csv_count, (
        f"raw.transacoes: {raw_count} linhas, CSV tem {csv_count}"
    )


# -- Integridade de chaves primárias ---------------------------------


@pytest.mark.integration
@pytest.mark.parametrize("table,pk_col", SOURCE_PKS.items())
def test_raw_pk_not_null(dw_conn, table, pk_col) -> None:
    """Chave primária em raw.* não deve conter valores NULL."""
    with dw_conn.cursor() as cur:
        cur.execute(f'SELECT COUNT(*) FROM raw."{table}" WHERE "{pk_col}" IS NULL')
        null_count = cur.fetchone()[0]
    assert null_count == 0, f"raw.{table}.{pk_col}: {null_count} valores NULL"


@pytest.mark.integration
def test_raw_colaborador_agencia_fk_not_null(dw_conn) -> None:
    """colaborador_agencia: ambas as FKs (composite PK) devem ser não-nulas."""
    with dw_conn.cursor() as cur:
        cur.execute(
            'SELECT COUNT(*) FROM raw."colaborador_agencia" '
            'WHERE "cod_colaborador" IS NULL OR "cod_agencia" IS NULL'
        )
        null_count = cur.fetchone()[0]
    assert null_count == 0, f"raw.colaborador_agencia: {null_count} linhas com FK nula"


# -- Tipos e parsing -------------------------------------------------


@pytest.mark.integration
def test_raw_transacoes_valor_not_null(dw_conn) -> None:
    """valor_transacao em raw.transacoes deve ser não-nulo (CSV parseado corretamente)."""
    with dw_conn.cursor() as cur:
        cur.execute('SELECT COUNT(*) FROM raw."transacoes" WHERE "valor_transacao" IS NULL')
        null_count = cur.fetchone()[0]
    assert null_count == 0, f"raw.transacoes: {null_count} valores NULL em valor_transacao"
