with source as (
    select * from {{ source('coverdash_prod', 'User') }}
),

renamed as (
    select
        -- identifiers
        id                              as user_id,

        -- contact info
        email,
        "firstName"                     as first_name,
        "lastName"                      as last_name,
        phone,

        -- status
        "isActive"                      as is_active,
        "subscribedToEmails"            as subscribed_to_emails,

        -- timestamps
        "createdAt"                     as created_at,
        "lastLogin"                     as last_login

    from source
)

select * from renamed
