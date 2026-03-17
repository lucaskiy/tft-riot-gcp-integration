-- =============================================================================
-- trait_comp_winrate.sql
-- Winrate por combinação de traits ativas (independente das unidades)
-- Permite responder: "qual combinação de traits tem melhor winrate?"
-- Ex: "5 Ionia + 2 Brutamontes + 4 Colossos" → top4_rate, win_rate
-- =============================================================================

{{
    config(
        materialized = 'table',
        tags = ['gold', 'daily', 'winrate', 'traits', 'comp']
    )
}}

WITH traits_per_player AS (
    SELECT
        match_id,
        puuid,
        tft_set_number,
        placement,
        top4,
        win,
        -- Composição de traits: "4 Colosso | 5 Ionia | 2 Brutamontes"
        STRING_AGG(
            CONCAT(CAST(tier_current AS STRING), ' ', trait_name),
            ' | '
            ORDER BY num_units DESC, trait_name
        ) AS trait_comp_key,
        COUNT(DISTINCT trait_name) AS active_trait_count,
        -- Traits principais (num_units >= 4) para filtro de análise
        STRING_AGG(
            IF(num_units >= 4,
                CONCAT(CAST(tier_current AS STRING), ' ', trait_name),
                NULL
            ),
            ' | '
            ORDER BY num_units DESC
        ) AS dominant_traits_key
    FROM {{ ref('dim_traits') }}
    WHERE is_active = TRUE
    GROUP BY match_id, puuid, tft_set_number, placement, top4, win
)

SELECT
    tft_set_number,
    trait_comp_key,
    dominant_traits_key,
    active_trait_count,

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
    END                                             AS tier

FROM traits_per_player
GROUP BY tft_set_number, trait_comp_key, dominant_traits_key, active_trait_count
HAVING COUNT(*) >= 5
ORDER BY top4_rate DESC