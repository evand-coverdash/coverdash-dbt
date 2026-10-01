/*
  business_funnel_daily
  ---------------------
  Daily funnel metrics showing how businesses progress from signup through
  first bind. One row per calendar day × license_name combination.

  Stages:
    1. businesses_created  — businesses created on this day
    2. applications_started — ApplicationSubmissions started by those businesses
    3. quotes_generated    — Quotes generated for those businesses
    4. policies_bound      — Policies bound for those businesses

  Use this model to track day-level conversion rates and identify where
  businesses are dropping off in the funnel.
*/

with businesses as (
    select
        date_trunc('day', business_created_at)::date   as activity_date,
        business_id,
        has_bound_policy,
        first_policy_created_at
    from {{ ref('int_business_latest') }}
),

applications as (
    select
        date_trunc('day', created_at)::date             as activity_date,
        business_id,
        license_name,
        application_submission_id
    from {{ ref('stg_application_submission') }}
    where not is_admin_quoting_tool
),

quotes as (
    select
        date_trunc('day', created_at)::date             as activity_date,
        business_id,
        license_name,
        quote_id
    from {{ ref('stg_quote') }}
),

policies as (
    select
        bound_date                                       as activity_date,
        business_id,
        license_name,
        policy_id,
        premium,
        estimated_commission
    from {{ ref('int_policy_revenue') }}
),

-- anchor on application date × license_name as the grain
daily_apps as (
    select
        activity_date,
        license_name,
        count(distinct business_id)                     as businesses_with_app,
        count(application_submission_id)                as applications_started
    from applications
    group by 1, 2
),

daily_quotes as (
    select
        activity_date,
        license_name,
        count(distinct business_id)                     as businesses_quoted,
        count(quote_id)                                 as quotes_generated
    from quotes
    group by 1, 2
),

daily_policies as (
    select
        activity_date,
        license_name,
        count(distinct business_id)                     as businesses_bound,
        count(policy_id)                                as policies_bound,
        sum(premium)                                    as total_premium_bound,
        sum(estimated_commission)                       as total_estimated_commission
    from policies
    group by 1, 2
),

daily_signups as (
    select
        date_trunc('day', business_created_at)::date    as activity_date,
        count(business_id)                              as businesses_created
    from {{ ref('int_business_latest') }}
    group by 1
),

joined as (
    select
        coalesce(a.activity_date, q.activity_date, p.activity_date)     as activity_date,
        coalesce(a.license_name,  q.license_name,  p.license_name)      as license_name,

        coalesce(a.businesses_with_app, 0)              as businesses_with_app,
        coalesce(a.applications_started, 0)             as applications_started,
        coalesce(q.businesses_quoted, 0)                as businesses_quoted,
        coalesce(q.quotes_generated, 0)                 as quotes_generated,
        coalesce(p.businesses_bound, 0)                 as businesses_bound,
        coalesce(p.policies_bound, 0)                   as policies_bound,
        coalesce(p.total_premium_bound, 0)              as total_premium_bound,
        coalesce(p.total_estimated_commission, 0)       as total_estimated_commission,

        -- conversion rates (quotes → bound)
        case
            when coalesce(q.quotes_generated, 0) > 0
            then round(
                coalesce(p.policies_bound, 0)::numeric
                / q.quotes_generated::numeric * 100, 2
            )
        end                                             as quote_to_bind_rate_pct

    from daily_apps a
    full outer join daily_quotes q
        on  q.activity_date = a.activity_date
        and q.license_name  = a.license_name
    full outer join daily_policies p
        on  p.activity_date = coalesce(a.activity_date, q.activity_date)
        and p.license_name  = coalesce(a.license_name,  q.license_name)
)

select
    j.*,
    s.businesses_created
from joined j
left join daily_signups s
    on s.activity_date = j.activity_date
order by activity_date desc, license_name
