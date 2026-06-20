-- Dashboard Comercial (BanVic) - perguntas de negocio respondidas pelos marts.
-- Narrativas: Camila Diniz (engajamento/churn) e Sofia Oliveira (alavancas).
-- Cole cada bloco como uma pergunta (card) no Metabase.

-- 1. KPIs comerciais (cartoes do topo do dashboard) - Camila
select
    total_clientes,
    clientes_ativos,
    taxa_ativos_pct,
    taxa_inativos_pct,
    media_transacoes_por_cliente
from marts.mart_kpi_comercial;

-- 2. Distribuicao de clientes por status de engajamento (pizza) - Camila
select
    engagement_status,
    count(*) as clientes
from marts.mart_engajamento_cliente
group by engagement_status
order by clientes desc;

-- 3. Top 20 clientes em risco de churn com maior saldo (retencao) - Camila
select
    client_sk,
    client_full_name,
    total_balance,
    transaction_count,
    days_since_last_transaction
from marts.mart_engajamento_cliente
where engagement_status = 'at_risk'
order by total_balance desc
limit 20;

-- 4. Ranking de alavancas que mais impactam transacoes/cliente - Sofia (CEO)
select
    impact_rank,
    driver,
    correlation,
    direction,
    significant_at_5pct
from marts.mart_ranking_alavancas
order by impact_rank;
