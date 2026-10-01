/*
  stg_application_submission
  --------------------------
  One row per application (business x line of coverage). No rows are filtered.

  Notes
    - is_submitted: status in COMPLETED / SENT_TO_QUOTING_ENGINE / NO_QUOTES_RETURNED, i.e. the
      application actually reached quoting (the warm-transfer tracker's definition).
    - is_admin_rater: entered by staff in the admin quoting tool with no checkout batch.
    - is_manual_application: entered by staff in the admin quoting tool and attached to a batch.
    - quoteInputs / quoteProgress (jsonb) are intentionally left out; they're large and slow.
*/

with source as (
    select * from {{ source('coverdash_prod', 'ApplicationSubmission') }}
),

renamed as (
    select
        -- identifiers
        id                                              as application_submission_id,
        "businessId"                                    as business_id,
        "userId"                                        as user_id,
        "applicationSubmissionBatchId"                  as application_submission_batch_id,
        "employeeContactInformationId"                  as employee_contact_information_id,

        -- application details
        "policyType"                                    as policy_type,
        "licenseName"                                   as license_name,
        status,
        status in ('COMPLETED', 'SENT_TO_QUOTING_ENGINE', 'NO_QUOTES_RETURNED')
                                                        as is_submitted,
        source                                          as submission_source,

        -- flags
        coalesce("isCrossSell", false)                  as is_cross_sell,
        coalesce("isHybrid", false)                     as is_hybrid,
        coalesce("isAdminQuotingTool", false)           as is_admin_quoting_tool,
        coalesce("isAdminQuotingTool", false) and "applicationSubmissionBatchId" is null
                                                        as is_admin_rater,
        coalesce("isAdminQuotingTool", false) and "applicationSubmissionBatchId" is not null
                                                        as is_manual_application,
        coalesce("isPostPurchaseCrossSell", false)      as is_post_purchase_cross_sell,
        "isRateCall1"                                   as is_rate_call1,
        coalesce("isPaygo", false)                      as is_paygo,
        coalesce(reminded, false)                       as reminded,
        coalesce(viewed, false)                         as viewed,
        "missingFields"                                 as missing_fields,

        -- timestamps (Eastern)
        "createdAt"                                     as created_at,
        "createdAt"::date                               as created_date,
        "updatedAt"                                     as updated_at,
        "effectiveDate"::date                           as effective_date,
        "expiryDate"::date                              as expiry_date,
        "viewedAt"                                      as viewed_at

    from source
)

select * from renamed
