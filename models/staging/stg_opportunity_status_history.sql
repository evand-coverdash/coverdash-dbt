/*
  stg_opportunity_status_history
  ------------------------------
  One row per opportunity change event (status, assignee, or confidence).

  Notes
    - change_type: STATUS / ASSIGNEE / CONFIDENCE. Stage-timing logic should filter to STATUS.
    - business_id is denormalized from Opportunity so downstream models don't need the join.
*/

with source as (
    select * from {{ source('coverdash_prod', 'OpportunityStatusHistory') }}
),

opportunity as (
    select id, "businessId" from {{ source('coverdash_prod', 'Opportunity') }}
),

renamed as (
    select
        h.id                                            as opportunity_status_history_id,
        h."opportunityId"                               as opportunity_id,
        o."businessId"                                  as business_id,
        h."changeType"                                  as change_type,
        h."from"                                        as from_value,
        h."to"                                          as to_value,
        h."createdAt"                                   as created_at

    from source h
    left join opportunity o
        on o.id = h."opportunityId"
)

select * from renamed
