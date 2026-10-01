/*
  stg_policy_transaction
  ----------------------
  One row per PolicyTransaction (the revenue ledger). No rows are filtered.

  Notes
    - signed_amount: RECEIVABLE = +amount, PAYABLE = -amount, as numeric.
    - is_partial_installment: COMMISSION_PARTIAL / TECHNOLOGY_ACCESS_FEE_PARTIAL are installment
      receipts against a parent row that already carries the full amount. Always exclude them
      from revenue; they double-count.
    - is_core_revenue: COMMISSION + TECHNOLOGY_ACCESS_FEE + AGENCY_FEE (the admin app's definition).
    - is_gross_revenue: every type except CANCELLATION and the partials (the warm-transfer tracker's
      "gross revenue", i.e. core + ENDORSEMENT + OTHER + REFUND).
    - created_at = when the row was booked (Eastern).
*/

with source as (
    select * from {{ source('coverdash_prod', 'PolicyTransaction') }}
),

renamed as (
    select
        -- identifiers
        id                                              as policy_transaction_id,
        "policyId"                                      as policy_id,

        -- classification
        "transactionType"                               as transaction_type,
        direction,
        status,
        "transactionType" in ('COMMISSION_PARTIAL', 'TECHNOLOGY_ACCESS_FEE_PARTIAL')
                                                        as is_partial_installment,
        "transactionType" in ('COMMISSION', 'TECHNOLOGY_ACCESS_FEE', 'AGENCY_FEE')
                                                        as is_core_revenue,
        "transactionType" not in ('CANCELLATION', 'COMMISSION_PARTIAL', 'TECHNOLOGY_ACCESS_FEE_PARTIAL')
                                                        as is_gross_revenue,
        "transactionType" = 'CANCELLATION'              as is_cancellation,
        case
            when "transactionType" in ('COMMISSION', 'COMMISSION_PARTIAL')                       then 'COMMISSION'
            when "transactionType" in ('TECHNOLOGY_ACCESS_FEE', 'TECHNOLOGY_ACCESS_FEE_PARTIAL',
                                       'AGENCY_FEE')                                             then 'TECH_FEE'
            else "transactionType"
        end                                             as revenue_bucket,
        coalesce("isParent", false)                     as is_parent,
        "endorsementReason"                             as endorsement_reason,
        description,

        -- amounts
        amount::numeric                                 as amount,
        case when direction = 'RECEIVABLE' then amount else -amount end::numeric
                                                        as signed_amount,
        "totalAmount"::numeric                          as total_amount,
        "amountReceived"::numeric                       as amount_received,
        rate::numeric                                   as rate,
        "closedOut"                                     as closed_out,

        -- timestamps (Eastern)
        "createdAt"                                     as created_at,
        "createdAt"::date                               as created_date,
        date_trunc('month', "createdAt")::date          as created_month,
        "dueBy"                                         as due_by

    from source
)

select * from renamed
