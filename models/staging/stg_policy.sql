/*
  stg_policy
  ----------
  One row per policy term. Renamed and lightly cleaned; no rows are filtered.

  Notes
    - Money is cast float -> numeric so sums don't drift.
    - sale_type: NULL is treated as NEW_BUSINESS (app behaviour).
    - is_new_business = sale_type 'NEW_BUSINESS' only (cross-sell excluded, matching AE credit rules).
    - is_retained_sale_type = RENEWAL / REMARKET / RENEWAL_CANCEL_REWRITE.
    - Dates (effective/expiry/cancellation) are calendar dates stored at 00:00, cast to date.
*/

with source as (
    select * from {{ source('coverdash_prod', 'Policy') }}
),

renamed as (
    select
        -- identifiers
        id                                              as policy_id,
        "businessId"                                    as business_id,
        "carrierId"                                     as carrier_id,
        "quoteId"                                       as quote_id,
        "externalPolicyId"                              as external_policy_id,
        "closeOpportunityId"                            as close_opportunity_id,
        "closePolicyId"                                 as close_policy_id,
        "renewedFromPolicyId"                           as renewed_from_policy_id,
        "policyCancellationReasonId"                    as policy_cancellation_reason_id,

        -- policy details
        "policyType"                                    as policy_type,
        "licenseName"                                   as license_name,
        status,
        status = 'BOUND'                                as is_active,
        "billingType"                                   as billing_type,
        coalesce("saleType", 'NEW_BUSINESS')            as sale_type,
        coalesce("saleType", 'NEW_BUSINESS') = 'NEW_BUSINESS'
                                                        as is_new_business,
        coalesce("saleType", 'NEW_BUSINESS') in ('RENEWAL', 'REMARKET', 'RENEWAL_CANCEL_REWRITE')
                                                        as is_retained_sale_type,
        "salesChannel"                                  as sales_channel,
        "underwritingCarrier"                           as underwriting_carrier,

        -- people (Policy.accountExecutive is sparsely filled; prefer Sale / Business for credit)
        "accountExecutive"                              as account_executive,
        "assignedAgent"                                 as assigned_agent,

        -- financials
        premium::numeric                                as premium,
        "commissionablePremium"::numeric                as commissionable_premium,
        "commissionRate"::numeric                       as commission_rate,
        (premium * "commissionRate")::numeric           as estimated_commission,
        "downPayment"::numeric                          as down_payment,
        "monthlyPayment"::numeric                       as monthly_payment,
        "mmrFee"::numeric                               as mmr_fee,

        -- renewal / product flags
        "isRenewal"                                     as is_renewal,
        "renewalCount"                                  as renewal_count,
        "borRenewal"                                    as bor_renewal,
        "isCancelRewrite"                               as is_cancel_rewrite,
        "isReinstated"                                  as is_reinstated,
        coalesce("isPartial", false)                    as is_partial,
        coalesce("instantPay", false)                   as is_instant_pay,
        coalesce("isPaygo", false)                      as is_paygo,
        "isAutoBind"                                    as is_auto_bind,

        -- cancellation
        "cancellationStatus"                            as cancellation_status,
        "cancellationDate"::date                        as cancellation_date,
        "cancellationEffectiveDate"::date               as cancellation_effective_date,
        "cancellationReason"                            as cancellation_reason,
        "reinstatementDate"::date                       as reinstatement_date,
        "borAwayStatus"                                 as bor_away_status,
        "borAwayDate"::date                             as bor_away_date,

        -- dates
        "effectiveDate"::date                           as effective_date,
        "expiryDate"::date                              as expiry_date,
        "createdAt"                                     as created_at,
        "createdAt"::date                               as created_date,
        "updatedAt"                                     as updated_at

    from source
)

select * from renamed
