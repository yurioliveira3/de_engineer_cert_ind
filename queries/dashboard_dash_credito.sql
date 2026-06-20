-- ============================================================
-- Analytics PoC - Dashboard Queries: Piloto de Crédito
-- ============================================================
-- All queries target the Gold layer (marts schema).
-- Run in Metabase or psql against analytics_dw.
-- ============================================================

-- 1. KPI: Total Propostas
select sum(proposal_count) as total_proposals
from marts.fct_funil_credito;

-- 2. KPI: Taxa de Aprovação (%)
select
    round(
        sum(case when proposal_status = 'Aprovada' then proposal_count else 0 end)
        * 100.0 / sum(proposal_count),
        2
    ) as approval_rate_pct
from marts.fct_funil_credito;

-- 3. KPI: Valor Total Financiado (apenas aprovadas)
select
    round(sum(case when proposal_status = 'Aprovada' then total_proposal_amount else 0 end), 2)
        as total_financed_amount
from marts.fct_funil_credito;

-- 4. Stacked Bar Chart: Evolução Mensal do Funil
select
    month,
    proposal_status,
    proposal_count
from marts.fct_funil_credito
order by month, proposal_status;

-- 5. Funnel Chart: Breakdown por Status (agregado)
select
    proposal_status,
    sum(proposal_count) as total,
    round(sum(total_proposal_amount), 2) as total_amount
from marts.fct_funil_credito
group by proposal_status
order by total desc;

-- 6. Horizontal Bar: Conversão por Agência
select
    agency_name,
    agency_type,
    total_proposals,
    approved_proposals,
    conversion_rate_pct,
    round(total_proposal_amount, 2) as total_proposal_amount
from marts.fct_performance_agencia
order by conversion_rate_pct desc;

-- 7. Table: Detalhamento por Status e Mês
select
    month,
    proposal_status,
    proposal_count,
    round(total_proposal_amount, 2) as total_proposal_amount,
    round(avg_interest_rate * 100, 4) as avg_interest_rate_pct
from marts.fct_funil_credito
order by month, proposal_status;
