/*
  stg_business_close_status_change
  --------------------------------
  One row per change to Business.closeStatus (the Close lead status), from ChangeLog.

  Notes
    - ChangeLog coverage starts 2025-09-22; businesses created earlier have incomplete history.
    - ChangeLog logs deletions as newValue NULL; those rows are dropped here.
    - Rows where the value didn't actually change (old = new) are dropped.
    - Filtered to one entityType / fieldName on purpose: ChangeLog is ~2.7M rows.
*/

with source as (
    select * from {{ source('coverdash_prod', 'ChangeLog') }}
    where "entityType" = 'BUSINESS'
      and "fieldName" = 'closeStatus'
),

renamed as (
    select
        id                                              as change_log_id,
        "entityId"                                      as business_id,
        "oldValue"                                      as old_close_status,
        "newValue"                                      as new_close_status,
        "changedBy"                                     as changed_by,
        "createdAt"                                     as created_at

    from source
    where "newValue" is not null
      and "oldValue" is distinct from "newValue"
)

select * from renamed
