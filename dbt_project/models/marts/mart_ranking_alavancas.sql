-- Mart de ranking de alavancas (narrativa CEO Sofia Oliveira).
-- Responde: "quais alavancas movem o ponteiro?" com um ranking quantitativo.
-- Metodo: correlacao de Pearson entre cada driver candidato e a metrica-alvo
--         (numero de transacoes por cliente), com t-statistic para significancia.
-- Nota: correlacao indica associacao, nao causalidade. Para inferencia causal
--       seria necessario um modelo de regressao multivariada controlada.

with base as (
    select
        transaction_count,
        total_balance,
        relationship_days,
        account_count,
        case when has_approved_credit then 1 else 0 end as has_credit_flag
    from {{ ref('mart_engajamento_cliente') }}
),

sample as (
    select count(*) as sample_size from base
),

correlations as (
    select
        'saldo_total' as driver,
        corr(transaction_count, total_balance) as correlation
    from base
    union all
    select
        'tempo_relacionamento' as driver,
        corr(transaction_count, relationship_days) as correlation
    from base
    union all
    select
        'quantidade_contas' as driver,
        corr(transaction_count, account_count) as correlation
    from base
    union all
    select
        'posse_credito_aprovado' as driver,
        corr(transaction_count, has_credit_flag) as correlation
    from base
),

stats as (
    select
        c.driver,
        c.correlation,
        s.sample_size,
        c.correlation * sqrt(
            (s.sample_size - 2) / nullif(1 - c.correlation ^ 2, 0)
        ) as t_statistic
    from correlations c
    cross join sample s
),

ranked as (
    select
        driver,
        round(correlation::numeric, 4) as correlation,
        round(abs(correlation)::numeric, 4) as abs_correlation,
        round((correlation ^ 2 * 100)::numeric, 2) as r_squared_pct,
        case
            when correlation > 0 then 'positivo'
            when correlation < 0 then 'negativo'
            else 'indefinido'
        end as direction,
        sample_size,
        round(t_statistic::numeric, 2) as t_statistic,
        abs(t_statistic) > 1.96 as significant_at_5pct,
        row_number() over (order by abs(correlation) desc nulls last) as impact_rank
    from stats
    where correlation is not null
)

select * from ranked
