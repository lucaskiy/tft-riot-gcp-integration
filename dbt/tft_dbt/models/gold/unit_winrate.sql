-- =============================================================================
-- unit_winrate.sql
-- Taxa de top4 e vitória por unidade
-- Permite responder: quais units têm maior winrate? em qual tier?
-- Inclui média de itens equipados e trait mais frequente com a unit
-- =============================================================================

{{
    config(
        materialized = 'table',
        tags = ['gold', 'daily', 'winrate', 'units']
    )
}}

WITH primary_traits AS (
    -- Trait de maior tier ativo por jogador por partida
    SELECT
        match_id,
        puuid,
        trait_name AS top_trait
    FROM {{ ref('dim_traits') }}
    WHERE is_active = TRUE
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY match_id, puuid
        ORDER BY tier_current DESC
    ) = 1
)

SELECT
    u.tft_set_number,
    u.character_id,
    u.tier,
    u.rarity,

    COUNT(*)                                            AS total_games,
    COUNTIF(u.top4)                                     AS total_top4,
    COUNTIF(u.win)                                      AS total_wins,
    ROUND(COUNTIF(u.top4) / COUNT(*) * 100, 2)          AS top4_rate,
    ROUND(COUNTIF(u.win)  / COUNT(*) * 100, 2)          AS win_rate,
    ROUND(AVG(u.placement), 2)                          AS avg_placement,
    ROUND(AVG(u.item_count), 2)                         AS avg_item_count,
    -- Trait primário mais comum entre partidas com esta unit
    APPROX_TOP_COUNT(pt.top_trait, 1)[OFFSET(0)].value  AS most_played_with_trait

FROM {{ ref('dim_units') }} u
LEFT JOIN primary_traits    pt  ON u.match_id = pt.match_id
                               AND u.puuid   = pt.puuid
GROUP BY u.tft_set_number, u.character_id, u.tier, u.rarity
HAVING COUNT(*) >= 10
ORDER BY top4_rate DESC
