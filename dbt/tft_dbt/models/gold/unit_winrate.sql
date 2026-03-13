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
    tier,
    rarity,

    COUNT(*)                                        AS total_games,
    COUNTIF(top4)                                   AS total_top4,
    COUNTIF(win)                                    AS total_wins,
    ROUND(COUNTIF(top4) / COUNT(*) * 100, 2)        AS top4_rate,
    ROUND(COUNTIF(win)  / COUNT(*) * 100, 2)        AS win_rate,
    ROUND(AVG(placement), 2)                        AS avg_placement

FROM deduped
GROUP BY tft_set_number, character_id, tier, rarity
HAVING COUNT(*) >= 10
ORDER BY top4_rate DESC