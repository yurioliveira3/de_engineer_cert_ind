with transactions as (
    select * from {{ ref('stg_transacoes') }}
),

aggregated as (
    select
        date(transaction_at) as transaction_date,
        transaction_type,
        count(*) as transaction_count,
        count(distinct account_id) as distinct_accounts,
        round(
            count(*) * 1.0
            / nullif(count(distinct account_id), 0),
            2
        ) as avg_tx_per_account
    from transactions
    group by 1, 2
)

select * from aggregated
