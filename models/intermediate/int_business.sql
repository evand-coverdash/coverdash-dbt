/*
  int_business
  ------------
  One row per business: dimensions, funnel milestone timestamps, cohort flags, and the
  premium / revenue measures from the warm-transfer tracker master query.

  Marts aggregate this model by any dimension (created_date, license, partner, campaign, AE, ...).
  The cohort flags are 0/1 integers, so sum(d7_converted) = the tracker's d7ConvertedBusinessCount.

  Definitions
    - Cohort date = business created_date (Eastern). "dN" = milestone date - business created
      date <= N days (calendar-date difference, same as the tracker).
    - Every timestamp is Eastern. Quote times are converted from UTC in stg_quote.
    - New business (NB) = sale_type 'NEW_BUSINESS' only (cross-sell excluded).
    - nb_gross_revenue_* = signed PolicyTransaction amounts on NB policies, every type except
      CANCELLATION, **excluding the *_PARTIAL installment types** (they double-count the parent).
      Windowed on transaction created_date (when it was booked).
    - nb_core_revenue_* = COMMISSION + TECHNOLOGY_ACCESS_FEE + AGENCY_FEE only (admin-app definition).
    - Policies and quotes on the test carrier 'Fake Insurance' are left out of every rollup.
    - is_test_business flags Business.isTest or an owner name containing COVERDASH/TEST. Rows are
      kept; filter `where not is_test_business` in marts.
    - Maturity flags compare to today in Eastern at build time.
*/

{{ config(materialized='table') }}

with business as (
    select * from {{ ref('stg_business') }}
),

users as (
    select user_id, full_name, email, is_test_name from {{ ref('stg_user') }}
),

license as (
    select * from {{ ref('stg_license') }}
),

employee as (
    select employee_name, employee_type, team from {{ ref('stg_employee_contact_information') }}
),

classification as (
    select * from {{ ref('stg_business_classification') }}
),

carrier as (
    select * from {{ ref('stg_carrier') }}
),

business_dates as (
    select business_id, created_date as business_created_date from business
),

-- one lead per business (1 business has 2; keep the latest)
lead as (
    select *
    from (
        select
            l.*,
            row_number() over (partition by l.business_id order by l.created_at desc) as rn
        from {{ ref('stg_lead') }} l
        where l.business_id is not null
    ) x
    where rn = 1
),

-- one warm transfer per business (1 business has 2; bid price is summed, attributes from the latest)
warm_transfer as (
    select
        business_id,
        count(*)                                                    as warm_transfer_count,
        sum(bid_price)                                              as warm_transfer_bid_price,
        min(created_at)                                             as first_warm_transfer_at,
        (array_agg(claimed_status     order by created_at desc))[1] as warm_transfer_claimed_status,
        (array_agg(status             order by created_at desc))[1] as warm_transfer_status,
        (array_agg(campaign_status_id order by created_at desc))[1] as warm_transfer_campaign_status_id
    from {{ ref('stg_warm_transfer') }}
    where business_id is not null
    group by 1
),

campaign as (
    select campaign_status_id, campaign_name from {{ ref('stg_campaign_status') }}
),

-- policies: counts, premium, first-bind timestamps (all sale types + NB, total + Chubb + GAIG)
policy_rollup as (
    select
        p.business_id,

        -- all sale types
        min(p.created_at)                                                                   as first_policy_created_at,
        count(*)                                                                            as policy_count,
        sum(p.premium)                                                                      as total_premium,
        count(*) filter (where p.is_active)                                                 as active_policy_count,
        sum(p.premium) filter (where p.is_active)                                           as active_premium,

        -- new business
        min(p.created_at) filter (where p.is_new_business)                                  as first_nb_policy_created_at,
        count(*) filter (where p.is_new_business)                                           as nb_policy_count,
        sum(p.premium) filter (where p.is_new_business)                                     as nb_premium,
        sum(p.premium) filter (where p.is_new_business
                                 and p.created_date - bd.business_created_date <= 30)       as d30_nb_premium,

        -- new business: Chubb
        min(p.created_at) filter (where p.is_new_business and c.carrier_group = 'Chubb')    as first_nb_chubb_policy_created_at,
        sum(p.premium)    filter (where p.is_new_business and c.carrier_group = 'Chubb')    as nb_chubb_premium,
        sum(p.premium)    filter (where p.is_new_business and c.carrier_group = 'Chubb'
                                    and p.created_date - bd.business_created_date <= 30)    as d30_nb_chubb_premium,

        -- new business: GAIG
        min(p.created_at) filter (where p.is_new_business and c.carrier_group = 'GAIG')     as first_nb_gaig_policy_created_at,
        sum(p.premium)    filter (where p.is_new_business and c.carrier_group = 'GAIG')     as nb_gaig_premium,
        sum(p.premium)    filter (where p.is_new_business and c.carrier_group = 'GAIG'
                                    and p.created_date - bd.business_created_date <= 30)    as d30_nb_gaig_premium

    from {{ ref('stg_policy') }} p
    join carrier c
        on c.carrier_id = p.carrier_id
    join business_dates bd
        on bd.business_id = p.business_id
    where not c.is_test_carrier
    group by 1
),

