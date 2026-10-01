/*
  stg_opportunity
  ---------------
  One row per sales opportunity (business x line), mirrored from Close.
*/

with source as (
    select * from {{ source('coverdash_prod', 'Opportunity') }}
),

renamed as (
    select
        -- identifiers
        id                                              as opportunity_id,
        "businessId"                                    as business_id,
        "policyId"                                      as policy_id,
        "closeOpportunityId"                            as close_opportunity_id,
        "employeeContactInformationId"                  as employee_contact_information_id,

        -- details
        "policyType"                                    as policy_type,
        status,
        status like 'SIT%'                              as is_surplus_lines,
        confidence,
        description,

        -- timestamps (Eastern)
        "createdAt"                                     as created_at,
        "updatedAt"                                     as updated_at,
        "statusLastUpdatedAt"                           as status_last_updated_at

    from source
)

select * from renamed
