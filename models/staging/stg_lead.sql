with source as (
    select * from {{ source('coverdash_prod', 'Lead') }}
),

renamed as (
    select
        -- identifiers
        id                              as lead_id,
        "businessId"                    as business_id,
        "userId"                        as user_id,

        -- assignment
        "accountExecutive"              as account_executive,
        "workflowTypeAssigned"          as workflow_type_assigned,

        -- status
        score,
        "madeContact"                   as made_contact,
        "isJunk"                        as is_junk,
        "timerPaused"                   as timer_paused,
        "isCurrentlyOnCallWithAe"       as is_currently_on_call_with_ae,

        -- timestamps
        "createdAt"                     as created_at,
        "expiryTime"                    as expiry_time,
        "pausedTime"                    as paused_time

    from source
)

select * from renamed
