/*
  int_ringba_call_ae
  ------------------
  One row per Ringba call x AE the call was routed to (~30% of calls ring more than one AE
  before someone answers).

  Definitions
    - was_dialed: a TargetDialed event for this AE on this call.
    - was_answered: this AE picked up (ConnectedCall). At most one AE per call.
    - was_missed: this AE was dialed and didn't pick up (another AE may have answered).
    - no_answer_events / busy_events: Ringba's NoAnswer / BusyCall events for this AE.
    - AE team / type come from EmployeeContactInformation by name (all Ringba targets match).
*/

with events as (
    select * from {{ ref('stg_ringba_call_event') }}
    where target_name is not null
),

calls as (
    select * from {{ ref('int_ringba_call') }}
),

employee as (
    select employee_name, employee_type, team
    from {{ ref('stg_employee_contact_information') }}
),

call_ae as (
    select
        ringba_call_id,
        target_name                                                         as account_executive,
        bool_or(event_name = 'TargetDialed')                                as was_dialed,
        bool_or(event_name = 'ConnectedCall')                               as was_answered,
        count(*) filter (where event_name = 'NoAnswer')                     as no_answer_events,
        count(*) filter (where event_name = 'BusyCall')                     as busy_events,
        min(event_at) filter (where event_name = 'TargetDialed')            as first_dialed_at,
        min(event_at) filter (where event_name = 'ConnectedCall')           as answered_at
    from events
    group by 1, 2
)

select
    -- keys
    ca.ringba_call_id,
    ca.account_executive,
    e.team                                                                  as ae_team,
    e.employee_type                                                         as ae_employee_type,

    -- call attributes
    c.call_date,
    c.call_week,
    c.call_month,
    c.partner_name,
    c.campaign_name,
    c.caller_number,
    c.is_duplicate,
    c.is_answered                                                           as call_was_answered,

    -- this AE's outcome
    ca.was_dialed,
    ca.was_answered,
    ca.was_dialed and not ca.was_answered                                   as was_missed,
    ca.no_answer_events,
    ca.busy_events,
    ca.first_dialed_at,
    ca.answered_at,
    case when ca.was_answered then c.call_length_seconds end                as answered_call_length_seconds

from call_ae ca
join calls c
    on c.ringba_call_id = ca.ringba_call_id
left join employee e
    on e.employee_name = ca.account_executive
