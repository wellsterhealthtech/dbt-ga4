{% set partitions_to_replace = ['current_date'] %}
{% for i in range(var('static_incremental_days')) %}
    {% set partitions_to_replace = partitions_to_replace.append('date_sub(current_date, interval ' + (i+1)|string + ' day)') %}
{% endfor %}
{% if var('property_ids', false) == false %}
    {% set relations_intraday = dbt_utils.get_relations_by_pattern(schema_pattern=var('dataset'), table_pattern='events_intraday_%', database=var('project')) %} 
{% endif %}
{{
    config(
        pre_hook="{{ ga4.combine_property_data() }}" if var('property_ids', false) else "",
        materialized = 'incremental',
        incremental_strategy = 'insert_overwrite',
        partition_by={
            "field": "event_date_dt",
            "data_type": "date",
        },
        partitions = partitions_to_replace,
        cluster_by=['event_name']
        
    )
}}

with source_daily as (
    select 
         
            
            parse_date('%Y%m%d',event_date) as event_date_dt,
            event_timestamp,
            DATETIME(TIMESTAMP_MICROS(event_timestamp), "Europe/Berlin") as event_timestamp_dt,
            event_name,
            event_params,
            event_previous_timestamp,
            event_value_in_usd,
            event_bundle_sequence_id,
            event_server_timestamp_offset,
            user_id,
            user_pseudo_id,
            privacy_info,
            user_properties,
            user_first_touch_timestamp,
            user_ltv,
            device,
            geo,
            app_info,
            traffic_source,
            stream_id,
            platform,
            ecommerce,

        (select array_agg(struct(d.item_id AS item_id,
                                        d.item_name AS item_name,
                                        d.item_brand AS item_brand,
                                        d.item_variant AS item_variant,
                                        d.item_category AS item_category,
                                        d.item_category2 AS item_category2,
                                        d.item_category3 AS item_category3,
                                        d.item_category4 AS item_category4,
                                        d.item_category5 AS item_category5,
                                        d.price_in_usd AS price_in_usd,
                                        d.price AS price,
                                        d.quantity AS quantity,
                                        d.item_revenue_in_usd AS item_revenue_in_usd,
                                        d.item_refund AS item_refund,
                                        d.coupon AS coupon,
                                        d.location_id AS location_id,
                                        d.item_list_id AS item_list_id,
                                        d.item_list_name AS item_list_name,
                                        d.promotion_id AS promotion_id,
                                        d.promotion_name AS promotion_name,
                                        d.creative_name AS creative_name,
                                        d.creative_slot AS creative_slot
                                    )
                                )
                from unnest(items) d
            ) as items
        from {{ source('ga4', 'events') }}
        where _table_suffix not like '%intraday%'
        and cast( left(_TABLE_SUFFIX, 8) as int64) >= {{var('start_date')}}
    {% if is_incremental() %}
        and parse_date('%Y%m%d', left(_TABLE_SUFFIX, 8)) in ({{ partitions_to_replace | join(',') }})
    {% endif %}
),

source_intraday as (
        select 
             
            
                parse_date('%Y%m%d',event_date) as event_date_dt,
                event_timestamp,
                DATETIME(TIMESTAMP_MICROS(event_timestamp), "Europe/Berlin") as event_timestamp_dt,
                event_name,
                event_params,
                event_previous_timestamp,
                event_value_in_usd,
                event_bundle_sequence_id,
                event_server_timestamp_offset,
                user_id,
                user_pseudo_id,
                privacy_info,
                user_properties,
                user_first_touch_timestamp,
                user_ltv,
                device,
                geo,
                app_info,
                traffic_source,
                stream_id,
                platform,
                ecommerce,

            (select array_agg(struct(d.item_id AS item_id,
                                            d.item_name AS item_name,
                                            d.item_brand AS item_brand,
                                            d.item_variant AS item_variant,
                                            d.item_category AS item_category,
                                            d.item_category2 AS item_category2,
                                            d.item_category3 AS item_category3,
                                            d.item_category4 AS item_category4,
                                            d.item_category5 AS item_category5,
                                            d.price_in_usd AS price_in_usd,
                                            d.price AS price,
                                            d.quantity AS quantity,
                                            d.item_revenue_in_usd AS item_revenue_in_usd,
                                            d.item_refund AS item_refund,
                                            d.coupon AS coupon,
                                            d.location_id AS location_id,
                                            d.item_list_id AS item_list_id,
                                            d.item_list_name AS item_list_name,
                                            d.promotion_id AS promotion_id,
                                            d.promotion_name AS promotion_name,
                                            d.creative_name AS creative_name,
                                            d.creative_slot AS creative_slot
                                        )
                                    )
                    from unnest(items) d
                ) as items
            from {{ source('ga4', 'events_intraday') }}
            where cast( left(_TABLE_SUFFIX, 8) as int64) >= {{var('start_date')}}
        {% if is_incremental() %}
            and parse_date('%Y%m%d', left(_TABLE_SUFFIX, 8)) in ({{ partitions_to_replace | join(',') }})
        {% endif %}
    ),
    unioned as (
        select *
        from source_daily
            union all
        select * 
        from source_intraday
    ),
    renamed as (
        select 
            {{ ga4.base_select_renamed() }}
        from unioned
    ),
    final as (
        select * from renamed
        qualify row_number() over(partition by event_date_dt, stream_id, user_pseudo_id, session_id, event_name, event_timestamp, to_json_string(ARRAY(SELECT params FROM UNNEST(event_params) AS params ORDER BY key))) = 1
    )

select *,
{{ map_stream_id("stream_id", var("stream_properties", "none")) }} AS stream_name
from final