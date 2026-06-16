with source as (
    select * from {{ source('raw', 'contas') }}
),

renamed as (
    select
        num_conta as account_id,
        cod_cliente as client_id,
        cod_agencia as agency_id,
        cod_colaborador as employee_id,
        tipo_conta as account_type,
        data_abertura as opening_date,
        saldo_total as total_balance,
        saldo_disponivel as available_balance,
        data_ultimo_lancamento as last_posting_date
    from source
)

select * from renamed
