/*
  wt_tracker_daily
  ----------------
  Business-cohort tracker (replaces the warm-transfer tracker master query).
  One row per business_created_date x license x claimed status x campaign x credited AE x
  workflow type (the master query's GROUP BY), with partner / transfer type / team carried along.

  Filter in the BI tool / sheet, not here:
    - date range (the master query used business_created_date >= 2026-04-01)
    - license exclusions (the master query excluded the warm-transfer vendor licenses)

  Differences from the master query (all intentional, reconciled 2026-10-01):
    - test businesses are excluded (Business.isTest or owner name contains COVERDASH/TEST)
    - revenue excludes the *_PARTIAL installment types
    - quote timing uses Eastern dates (the master compared UTC quote dates to Eastern business dates)

  Ratios (conversion %, average premium, average time to quote) should be computed in the BI
  layer as ratio-of-sums, e.g. sum(d7_converted_business_count) / sum(business_count).
*/

with business as (
    select * from {{ ref('int_business') }}
    where not is_test_business
)

select
    -- grain
    business_created_date,
    license_name,
    claimed_status,
    warm_transfer_campaign,
    credited_account_executive,
    workflow_type,

    -- attributes of the grain (functionally dependent, so they don't split rows)
    business_created_week,
    business_created_month,
    max(is_mature_d7)                                   as is_mature_d7,
    max(is_mature_d14)                                  as is_mature_d14,
    max(is_mature_d30)                                  as is_mature_d30,
    max(partner_name)                                   as partner_name,
    max(transfer_type)                                  as transfer_type,
    max(campaign_type)                                  as campaign_type,
    max(credited_ae_team)                               as credited_ae_team,

    -- volume and cost
    count(*)                                            as business_count,
    sum(warm_transfer_bid_price)                        as total_bid_price,

    -- contact / junk
    sum(d7_attempted_to_contact)                        as d7_attempted_to_contact_business_count,
    sum(d7_made_contact)                                as d7_made_contact_business_count,
    sum(d7_junk)                                        as d7_junk_business_count,

    -- quote
    sum(quoted)                                         as quoted_business_count,
    sum(d7_quoted)                                      as d7_quoted_business_count,
    sum(d30_quoted)                                     as d30_quoted_business_count,
    coalesce(sum(days_to_d30_quote), 0)                 as total_days_to_d30_quote,
    sum(d7_quote_presented)                             as d7_quote_presented_business_count,
    sum(quote_count)                                    as quote_count,

    -- bind
    sum(converted)                                      as converted_business_count,
    sum(d1_converted)                                   as d1_converted_business_count,
    sum(d7_converted)                                   as d7_converted_business_count,
    sum(d14_converted)                                  as d14_converted_business_count,
    sum(d30_converted)                                  as d30_converted_business_count,
    sum(d60_converted)                                  as d60_converted_business_count,
    sum(d90_converted)                                  as d90_converted_business_count,
    sum(nb_policy_count)                                as nb_policy_count,

    -- premium
    sum(nb_premium)                                     as nb_premium,
    sum(d30_nb_premium)                                 as d30_nb_premium,

    -- revenue (NB, gross of cancellations, partials excluded)
    sum(d7_nb_gross_revenue)                            as d7_nb_gross_revenue,
    sum(d14_nb_gross_revenue)                           as d14_nb_gross_revenue,
    sum(d30_nb_gross_revenue)                           as d30_nb_gross_revenue,
    sum(nb_gross_revenue)                               as nb_gross_revenue,
    sum(d30_nb_core_revenue)                            as d30_nb_core_revenue,
    sum(nb_cancellation_amount)                         as nb_cancellation_amount,

    -- Chubb
    sum(d7_chubb_quoted)                                as d7_chubb_quoted_business_count,
    sum(case when d7_chubb_quoted = 1 then chubb_quoted_premium else 0 end)
                                                        as d7_chubb_quoted_premium,
    sum(d7_chubb_converted)                             as d7_chubb_converted_business_count,
    sum(d30_chubb_converted)                            as d30_chubb_converted_business_count,
    sum(d30_nb_chubb_premium)                           as d30_nb_chubb_premium,
    sum(d30_nb_chubb_gross_revenue)                     as d30_nb_chubb_gross_revenue,

    -- GAIG
    sum(d7_gaig_quoted)                                 as d7_gaig_quoted_business_count,
    sum(case when d7_gaig_quoted = 1 then gaig_quoted_premium else 0 end)
                                                        as d7_gaig_quoted_premium,
    sum(d7_gaig_converted)                              as d7_gaig_converted_business_count,
    sum(d30_gaig_converted)                             as d30_gaig_converted_business_count,
    sum(d30_nb_gaig_premium)                            as d30_nb_gaig_premium,
    sum(d30_nb_gaig_gross_revenue)                      as d30_nb_gaig_gross_revenue

from business
group by
    business_created_date,
    license_name,
    claimed_status,
    warm_transfer_campaign,
    credited_account_executive,
    workflow_type,
    business_created_week,
    business_created_month
