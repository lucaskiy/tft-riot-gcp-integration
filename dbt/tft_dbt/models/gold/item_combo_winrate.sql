-- =============================================================================
-- item_combo_winrate.sql
-- Melhor combinação completa de itens por unidade (BiS — Best in Slot)
-- Responde: "qual build de itens tem maior top4 rate no Syndra?"
-- Normaliza a ordem dos itens para evitar duplicatas (A+B = B+A)
-- =============================================================================

{{
    config(
        materialized = 'table',
        tags = ['gold', 'daily', 'winrate', 'items']
    )
}}

WITH items_exploded AS (
    SELECT
        match_id,
        puuid,
        character_id,
        tft_set_number,
        placement,
        top4,
        win,
        item_count,
        item
    FROM {{ ref('dim_units') }},
    UNNEST(JSON_VALUE_ARRAY(item_names_json)) AS item
    WHERE item_names_json IS NOT NULL
      AND item_count >= 2
),

-- Agrupa todos os itens de cada unit numa partida e normaliza a ordem
combo_per_unit AS (
    SELECT
        match_id,
        puuid,
        character_id,
        tft_set_number,
        placement,
        top4,
        win,
        item_count                                          AS item_combo_size,
        STRING_AGG(item, ' + ' ORDER BY item)               AS item_combo
    FROM items_exploded
    GROUP BY match_id, puuid, character_id, tft_set_number,
             placement, top4, win, item_count
)

SELECT
    tft_set_number,
    character_id,
    item_combo,
    item_combo_size,

    COUNT(*)                                        AS total_games,
    COUNTIF(top4)                                   AS total_top4,
    COUNTIF(win)                                    AS total_wins,
    ROUND(COUNTIF(top4) / COUNT(*) * 100, 2)        AS top4_rate,
    ROUND(COUNTIF(win)  / COUNT(*) * 100, 2)        AS win_rate,
    ROUND(AVG(placement), 2)                        AS avg_placement

FROM combo_per_unit
GROUP BY tft_set_number, character_id, item_combo, item_combo_size
HAVING COUNT(*) >= 5
ORDER BY character_id, top4_rate DESC
