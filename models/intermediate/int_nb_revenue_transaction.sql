/*
  int_nb_revenue_transaction
  --------------------------
  One row per PolicyTransaction that counts toward net new-business revenue ("Scenario D").

  Definitions
    - Date = when the transaction was booked (PolicyTransaction.createdAt, Eastern).
    - Scope: NEW_BUSINESS policies only (NULL sale type = NEW_BUSINESS; cross-sell excluded).
    - Types: COMMISSION, TECHNOLOGY_ACCESS_FEE, AGENCY_FEE, ENDORSEMENT, CANCELLATION.
      *_PARTIAL, OTHER and REFUND are excluded. Signed: RECEIVABLE +, PAYABLE -.
    - 90-day rule: cancellation-driven rows (stg_policy_transaction.is_cancellation_driven) count
      only if booked within 90 days of the policy's created_at. Rate-correction offsets always count.
    - Test data excluded: 'Fake Insurance' carrier, Business.isTest, owner name containing
      COVERDASH / TEST.
*/

with txn as (
    select * from {{ ref('stg_policy_transaction') }}
    where transaction_type in ('COMMISSION', 'TECHNOLOGY_ACCESS_FEE', 'AGENCY_FEE', 'ENDORSEMENT', 'CANCELLATION')
),

policy as (
    select * from {{ ref('stg_policy') }}
    where is_new_business
),

carrier as (
    select carrier_id, is_test_carrier from {{ ref('stg_carrier') }}
),

business as (
    select business_id, user_id, is_test_flag, created_at from {{ ref('stg_business') }}
),

users as (
    select user_id, is_test_name from {{ ref('stg_user') }}
)

select
    -- keys
    t.policy_transaction_id,
    t.policy_id,
    p.business_id,

    -- booking date (Eastern)
    t.created_at                                                            as booked_at,
    t.created_date                                                          as booked_date,

    -- classification
    t.transaction_type,
    case when t.transaction_type in ('TECHNOLOGY_ACCESS_FEE', 'AGENCY_FEE') then 'TECH_FEE'
         else t.transaction_type end                                        as revenue_bucket,
    t.direction,
    t.is_cancellation_driven,

    -- amount
    t.signed_amount,

    -- context
    p.created_at                                                            as policy_created_at,
    b.created_at                                                            as business_created_at,
    t.created_date - p.created_date                                         as days_policy_to_booking

from txn t
join policy p
    on p.policy_id = t.policy_id
join carrier c
    on c.carrier_id = p.carrier_id
join business b
    on b.business_id = p.business_id
left join users u
    on u.user_id = b.user_id
where not c.is_test_carrier
  and not b.is_test_flag
  and not coalesce(u.is_test_name, false)
  and not (t.is_cancellation_driven and t.created_at >= p.created_at + interval '90 days')
