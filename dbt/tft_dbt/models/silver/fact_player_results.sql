-- =============================================================================
-- silver_participants.sql
-- Uma linha por jogador por partida (8 linhas por match)
-- Explode o array participants_json
-- =============================================================================

{{
    config(
        materialized     = 'incremental',
        unique_key       = ['match_id', 'puuid'],
        on_schema_change = 'sync_all_columns',
        partition_by     = {'field': 'ingestion_date', 'data_type': 'date'},
        tags             = ['silver', 'daily', 'participants']
    )
}}

WITH exploded AS (
    SELECT
        match_id,
        game_datetime,
        tft_set_number,
        ingestion_date,
        REGEXP_EXTRACT(game_version, r'16\.\d+\.\d+') AS patch,
        p
    FROM {{ ref('stg_matches') }},
    UNNEST(JSON_QUERY_ARRAY(participants_json)) AS p
),

parsed AS (
    SELECT
        match_id,
        game_datetime,
        tft_set_number,
        ingestion_date,
        patch,

        -- Identificação do jogador
        JSON_VALUE(p, '$.puuid')                                        AS puuid,
        JSON_VALUE(p, '$.riotIdGameName')                               AS riot_id_game_name,
        JSON_VALUE(p, '$.riotIdTagline')                                AS riot_id_tagline,

        -- Resultado
        CAST(JSON_VALUE(p, '$.placement') AS INT64)                     AS placement,
        CAST(JSON_VALUE(p, '$.win') AS BOOL)                            AS win,
        CAST(JSON_VALUE(p, '$.level') AS INT64)                         AS level,
        CAST(JSON_VALUE(p, '$.last_round') AS INT64)                    AS last_round,
        CAST(JSON_VALUE(p, '$.gold_left') AS INT64)                     AS gold_left,
        CAST(JSON_VALUE(p, '$.players_eliminated') AS INT64)            AS players_eliminated,
        CAST(JSON_VALUE(p, '$.total_damage_to_players') AS INT64)       AS total_damage_to_players,
        CAST(JSON_VALUE(p, '$.time_eliminated') AS FLOAT64)             AS time_eliminated_seconds,

        -- Top 4 flag (útil para análises de winrate)
        CAST(JSON_VALUE(p, '$.placement') AS INT64) <= 4                AS top4,

        -- Arrays para explodir em outras tabelas
        JSON_QUERY(p, '$.traits')                                       AS traits_json,
        JSON_QUERY(p, '$.units')                                        AS units_json,

        -- Companion (para análise de cosméticos se necessário)
        JSON_VALUE(p, '$.companion.species')                            AS companion_species,

        CURRENT_TIMESTAMP()                                             AS dbt_updated_at
    FROM exploded
)

SELECT * FROM parsed

{% if is_incremental() %}
    WHERE dbt_updated_at >= (
        SELECT MAX(dbt_updated_at) FROM {{ this }}
    )
{% endif %}