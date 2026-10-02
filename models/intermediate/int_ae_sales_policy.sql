/*
  int_ae_sales_policy
  -------------------
  One row per policy, with the AE Sales "policies bound" eligibility rebuilt as of the app's
  monthly snapshot. Mirrors the frozen AccountExecutiveStat.policiesBound count
  (reproduced within 0-6 policies per month for Jan-Aug 2026).

  is_ae_sales_policy is true when ALL of:
    - sale_type NEW_BUSINESS (NULL counts) OR the policy is a broker-of-record renewal (borRenewal)
    - premium > 0
    - status at the snapshot is not CANCELLED. Snapshot = 05:05 ET on the 1st of the month after
      the policy was created (when the app freezes AE stats). Status is rebuilt from ChangeLog:
      the last status change before the snapshot, else the "from" value of the first change
      after it, else the current status. ChangeLog starts 2025-09-22, so older policies use the
      current status.
    - not on the 'Fake Insurance' carrier, Business.isTest not true
    - AE Sales test-name rule: excluded only when the owner has BOTH a first and last name and
      the full name contains COVERDASH or TEST (slightly narrower than the standard rule)
    - the business has an owner User, an industry classification and a license that exists
      (the app's report inner-joins all three)
*/

with policy as (
    select
        p.*,
        date_trunc('month', p.created_at) + interval '1 month 5 hours 5 minutes' as snapshot_at
    from {{ ref('stg_policy') }} p
),

status_change as (
    select * from {{ ref('stg_policy_status_change') }}
),

last_change_before as (
    select distinct on (p.policy_id)
        p.policy_id,
        sc.new_status
    from policy p
    join status_change sc
        on sc.policy_id = p.policy_id
       and sc.changed_at < p.snapshot_at
    order by p.policy_id, sc.changed_at desc
),

first_change_after as (
    select distinct on (p.policy_id)
        p.policy_id,
        sc.old_status
    from policy p
    join status_change sc
        on sc.policy_id = p.policy_id
       and sc.changed_at >= p.snapshot_at
    order by p.policy_id, sc.changed_at asc
),

business as (
    select business_id, user_id, business_classification_id, license_name, is_test_flag
    from {{ ref('stg_business') }}
),

users as (
    select user_id, first_name, last_name from {{ ref('stg_user') }}
),

carrier as (
    select carrier_id, is_test_carrier from {{ ref('stg_carrier') }}
),

classification as (
    select business_classification_id from {{ ref('stg_business_classification') }}
),

license as (
    select license_name from {{ ref('stg_license') }}
),

joined as (
    select
        p.policy_id,
        p.business_id,
        p.created_at                                                        as policy_created_at,
        p.created_date                                                      as policy_created_date,
        p.sale_type,
        p.bor_renewal,
        p.premium,
        p.status                                                            as current_status,
        p.snapshot_at,
        coalesce(lb.new_status, fa.old_status, p.status)                    as status_at_snapshot,

        -- eligibility parts
        (p.is_new_business or coalesce(p.bor_renewal, false))               as is_eligible_sale_type,
        coalesce(p.premium > 0, false)                                      as has_premium,
        coalesce(c.is_test_carrier, false)                                  as is_test_carrier,
        coalesce(b.is_test_flag, false)                                     as is_test_business_flag,
        coalesce(
            u.first_name is not null and u.last_name is not null
            and (upper(u.first_name || ' ' || u.last_name) like '%COVERDASH%'
                 or upper(u.first_name || ' ' || u.last_name) like '%TEST%'),
            false)                                                          as is_test_name_ae_rule,
        (u.user_id is not null
         and cls.business_classification_id is not null
         and lic.license_name is not null)                                  as has_required_joins

    from policy p
    left join last_change_before lb     on lb.policy_id = p.policy_id
    left join first_change_after fa     on fa.policy_id = p.policy_id
    left join carrier c                 on c.carrier_id = p.carrier_id
    left join business b                on b.business_id = p.business_id
    left join users u                   on u.user_id = b.user_id
    left join classification cls        on cls.business_classification_id = b.business_classification_id
    left join license lic               on lic.license_name = b.license_name
)

select
    *,
    is_eligible_sale_type
        and has_premium
        and status_at_snapshot is distinct from 'CANCELLED'
        and not is_test_carrier
        and not is_test_business_flag
        and not is_test_name_ae_rule
        and has_required_joins                                              as is_ae_sales_policy
from joined
