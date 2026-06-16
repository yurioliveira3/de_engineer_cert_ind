with funnel as (
    select * from {{ ref('fct_funil_credito') }}
),

aggregated as (
    select
        sum(proposal_count) as total_proposals,
        sum(case when proposal_status = 'Aprovada' then proposal_count else 0 end)
            as approved_proposals,
        sum(case when proposal_status != 'Aprovada' then proposal_count else 0 end)
            as rejected_proposals,
        round(
            sum(case when proposal_status = 'Aprovada' then proposal_count else 0 end)
            * 100.0 / nullif(sum(proposal_count), 0),
            2
        ) as approval_rate_pct,
        round(sum(total_proposal_amount), 2) as total_proposal_amount,
        round(sum(case when proposal_status = 'Aprovada' then total_proposal_amount else 0 end), 2)
            as total_financed_amount,
        round(avg(avg_interest_rate) * 100, 4) as avg_interest_rate_pct
    from funnel
)

select * from aggregated
