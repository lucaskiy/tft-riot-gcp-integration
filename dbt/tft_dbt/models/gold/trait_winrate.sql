-- =============================================================================
-- gold_trait_winrate.sql
-- Taxa de top4 e vitória por trait ativo
-- Permite responder: quais traits têm maior winrate? em qual tier?
-- =============================================================================

{{
    config(
        materialized = 'table',
        tags = ['gold', 'daily', 'winrate', 'traits']
    )
}}

SELECT
    tft_set_number,
    trait_name,
    tier_current,
    tier_total,

    COUNT(*)                                        AS total_games,
    COUNTIF(top4)                                   AS total_top4,
    COUNTIF(win)                                    AS total_wins,
    ROUND(COUNTIF(top4) / COUNT(*) * 100, 2)        AS top4_rate,
    ROUND(COUNTIF(win)  / COUNT(*) * 100, 2)        AS win_rate,
    ROUND(AVG(placement), 2)                        AS avg_placement,
    ROUND(AVG(num_units), 2)                        AS avg_units_in_trait

FROM {{ ref('dim_traits') }}
WHERE is_active = TRUE
GROUP BY tft_set_number, trait_name, tier_current, tier_total
HAVING COUNT(*) >= 10
ORDER BY top4_rate DESC