/*
  int_business_latest
  -------------------
  One row per business, enriched with lead assignment and first policy date.
  Used as the base for funnel and conversion analysis.
*/

with business as (
    select * from {{ ref('stg_business') }}
),

lead as (
    select * from {{ ref('stg_lead') }}
),

first_policy as (
    select
        business_id,
        min(created_at)                 as first_policy_created_at,
        count(*)                        as total_policies_bound,
        sum(premium)                    as total_lifetime_premium
    from {{ ref('stg_policy') }}
    where status = 'BOUND'
    group by 1
),

joined as (
    select
        -- business
        b.business_id,
        b.user_id,
        b.business_name,
        b.legal_entity_type,
        b.total_annual_revenue,
        b.total_annual_payroll,
        b.total_number_of_employees,
        b.years_in_business,
        b.created_at                    as business_created_at,

        -- lead
        l.lead_id,
        l.account_executive,
        l.made_contact,
        l.is_junk,
        l.score                         as lead_score,
        l.created_at                    as lead_created_at,
        l.expiry_time                   as lead_expiry_time,

        -- policy history
        fp.first_policy_created_at,
        fp.total_policies_bound,
        fp.total_lifetime_premium,

        -- derived
        case
            when fp.first_policy_created_at is not null then true
            else false
        end                             as has_bound_policy,

        case
            when fp.first_policy_created_at is not null and l.created_at is not null
            then extract(day from fp.first_policy_created_at - l.created_at)
        end                             as days_lead_to_first_policy

    from business b
    left join lead l
        on l.business_id = b.business_id
    left join first_policy fp
        on fp.business_id = b.business_id
)

select * from joined
