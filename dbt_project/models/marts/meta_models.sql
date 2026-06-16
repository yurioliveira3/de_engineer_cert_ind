{{ config(materialized='view') }}

with models as (
    select
        c.relname as model_name,
        n.nspname as schema_name,
        case c.relkind
            when 'r' then 'table'
            when 'v' then 'view'
            when 'm' then 'materialized_view'
            else c.relkind::text
        end as materialization,
        c.reltuples::bigint as estimated_row_count,
        pg_size_pretty(pg_total_relation_size(c.oid)) as total_size,
        pg_size_pretty(pg_relation_size(c.oid)) as table_size,
        obj_description(c.oid) as description
    from pg_class c
    inner join pg_namespace n on c.relnamespace = n.oid
    where
        n.nspname in ('staging', 'marts', 'raw')
        and c.relkind in ('r', 'v')
        and not c.relname like 'pg_%'
        and not c.relname like 'dbt_%'
)

select
    model_name,
    schema_name,
    materialization,
    greatest(estimated_row_count, 0) as row_count,
    total_size,
    table_size,
    description,
    case schema_name
        when 'raw' then 'bronze'
        when 'staging' then 'silver'
        when 'marts' then 'gold'
    end as medallion_layer,
    now() as captured_at
from models
order by schema_name, model_name
