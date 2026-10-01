/*
  stg_campaign_status
  -------------------
  One row per warm-transfer / call campaign.
*/

with source as (
    select * from {{ source('coverdash_prod', 'CampaignStatus') }}
),

renamed as (
    select
        id                                              as campaign_status_id,
        "partnerId"                                     as partner_id,
        "campaignName"                                  as campaign_name,
        "campaignExternalId"                            as campaign_external_id,
        "ringbaCampaignId"                              as ringba_campaign_id,
        "bidCost"::numeric                              as bid_cost,
        coalesce(available, false)                      as is_available,
        coalesce("isTivlyCampaign", false)              as is_tivly_campaign,
        coalesce("isHighRevenueCampaign", false)        as is_high_revenue_campaign,
        coalesce("containsEnterprise", false)           as contains_enterprise

    from source
)

select * from renamed
