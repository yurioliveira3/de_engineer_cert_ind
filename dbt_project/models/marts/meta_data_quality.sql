{{ config(materialized='view') }}

with orphan_contas as (
    select
        'stg_contas' as model_name,
        'client_id' as column_name,
        'relationships' as test_type,
        'FAIL' as status,
        count(*) as failure_count,
        'Found ' || count(*) || ' account(s) referencing non-existent client(s)' as message
    from {{ ref('stg_contas') }} c
    left join {{ ref('stg_clientes') }} cl on c.client_id = cl.client_id
    where cl.client_id is null
),

orphan_propostas as (
    select
        'stg_propostas_credito' as model_name,
        'client_id' as column_name,
        'relationships' as test_type,
        'FAIL' as status,
        count(*) as failure_count,
        'Found ' || count(*) || ' proposal(s) referencing non-existent client(s)' as message
    from {{ ref('stg_propostas_credito') }} p
    left join {{ ref('stg_clientes') }} cl on p.client_id = cl.client_id
    where cl.client_id is null
),

null_clientes as (
    select
        'stg_clientes' as model_name,
        'client_id' as column_name,
        'not_null' as test_type,
        case when count(*) filter (where client_id is null) = 0 then 'PASS' else 'FAIL' end
            as status,
        count(*) filter (where client_id is null) as failure_count,
        'null check on client_id' as message
    from {{ ref('stg_clientes') }}
),

null_agencias as (
    select
        'stg_agencias' as model_name,
        'agency_id' as column_name,
        'not_null' as test_type,
        case when count(*) filter (where agency_id is null) = 0 then 'PASS' else 'FAIL' end
            as status,
        count(*) filter (where agency_id is null) as failure_count,
        'null check on agency_id' as message
    from {{ ref('stg_agencias') }}
),

null_propostas as (
    select
        'stg_propostas_credito' as model_name,
        'proposal_id' as column_name,
        'not_null' as test_type,
        case when count(*) filter (where proposal_id is null) = 0 then 'PASS' else 'FAIL' end
            as status,
        count(*) filter (where proposal_id is null) as failure_count,
        'null check on proposal_id' as message
    from {{ ref('stg_propostas_credito') }}
),

null_contas as (
    select
        'stg_contas' as model_name,
        'account_id' as column_name,
        'not_null' as test_type,
        case when count(*) filter (where account_id is null) = 0 then 'PASS' else 'FAIL' end
            as status,
        count(*) filter (where account_id is null) as failure_count,
        'null check on account_id' as message
    from {{ ref('stg_contas') }}
),

unique_clientes as (
    select
        'stg_clientes' as model_name,
        'client_id' as column_name,
        'unique' as test_type,
        case when count(*) = 0 then 'PASS' else 'FAIL' end as status,
        count(*) as failure_count,
        'uniqueness check on client_id' as message
    from (
        select client_id from {{ ref('stg_clientes') }}
        group by client_id
        having count(*) > 1
    ) dup
),

unique_agencias as (
    select
        'stg_agencias' as model_name,
        'agency_id' as column_name,
        'unique' as test_type,
        case when count(*) = 0 then 'PASS' else 'FAIL' end as status,
        count(*) as failure_count,
        'uniqueness check on agency_id' as message
    from (
        select agency_id from {{ ref('stg_agencias') }}
        group by agency_id
        having count(*) > 1
    ) dup
),

unique_contas as (
    select
        'stg_contas' as model_name,
        'account_id' as column_name,
        'unique' as test_type,
        case when count(*) = 0 then 'PASS' else 'FAIL' end as status,
        count(*) as failure_count,
        'uniqueness check on account_id' as message
    from (
        select account_id from {{ ref('stg_contas') }}
        group by account_id
        having count(*) > 1
    ) dup
),

unique_propostas as (
    select
        'stg_propostas_credito' as model_name,
        'proposal_id' as column_name,
        'unique' as test_type,
        case when count(*) = 0 then 'PASS' else 'FAIL' end as status,
        count(*) as failure_count,
        'uniqueness check on proposal_id' as message
    from (
        select proposal_id
        from {{ ref('stg_propostas_credito') }}
        group by proposal_id
        having count(*) > 1
    ) dup
)

select * from orphan_contas
union all
select * from orphan_propostas
union all
select * from null_clientes
union all
select * from null_agencias
union all
select * from null_propostas
union all
select * from null_contas
union all
select * from unique_clientes
union all
select * from unique_agencias
union all
select * from unique_contas
union all
select * from unique_propostas
order by status desc, model_name asc, column_name asc
