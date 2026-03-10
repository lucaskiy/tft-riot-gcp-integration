-- =============================================================================
-- gold_player_match_obt.sql
-- One Big Table — base principal para exploração no Looker Studio
-- Uma linha por jogador por partida com arrays de units, traits e itens
-- =============================================================================

{{
    config(
        materialized     = 'table',
        tags = ['gold', 'daily', 'obt']
    )
}}

WITH units_agg AS (
    SELECT
        match_id,
        puuid,
        ARRAY_AGG(
            STRUCT(
                character_id,
                tier,
                rarity,
                item_names_json,
                item_count
            )
        ) AS units
    FROM {{ ref('dim_units') }}
    GROUP BY match_id, puuid
),

traits_agg AS (
    SELECT
        match_id,
        puuid,
        ARRAY_AGG(
            STRUCT(
                trait_name,
                num_units,
                tier_current,
                tier_total,
                style,
                is_active
            )
        ) AS traits
    FROM {{ ref('dim_traits') }}
    GROUP BY match_id, puuid
)

SELECT
    -- Partida
    p.match_id,
    m.game_datetime,
    m.game_length_minutes,
    m.game_version,
    m.tft_set_number,
    m.tft_set_core_name,
    m.tft_game_type,
    m.ingestion_date,

    -- Jogador
    p.puuid,
    p.riot_id_game_name,
    p.riot_id_tagline,

    -- Resultado
    p.placement,
    p.win,
    p.top4,
    p.level,
    p.gold_left,
    p.last_round,
    p.players_eliminated,
    p.total_damage_to_players,
    p.time_eliminated_seconds,

    -- Arrays desnormalizados
    u.units,
    t.traits

FROM {{ ref('fact_player_results') }}  p
LEFT JOIN {{ ref('dim_matches') }}     m  ON p.match_id = m.match_id
LEFT JOIN units_agg                    u  ON p.match_id = u.match_id AND p.puuid = u.puuid
LEFT JOIN traits_agg                   t  ON p.match_id = t.match_id AND p.puuid = t.puuid