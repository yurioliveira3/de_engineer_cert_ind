-- Mart comercial (narrativa Camila Diniz): engajamento por cliente.
-- Responde: transacoes por cliente, clientes ativos e risco de churn.
-- Grao: 1 linha por cliente que possui ao menos uma conta.

with clientes as (
    select * from {{ ref('stg_clientes') }}
),

contas as (
    select * from {{ ref('stg_contas') }}
),

transacoes as (
    select * from {{ ref('stg_transacoes') }}
),

credito_aprovado as (
    select distinct client_id
    from {{ ref('stg_propostas_credito') }}
    where proposal_status = 'Aprovada'
),

ref_date as (
    select max(transaction_at)::date as reference_date
    from {{ ref('stg_transacoes') }}
),

contas_por_cliente as (
    select
        client_id,
        count(*) as account_count,
        sum(total_balance) as total_balance
    from contas
    group by client_id
),

tx_por_cliente as (
    select
        co.client_id,
        count(t.transaction_id) as transaction_count,
        sum(t.transaction_amount) as transaction_total_amount,
        max(t.transaction_at)::date as last_transaction_date
    from contas co
    left join transacoes t
        on co.account_id = t.account_id
    group by co.client_id
),

final as (
    select
        cl.client_id,
        cl.client_full_name,
        cl.client_type,
        cl.onboarding_date::date as onboarding_date,
        cpc.account_count,
        cpc.total_balance,
        coalesce(txc.transaction_count, 0) as transaction_count,
        coalesce(txc.transaction_total_amount, 0) as transaction_total_amount,
        round(
            coalesce(txc.transaction_count, 0)::numeric
            / nullif(cpc.account_count, 0),
            2
        ) as avg_tx_per_account,
        txc.last_transaction_date,
        rd.reference_date - txc.last_transaction_date as days_since_last_transaction,
        rd.reference_date - cl.onboarding_date::date as relationship_days,
        ca.client_id is not null as has_approved_credit,
        case
            when txc.last_transaction_date is null then 'never_used'
            when rd.reference_date - txc.last_transaction_date <= 90 then 'active'
            when rd.reference_date - txc.last_transaction_date <= 360 then 'at_risk'
            else 'churned'
        end as engagement_status
    from clientes cl
    inner join contas_por_cliente cpc
        on cl.client_id = cpc.client_id
    left join tx_por_cliente txc
        on cl.client_id = txc.client_id
    left join credito_aprovado ca
        on cl.client_id = ca.client_id
    cross join ref_date rd
)

select * from final