-- quotes: counts, quoted premium, first-quote timestamps (total + Chubb + GAIG)
quote_rollup as (
    select
        q.business_id,
        min(q.created_at)                                                   as first_quote_created_at,
        count(*)                                                            as quote_count,
        sum(q.quoted_premium)                                               as total_quoted_premium,
        min(q.created_at)      filter (where c.carrier_group = 'Chubb')     as first_chubb_quote_created_at,
        sum(q.quoted_premium)  filter (where c.carrier_group = 'Chubb')     as chubb_quoted_premium,
        min(q.created_at)      filter (where c.carrier_group = 'GAIG')      as first_gaig_quote_created_at,
        sum(q.quoted_premium)  filter (where c.carrier_group = 'GAIG')      as gaig_quoted_premium
    from {{ ref('stg_quote') }} q
    join carrier c
        on c.carrier_id = q.carrier_id
    where q.business_id is not null
      and not c.is_test_carrier
    group by 1
),

-- revenue: signed ledger amounts. NB windows are measured from the business created date.
revenue_rollup as (
    select
        p.business_id,

        -- NB gross revenue (all types except CANCELLATION and *_PARTIAL)
        sum(t.signed_amount) filter (where p.is_new_business and t.is_gross_revenue
                                       and t.created_date - bd.business_created_date <= 7)      as d7_nb_gross_revenue,
        sum(t.signed_amount) filter (where p.is_new_business and t.is_gross_revenue
                                       and t.created_date - bd.business_created_date <= 14)     as d14_nb_gross_revenue,
        sum(t.signed_amount) filter (where p.is_new_business and t.is_gross_revenue
                                       and t.created_date - bd.business_created_date <= 30)     as d30_nb_gross_revenue,
        sum(t.signed_amount) filter (where p.is_new_business and t.is_gross_revenue)            as nb_gross_revenue,
        sum(t.signed_amount) filter (where p.is_new_business and t.is_gross_revenue and c.carrier_group = 'Chubb'
                                       and t.created_date - bd.business_created_date <= 30)     as d30_nb_chubb_gross_revenue,
        sum(t.signed_amount) filter (where p.is_new_business and t.is_gross_revenue and c.carrier_group = 'GAIG'
                                       and t.created_date - bd.business_created_date <= 30)     as d30_nb_gaig_gross_revenue,

        -- NB core revenue (commission + tech fee + agency fee)
        sum(t.signed_amount) filter (where p.is_new_business and t.is_core_revenue
                                       and t.created_date - bd.business_created_date <= 30)     as d30_nb_core_revenue,
        sum(t.signed_amount) filter (where p.is_new_business and t.is_core_revenue)             as nb_core_revenue,

        -- NB cancellations (signed, so clawbacks are negative)
        sum(t.signed_amount) filter (where p.is_new_business and t.is_cancellation)             as nb_cancellation_amount,
        min(t.created_at)    filter (where p.is_new_business and t.is_cancellation)             as first_nb_cancellation_booked_at,

        -- all sale types, core revenue
        sum(t.signed_amount) filter (where t.is_core_revenue)                                   as total_core_revenue

    from {{ ref('stg_policy_transaction') }} t
    join {{ ref('stg_policy') }} p
        on p.policy_id = t.policy_id
    join carrier c
        on c.carrier_id = p.carrier_id
    join business_dates bd
        on bd.business_id = p.business_id
    where not c.is_test_carrier
      and not t.is_partial_installment
    group by 1
),

