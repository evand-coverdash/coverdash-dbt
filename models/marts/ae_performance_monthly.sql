/*
  ae_performance_monthly
  ----------------------
  Monthly performance scorecard per Account Executive.
  Covers lead intake, contact rate, and policy revenue outcomes.

  One row per account_executive × calendar month.
  AEs with no activity in a given month are excluded.
*/

with leads as (
    select
        date_trunc('month', lead_created_at)::date      as activity_month,
        account_executive,
        count(lead_id)                                  as leads_assigned,
        count(case when made_contact then 1 end)        as leads_contacted,
        count(case when is_junk then 1 end)             as leads_marked_junk,
        avg(lead_score)                                 as avg_lead_score
    from {{ ref('int_business_latest') }}
    where account_executive is not null
      and lead_id is not null
    group by 1, 2
),

policies as (
    select
        bound_month                                     as activity_month,
        account_executive,
        count(policy_id)                                as policies_bound,
        count(case when not is_renewal then 1 end)      as new_policies_bound,
        count(case when is_renewal then 1 end)          as renewals_bound,
        count(distinct business_id)                     as unique_businesses_bound,
        sum(premium)                                    as total_premium,
        sum(estimated_commission)                       as total_estimated_commission,
        avg(premium)                                    as avg_premium_per_policy,
        count(distinct policy_type)                     as distinct_policy_types
    from {{ ref('int_policy_revenue') }}
    where account_executive is not null
    group by 1, 2
),

joined as (
    select
        coalesce(l.activity_month, p.activity_month)    as activity_month,
        coalesce(l.account_executive, p.account_executive) as account_executive,

        -- lead metrics
        coalesce(l.leads_assigned, 0)                   as leads_assigned,
        coalesce(l.leads_contacted, 0)                  as leads_contacted,
        coalesce(l.leads_marked_junk, 0)                as leads_marked_junk,
        l.avg_lead_score,

        -- policy metrics
        coalesce(p.policies_bound, 0)                   as policies_bound,
        coalesce(p.new_policies_bound, 0)               as new_policies_bound,
        coalesce(p.renewals_bound, 0)                   as renewals_bound,
        coalesce(p.unique_businesses_bound, 0)          as unique_businesses_bound,
        coalesce(p.total_premium, 0)                    as total_premium,
        coalesce(p.total_estimated_commission, 0)       as total_estimated_commission,
        p.avg_premium_per_policy,
        coalesce(p.distinct_policy_types, 0)            as distinct_policy_types,

        -- conversion metrics
        case
            when coalesce(l.leads_assigned, 0) > 0
            then round(
                coalesce(l.leads_contacted, 0)::numeric
                / l.leads_assigned::numeric * 100, 2
            )
        end                                             as contact_rate_pct,

        case
            when coalesce(l.leads_contacted, 0) > 0
            then round(
                coalesce(p.unique_businesses_bound, 0)::numeric
                / l.leads_contacted::numeric * 100, 2
            )
        end                                             as contact_to_bind_rate_pct,

        case
            when coalesce(l.leads_assigned, 0) > 0
            then round(
                coalesce(p.unique_businesses_bound, 0)::numeric
                / l.leads_assigned::numeric * 100, 2
            )
        end                                             as overall_close_rate_pct

    from leads l
    full outer join policies p
        on  p.activity_month    = l.activity_month
        and p.account_executive = l.account_executive
)

select *
from joined
order by activity_month desc, total_premium desc
