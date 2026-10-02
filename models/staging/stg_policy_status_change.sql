/*
  stg_policy_status_change
  ------------------------
  One row per change to Policy.status, from ChangeLog (coverage starts 2025-09-22).

  Notes
    - Rows are NOT de-duplicated or cleaned: the AE Sales snapshot logic in int_ae_sales_policy
      reproduces the app's frozen AccountExecutiveStat using these rows exactly as logged.
    - Deletions are logged with new_status NULL.
    - Filtered to one entityType / fieldName on purpose: ChangeLog is ~2.7M rows.
*/

with source as (
    select * from {{ source('coverdash_prod', 'ChangeLog') }}
    where "entityType" = 'POLICY'
      and "fieldName" = 'status'
)

select
    id                                                  as change_log_id,
    "entityId"                                          as policy_id,
    "oldValue"                                          as old_status,
    "newValue"                                          as new_status,
    "changedBy"                                         as changed_by,
    "createdAt"                                         as changed_at

from source
