-- ============================================================
-- Analytics PoC - Dashboard Queries: 5 Principais Insights
-- ============================================================
-- All queries target the Gold layer (marts schema).
-- Run in Metabase or psql against analytics_dw.
-- ============================================================

-- 1. Propostas nunca saíram do status 'Enviada'
-- Identifica o gargalo no funil: propostas que entraram mas nunca avançaram
select
    month,
    proposal_status,
    proposal_count,
    total_proposal_amount
from marts.fct_funil_credito
where proposal_status = 'Enviada'
order by month;

-- 2. Motivo de agências converterem mais propostas
-- Ranking de agências por taxa de conversão - performance comparada
select
    agency_sk,
    agency_name,
    agency_type,
    total_proposals,
    approved_proposals,
    conversion_rate_pct,
    total_proposal_amount
from marts.fct_performance_agencia
order by conversion_rate_pct desc;

-- 3. Aumento elevado de transações em Dez/22 - bug ou evento real?
-- Anomalia de volume: dias com tx count muito acima da média
with stats as (
    select
        avg(transaction_count) as avg_count,
        stddev(transaction_count) as std_count
    from marts.fct_volume_diario_transacoes
)

select
    transaction_date,
    transaction_type,
    transaction_count,
    distinct_accounts,
    avg_tx_per_account,
    case
        when transaction_count > (select avg_count + 3 * std_count from stats)
            then 'ANOMALY'
        else 'NORMAL'
    end as flag
from marts.fct_volume_diario_transacoes
where
    extract(year from transaction_date) = 2022
    and extract(month from transaction_date) = 12
order by transaction_count desc;

-- 4. Contas sem movimentação há muito tempo
-- Segmentação: ativas, dormentes ou nunca usadas
select
    account_sk,
    client_fk,
    agency_fk,
    total_balance,
    last_transaction_date,
    days_since_last_transaction,
    activity_status
from marts.fct_atividade_contas
where activity_status in ('dormant', 'never_used')
order by total_balance desc;

-- 5. Clientes com saldo elevado, sem crédito aprovado
-- Oportunidade de cross-sell: R$ 13.3M represados
select
    client_fk,
    client_full_name,
    account_fk,
    total_balance,
    agency_fk
from marts.mart_oportunidade_crosssell
order by total_balance desc;

-- 6. Ranking de alavancas — qual driver move o engajamento transacional? (Sofia/CEO)
-- Gráfico de barras horizontal no Metabase: eixo x = correlation, eixo y = driver_label.
-- Colorir por direction (positivo=verde, negativo=vermelho).
-- Insight esperado: nenhum driver explica mais de 1% da variância — o achado é a ausência de sinal forte.
select
    impact_rank,
    driver,
    correlation,
    direction,
    significant_at_5pct,
    r_squared_pct,
    sample_size,
    case
        when significant_at_5pct and r_squared_pct >= 5 then 'Relevante'
        when significant_at_5pct and r_squared_pct < 5 then 'Significativo mas fraco'
        else 'Sem evidência'
    end as verdict
from marts.mart_ranking_alavancas
order by impact_rank;

-- 7. Tabela de contexto estatístico — acompanha o gráfico 6 (Sofia/CEO)
-- Exibe como tabela estática no dashboard abaixo do gráfico de barras.
-- Rodapé recomendado: "Correlação mede associação linear. r² < 1% indica
-- relevância prática negligenciável mesmo quando p < 0,05."
select
    impact_rank as "#",
    driver as "Alavanca",
    correlation as "r (Pearson)",
    r_squared_pct || '%' as "r² (variância explicada)",
    case when significant_at_5pct then 'Sim' else 'Não' end as "Significativo (p<0,05)?",
    case
        when significant_at_5pct and r_squared_pct >= 5 then 'Relevante'
        when significant_at_5pct and r_squared_pct < 5 then 'Significativo mas fraco'
        else 'Sem evidência'
    end as "Veredito",
    sample_size as "n (clientes)"
from marts.mart_ranking_alavancas
order by impact_rank;
