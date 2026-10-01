with source as (
    select * from {{ source('coverdash_prod', 'Business') }}
),

renamed as (
    select
        -- identifiers
        id                              as business_id,
        "userId"                        as user_id,
        "businessClassificationId"      as business_classification_id,

        -- business info
        name                            as business_name,
        "legalEntityType"               as legal_entity_type,
        "companyType"                   as company_type,
        "yearsInBusiness"               as years_in_business,
        "businessStartYear"             as business_start_year,
        website,

        -- financials
        "totalAnnualRevenue"            as total_annual_revenue,
        "totalAnnualPayroll"            as total_annual_payroll,
        "totalNumberOfEmployees"        as total_number_of_employees,
        "numberOfOwnerOfficers"         as number_of_owner_officers,

        -- timestamps
        "createdAt"                     as created_at

    from source
)

select * from renamed
