with proposals as (
    select * from {{ ref('stg_propostas_credito') }}
),

aggregated as (
    select
        date_trunc('month', proposal_date) as month,
        proposal_status,
        count(*) as proposal_count,
        sum(proposal_amount) as total_proposal_amount,
        avg(monthly_interest_rate) as avg_interest_rate
    from proposals
    group by 1, 2
)

select * from aggregated
