/*
  int_policy_revenue
  ------------------
  Bound policies enriched with revenue calculations and time dimensions.
  Used as the base for all revenue and commission mart models.

  license_name is the BUSINESS's license (the partner), not Policy.licenseName, which is empty
  on ~77% of active policies. The policy's own value is kept as policy_license_name.
*/

with policy as (
    select
        p.*,
        b.license_name                                      as business_license_name
    from {{ ref('stg_policy') }} p
    left join {{ ref('stg_business') }} b
        on b.business_id = p.business_id
    where p.status = 'BOUND'
),

enriched as (
    select
        -- keys
        policy_id,
        business_id,
        carrier_id,
        quote_id,
        close_opportunity_id,
        renewed_from_policy_id,

        -- dimensions
        policy_type,
        coalesce(business_license_name, '(no license)')     as license_name,
        license_name                                        as policy_license_name,
        billing_type,
        sale_type,
        sales_channel,
        underwriting_carrier,
        account_executive,
        assigned_agent,
        is_renewal,
        renewal_count,
        bor_renewal,
        is_auto_bind,
        is_paygo,

        -- revenue
        premium,
        commissionable_premium,
        commission_rate,
        estimated_commission,
        mmr_fee,

        -- dates
        effective_date,
        expiry_date,
        created_at                                          as bound_at,

        -- time dimensions for aggregation
        date_trunc('day',  created_at)::date                as bound_date,
        date_trunc('week', created_at)::date                as bound_week,
        date_trunc('month', created_at)::date               as bound_month,
        date_trunc('quarter', created_at)::date             as bound_quarter,
        extract(year from created_at)::integer              as bound_year,

        date_trunc('month', effective_date)::date           as effective_month

    from policy
)

select * from enriched
