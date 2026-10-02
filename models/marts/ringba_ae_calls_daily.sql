/*
  ringba_ae_calls_daily
  ---------------------
  Ringba calls per AE per day: calls routed to the AE, answered, and missed. Replaces the
  Ringba call query (date x targetName).

  Grain: call_date (Eastern) x account_executive x partner_name.

  Definitions
    - calls_routed: calls with any routing event for this AE (the old query's eventCount).
    - calls_answered: calls this AE picked up (ConnectedCall; the old query's connectedCallCount).
    - calls_missed: calls this AE was dialed on and didn't pick up. Another AE may have answered;
      see missed_calls_answered_by_other.
    - A call that rang three AEs counts once for each of them, so summing calls_routed across AEs
      exceeds the number of calls. Use ringba_calls_daily for call totals.
    - Dates use the call's Eastern start date (the old query used the UTC event date, which put
      evening calls on the next day).
*/

with call_ae as (
    select * from {{ ref('int_ringba_call_ae') }}
),

dates as (
    select * from {{ ref('dim_date') }}
)

select
    -- grain
    a.call_date,
    a.account_executive,
    a.partner_name,

    -- attributes of the grain
    max(a.ae_team)                                                          as ae_team,
    max(a.ae_employee_type)                                                 as ae_employee_type,
    max(d.week_start)                                                       as week_start,
    max(d.month_start)                                                      as month_start,
    bool_or(d.is_weekend)                                                   as is_weekend,

    -- outcome
    count(*)                                                                as calls_routed,
    count(*) filter (where a.was_dialed)                                    as calls_dialed,
    count(*) filter (where a.was_answered)                                  as calls_answered,
    count(*) filter (where a.was_missed)                                    as calls_missed,
    count(*) filter (where a.was_missed and a.call_was_answered)            as missed_calls_answered_by_other,
    count(*) filter (where a.was_answered and a.is_duplicate)               as duplicate_calls_answered,
    sum(a.no_answer_events)                                                 as no_answer_events,
    sum(a.busy_events)                                                      as busy_events,

    -- talk time on answered calls
    coalesce(sum(a.answered_call_length_seconds), 0)                        as answered_talk_seconds

from call_ae a
join dates d
    on d.date_day = a.call_date
group by 1, 2, 3
