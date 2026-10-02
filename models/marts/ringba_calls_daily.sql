/*
  ringba_calls_daily
  ------------------
  Inbound Ringba calls by day, partner and campaign: how many came in, were routed to an AE,
  answered, or missed. Call-level view (each call counted once, however many AEs it rang).
  For per-AE answered / missed counts use ringba_ae_calls_daily.

  Grain: call_date (Eastern) x partner_name x campaign_name.
  Rates are ratio-of-sums in the BI layer, e.g. answer rate = sum(answered_calls) / sum(routed_calls),
  avg seconds to answer = sum(total_seconds_to_answer) / sum(answered_calls).
*/

with calls as (
    select * from {{ ref('int_ringba_call') }}
),

dates as (
    select * from {{ ref('dim_date') }}
)

select
    -- grain
    c.call_date,
    c.partner_name,
    c.campaign_name,

    -- attributes of the grain
    max(d.week_start)                                                       as week_start,
    max(d.month_start)                                                      as month_start,
    bool_or(d.is_weekend)                                                   as is_weekend,
    bool_or(c.is_high_revenue_campaign)                                     as is_high_revenue_campaign,

    -- volume and outcome
    count(*)                                                                as calls,
    count(*) filter (where c.is_routed)                                     as routed_calls,
    count(*) filter (where c.is_answered)                                   as answered_calls,
    count(*) filter (where c.is_missed)                                     as missed_calls,
    count(*) filter (where c.is_unrouted)                                   as unrouted_calls,
    count(*) filter (where c.is_duplicate)                                  as duplicate_calls,
    count(*) filter (where c.is_no_target_found)                            as no_target_found_calls,
    count(*) filter (where c.has_converted)                                 as converted_calls,

    -- routing effort and speed
    sum(c.ae_count_dialed)                                                  as ae_dials,
    sum(c.no_answer_events)                                                 as no_answer_events,
    coalesce(sum(c.seconds_to_answer) filter (where c.is_answered), 0)      as total_seconds_to_answer,

    -- talk time
    coalesce(sum(c.call_length_seconds) filter (where c.is_answered), 0)    as answered_talk_seconds

from calls c
join dates d
    on d.date_day = c.call_date
group by 1, 2, 3
