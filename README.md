# coverdash-dbt

dbt project for Coverdash analytics. It reads the prod app tables from the **prod read replica** and builds every model into a **separate analytics Postgres database**. dbt never has write access to prod.

```
prod read replica (read-only)        analytics database (writable)
  public."Business", ...   <- fdw --  replica."Business", ...   foreign tables, no data
                                      staging.stg_*             tables, pulled from the replica once per run
                                      intermediate.int_*        tables, built locally
                                      marts.*                   tables, read by BI / Google Sheets
```

## Layers

| Layer | Schema (prod target) | What it does |
|---|---|---|
| `models/staging` | `staging` | One model per source table. Renames columns to snake_case, casts money to numeric, puts timestamps on Eastern, adds row flags. No filtering. |
| `models/intermediate` | `intermediate` | Business logic at a clean grain: `int_business` (one row per business), `int_warm_transfer` (one row per ping), `int_policy_revenue`. |
| `models/marts` | `marts` | Reporting tables: `wt_tracker_daily`, `wt_pings_daily`, `business_funnel_daily`, `ae_performance_monthly`, `policy_revenue_summary`. |

Every model is built as a table. This matters: views over the foreign tables would re-query the replica every time anything read them.

## One-time setup (engineering)

Run these in the **analytics database** as an admin. Replace the `<...>` values with real ones.

```sql
-- 1. Link to the prod read replica
create extension if not exists postgres_fdw;

create server prod_replica
    foreign data wrapper postgres_fdw
    options (host '<replica host>', port '5432', dbname 'postgres', sslmode 'require',
             fetch_size '10000');            -- default is 100 rows per round trip; too slow for full pulls

-- 2. dbt's login to the analytics database
create role dbt_analytics login password '<dbt password>';
grant create on database <analytics db> to dbt_analytics;   -- lets dbt create staging / intermediate / marts

-- 3. How dbt's session authenticates to the replica (a READ-ONLY replica login)
create user mapping for dbt_analytics
    server prod_replica
    options (user '<replica read-only user>', password '<replica password>');

-- 4. Foreign tables (definitions only, no data copied)
create schema replica authorization dbt_analytics;
import foreign schema public from server prod_replica into replica;
grant usage on schema replica to dbt_analytics;
grant select on all tables in schema replica to dbt_analytics;
```

**When the app schema changes:** foreign tables don't pick up prod schema changes automatically. A new column is invisible and a dropped column errors. To refresh them, re-import:

```sql
drop schema replica cascade;
create schema replica authorization dbt_analytics;
import foreign schema public from server prod_replica into replica;
grant usage on schema replica to dbt_analytics;
grant select on all tables in schema replica to dbt_analytics;
```

Because every model is a table, nothing depends on the foreign tables between runs, so `cascade` only drops the foreign tables themselves.

## Running

```bash
cp profiles.example.yml profiles.yml        # gitignored; reads credentials from env vars
export DBT_HOST=<analytics host> DBT_DBNAME=<analytics db> DBT_USER=dbt_analytics DBT_PASSWORD=<...>
dbt deps                                     # installs dbt_utils
dbt build --target dev                       # builds and tests into dbt_analytics_dev_<layer>
dbt build --target prod                      # builds and tests into staging / intermediate / marts
```

- The `dev` target writes to `dbt_analytics_dev_staging` / `_intermediate` / `_marts`, so development runs never overwrite the tables dashboards read (see `macros/generate_schema_name.sql`).
- If the foreign-table schema isn't named `replica`, pass `--vars '{source_schema: <name>}'` or change `vars.source_schema` in `dbt_project.yml`.
- A full build is small (about 1.3M staging rows; the whole chain took about 9 seconds of query time when tested against the replica). Schedule `dbt build --target prod` hourly or daily.

## Conventions

- Timestamps are US Eastern wall-clock, except `Quote.createdAt`, which is UTC and converted in `stg_quote`.
- Revenue always excludes `COMMISSION_PARTIAL` / `TECHNOLOGY_ACCESS_FEE_PARTIAL`, which double-count their parent rows.
- New business means `sale_type = 'NEW_BUSINESS'` only (cross-sell excluded).
- Test data is flagged (`is_test_business`) in intermediate models and excluded in marts.
