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
),

-- Deduplica — evita contar 2x o mesmo item quando há cópias do campeão
deduped AS (
    SELECT DISTINCT
        match_id,
        puuid,
        character_id,
        tier,
        tft_set_number,
        placement,
        top4,
        win,
        item_name
    FROM items_exploded
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
    ROUND(AVG(placement), 2)                        AS avg_placement,
    CASE
        WHEN ROUND(COUNTIF(top4) / COUNT(*) * 100, 2) >= 75 THEN 'S'
        WHEN ROUND(COUNTIF(top4) / COUNT(*) * 100, 2) >= 55 THEN 'A'
        WHEN ROUND(COUNTIF(top4) / COUNT(*) * 100, 2) >= 35 THEN 'B'
        ELSE 'C'
    END                                             AS tier

FROM deduped
GROUP BY tft_set_number, item_name, character_id
HAVING COUNT(*) >= 10
ORDER BY top4_rate DESC