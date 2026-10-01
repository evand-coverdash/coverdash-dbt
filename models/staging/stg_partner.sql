/*
  stg_partner
  -----------
  One row per partner company (each has one or more licenses).
  Secrets (clientSecret, Stripe keys) are intentionally not selected.
*/

with source as (
    select * from {{ source('coverdash_prod', 'Partner') }}
),

renamed as (
    select
        id                                              as partner_id,
        name                                            as partner_name,
        "profileType"                                   as partner_profile_type,
        coalesce("payGoEnabled", false)                 as is_paygo_enabled,
        "createdAt"                                     as created_at

    from source
)

select * from renamed
