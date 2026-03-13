-- =============================================================================
-- comp_winrate.sql
-- Winrate por composição de unidades + traits ativas
-- comp_key     = unidades ordenadas alfabeticamente
-- traits_key   = todas as traits ativas ordenadas por num_units desc
-- comp_full_key = comp_key + traits_key (chave combinada para análise exata)
-- Permite responder: "5 Ionia + 2 Brutamontes + 4 Colossos com X unidades"
-- =============================================================================

{{
    config(
        materialized = 'table',
        tags = ['gold', 'daily', 'winrate', 'comp']
    )
}}

WITH comp_per_player AS (
    SELECT
        u.match_id,
        u.puuid,
        u.tft_set_number,
        u.placement,
        u.top4,
        u.win,
        STRING_AGG(u.character_id, ' | ' ORDER BY u.character_id) AS units_key,
        COUNT(DISTINCT u.character_id)                             AS comp_size
    FROM {{ ref('dim_units') }} u
    GROUP BY u.match_id, u.puuid, u.tft_set_number, u.placement, u.top4, u.win
),

-- Todas as traits ativas agregadas por jogador
traits_per_player AS (
    SELECT
        match_id,
        puuid,
        STRING_AGG(
            CONCAT(CAST(tier_current AS STRING), ' ', trait_name),
            ' | '
            ORDER BY num_units DESC, trait_name
        ) AS traits_key,
        COUNT(DISTINCT trait_name) AS active_trait_count
    FROM {{ ref('dim_traits') }}
    WHERE is_active = TRUE
    GROUP BY match_id, puuid
),

-- Trait principal — maior tier ativo (eixo da composição)
primary_trait_per_player AS (
    SELECT
        match_id,
        puuid,
        trait_name AS primary_trait
    FROM {{ ref('dim_traits') }}
    WHERE is_active = TRUE
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY match_id, puuid
        ORDER BY tier_current DESC, SAFE_DIVIDE(tier_current, tier_total) DESC
    ) = 1
)

SELECT
    c.tft_set_number,
    m.game_version,
    c.units_key,
    COALESCE(t.traits_key, 'unknown')                               AS traits_key,
    CONCAT(c.units_key, ' || ', COALESCE(t.traits_key, ''))         AS comp_full_key,
    c.comp_size,
    COALESCE(t.active_trait_count, 0)                               AS active_trait_count,
    pt.primary_trait,

    COUNT(*)                                        AS total_games,
    COUNTIF(c.top4)                                 AS total_top4,
    COUNTIF(c.win)                                  AS total_wins,
    ROUND(COUNTIF(c.top4) / COUNT(*) * 100, 2)      AS top4_rate,
    ROUND(COUNTIF(c.win)  / COUNT(*) * 100, 2)      AS win_rate,
    ROUND(AVG(c.placement), 2)                      AS avg_placement,
    ROUND(AVG(p.level), 2)                          AS avg_level

FROM comp_per_player                               c
LEFT JOIN {{ ref('dim_matches') }}             m   ON c.match_id = m.match_id
LEFT JOIN {{ ref('fact_player_results') }}     p   ON c.match_id = p.match_id
                                                  AND c.puuid   = p.puuid
LEFT JOIN traits_per_player                    t   ON c.match_id = t.match_id
                                                  AND c.puuid   = t.puuid
LEFT JOIN primary_trait_per_player             pt  ON c.match_id = pt.match_id
                                                  AND c.puuid   = pt.puuid
GROUP BY
    c.tft_set_number,
    m.game_version,
    c.units_key,
    t.traits_key,
    c.comp_size,
    t.active_trait_count,
    pt.primary_trait
HAVING COUNT(*) >= 5
ORDER BY top4_rate DESC