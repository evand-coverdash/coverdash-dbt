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
        trim(coalesce("firstName", '') || ' ' || coalesce("lastName", ''))
                                        as full_name,
        phone,

        -- test-data rule used by the app's reports: owner name contains COVERDASH or TEST
        upper(coalesce("firstName", '') || ' ' || coalesce("lastName", '')) like '%COVERDASH%'
            or upper(coalesce("firstName", '') || ' ' || coalesce("lastName", '')) like '%TEST%'
                                        as is_test_name,

        -- status
        "isActive"                      as is_active,
        "subscribedToEmails"            as subscribed_to_emails,

        -- timestamps
        "createdAt"                     as created_at,
        "lastLogin"                     as last_login

    from source
)

select * from renamed
