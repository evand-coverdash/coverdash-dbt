{#
  Schema naming
  -------------
  prod target: models land in the plain folder schema (staging / intermediate / marts).
  any other target (dev): <target schema>_<folder schema>, e.g. dbt_analytics_dev_marts, so
  development runs never overwrite the tables dashboards read.
#}

{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- elif target.name == 'prod' -%}
        {{ custom_schema_name | trim }}
    {%- else -%}
        {{ target.schema }}_{{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
