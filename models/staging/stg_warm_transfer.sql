/*
  stg_warm_transfer
  -----------------
  One row per warm-transfer ping offered by a lead vendor. No rows are filtered.

  Notes
    - Most REJECTED / ERROR pings never create a Business, so business_id is NULL on ~half the rows.
      Use this model (via int_warm_transfer), not int_business, for ping counts, acceptance and
      rejection reasons.
    - ~73% of pings have no campaignStatusId (almost all All Web Leads data-lead pings).
      payload_vendor identifies the vendor from the request payload shape so those pings can
      still be attributed:
        awlToken key   -> All Web Leads
        pro_email key  -> Housecall Pro
        duns key       -> Bold Penguin (inferred: every business created from this payload
                          shape carries the Bold Penguin license)
    - claimed_status: NULL is treated as CLAIMED (tracker rule). Only meaningful on ACCEPTED pings.
    - bid_price is the vendor's offered price and is populated on rejected pings too; only
      accepted pings are a cost.
*/

with source as (
    select * from {{ source('coverdash_prod', 'WarmTransfer') }}
),

renamed as (
    select
        -- identifiers
        id                                              as warm_transfer_id,
        "businessId"                                    as business_id,
        "campaignStatusId"                              as campaign_status_id,
        "externalBusinessId"                            as external_business_id,

        -- status
        status,
        status = 'ACCEPTED'                             as is_accepted,
        status = 'REJECTED'                             as is_rejected,
        status = 'ERROR'                                as is_error,
        status = 'RECEIVED'                             as is_received,
        coalesce("claimedStatus", 'CLAIMED')            as claimed_status,
        "soldBy"                                        as sold_by,

        -- rejection
        "rejectionReason"                               as rejection_reason,
        case
            when "rejectionReason" is null                                          then null
            when "rejectionReason" ilike '%daily cap%'                              then 'Daily cap reached'
            when "rejectionReason" ilike '%rejection hours%'                        then 'Outside acceptance hours'
            when "rejectionReason" ilike 'No available AEs%'
              or "rejectionReason" ilike '%no agents available%'                    then 'No AE available'
            when "rejectionReason" ilike '%Commercial Auto%'                        then 'Commercial auto restriction'
            when "rejectionReason" ilike '%does not meet the lead requirements%'
              or "rejectionReason" ilike '%below minimum%'
              or "rejectionReason" ilike '%legal_entity_id%'
              or "rejectionReason" ilike '%unknown sicCode%'
              or "rejectionReason" ilike '%invalid awlCampaign%'                    then 'Did not meet lead requirements'
            when "rejectionReason" ilike 'Missing %'
              or "rejectionReason" ilike 'Invalid %'                                then 'Missing or invalid data'
            else 'Other'
        end                                             as rejection_reason_category,

        -- payload-derived attribution (see notes)
        -- key-exists (?) not ->>: the duns key is often present with a JSON null value
        case
            when "apiRequestJson" ? 'awlToken'  then 'All Web Leads'
            when "apiRequestJson" ? 'pro_email' then 'Housecall Pro'
            when "apiRequestJson" ? 'duns'      then 'Bold Penguin'
        end                                             as payload_vendor,
        nullif(trim("apiRequestJson" ->> 'awlCampaign'), '')
                                                        as awl_campaign,

        -- money
        "bidPrice"::numeric                             as bid_price,

        -- timestamps (Eastern)
        "createdAt"                                     as created_at,
        "createdAt"::date                               as created_date,
        "claimedAt"                                     as claimed_at,
        "laqAssignedAt"                                 as laq_assigned_at,
        "updatedAt"                                     as updated_at

    from source
)

select * from renamed
