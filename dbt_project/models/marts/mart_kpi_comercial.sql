-- KPIs comerciais agregados (single-row) para o dashboard da Camila.
-- Pre-computa as metricas de engajamento: zero agregacao necessaria no BI.

with engajamento as (
    select * from {{ ref('mart_engajamento_cliente') }}
),

kpis as (
    select
        count(*) as total_clientes,
        count(*) filter (where engagement_status = 'active') as clientes_ativos,
        count(*) filter (where engagement_status = 'at_risk') as clientes_em_risco,
        count(*) filter (where engagement_status = 'churned') as clientes_churned,
        count(*) filter (where engagement_status = 'never_used') as clientes_sem_uso,
        round(
            count(*) filter (where engagement_status = 'active') * 100.0
            / nullif(count(*), 0),
            2
        ) as taxa_ativos_pct,
        round(
            count(*) filter (where engagement_status in ('at_risk', 'churned')) * 100.0
            / nullif(count(*), 0),
            2
        ) as taxa_inativos_pct,
        round(avg(transaction_count), 2) as media_transacoes_por_cliente,
        round(
            count(*) filter (where has_approved_credit) * 100.0
            / nullif(count(*), 0),
            2
        ) as taxa_posse_credito_pct
    from engajamento
)

select * from kpis
