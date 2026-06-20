with max_date as (
    select max(transaction_at)::date as reference_date
    from {{ ref('stg_transacoes') }}
),

last_tx_per_account as (
    select
        account_id,
        max(transaction_at)::date as last_transaction_date
    from {{ ref('stg_transacoes') }}
    group by account_id
),

classified as (
    select
        c.account_id as account_sk,
        c.client_id as client_fk,
        c.agency_id as agency_fk,
        c.total_balance,
        lt.last_transaction_date,
        md.reference_date - lt.last_transaction_date as days_since_last_transaction,
        case
            when lt.last_transaction_date is null then 'never_used'
            when md.reference_date - lt.last_transaction_date <= 90 then 'active'
            else 'dormant'
        end as activity_status
    from {{ ref('stg_contas') }} c
    left join last_tx_per_account lt
        on c.account_id = lt.account_id
    cross join max_date md
)

select * from classified