-- Close lead-status milestones (ChangeLog coverage starts 2025-09-22)
close_status as (
    select
        business_id,
        min(created_at) filter (where new_close_status = 'Attempted to Contact')   as first_attempted_to_contact_at,
        min(created_at) filter (where new_close_status = 'Made Contact')           as first_made_contact_at,
        min(created_at) filter (where new_close_status = 'Junk')                   as first_junk_at,
        min(created_at) filter (where new_close_status = 'Customer')               as first_customer_status_at
    from {{ ref('stg_business_close_status_change') }}
    group by 1
),

-- opportunity stage milestones
opportunity_milestones as (
    select
        business_id,
        min(created_at) filter (where to_value = 'QUOTING')             as first_quoting_status_at,
        min(created_at) filter (where to_value like 'SIT%')             as first_sit_status_at,
        min(created_at) filter (where to_value = 'QUOTED')              as first_quoted_status_at,
        min(created_at) filter (where to_value = 'QUOTE_PRESENTED')     as first_quote_presented_at,
        min(created_at) filter (where to_value = 'WON')                 as first_won_status_at,
        min(created_at) filter (where to_value = 'LOST')                as first_lost_status_at
    from {{ ref('stg_opportunity_status_history') }}
    where change_type = 'STATUS'
      and business_id is not null
    group by 1
),

-- application milestones
application_milestones as (
    select
        business_id,
        min(created_at)                                                 as first_application_started_at,
        count(*) filter (where is_submitted)                            as submitted_application_count,
        min(created_at) filter (where is_submitted)                     as first_application_submitted_at,
        min(created_at) filter (where is_submitted and viewed)          as first_viewed_application_submitted_at,
        min(created_at) filter (where is_submitted and is_admin_rater)  as first_admin_rater_application_at,
        min(created_at) filter (where is_submitted and is_manual_application)
                                                                        as first_manual_application_at
    from {{ ref('stg_application_submission') }}
    where business_id is not null
    group by 1
),

