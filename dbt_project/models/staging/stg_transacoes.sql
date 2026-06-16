with source as (
    select * from {{ source('raw', 'transacoes') }}
),

renamed as (
    select
        cod_transacao::bigint as transaction_id,
        num_conta::bigint as account_id,
        data_transacao::timestamptz as transaction_at,
        nome_transacao as transaction_type,
        valor_transacao::numeric as transaction_amount
    from source
)

select * from renamed
