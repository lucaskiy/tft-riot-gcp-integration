-- =============================================================================
-- stg_matches.sql
-- Extrai campos do JSON bruto da Bronze para colunas tipadas
-- View — sem custo de armazenamento, atualiza automaticamente
-- =============================================================================

{{
    config(
        materialized = 'view',
        tags         = ['staging', 'daily']
    )
}}

WITH raw AS (
    SELECT
        metadata,
        info,
        date        AS ingestion_date,
        _FILE_NAME  AS source_file
    FROM {{ source('bronze', 'raw_matches') }}
)

SELECT
    -- Identificação
    JSON_VALUE(metadata, '$.match_id')                              AS match_id,
    JSON_VALUE(metadata, '$.data_version')                          AS data_version,

    -- Partida
    CAST(JSON_VALUE(info, '$.gameId') AS INT64)                     AS game_id,
    TIMESTAMP_MILLIS(
        CAST(JSON_VALUE(info, '$.game_datetime') AS INT64)
    )                                                               AS game_datetime,
    CAST(JSON_VALUE(info, '$.game_length') AS FLOAT64)              AS game_length_seconds,
    JSON_VALUE(info, '$.game_version')                              AS game_version,
    CAST(JSON_VALUE(info, '$.queue_id') AS INT64)                   AS queue_id,
    JSON_VALUE(info, '$.tft_set_core_name')                         AS tft_set_core_name,
    CAST(JSON_VALUE(info, '$.tft_set_number') AS INT64)             AS tft_set_number,
    JSON_VALUE(info, '$.tft_game_type')                             AS tft_game_type,
    JSON_VALUE(info, '$.endOfGameResult')                           AS end_of_game_result,

    -- Participants raw para explodir na Silver
    JSON_QUERY(info, '$.participants')                              AS participants_json,

    -- Lineage
    ingestion_date,
    source_file,
    CURRENT_TIMESTAMP()                                             AS dbt_updated_at

FROM raw
WHERE JSON_VALUE(metadata, '$.match_id') IS NOT NULL