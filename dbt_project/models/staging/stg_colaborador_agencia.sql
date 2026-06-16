with source as (
    select * from {{ source('raw', 'colaborador_agencia') }}
),

renamed as (
    select
        cod_colaborador as employee_id,
        cod_agencia as agency_id
    from source
)

select * from renamed
