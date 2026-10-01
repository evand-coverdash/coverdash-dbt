with source as (
    select * from {{ source('coverdash_prod', 'Quote') }}
),

renamed as (
    select
        -- identifiers
        id                              as quote_id,
        "businessId"                    as business_id,
        "applicationSubmissionId"       as application_submission_id,
        "carrierId"                     as carrier_id,
        "opportunityId"                 as opportunity_id,

        -- quote details
        "licenseName"                   as license_name,
        "policyTypeUpdated"             as policy_type,
        status,
        "billingType"                   as billing_type,
        "paymentInterval"               as payment_interval,
        "instantPay"                    as instant_pay,

        -- pricing
        price                           as quoted_premium,
        "agencyFees"                    as agency_fees,
        taxes,
        "technologyFee"                 as technology_fee,
        "policyFee"                     as policy_fee,
        "mmrFee"                        as mmr_fee,
        "otherFees"                     as other_fees,
        "commissionRate"                as commission_rate,

        -- payment plan
        "downPayment"                   as down_payment,
        "installmentAmount"             as installment_amount,
        "numOfInstallments"             as num_of_installments,

        -- timestamps
        "createdAt"                     as created_at,
        "expiresAt"                     as expires_at

    from source
)

select * from renamed
