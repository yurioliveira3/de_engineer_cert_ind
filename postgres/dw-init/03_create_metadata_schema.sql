\c analytics_dw;

CREATE SCHEMA IF NOT EXISTS metadata;

CREATE TABLE IF NOT EXISTS metadata.test_results (
    test_name       TEXT,
    model_name      TEXT,
    column_name     TEXT,
    status          TEXT,
    message         TEXT,
    executed_at     TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS metadata.model_runs (
    model_name       TEXT,
    materialization  TEXT,
    schema_name      TEXT,
    row_count        BIGINT,
    status           TEXT,
    message          TEXT,
    executed_at      TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
