{{
  config(
    materialized='incremental'
  )
}}

 with scroll_with_params as (
   select *,
      {{ ga4.unnest_key('event_params', 'percent_scrolled', 'int_value') }}
      {% if var("default_custom_parameters", "none") != "none" %}
        {{ ga4.stage_custom_parameters( var("default_custom_parameters") )}}
      {% endif %}
      {% if var("scroll_custom_parameters", "none") != "none" %}
        {{ ga4.stage_custom_parameters( var("scroll_custom_parameters") )}}
      {% endif %}
 from {{ref('stg_ga4__events')}}    
 where event_name = 'scroll'
 {% if is_incremental() %}
    and event_date_dt = CURRENT_DATE()
 {% endif %}
)

select * from scroll_with_params