joined as (
    select
        -- business
        b.business_id,
        b.user_id,
        b.close_lead_id,
        b.business_name,
        u.full_name                                                     as owner_name,
        u.email                                                         as owner_email,
        b.legal_entity_type,
        b.company_type,
        b.total_annual_revenue,
        b.total_annual_payroll,
        b.total_number_of_employees,
        b.years_in_business,
        b.close_status,
        b.is_high_risk,
        b.is_test_flag or coalesce(u.is_test_name, false)               as is_test_business,

        -- cohort
        b.created_at                                                    as business_created_at,
        b.created_date                                                  as business_created_date,
        b.created_week                                                  as business_created_week,
        b.created_month                                                 as business_created_month,
        (now() at time zone 'America/New_York')::date - b.created_date  as business_age_days,

        -- acquisition
        b.license_name,
        lic.partner_name,
        lic.partner_profile_type,
        coalesce(lic.transfer_type, 'Partner')                          as transfer_type,
        b.warm_transfer_campaign,
        b.campaign_type,
        cmp.campaign_name                                               as warm_transfer_campaign_name,
        case when wt.business_id is null then 'OTHER'
             else wt.warm_transfer_claimed_status end                   as claimed_status,
        wt.warm_transfer_status,
        wt.first_warm_transfer_at,
        coalesce(wt.warm_transfer_bid_price, 0)                         as warm_transfer_bid_price,

        -- people
        b.credited_account_executive,
        e.team                                                          as credited_ae_team,
        e.employee_type                                                 as credited_ae_employee_type,
        b.account_executive,
        b.account_manager,
        b.sold_by,
        l.lead_id,
        l.account_executive                                             as lead_account_executive,
        coalesce(l.workflow_type_assigned, 'NONE')                      as workflow_type,
        l.made_contact,
        l.is_junk,
        l.score                                                         as lead_score,
        l.created_at                                                    as lead_created_at,
        l.expiry_time                                                   as lead_expiry_time,

        -- industry
        cls.classification_name,
        cls.naics_code,
        cls.industry,
        cls.sub_industry,
        cls.naics_sub_industry,

        -- milestone timestamps
        cs.first_attempted_to_contact_at,
        cs.first_made_contact_at,
        cs.first_junk_at,
        cs.first_customer_status_at,
        am.first_application_started_at,
        am.first_application_submitted_at,
        am.first_viewed_application_submitted_at,
        am.first_admin_rater_application_at,
        am.first_manual_application_at,
        om.first_quoting_status_at,
        om.first_sit_status_at,
        om.first_quoted_status_at,
        om.first_quote_presented_at,
        om.first_won_status_at,
        om.first_lost_status_at,
        qr.first_quote_created_at,
        qr.first_chubb_quote_created_at,
        qr.first_gaig_quote_created_at,
        pr.first_policy_created_at,
        pr.first_nb_policy_created_at,
        pr.first_nb_chubb_policy_created_at,
        pr.first_nb_gaig_policy_created_at,
        rr.first_nb_cancellation_booked_at,

        -- days from business created date to each milestone
        cs.first_attempted_to_contact_at::date    - b.created_date      as days_to_attempted_to_contact,
        cs.first_made_contact_at::date            - b.created_date      as days_to_made_contact,
        cs.first_junk_at::date                    - b.created_date      as days_to_junk,
        am.first_application_submitted_at::date   - b.created_date      as days_to_application_submitted,
        om.first_quote_presented_at::date         - b.created_date      as days_to_quote_presented,
        qr.first_quote_created_at::date           - b.created_date      as days_to_first_quote,
        qr.first_chubb_quote_created_at::date     - b.created_date      as days_to_first_chubb_quote,
        qr.first_gaig_quote_created_at::date      - b.created_date      as days_to_first_gaig_quote,
        pr.first_policy_created_at::date          - b.created_date      as days_to_first_policy,
        pr.first_nb_policy_created_at::date       - b.created_date      as days_to_first_nb_policy,
        pr.first_nb_chubb_policy_created_at::date - b.created_date      as days_to_first_nb_chubb_policy,
        pr.first_nb_gaig_policy_created_at::date  - b.created_date      as days_to_first_nb_gaig_policy,

        -- volume measures
        coalesce(am.submitted_application_count, 0)                     as submitted_application_count,
        coalesce(qr.quote_count, 0)                                     as quote_count,
        coalesce(qr.total_quoted_premium, 0)                            as total_quoted_premium,
        coalesce(qr.chubb_quoted_premium, 0)                            as chubb_quoted_premium,
        coalesce(qr.gaig_quoted_premium, 0)                             as gaig_quoted_premium,
        coalesce(pr.policy_count, 0)                                    as policy_count,
        coalesce(pr.active_policy_count, 0)                             as active_policy_count,
        coalesce(pr.nb_policy_count, 0)                                 as nb_policy_count,

        -- premium measures
        coalesce(pr.total_premium, 0)                                   as total_premium,
        coalesce(pr.active_premium, 0)                                  as active_premium,
        coalesce(pr.nb_premium, 0)                                      as nb_premium,
        coalesce(pr.d30_nb_premium, 0)                                  as d30_nb_premium,
        coalesce(pr.nb_chubb_premium, 0)                                as nb_chubb_premium,
        coalesce(pr.d30_nb_chubb_premium, 0)                            as d30_nb_chubb_premium,
        coalesce(pr.nb_gaig_premium, 0)                                 as nb_gaig_premium,
        coalesce(pr.d30_nb_gaig_premium, 0)                             as d30_nb_gaig_premium,

        -- revenue measures
        coalesce(rr.d7_nb_gross_revenue, 0)                             as d7_nb_gross_revenue,
        coalesce(rr.d14_nb_gross_revenue, 0)                            as d14_nb_gross_revenue,
        coalesce(rr.d30_nb_gross_revenue, 0)                            as d30_nb_gross_revenue,
        coalesce(rr.nb_gross_revenue, 0)                                as nb_gross_revenue,
        coalesce(rr.d30_nb_chubb_gross_revenue, 0)                      as d30_nb_chubb_gross_revenue,
        coalesce(rr.d30_nb_gaig_gross_revenue, 0)                       as d30_nb_gaig_gross_revenue,
        coalesce(rr.d30_nb_core_revenue, 0)                             as d30_nb_core_revenue,
        coalesce(rr.nb_core_revenue, 0)                                 as nb_core_revenue,
        coalesce(rr.nb_cancellation_amount, 0)                          as nb_cancellation_amount,
        coalesce(rr.total_core_revenue, 0)                              as total_core_revenue

    from business b
    left join users u                   on u.user_id = b.user_id
    left join license lic               on lic.license_name = b.license_name
    left join employee e                on e.employee_name = b.credited_account_executive
    left join classification cls        on cls.business_classification_id = b.business_classification_id
    left join lead l                    on l.business_id = b.business_id
    left join warm_transfer wt          on wt.business_id = b.business_id
    left join campaign cmp              on cmp.campaign_status_id = wt.warm_transfer_campaign_status_id
    left join policy_rollup pr          on pr.business_id = b.business_id
    left join quote_rollup qr           on qr.business_id = b.business_id
    left join revenue_rollup rr         on rr.business_id = b.business_id
    left join close_status cs           on cs.business_id = b.business_id
    left join opportunity_milestones om on om.business_id = b.business_id
    left join application_milestones am on am.business_id = b.business_id
),

