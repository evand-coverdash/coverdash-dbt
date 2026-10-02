/*
  dim_date
  --------
  One row per calendar day from 2023-01-01 (first policy) through the end of next year.
  Join any daily mart to it on its date column to fill gaps (days with no activity) or to
  group by week / month / quarter consistently.

  Weeks start on Monday (Postgres date_trunc('week')). "Today" is Eastern at build time.
*/

with days as (
    select d::date as date_day
    from generate_series(
        date '2023-01-01',
        (date_trunc('year', now() at time zone 'America/New_York') + interval '2 years - 1 day')::date,
        interval '1 day'
    ) as d
)

select
    date_day,
    date_trunc('week',    date_day)::date                                   as week_start,
    date_trunc('month',   date_day)::date                                   as month_start,
    date_trunc('quarter', date_day)::date                                   as quarter_start,
    date_trunc('year',    date_day)::date                                   as year_start,
    extract(year    from date_day)::int                                     as year,
    extract(quarter from date_day)::int                                     as quarter,
    extract(month   from date_day)::int                                     as month,
    to_char(date_day, 'YYYY-MM')                                            as year_month,
    extract(day     from date_day)::int                                     as day_of_month,
    extract(isodow  from date_day)::int                                     as day_of_week,      -- 1 = Monday
    to_char(date_day, 'Dy')                                                 as day_name,
    extract(isodow  from date_day) in (6, 7)                                as is_weekend,
    (date_day = (date_trunc('month', date_day) + interval '1 month - 1 day')::date)
                                                                            as is_month_end,
    date_day <= (now() at time zone 'America/New_York')::date               as is_past_or_today,
    date_day = (now() at time zone 'America/New_York')::date                as is_today
from days
