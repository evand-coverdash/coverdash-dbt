/*
  int_warm_transfer
  -----------------
  One row per warm-transfer ping, with the vendor (partner) and campaign resolved and the
  downstream outcome of the business it created (if any) joined from int_business.

  Partner resolution, first non-null wins (partner_resolved_from says which):
    1. campaign   - CampaignStatus.partnerId
    2. business   - the created business's license -> partner
    3. payload    - stg_warm_transfer.payload_vendor (request-payload shape)
    4. 'Unknown'

  Campaign name: CampaignStatus.campaignName, else the AWL campaign in the payload, else
  Business.warmTransferCampaign.

  Downstream outcome columns are NULL when the ping created no business. Conversion windows are
  measured from the business created date, which is the ping date for accepted pings.
*/

with pings as (
    select * from {{ ref('stg_warm_transfer') }}
),

campaign as (
    select * from {{ ref('stg_campaign_status') }}
),

partner as (
    select partner_id, partner_name from {{ ref('stg_partner') }}
),

business as (
    select * from {{ ref('int_business') }}
),

joined as (
    select
        -- keys
        w.warm_transfer_id,
        w.business_id,
        w.campaign_status_id,

        -- date
        w.created_at,
        w.created_date,
        date_trunc('week',  w.created_at)::date                         as created_week,
        date_trunc('month', w.created_at)::date                         as created_month,
        (now() at time zone 'America/New_York')::date - w.created_date  as ping_age_days,

        -- vendor / campaign
        coalesce(cp.partner_name, b.partner_name, w.payload_vendor, 'Unknown')
                                                                        as partner_name,
        case
            when cp.partner_name   is not null then 'campaign'
            when b.partner_name    is not null then 'business'
            when w.payload_vendor  is not null then 'payload'
            else 'unknown'
        end                                                             as partner_resolved_from,
        coalesce(c.campaign_name, w.awl_campaign, b.warm_transfer_campaign)
                                                                        as campaign_name,
        coalesce(c.is_high_revenue_campaign, false)                     as is_high_revenue_campaign,

        -- ping outcome
        w.status,
        w.is_accepted,
        w.is_rejected,
        w.is_error,
        w.is_received,
        case when w.is_accepted then w.claimed_status end               as claimed_status,
        w.rejection_reason,
        w.rejection_reason_category,
        w.bid_price,
        case when w.is_accepted then w.bid_price end                    as accepted_bid_price,

        -- business it created
        b.license_name,
        b.transfer_type,
        b.credited_account_executive,
        b.credited_ae_team,
        b.workflow_type,
        coalesce(b.is_test_business, false)                             as is_test_business,
        b.quoted,
        b.d7_quoted,
        b.converted,
        b.d7_converted,
        b.d30_converted,
        b.nb_policy_count,
        b.nb_premium,
        b.d30_nb_premium,
        b.d30_nb_gross_revenue,
        b.nb_gross_revenue

    from pings w
    left join campaign c
        on c.campaign_status_id = w.campaign_status_id
    left join partner cp
        on cp.partner_id = c.partner_id
    left join business b
        on b.business_id = w.business_id
)

select * from joined
