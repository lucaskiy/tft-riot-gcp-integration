-- =============================================================================
-- dim_traits.sql
-- Uma linha por trait por jogador por partida
-- trait_name é a chave — ex: "TFT16_Bilgewater"
-- =============================================================================

{{
    config(
        materialized     = 'incremental',
        unique_key       = ['match_id', 'puuid', 'trait_name'],
        on_schema_change = 'sync_all_columns',
        tags             = ['silver', 'daily', 'traits']
    )
}}

WITH traits_exploded AS (
    SELECT
        match_id,
        puuid,
        game_datetime,
        tft_set_number,
        placement,
        top4,
        win,
        ingestion_date,
        t
    FROM {{ ref('fact_player_results') }},
    UNNEST(JSON_QUERY_ARRAY(traits_json)) AS t
)

SELECT
    match_id,
    puuid,
    game_datetime,
    tft_set_number,
    placement,
    top4,
    win,

    JSON_VALUE(t, '$.name')                             AS trait_name,
    CAST(JSON_VALUE(t, '$.num_units') AS INT64)         AS num_units,
    CAST(JSON_VALUE(t, '$.tier_current') AS INT64)      AS tier_current,
    CAST(JSON_VALUE(t, '$.tier_total') AS INT64)        AS tier_total,
    CAST(JSON_VALUE(t, '$.style') AS INT64)             AS style,
    CAST(JSON_VALUE(t, '$.tier_current') AS INT64) > 0  AS is_active,

    ingestion_date,
    CURRENT_TIMESTAMP()                                 AS dbt_updated_at

FROM traits_exploded

{% if is_incremental() %}
    WHERE ingestion_date >= (
        SELECT MAX(ingestion_date) FROM {{ this }}
    )
{% endif %}