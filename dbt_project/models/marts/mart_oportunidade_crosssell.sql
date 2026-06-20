with clientes_com_credito_aprovado as (
    select distinct client_id
    from {{ ref('stg_propostas_credito') }}
    where proposal_status = 'Aprovada'
),

oportunidades as (
    select
        cl.client_id as client_fk,
        cl.client_full_name,
        c.account_id as account_fk,
        c.total_balance,
        c.agency_id as agency_fk
    from {{ ref('stg_contas') }} c
    inner join {{ ref('stg_clientes') }} cl
        on c.client_id = cl.client_id
    left join clientes_com_credito_aprovado cca
        on c.client_id = cca.client_id
    where
        c.total_balance > 20000
        and cca.client_id is null
)

select * from oportunidades
