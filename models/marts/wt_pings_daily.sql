/*
  wt_pings_daily
  --------------
  Ping-level warm-transfer tracker: pings, acceptances, rejections (with reasons), claimed
  ("answered") transfers, cost, and the downstream conversion of the businesses those pings created.

  One row per ping date x partner x campaign x status x claimed status x rejection reason x
  credited AE. Rejected pings have no business, so AE / license columns are NULL on those rows.

  Definitions
    - partner_name is resolved per ping (campaign -> business license -> payload shape); see
      int_warm_transfer. ~73% of pings have no campaign, mostly All Web Leads data leads.
    - accepted_bid_price = bid on ACCEPTED pings (the cost). offered_bid_price includes rejected
      pings, which also carry a bid. The business-cohort tracker's total_bid_price only counts
      pings that created a business, so it's slightly lower than accepted_bid_price.
    - claimed_status is only set on accepted pings (NULL = CLAIMED).
    - Pings whose business is test data are excluded. Pings with no business are kept.
    - Downstream conversion is measured from the business created date (= ping date).
*/

with pings as (
    select * from {{ ref('int_warm_transfer') }}
    where not is_test_business
)

select
    -- grain
    created_date                                        as ping_date,
    partner_name,
    campaign_name,
    status,
    claimed_status,
    rejection_reason_category,
    rejection_reason,
    credited_account_executive,

    -- attributes of the grain
    created_week                                        as ping_week,
    created_month                                       as ping_month,
    max(case when ping_age_days >= 7  then 1 else 0 end) as is_mature_d7,
    max(case when ping_age_days >= 30 then 1 else 0 end) as is_mature_d30,
    max(credited_ae_team)                               as credited_ae_team,
    bool_or(is_high_revenue_campaign)                   as is_high_revenue_campaign,

    -- ping funnel
    count(*)                                            as ping_count,
    count(*) filter (where is_accepted)                 as accepted_count,
    count(*) filter (where is_rejected)                 as rejected_count,
    count(*) filter (where is_error)                    as error_count,
    count(*) filter (where is_received)                 as received_count,
    count(*) filter (where claimed_status = 'CLAIMED')  as claimed_count,
    count(*) filter (where claimed_status = 'UNCLAIMED') as unclaimed_count,
    count(business_id)                                  as business_count,

    -- cost
    coalesce(sum(accepted_bid_price), 0)                as accepted_bid_price,
    coalesce(sum(bid_price), 0)                         as offered_bid_price,

    -- downstream (businesses created by these pings)
    coalesce(sum(quoted), 0)                            as quoted_business_count,
    coalesce(sum(d7_quoted), 0)                         as d7_quoted_business_count,
    coalesce(sum(converted), 0)                         as converted_business_count,
    coalesce(sum(d7_converted), 0)                      as d7_converted_business_count,
    coalesce(sum(d30_converted), 0)                     as d30_converted_business_count,
    coalesce(sum(nb_policy_count), 0)                   as nb_policy_count,
    coalesce(sum(nb_premium), 0)                        as nb_premium,
    coalesce(sum(d30_nb_premium), 0)                    as d30_nb_premium,
    coalesce(sum(d30_nb_gross_revenue), 0)              as d30_nb_gross_revenue,
    coalesce(sum(nb_gross_revenue), 0)                  as nb_gross_revenue

from pings
group by
    created_date,
    partner_name,
    campaign_name,
    status,
    claimed_status,
    rejection_reason_category,
    rejection_reason,
    credited_account_executive,
    created_week,
    created_month
