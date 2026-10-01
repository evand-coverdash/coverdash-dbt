/*
  stg_business_classification
  ---------------------------
  One row per industry classification (NAICS-based taxonomy).
  Per-carrier class codes and appetite columns are left out; add them if a model needs them.
*/

with source as (
    select * from {{ source('coverdash_prod', 'BusinessClassification') }}
),

renamed as (
    select
        id                                              as business_classification_id,
        display                                         as classification_name,
        naics17                                         as naics_code,
        industry,
        "subIndustry"                                   as sub_industry,
        filter3                                         as naics_sub_industry,
        "sicCode"                                       as sic_code

    from source
)

select * from renamed
