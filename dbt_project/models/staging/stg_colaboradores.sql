with source as (
    select * from {{ source('raw', 'colaboradores') }}
),

renamed as (
    select
        cod_colaborador as employee_id,
        primeiro_nome as first_name,
        ultimo_nome as last_name,
        email,
        cpf,
        data_nascimento as birth_date,
        endereco as address,
        cep as postal_code
    from source
)

select * from renamed
