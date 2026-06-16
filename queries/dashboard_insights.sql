-- ============================================================
-- Analytics PoC - Dashboard Queries: 5 Principais Insights
-- ============================================================
-- All queries target the Gold layer (marts schema).
-- Run in Metabase or psql against analytics_dw.
-- ============================================================

-- 1. Propostas nunca saíram do status 'Enviada'
-- Identifica o gargalo no funil: propostas que entraram mas nunca avançaram
SELECT
    month,
    proposal_status,
    proposal_count,
    total_proposal_amount
FROM marts.fct_funil_credito
WHERE proposal_status = 'Enviada'
ORDER BY month;

-- 2. Motivo de agências converterem mais propostas
-- Ranking de agências por taxa de conversão - performance comparada
SELECT
    agency_id,
    agency_name,
    agency_type,
    total_proposals,
    approved_proposals,
    conversion_rate_pct,
    total_proposal_amount
FROM marts.fct_performance_agencia
ORDER BY conversion_rate_pct DESC;

-- 3. Aumento elevado de transações em Dez/22 - bug ou evento real?
-- Anomalia de volume: dias com tx count muito acima da média
WITH stats AS (
    SELECT
        avg(transaction_count) as avg_count,
        stddev(transaction_count) as std_count
    FROM marts.fct_volume_diario_transacoes
)
SELECT
    transaction_date,
    transaction_type,
    transaction_count,
    distinct_accounts,
    avg_tx_per_account,
    CASE
        WHEN transaction_count > (SELECT avg_count + 3 * std_count FROM stats)
        THEN 'ANOMALY'
        ELSE 'NORMAL'
    END as flag
FROM marts.fct_volume_diario_transacoes
WHERE EXTRACT(YEAR FROM transaction_date) = 2022
  AND EXTRACT(MONTH FROM transaction_date) = 12
ORDER BY transaction_count DESC;

-- 4. Contas sem movimentação há muito tempo
-- Segmentação: ativas, dormentes ou nunca usadas
SELECT
    account_id,
    client_id,
    agency_id,
    total_balance,
    last_transaction_date,
    days_since_last_transaction,
    activity_status
FROM marts.fct_atividade_contas
WHERE activity_status IN ('dormant', 'never_used')
ORDER BY total_balance DESC;

-- 5. Clientes com saldo elevado, sem crédito aprovado
-- Oportunidade de cross-sell: R$ 13.3M represados
SELECT
    client_id,
    client_full_name,
    account_id,
    total_balance,
    agency_id
FROM marts.mart_oportunidade_crosssell
ORDER BY total_balance DESC;