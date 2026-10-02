# coverdash-dbt

dbt project for Coverdash analytics. It reads the production app tables in `public` and builds every model as a table in the **`analytics` schema** of the same database. The dbt login can create tables in `analytics` only and is read-only everywhere else, so it can't change app data. Everything built there replicates to the read replicas within about a second, and BI tools read the marts from the replica.

```
coverdash-prod PRIMARY                         read REPLICAS (BI tools connect here)
  public."Business", ...   (app tables)  ───►   public.*      (same data, read-only)
        │  dbt reads (read-only)
        ▼
  analytics.stg_*  ─►  analytics.int_*  ─►  analytics.<marts>   ───►   analytics.*   (~1 s behind)
```

## Layers

All models live in one schema (the login can't create schemas); the name prefix marks the layer.

| Folder | Prefix | What it does |
|---|---|---|
| `models/staging` | `stg_` | One model per source table. Renames columns to snake_case, casts money to numeric, puts timestamps on Eastern, adds row flags. No filtering. |
| `models/intermediate` | `int_` | Business logic at a clean grain: `int_business` (one row per business), `int_warm_transfer` (one row per ping), `int_policy_revenue`. |
| `models/marts` | none | Reporting tables: `wt_tracker_daily`, `wt_pings_daily`, `business_funnel_daily`, `ae_performance_monthly`, `policy_revenue_summary`. |

Every model is built as a **table**, never a view. A view in this database would depend on the app's tables and could block the app's Prisma schema migrations.

## Connection

| | |
|---|---|
| Host | `us-east-1.pg.psdb.cloud`, port 5432, database `postgres` |
| dbt login | `pscale_api_gjhxhe7cnogv.df5pi3b1h553` (connects to the primary; writes can't go to a replica) |
| Target schema | `analytics` |
| BI tools | Use a read-only login with the `\|replica` suffix. Logins with the built-in `pg_read_all_data` role can already read `analytics`. |

## Running

```bash
cp profiles.example.yml profiles.yml        # gitignored
export DBT_PASSWORD=<dbt login password>     # PowerShell: $env:DBT_PASSWORD = "<...>"
dbt deps                                     # installs dbt_utils
dbt debug                                    # checks the connection only
dbt build                                    # builds all models into analytics.* and runs the tests
```

- `dbt build` reads `public` and writes only to `analytics`. A full build is small (about 1.3M staging rows; the whole chain took about 9 seconds of query time when tested).
- **Schedule builds off-hours** or between dashboard refreshes. When dbt swaps a table in, a dashboard query reading that same table on a replica can be cancelled after 30 seconds. Re-running the query fixes it.
- **There's no separate dev schema yet.** Every run overwrites the tables the dashboards read. To test changes safely, ask engineering for an `analytics_dev` schema with the same grants, then use `dbt build --target dev`.

## Conventions

- Timestamps are US Eastern wall-clock, except `Quote.createdAt`, which is UTC and converted in `stg_quote`.
- Revenue always excludes `COMMISSION_PARTIAL` / `TECHNOLOGY_ACCESS_FEE_PARTIAL`, which double-count their parent rows.
- New business means `sale_type = 'NEW_BUSINESS'` only (cross-sell excluded).
- Test data is flagged (`is_test_business`) in intermediate models and excluded in marts.
