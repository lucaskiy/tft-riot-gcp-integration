-- =============================================================================
-- core_comp_winrate.sql
-- Winrate por composição CORE — agrupa composições que compartilham o mesmo
-- núcleo de unidades independente das unidades de suporte/flexíveis
-- core_size = 6 unidades com maior custo (mais importantes para a comp)
-- =============================================================================

{{
    config(
        materialized = 'table',
        tags         = ['gold', 'daily', 'winrate', 'comp']
    )
}}

WITH units_ranked AS (
    -- Ranqueia unidades por custo dentro de cada jogador/partida
    -- unidades mais caras = core da composição
    SELECT
        match_id,
        puuid,
        tft_set_number,
        placement,
        top4,
        win,
        character_id,
        rarity,
        ROW_NUMBER() OVER (
            PARTITION BY match_id, puuid
            ORDER BY rarity DESC, character_id ASC
        ) AS unit_rank
    FROM {{ ref('dim_units') }}
),

-- Pega as top 6 unidades por custo = core da composição
core_units AS (
    SELECT
        match_id,
        puuid,
        tft_set_number,
        placement,
        top4,
        win,
        STRING_AGG(character_id, ' | ' ORDER BY character_id) AS core_key,
        COUNT(DISTINCT character_id)                           AS core_size
    FROM units_ranked
    WHERE unit_rank <= 6
    GROUP BY match_id, puuid, tft_set_number, placement, top4, win
),

-- Trait principal da composição
primary_trait AS (
    SELECT
        match_id,
        puuid,
        trait_name AS primary_trait
    FROM {{ ref('dim_traits') }}
    WHERE is_active = TRUE
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY match_id, puuid
        ORDER BY tier_current DESC, num_units DESC
    ) = 1
)

SELECT
    c.tft_set_number,
    c.core_key,
    c.core_size,
    pt.primary_trait,

    COUNT(*)                                        AS total_games,
    COUNTIF(c.top4)                                 AS total_top4,
    COUNTIF(c.win)                                  AS total_wins,
    ROUND(COUNTIF(c.top4) / COUNT(*) * 100, 2)      AS top4_rate,
    ROUND(COUNTIF(c.win)  / COUNT(*) * 100, 2)      AS win_rate,
    ROUND(AVG(c.placement), 2)                      AS avg_placement,
    CASE
        WHEN ROUND(COUNTIF(c.top4) / COUNT(*) * 100, 2) >= 75 THEN 'S'
        WHEN ROUND(COUNTIF(c.top4) / COUNT(*) * 100, 2) >= 55 THEN 'A'
        WHEN ROUND(COUNTIF(c.top4) / COUNT(*) * 100, 2) >= 35 THEN 'B'
        ELSE 'C'
    END                                              AS tier

FROM core_units                 c
LEFT JOIN primary_trait         pt ON c.match_id = pt.match_id
                                   AND c.puuid   = pt.puuid
GROUP BY c.tft_set_number, c.core_key, c.core_size, pt.primary_trait
HAVING COUNT(*) >= 3
ORDER BY top4_rate DESC