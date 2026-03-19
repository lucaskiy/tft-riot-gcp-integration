-- =============================================================================
-- item_combo_winrate.sql
-- Melhor combinação completa de itens por unidade (BiS — Best in Slot)
-- Responde: "qual build de itens tem maior top4 rate no Yasuo?"
-- Normaliza a ordem dos itens para evitar duplicatas (A+B = B+A)
-- =============================================================================

{{
    config(
        materialized = 'table',
        tags         = ['gold', 'daily', 'winrate', 'items']
    )
}}

WITH items_exploded AS (
    SELECT
        match_id,
        patch,
        puuid,
        character_id,
        tft_set_number,
        placement,
        top4,
        win,
        item_count,
        item
    FROM {{ ref('fact_units') }},
    UNNEST(JSON_VALUE_ARRAY(item_names_json)) AS item
    WHERE item_names_json IS NOT NULL
      AND item_count >= 2
),

combo_per_unit AS (
    SELECT
        match_id,
        patch,
        puuid,
        character_id,
        tft_set_number,
        placement,
        top4,
        win,
        item_count                                          AS item_combo_size,
        STRING_AGG(item, ' + ' ORDER BY item)               AS item_combo,
        -- Array de URLs dos itens para uso no Looker
        STRING_AGG(
            CONCAT(
                'https://storage.googleapis.com/tft-assets-tft-gcp-integration/items/',
                LOWER(item),
                '.png'
            ),
            ' | ' ORDER BY item
        )                                                   AS item_icon_urls
    FROM items_exploded
    GROUP BY match_id, patch, puuid, character_id, tft_set_number,
             placement, top4, win, item_count
)

SELECT
    tft_set_number,
    patch,

    -- Identificação da unidade
    character_id,
    REGEXP_REPLACE(character_id, r'^(?i)tft\d+_', '')                              AS character_name,
    CONCAT(
        'https://storage.googleapis.com/tft-assets-tft-gcp-integration/champions/',
        LOWER(character_id),
        '.png'
    )                                                                               AS icon_url,

    -- Combinação de itens
    item_combo,
    REGEXP_REPLACE(item_combo, r'(?i)tft\d+_item_|(?i)tft\d+_', '')               AS item_combo_display,

    -- URLs individuais dos ícones separadas por " | "
    -- Ex: "https://.../items/tft_item_bf.png | https://.../items/tft_item_ie.png"
    item_icon_urls,

    -- Primeira URL (item principal) para uso como imagem única no Looker
    SPLIT(item_icon_urls, ' | ')[OFFSET(0)]                                        AS item_icon_url_1,
    CASE WHEN ARRAY_LENGTH(SPLIT(item_icon_urls, ' | ')) > 1
        THEN SPLIT(item_icon_urls, ' | ')[OFFSET(1)] END                           AS item_icon_url_2,
    CASE WHEN ARRAY_LENGTH(SPLIT(item_icon_urls, ' | ')) > 2
        THEN SPLIT(item_icon_urls, ' | ')[OFFSET(2)] END                           AS item_icon_url_3,

    item_combo_size,

    COUNT(*)                                        AS total_games,
    COUNTIF(top4)                                   AS total_top4,
    COUNTIF(win)                                    AS total_wins,
    ROUND(COUNTIF(top4) / COUNT(*) * 100, 2)        AS top4_rate,
    ROUND(COUNTIF(win)  / COUNT(*) * 100, 2)        AS win_rate,
    ROUND(AVG(placement), 2)                        AS avg_placement,

    CASE
        WHEN COUNT(*) < 15                                       THEN 'N/A'
        WHEN ROUND(COUNTIF(top4) / COUNT(*) * 100, 2) >= 80      THEN 'S'
        WHEN ROUND(COUNTIF(top4) / COUNT(*) * 100, 2) >= 70      THEN 'A'
        WHEN ROUND(COUNTIF(top4) / COUNT(*) * 100, 2) >= 50      THEN 'B'
        ELSE 'C'
    END                                             AS tier_winrate

FROM combo_per_unit
GROUP BY tft_set_number, patch, character_id, item_combo, item_combo_size, item_icon_urls
HAVING COUNT(*) >= 5
ORDER BY character_id, top4_rate DESC