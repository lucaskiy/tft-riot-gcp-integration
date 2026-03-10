-- =============================================================================
-- silver_units.sql
-- Uma linha por unidade por jogador por partida
-- =============================================================================

{{
    config(
        materialized     = 'incremental',
        unique_key       = ['match_id', 'puuid', 'character_id', 'rarity'],
        on_schema_change = 'sync_all_columns',
        tags             = ['silver', 'daily', 'units']
    )
}}

WITH units_exploded AS (
    SELECT
        match_id,
        puuid,
        game_datetime,
        tft_set_number,
        placement,
        top4,
        win,
        u
    FROM {{ ref('fact_player_results') }},
    UNNEST(JSON_QUERY_ARRAY(units_json)) AS u
)

SELECT
    match_id,
    puuid,
    game_datetime,
    tft_set_number,
    placement,
    top4,
    win,

    JSON_VALUE(u, '$.character_id')                     AS character_id,
    CAST(JSON_VALUE(u, '$.tier') AS INT64)              AS tier,
    CAST(JSON_VALUE(u, '$.rarity') AS INT64)            AS rarity,

    -- Items equipados como array de strings
    JSON_QUERY(u, '$.itemNames')                        AS item_names_json,

    -- Quantidade de items
    ARRAY_LENGTH(JSON_QUERY_ARRAY(u, '$.itemNames'))    AS item_count,

    CURRENT_TIMESTAMP()                                 AS dbt_updated_at

FROM units_exploded

{% if is_incremental() %}
    WHERE match_id NOT IN (SELECT DISTINCT match_id FROM {{ this }})
{% endif %}