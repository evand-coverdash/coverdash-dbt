/*
  policy_revenue_summary
  ----------------------
  Monthly revenue aggregated by policy type and license name.
  Covers premium written, estimated commission, and policy counts.

  One row per bound_month × policy_type × license_name.
  Use this model for revenue trending, P&L analysis, and
  carrier/program mix reporting in Metabase.
*/

with base as (
    select
        bound_month,
        bound_quarter,
        bound_year,
        policy_type,
        license_name,
        underwriting_carrier,
        billing_type,
        sale_type,
        sales_channel,
        is_renewal,
        is_paygo,

        -- volume
        count(policy_id)                                as policies_bound,
        count(distinct business_id)                     as unique_businesses,

        -- revenue
        sum(premium)                                    as gross_written_premium,
        sum(commissionable_premium)                     as total_commissionable_premium,
        sum(estimated_commission)                       as total_estimated_commission,
        sum(mmr_fee)                                    as total_mmr_fees,

        -- averages
        avg(premium)                                    as avg_premium,
        avg(commission_rate)                            as avg_commission_rate,

        -- renewal mix
        count(case when not is_renewal then 1 end)      as new_business_policies,
        count(case when is_renewal then 1 end)          as renewal_policies,
        sum(case when not is_renewal then premium end)  as new_business_premium,
        sum(case when is_renewal then premium end)      as renewal_premium

    from {{ ref('int_policy_revenue') }}
    group by 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
),

with_rates as (
    select
        *,

        -- renewal rate by volume
        case
            when policies_bound > 0
            then round(renewal_policies::numeric / policies_bound::numeric * 100, 2)
        end                                             as renewal_rate_pct,

        -- effective commission rate (actual commissionable vs premium)
        case
            when gross_written_premium > 0
            then round(
                total_estimated_commission::numeric
                / gross_written_premium::numeric * 100, 2
            )
        end                                             as effective_commission_rate_pct

    from base
)

select *
from with_rates
order by bound_month desc, gross_written_premium desc
