with source as (
    select * from {{ source('raw', 'agencias') }}
),

renamed as (
    select
        cod_agencia as agency_id,
        nome as agency_name,
        endereco as address,
        cidade as city,
        uf as state,
        data_abertura as opening_date,
        tipo_agencia as agency_type
    from source
)

select * from renamed
