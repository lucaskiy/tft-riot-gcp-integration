-- =============================================================================
-- gold_comp_winrate.sql
-- Taxa de top4 e vitória por composição de units
-- Composição = conjunto de units únicas em uma partida (ordenado alfabeticamente)
-- Permite responder: quais composições têm maior winrate?
-- =============================================================================

{{
    config(
        materialized = 'table',
        tags = ['gold', 'daily', 'winrate', 'comp']
    )
}}

WITH comp_per_player AS (
    SELECT
        match_id,
        puuid,
        tft_set_number,
        placement,
        top4,
        win,
        -- Gera string da composição ordenando os character_ids alfabeticamente
        STRING_AGG(character_id, ' | ' ORDER BY character_id) AS comp_key,
        COUNT(DISTINCT character_id)                           AS comp_size
    FROM {{ ref('dim_units') }}
    GROUP BY match_id, puuid, tft_set_number, placement, top4, win
)

SELECT
    tft_set_number,
    comp_key,
    comp_size,

    COUNT(*)                                        AS total_games,
    COUNTIF(top4)                                   AS total_top4,
    COUNTIF(win)                                    AS total_wins,
    ROUND(COUNTIF(top4) / COUNT(*) * 100, 2)        AS top4_rate,
    ROUND(COUNTIF(win)  / COUNT(*) * 100, 2)        AS win_rate,
    ROUND(AVG(placement), 2)                        AS avg_placement

FROM comp_per_player
GROUP BY tft_set_number, comp_key, comp_size
HAVING COUNT(*) >= 5
ORDER BY top4_rate DESC