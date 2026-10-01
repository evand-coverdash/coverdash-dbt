with source as (
    select * from {{ source('coverdash_prod', 'Policy') }}
),

renamed as (
    select
        -- identifiers
        id                              as policy_id,
        "businessId"                    as business_id,
        "carrierId"                     as carrier_id,
        "quoteId"                       as quote_id,
        "externalPolicyId"              as external_policy_id,
        "closeOpportunityId"            as close_opportunity_id,
        "closePolicyId"                 as close_policy_id,
        "renewedFromPolicyId"           as renewed_from_policy_id,

        -- policy details
        "policyType"                    as policy_type,
        "licenseName"                   as license_name,
        status,
        "billingType"                   as billing_type,
        "saleType"                      as sale_type,
        "salesChannel"                  as sales_channel,
        "underwritingCarrier"           as underwriting_carrier,

        -- people
        "accountExecutive"              as account_executive,
        "assignedAgent"                 as assigned_agent,

        -- financials
        premium,
        "commissionablePremium"         as commissionable_premium,
        "commissionRate"                as commission_rate,
        premium * "commissionRate"      as estimated_commission,
        "downPayment"                   as down_payment,
        "monthlyPayment"                as monthly_payment,
        "mmrFee"                        as mmr_fee,

        -- renewal flags
        "isRenewal"                     as is_renewal,
        "renewalCount"                  as renewal_count,
        "borRenewal"                    as bor_renewal,
        "isCancelRewrite"               as is_cancel_rewrite,
        "isReinstated"                  as is_reinstated,
        "isPaygo"                       as is_paygo,
        "isAutoBind"                    as is_auto_bind,

        -- cancellation
        "cancellationStatus"            as cancellation_status,
        "cancellationDate"              as cancellation_date,
        "cancellationReason"            as cancellation_reason,

        -- dates
        "effectiveDate"                 as effective_date,
        "expiryDate"                    as expiry_date,
        "createdAt"                     as created_at,
        "updatedAt"                     as updated_at

    from source
)

select * from renamed
