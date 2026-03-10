-- =============================================================================
-- gold_item_winrate.sql
-- Taxa de top4 e vitória por item por unidade
-- Permite responder: qual item em qual unit tem maior winrate?
-- =============================================================================

{{
    config(
        materialized = 'table',
        tags = ['gold', 'daily', 'winrate', 'items']
    )
}}

WITH items_exploded AS (
    SELECT
        u.match_id,
        u.puuid,
        u.character_id,
        u.tier,
        u.tft_set_number,
        u.placement,
        u.top4,
        u.win,
        item_name
    FROM {{ ref('dim_units') }} u,
    UNNEST(JSON_VALUE_ARRAY(u.item_names_json)) AS item_name
    WHERE u.item_names_json IS NOT NULL
      AND JSON_VALUE_ARRAY(u.item_names_json) IS NOT NULL
)

SELECT
    tft_set_number,
    item_name,
    character_id,

    COUNT(*)                                        AS total_games,
    COUNTIF(top4)                                   AS total_top4,
    COUNTIF(win)                                    AS total_wins,
    ROUND(COUNTIF(top4) / COUNT(*) * 100, 2)        AS top4_rate,
    ROUND(COUNTIF(win)  / COUNT(*) * 100, 2)        AS win_rate,
    ROUND(AVG(placement), 2)                        AS avg_placement

FROM items_exploded
GROUP BY tft_set_number, item_name, character_id
HAVING COUNT(*) >= 10
ORDER BY top4_rate DESC