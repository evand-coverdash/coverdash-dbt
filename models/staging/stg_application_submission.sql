with source as (
    select * from {{ source('coverdash_prod', 'ApplicationSubmission') }}
),

renamed as (
    select
        -- identifiers
        id                              as application_submission_id,
        "businessId"                    as business_id,
        "userId"                        as user_id,

        -- application details
        "policyType"                    as policy_type,
        "licenseName"                   as license_name,
        status,
        source                          as submission_source,

        -- flags
        "isCrossSell"                   as is_cross_sell,
        "isHybrid"                      as is_hybrid,
        "isAdminQuotingTool"            as is_admin_quoting_tool,
        "isPostPurchaseCrossSell"       as is_post_purchase_cross_sell,
        "isRateCall1"                   as is_rate_call1,
        "isPaygo"                       as is_paygo,
        "reminded"                      as reminded,
        "viewed"                        as viewed,

        -- timestamps
        "createdAt"                     as created_at,
        "updatedAt"                     as updated_at,
        "effectiveDate"                 as effective_date,
        "expiryDate"                    as expiry_date,
        "viewedAt"                      as viewed_at

    from source
)

select * from renamed
