-- ============================================================
-- Analytics PoC - Dashboard Queries: Piloto de Crédito
-- ============================================================
-- All queries target the Gold layer (marts schema).
-- Run in Metabase or psql against analytics_dw.
-- ============================================================

-- 1. KPI: Total Propostas
SELECT SUM(proposal_count) AS total_proposals
FROM marts.fct_funil_credito;

-- 2. KPI: Taxa de Aprovação (%)
SELECT
    ROUND(
        SUM(CASE WHEN proposal_status = 'Aprovada' THEN proposal_count ELSE 0 END)
        * 100.0 / SUM(proposal_count)
    , 2) AS approval_rate_pct
FROM marts.fct_funil_credito;

-- 3. KPI: Valor Total Financiado (apenas aprovadas)
SELECT
    ROUND(SUM(CASE WHEN proposal_status = 'Aprovada' THEN total_proposal_amount ELSE 0 END), 2)
    AS total_financed_amount
FROM marts.fct_funil_credito;

-- 4. Stacked Bar Chart: Evolução Mensal do Funil
SELECT
    month,
    proposal_status,
    proposal_count
FROM marts.fct_funil_credito
ORDER BY month, proposal_status;

-- 5. Funnel Chart: Breakdown por Status (agregado)
SELECT
    proposal_status,
    SUM(proposal_count) AS total,
    ROUND(SUM(total_proposal_amount), 2) AS total_amount
FROM marts.fct_funil_credito
GROUP BY proposal_status
ORDER BY total DESC;

-- 6. Horizontal Bar: Conversão por Agência
SELECT
    agency_name,
    agency_type,
    total_proposals,
    approved_proposals,
    conversion_rate_pct,
    ROUND(total_proposal_amount, 2) AS total_proposal_amount
FROM marts.fct_performance_agencia
ORDER BY conversion_rate_pct DESC;

-- 7. Table: Detalhamento por Status e Mês
SELECT
    month,
    proposal_status,
    proposal_count,
    ROUND(total_proposal_amount, 2) AS total_proposal_amount,
    ROUND(avg_interest_rate * 100, 4) AS avg_interest_rate_pct
FROM marts.fct_funil_credito
ORDER BY month, proposal_status;