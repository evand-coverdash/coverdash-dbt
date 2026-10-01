/*
  stg_quote
  ---------
  One row per quote. Renamed and lightly cleaned; no rows are filtered.

  Notes
    - Quote.createdAt is the ONLY timestamptz in the DB (real UTC). created_at here is converted to
      Eastern wall-clock so it lines up with every other model; the raw value is kept as created_at_utc.
    - Money is cast float -> numeric.
*/

with source as (
    select * from {{ source('coverdash_prod', 'Quote') }}
),

renamed as (
    select
        -- identifiers
        id                                              as quote_id,
        "businessId"                                    as business_id,
        "applicationSubmissionId"                       as application_submission_id,
        "carrierId"                                     as carrier_id,
        "opportunityId"                                 as opportunity_id,

        -- quote details
        "licenseName"                                   as license_name,
        "policyTypeUpdated"                             as policy_type,
        status,
        "billingType"                                   as billing_type,
        "paymentInterval"                               as payment_interval,
        coalesce("instantPay", false)                   as is_instant_pay,
        coalesce("isHybridPay", false)                  as is_hybrid_pay,
        status = 'MANUAL'                               as is_manual,
        coalesce("isVisible", true)                     as is_visible,
        "underwritingCarrier"                           as underwriting_carrier,

        -- pricing
        price::numeric                                  as quoted_premium,
        "agencyFees"::numeric                           as agency_fees,
        taxes::numeric                                  as taxes,
        "technologyFee"::numeric                        as technology_fee,
        "policyFee"::numeric                            as policy_fee,
        "mmrFee"::numeric                               as mmr_fee,
        "otherFees"::numeric                            as other_fees,
        "commissionRate"::numeric                       as commission_rate,

        -- payment plan
        "downPayment"::numeric                          as down_payment,
        "installmentAmount"::numeric                    as installment_amount,
        "numOfInstallments"                             as num_of_installments,

        -- timestamps
        "createdAt" at time zone 'America/New_York'     as created_at,
        ("createdAt" at time zone 'America/New_York')::date
                                                        as created_date,
        "createdAt"                                     as created_at_utc,
        "expiresAt"                                     as expires_at

    from source
)

select * from renamed
