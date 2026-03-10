-- =============================================================================
-- silver_matches.sql
-- Uma linha por partida — fatos da partida sem dados de jogadores
-- Incremental por match_id — só processa partidas novas
-- =============================================================================

{{
    config(
        materialized     = 'incremental',
        unique_key       = 'match_id',
        on_schema_change = 'sync_all_columns',
        tags             = ['silver', 'daily', 'matches']
    )
}}

SELECT
    match_id,
    data_version,
    game_id,
    game_datetime,
    ROUND(game_length_seconds / 60, 2)  AS game_length_minutes,
    game_version,
    queue_id,
    tft_set_core_name,
    tft_set_number,
    tft_game_type,
    end_of_game_result,
    ingestion_date,
    source_file,
    dbt_updated_at

FROM {{ ref('stg_matches') }}

{% if is_incremental() %}
    WHERE match_id NOT IN (SELECT match_id FROM {{ this }})
{% endif %}