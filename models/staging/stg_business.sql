/*
  stg_business
  ------------
  One row per business. Renamed and lightly cleaned; no rows are filtered.

  Notes
    - created_at is Eastern wall-clock (no zone), like every Coverdash timestamp except Quote.createdAt.
    - credited_account_executive = coalesce(soldBy, accountExecutive), the AE credit rule from the
      warm-transfer tracker. soldBy can hold the literal 'API Account' (no AE picked the lead up).
    - is_test_flag is only Business.isTest. The full test-data rule (owner name contains
      COVERDASH/TEST) is applied in int_business as is_test_business.
*/

with source as (
    select * from {{ source('coverdash_prod', 'Business') }}
),

renamed as (
    select
        -- identifiers
        id                                              as business_id,
        "userId"                                        as user_id,
        "businessClassificationId"                      as business_classification_id,
        "closeId"                                       as close_lead_id,
        "leadOriginatorEmployeeId"                      as lead_originator_employee_id,
        "createdAtCohortId"                             as created_at_cohort_id,

        -- business info
        name                                            as business_name,
        upper(trim("legalEntityType"))                  as legal_entity_type,
        "companyType"                                   as company_type,
        "yearsInBusiness"                               as years_in_business,
        "businessStartYear"                             as business_start_year,
        website,

        -- financials
        "totalAnnualRevenue"                            as total_annual_revenue,
        "totalAnnualPayroll"                            as total_annual_payroll,
        "totalNumberOfEmployees"                        as total_number_of_employees,
        "numberOfOwnerOfficers"                         as number_of_owner_officers,

        -- acquisition
        "licenseName"                                   as license_name,
        "warmTransferCampaign"                          as warm_transfer_campaign,
        case when lower("warmTransferCampaign") like '%carrier%' then 'Test'
             else 'Prod' end                            as campaign_type,
        "tivlyCampaign"                                 as tivly_campaign,
        "partnerTrackingId"                             as partner_tracking_id,
        "isQualifiedPartnerLead"                        as is_qualified_partner_lead,
        "qualifiedPartnerLeadAt"                        as qualified_partner_lead_at,
        "hasBeenSold"                                   as has_been_sold,

        -- sales ops
        "accountExecutive"                              as account_executive,
        "accountManager"                                as account_manager,
        "soldBy"                                        as sold_by,
        coalesce("soldBy", "accountExecutive")          as credited_account_executive,
        "closeStatus"                                   as close_status,
        "closeJunkParentReason"                         as close_junk_parent_reason,
        "closeJunkExplanation"                          as close_junk_explanation,
        "isHighRisk"                                    as is_high_risk,
        "highRiskReason"                                as high_risk_reason,

        -- flags
        coalesce("isTest", false)                       as is_test_flag,

        -- timestamps (Eastern)
        "createdAt"                                     as created_at,
        "createdAt"::date                               as created_date,
        date_trunc('week',  "createdAt")::date          as created_week,
        date_trunc('month', "createdAt")::date          as created_month

    from source
)

select * from renamed
