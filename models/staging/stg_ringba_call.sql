/*
  stg_ringba_call
  ---------------
  One row per inbound call tracked by Ringba (warm-transfer / call campaigns). No rows are filtered.

  Notes
    - Ringba timestamps (callDt) are UTC wall-clock, unlike almost every other Coverdash
      timestamp. called_at converts them to Eastern; called_at_utc keeps the raw value.
    - ingestedAt is Eastern (when our system received the call record).
    - ~8% of calls have no callDt, no events, and zero length: never routed. They're kept,
      dated by ingestion (call_date falls back to ingested_at), and flagged downstream.
*/

with source as (
    select * from {{ source('coverdash_prod', 'RingbaCallLog') }}
),

renamed as (
    select
        -- identifiers
        id                                              as ringba_call_id,
        "inboundCallId"                                 as inbound_call_id,
        "campaignStatusId"                              as campaign_status_id,
        "ringbaCampaignId"                              as ringba_campaign_id,
        "callerNumber"                                  as caller_number,

        -- outcome
        coalesce("hasConnected", false)                 as has_connected,
        coalesce("hasConverted", false)                 as has_converted,
        coalesce("callLengthInSeconds", 0)              as call_length_seconds,

        -- timestamps
        "callDt" at time zone 'UTC' at time zone 'America/New_York'
                                                        as called_at,
        "callDt"                                        as called_at_utc,
        "ingestedAt"                                    as ingested_at,
        coalesce("callDt" at time zone 'UTC' at time zone 'America/New_York', "ingestedAt")::date
                                                        as call_date

    from source
)

select * from renamed
