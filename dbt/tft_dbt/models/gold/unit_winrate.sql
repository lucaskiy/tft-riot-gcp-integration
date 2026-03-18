-- =============================================================================
-- gold_unit_winrate.sql
-- Taxa de top4 e vitória por unidade
-- Permite responder: quais units têm maior winrate? em qual tier?
-- =============================================================================

{{
    config(
        materialized = 'table',
        tags = ['gold', 'daily', 'winrate', 'units']
    )
}}

-- Deduplica por jogador por partida — evita contar 2x quando há
-- múltiplas cópias do mesmo campeão (ex: 2x Yasuo tier 1)
WITH deduped AS (
    SELECT DISTINCT
        match_id,
        puuid,
        tft_set_number,
        character_id,
        tier,
        rarity,
        placement,
        top4,
        win
    FROM {{ ref('dim_units') }}
)

SELECT
    tft_set_number,
    character_id,
    REGEXP_REPLACE(character_id, r'^(?i)tft\d+_', '')                              AS character_name,
    CONCAT(
        'https://raw.communitydragon.org/latest/game/assets/ux/tft/championsplashes/',
        LOWER(REGEXP_REPLACE(character_id, r'^(?i)tft\d+_', 'tft16_')),
        '_square.png'
    )                                                                               AS icon_url,
    tier,
    rarity,

    COUNT(*)                                        AS total_games,
    COUNTIF(top4)                                   AS total_top4,
    COUNTIF(win)                                    AS total_wins,
    ROUND(COUNTIF(top4) / COUNT(*) * 100, 2)        AS top4_rate,
    ROUND(COUNTIF(win)  / COUNT(*) * 100, 2)        AS win_rate,
    ROUND(AVG(placement), 2)                        AS avg_placement,
    CASE
        WHEN ROUND(COUNTIF(top4) / COUNT(*) * 100, 2) >= 75 THEN 'S'
        WHEN ROUND(COUNTIF(top4) / COUNT(*) * 100, 2) >= 55 THEN 'A'
        WHEN ROUND(COUNTIF(top4) / COUNT(*) * 100, 2) >= 35 THEN 'B'
        ELSE 'C'
    END                                                 AS performance_tier

FROM deduped
GROUP BY tft_set_number, character_id, tier, rarity
HAVING COUNT(*) >= 10
ORDER BY top4_rate DESC