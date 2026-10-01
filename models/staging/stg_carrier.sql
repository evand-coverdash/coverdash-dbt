/*
  stg_carrier
  -----------
  One row per carrier / wholesaler.

  Notes
    - is_test_carrier flags 'Fake Insurance' (test data).
    - carrier_group buckets the carriers we track individually in reporting (Chubb, GAIG);
      everything else is 'Other'. Add carriers here, not in downstream CASE statements.
*/

with source as (
    select * from {{ source('coverdash_prod', 'Carrier') }}
),

renamed as (
    select
        id                                              as carrier_id,
        name                                            as carrier_name,
        case name
            when 'Chubb'                          then 'Chubb'
            when 'Great American Insurance Group' then 'GAIG'
            else 'Other'
        end                                             as carrier_group,
        coalesce("isWholesaler", false)                 as is_wholesaler,
        coalesce("agencyBill", false)                   as is_agency_bill,
        name = 'Fake Insurance'                         as is_test_carrier

    from source
)

select * from renamed
