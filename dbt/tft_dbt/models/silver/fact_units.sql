-- =============================================================================
-- fact_units.sql
-- Uma linha por unidade por jogador por partida
-- unit_key = chave surrogada para lidar com múltiplas cópias do mesmo campeão
-- (ex: 2x Yasuo tier 1 antes de virar 2 estrelas)
-- =============================================================================

{{
    config(
        materialized     = 'incremental',
        unique_key       = 'unit_key',
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
        ingestion_date,
        patch,
        u
    FROM {{ ref('fact_player_results') }},
    UNNEST(JSON_QUERY_ARRAY(units_json)) AS u
),

units_with_position AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY match_id, puuid
            ORDER BY JSON_VALUE(u, '$.character_id'), JSON_VALUE(u, '$.tier')
        ) AS unit_position
    FROM units_exploded
)

SELECT
    -- Chave surrogada: match + jogador + posição da unidade no array
    CONCAT(match_id, '_', puuid, '_', CAST(unit_position AS STRING)) AS unit_key,

    match_id,
    patch,
    puuid,
    game_datetime,
    tft_set_number,
    placement,
    top4,
    win,
    unit_position,

    JSON_VALUE(u, '$.character_id')                     AS character_id,
    CAST(JSON_VALUE(u, '$.tier') AS INT64)              AS tier,
    CAST(JSON_VALUE(u, '$.rarity') AS INT64)            AS rarity,

    -- Items equipados como array JSON de strings
    JSON_QUERY(u, '$.itemNames')                        AS item_names_json,

    -- Quantidade de items
    ARRAY_LENGTH(JSON_QUERY_ARRAY(u, '$.itemNames'))    AS item_count,

    ingestion_date,
    CURRENT_TIMESTAMP()                                 AS dbt_updated_at

FROM units_with_position

{% if is_incremental() %}
    WHERE ingestion_date >= (
        SELECT MAX(ingestion_date) FROM {{ this }}
    )
{% endif %}