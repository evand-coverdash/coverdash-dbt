/*
  int_ringba_call
  ---------------
  One row per Ringba inbound call: partner and campaign resolved, plus the call's routing outcome.

  Definitions
    - partner_name comes from the call's campaign (CampaignStatus -> Partner); 'Other' when the
      call has no campaign (~0.3% of calls).
    - is_routed: at least one AE was dialed (TargetDialed event).
    - is_answered: an AE picked up (ConnectedCall event; identical to RingbaCallLog.hasConnected).
    - is_missed: routed but no AE picked up.
    - is_unrouted: no AE was ever dialed (no events at all, no target found, ...).
    - is_duplicate: Ringba flagged the caller as a repeat within its dedupe window (DuplicateCall
      event). Duplicates are still routed and answered like any call; the flag matters for vendor
      billing, not for AE workload.
    - answered_by: the AE on the ConnectedCall event (at most one per call).
*/

with calls as (
    select * from {{ ref('stg_ringba_call') }}
),

events as (
    select * from {{ ref('stg_ringba_call_event') }}
),

campaign as (
    select campaign_status_id, partner_id, campaign_name, is_high_revenue_campaign
    from {{ ref('stg_campaign_status') }}
),

partner as (
    select partner_id, partner_name from {{ ref('stg_partner') }}
),

call_events as (
    select
        ringba_call_id,
        count(*)                                                            as event_count,
        count(distinct target_name)                                         as ae_count_dialed,
        bool_or(event_name = 'TargetDialed')                                as is_routed,
        bool_or(event_name = 'ConnectedCall')                               as is_answered,
        bool_or(event_name = 'DuplicateCall')                               as is_duplicate,
        bool_or(event_name = 'NoTargetFound')                               as is_no_target_found,
        count(*) filter (where event_name = 'NoAnswer')                     as no_answer_events,
        min(event_at) filter (where event_name = 'TargetDialed')            as first_dialed_at,
        min(event_at) filter (where event_name = 'ConnectedCall')           as answered_at,
        max(target_name) filter (where event_name = 'ConnectedCall')        as answered_by
    from events
    group by 1
)

select
    -- keys
    c.ringba_call_id,
    c.inbound_call_id,
    c.campaign_status_id,
    c.caller_number,

    -- date
    c.called_at,
    c.call_date,
    date_trunc('week',  c.call_date)::date                                  as call_week,
    date_trunc('month', c.call_date)::date                                  as call_month,

    -- source
    case when c.campaign_status_id is null then 'Other'
         else coalesce(p.partner_name, 'Other') end                         as partner_name,
    coalesce(cs.campaign_name, '(no campaign)')                             as campaign_name,
    coalesce(cs.is_high_revenue_campaign, false)                            as is_high_revenue_campaign,

    -- routing outcome
    coalesce(e.event_count, 0)                                              as event_count,
    coalesce(e.ae_count_dialed, 0)                                          as ae_count_dialed,
    coalesce(e.is_routed, false)                                            as is_routed,
    coalesce(e.is_answered, false)                                          as is_answered,
    coalesce(e.is_routed, false) and not coalesce(e.is_answered, false)     as is_missed,
    not coalesce(e.is_routed, false)                                        as is_unrouted,
    coalesce(e.is_duplicate, false)                                         as is_duplicate,
    coalesce(e.is_no_target_found, false)                                   as is_no_target_found,
    coalesce(e.no_answer_events, 0)                                         as no_answer_events,
    e.answered_by,
    e.first_dialed_at,
    e.answered_at,
    extract(epoch from e.answered_at - e.first_dialed_at)::int              as seconds_to_answer,

    -- talk time
    c.call_length_seconds,
    c.has_converted

from calls c
left join call_events e
    on e.ringba_call_id = c.ringba_call_id
left join campaign cs
    on cs.campaign_status_id = c.campaign_status_id
left join partner p
    on p.partner_id = cs.partner_id
