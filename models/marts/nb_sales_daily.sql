/*
  nb_sales_daily
  --------------
  Daily new-business sales: net NB revenue by the day it was booked ("Scenario D") and the
  AE Sales policy count by the day the policy was created. Replaces the monthly Scenario D /
  AE Sales-style query; roll up to months with month_start.

  Grain: activity_date x same_month_sale x license_name x account_executive.
  transfer_type, partner_name and the AE's team are attributes of license / AE.

  Definitions
    - Revenue rows come from int_nb_revenue_transaction (NB only, 5 transaction types, 90-day rule
      for cancellation-driven rows, test data excluded). activity_date = booked date (Eastern).
    - Policy rows come from int_ae_sales_policy where is_ae_sales_policy. activity_date = the
      policy's created date (Eastern).
    - same_month_sale: the activity month equals the business's created month.
    - account_executive = Business.soldBy, NULL kept as NULL (the AE Sales page shows NULL as
      'API Account').
    - business_count is additive within a calendar month: each business is counted once per
      month, on the day of its first counted transaction that month. sum() over a single month
      = distinct businesses with revenue that month. Summing across months counts a business
      once per month it had revenue.
    - nb_net_revenue = commission + tech_fee + endorsement + cancellation (the old query called
      this ae_gross_revenue).
*/

with revenue as (
    select
        booked_date                                                         as activity_date,
        business_id,
        revenue_bucket,
        signed_amount,
        row_number() over (
            partition by business_id, date_trunc('month', booked_date)
            order by booked_at, policy_transaction_id
        ) = 1                                                               as is_first_in_month
    from {{ ref('int_nb_revenue_transaction') }}
),

policies as (
    select
        policy_created_date                                                 as activity_date,
        business_id,
        policy_id,
        premium
    from {{ ref('int_ae_sales_policy') }}
    where is_ae_sales_policy
),

rows_unioned as (
    select
        activity_date, business_id,
        signed_amount                                                       as amount,
        revenue_bucket,
        case when is_first_in_month then 1 else 0 end                       as first_in_month,
        0                                                                   as policy_count,
        0::numeric                                                          as policy_premium
    from revenue

    union all

    select
        activity_date, business_id,
        0::numeric, null, 0,
        1,
        premium
    from policies
),

business as (
    select business_id, license_name, sold_by, created_month
    from {{ ref('stg_business') }}
),

license as (
    select license_name, partner_name, transfer_type from {{ ref('stg_license') }}
),

employee as (
    select employee_name, team from {{ ref('stg_employee_contact_information') }}
),

dates as (
    select * from {{ ref('dim_date') }}
)

select
    -- grain
    r.activity_date,
    date_trunc('month', r.activity_date)::date = b.created_month            as same_month_sale,
    coalesce(b.license_name, '(no license)')                                as license_name,
    b.sold_by                                                               as account_executive,

    -- attributes of the grain
    max(d.week_start)                                                       as week_start,
    max(d.month_start)                                                      as month_start,
    max(d.quarter_start)                                                    as quarter_start,
    max(d.year)                                                             as year,
    bool_or(d.is_weekend)                                                   as is_weekend,
    max(coalesce(l.transfer_type, 'Partner'))                               as transfer_type,
    max(l.partner_name)                                                     as partner_name,
    max(e.team)                                                             as ae_team,

    -- revenue (NB, net)
    sum(r.amount)                                                           as nb_net_revenue,
    sum(r.amount) filter (where r.revenue_bucket = 'COMMISSION')            as commission,
    sum(r.amount) filter (where r.revenue_bucket = 'TECH_FEE')              as tech_fee,
    sum(r.amount) filter (where r.revenue_bucket = 'ENDORSEMENT')           as endorsement,
    sum(r.amount) filter (where r.revenue_bucket = 'CANCELLATION')          as cancellation,
    sum(r.first_in_month)                                                   as business_count,

    -- AE Sales policies
    sum(r.policy_count)                                                     as ae_sales_policies,
    sum(r.policy_premium)                                                   as ae_sales_premium

from rows_unioned r
join business b
    on b.business_id = r.business_id
left join license l
    on l.license_name = b.license_name
left join employee e
    on e.employee_name = b.sold_by
join dates d
    on d.date_day = r.activity_date
group by 1, 2, 3, 4
