with propostas_com_agencia as (
    select
        p.proposal_id,
        p.proposal_status,
        p.proposal_amount,
        ca.agency_id
    from {{ ref('stg_propostas_credito') }} p
    inner join {{ ref('stg_colaborador_agencia') }} ca
        on p.employee_id = ca.employee_id
),

aggregated as (
    select
        a.agency_id as agency_sk,
        a.agency_name,
        a.agency_type,
        count(p.proposal_id) as total_proposals,
        sum(case when p.proposal_status = 'Aprovada' then 1 else 0 end) as approved_proposals,
        round(
            sum(case when p.proposal_status = 'Aprovada' then 1 else 0 end)
            * 100.0 / nullif(count(p.proposal_id), 0),
            2
        ) as conversion_rate_pct,
        sum(p.proposal_amount) as total_proposal_amount
    from {{ ref('stg_agencias') }} a
    left join propostas_com_agencia p
        on a.agency_id = p.agency_id
    group by 1, 2, 3
)

select * from aggregated
