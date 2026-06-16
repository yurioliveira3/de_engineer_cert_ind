with source as (
    select * from {{ source('raw', 'propostas_credito') }}
),

renamed as (
    select
        cod_proposta as proposal_id,
        cod_cliente as client_id,
        cod_colaborador as employee_id,
        data_entrada_proposta as proposal_date,
        taxa_juros_mensal as monthly_interest_rate,
        valor_proposta as proposal_amount,
        valor_financiamento as financing_amount,
        valor_entrada as down_payment,
        valor_prestacao as installment_amount,
        quantidade_parcelas as installment_count,
        carencia as grace_period,
        status_proposta as proposal_status
    from source
)

select * from renamed