final as (
    select
        *,

        -- maturity: the cohort has had at least N full days to convert
        case when business_age_days >= 7  then 1 else 0 end            as is_mature_d7,
        case when business_age_days >= 14 then 1 else 0 end            as is_mature_d14,
        case when business_age_days >= 30 then 1 else 0 end            as is_mature_d30,
        case when business_age_days >= 60 then 1 else 0 end            as is_mature_d60,
        case when business_age_days >= 90 then 1 else 0 end            as is_mature_d90,

        -- contact / junk (0/1)
        case when days_to_attempted_to_contact <= 7 then 1 else 0 end  as d7_attempted_to_contact,
        case when days_to_made_contact <= 7 then 1 else 0 end          as d7_made_contact,
        case when days_to_junk <= 7 then 1 else 0 end                  as d7_junk,

        -- quote (0/1)
        case when first_quote_created_at is not null then 1 else 0 end as quoted,
        case when days_to_first_quote <= 7  then 1 else 0 end          as d7_quoted,
        case when days_to_first_quote <= 30 then 1 else 0 end          as d30_quoted,
        case when days_to_first_quote <= 30 then days_to_first_quote end
                                                                        as days_to_d30_quote,
        case when days_to_quote_presented <= 7 then 1 else 0 end       as d7_quote_presented,

        -- bind, any sale type (0/1)
        case when first_policy_created_at is not null then 1 else 0 end
                                                                        as converted,
        case when days_to_first_policy <= 1  then 1 else 0 end         as d1_converted,
        case when days_to_first_policy <= 7  then 1 else 0 end         as d7_converted,
        case when days_to_first_policy <= 14 then 1 else 0 end         as d14_converted,
        case when days_to_first_policy <= 30 then 1 else 0 end         as d30_converted,
        case when days_to_first_policy <= 60 then 1 else 0 end         as d60_converted,
        case when days_to_first_policy <= 90 then 1 else 0 end         as d90_converted,

        -- Chubb (0/1). Pair d7_chubb_quoted with chubb_quoted_premium for the tracker's
        -- d7ChubbQuotedPremiumAmount (all Chubb quote premium for businesses first quoted by day 7).
        case when days_to_first_chubb_quote <= 7 then 1 else 0 end     as d7_chubb_quoted,
        case when days_to_first_nb_chubb_policy <= 7  then 1 else 0 end
                                                                        as d7_chubb_converted,
        case when days_to_first_nb_chubb_policy <= 30 then 1 else 0 end
                                                                        as d30_chubb_converted,

        -- GAIG (0/1)
        case when days_to_first_gaig_quote <= 7 then 1 else 0 end      as d7_gaig_quoted,
        case when days_to_first_nb_gaig_policy <= 7  then 1 else 0 end as d7_gaig_converted,
        case when days_to_first_nb_gaig_policy <= 30 then 1 else 0 end as d30_gaig_converted

    from joined
)

select * from final
