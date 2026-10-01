/*
  stg_license
  -----------
  One row per partner license (integration / placement), with partner fields joined on.

  Notes
    - license_name is the join key everywhere (Business.licenseName, Quote.licenseName, ...).
    - transfer_type is the acquisition-channel bucket from the warm-transfer tracker. Add new
      licenses to these lists here so every downstream model picks them up.
*/

with source as (
    select * from {{ source('coverdash_prod', 'License') }}
),

partner as (
    select * from {{ source('coverdash_prod', 'Partner') }}
),

renamed as (
    select
        -- identifiers
        l.id                                            as license_id,
        l.name                                          as license_name,
        l."partnerId"                                   as partner_id,
        l."parentLicenseId"                             as parent_license_id,

        -- partner
        p.name                                          as partner_name,
        p."profileType"                                 as partner_profile_type,

        -- channel
        case
            when l.name in ('Housecall Pro - Sales Channel', 'Smart Financial', 'Smart Financial - Data Leads',
                            'CTQ', 'Tivly', 'Tivly - PathPoint', 'Bold Penguin', 'All Web Leads',
                            'Switchboard', 'QuinStreet')
                then 'Warm Transfer'
            when l.name in ('Trusted Choice - Prebidder', 'Trusted Choice', 'All Web Leads – Data Leads',
                            'All Web Leads – Fresh Data Leads', 'Swyft Filings - Sonic', 'Kapitus',
                            'Collective - Activation Flow')
                then 'Data Lead'
            when l.name in ('Coverdash Website', 'Coverdash Admin App', 'Coverdash Emails')
                then 'Other Non-Partner'
            else 'Partner'
        end                                             as transfer_type,

        -- config
        l."integrationType"                             as integration_type,
        l."leadIntakeType"                              as lead_intake_type,
        l."policyType"                                  as policy_type,
        l."companyType"                                 as company_type,
        coalesce(l."instantPayEnabled", false)          as is_instant_pay_enabled,
        coalesce(l."leadSellingEnabled", false)         as is_lead_selling_enabled,
        l."laqPriority"                                 as laq_priority,
        l."createdAt"                                   as created_at

    from source l
    left join partner p
        on p.id = l."partnerId"
)

select * from renamed
