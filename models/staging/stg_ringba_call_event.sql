/*
  stg_ringba_call_event
  ---------------------
  One row per Ringba call event (TargetDialed, ConnectedCall, NoAnswer, DuplicateCall, ...).
  No rows are filtered. rawPayload is intentionally left out.

  Notes
    - eventTimestamp is UTC wall-clock; event_at converts it to Eastern.
    - target_name is the AE the call was routed to (matches EmployeeContactInformation.name).
      It's only set on routing events (TargetDialed, NoAnswer, BusyCall, ConnectedCall,
      ConvertedCall); call-level events (DuplicateCall, CallPlanDetail, ...) have no target.
    - failReason mostly holds Ringba ids, not readable reasons; kept for reference only.
*/

with source as (
    select * from {{ source('coverdash_prod', 'RingbaCallEvent') }}
),

renamed as (
    select
        id                                              as ringba_call_event_id,
        "ringbaCallLogId"                               as ringba_call_id,
        "eventName"                                     as event_name,
        "targetId"                                      as target_id,
        "targetName"                                    as target_name,
        "targetNumber"                                  as target_number,
        "conversionAmount"::numeric                     as conversion_amount,
        "failReason"                                    as fail_reason,
        "eventTimestamp" at time zone 'UTC' at time zone 'America/New_York'
                                                        as event_at,
        "eventTimestamp"                                as event_at_utc

    from source
)

select * from renamed
