with source as (
    select * from {{ source('raw', 'clientes') }}
),

renamed as (
    select
        cod_cliente as client_id,
        primeiro_nome || ' ' || ultimo_nome as client_full_name,
        email,
        tipo_cliente as client_type,
        data_inclusao as onboarding_date,
        cpfcnpj as cpf_cnpj,
        data_nascimento as birth_date,
        endereco as address,
        cep as postal_code
    from source
)

select * from renamed
