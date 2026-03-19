-- =============================================================================
-- core_comp_winrate.sql
-- Winrate por composição CORE — agrupa composições que compartilham o mesmo
-- núcleo de unidades independente das unidades de suporte/flexíveis
-- core_size = todas as unidades da composição (até 9)
-- =============================================================================

{{
    config(
        materialized = 'table',
        tags         = ['gold', 'daily', 'winrate', 'comp']
    )
}}

WITH units_ranked AS (
    SELECT
        match_id,
        patch,
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
    FROM {{ ref('fact_units') }}
),

core_units AS (
    SELECT
        match_id,
        patch,
        puuid,
        tft_set_number,
        placement,
        top4,
        win,
        STRING_AGG(character_id, ' | ' ORDER BY character_id)   AS core_key,
        -- Display sem prefixo
        STRING_AGG(
            REGEXP_REPLACE(character_id, r'(?i)tft\d+_', ''),
            ' | ' ORDER BY character_id
        )                                                        AS core_key_display,
        -- URLs dos ícones de cada unit do core separadas por " | "
        STRING_AGG(
            CONCAT(
                'https://storage.googleapis.com/tft-assets-tft-gcp-integration/champions/',
                LOWER(character_id),
                '.png'
            ),
            ' | ' ORDER BY character_id
        )                                                        AS core_icon_urls,
        COUNT(DISTINCT character_id)                             AS core_size
    FROM units_ranked
    GROUP BY match_id, patch, puuid, tft_set_number, placement, top4, win
),

primary_trait AS (
    SELECT
        match_id,
        puuid,
        trait_name AS primary_trait
    FROM {{ ref('fact_traits') }}
    WHERE is_active = TRUE
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY match_id, puuid
        ORDER BY tier_current DESC, num_units DESC
    ) = 1
)

SELECT
    c.tft_set_number,
    c.patch,
    c.core_key,
    c.core_key_display,
    c.core_icon_urls,

    -- URLs individuais para cada slot do core (até 6 units)
    SPLIT(c.core_icon_urls, ' | ')[OFFSET(0)]                                       AS unit_icon_1,
    CASE WHEN ARRAY_LENGTH(SPLIT(c.core_icon_urls, ' | ')) > 1
        THEN SPLIT(c.core_icon_urls, ' | ')[OFFSET(1)] END                          AS unit_icon_2,
    CASE WHEN ARRAY_LENGTH(SPLIT(c.core_icon_urls, ' | ')) > 2
        THEN SPLIT(c.core_icon_urls, ' | ')[OFFSET(2)] END                          AS unit_icon_3,
    CASE WHEN ARRAY_LENGTH(SPLIT(c.core_icon_urls, ' | ')) > 3
        THEN SPLIT(c.core_icon_urls, ' | ')[OFFSET(3)] END                          AS unit_icon_4,
    CASE WHEN ARRAY_LENGTH(SPLIT(c.core_icon_urls, ' | ')) > 4
        THEN SPLIT(c.core_icon_urls, ' | ')[OFFSET(4)] END                          AS unit_icon_5,
    CASE WHEN ARRAY_LENGTH(SPLIT(c.core_icon_urls, ' | ')) > 5
        THEN SPLIT(c.core_icon_urls, ' | ')[OFFSET(5)] END                          AS unit_icon_6,
    CASE WHEN ARRAY_LENGTH(SPLIT(c.core_icon_urls, ' | ')) > 6
        THEN SPLIT(c.core_icon_urls, ' | ')[OFFSET(6)] END                          AS unit_icon_7,
    CASE WHEN ARRAY_LENGTH(SPLIT(c.core_icon_urls, ' | ')) > 7
        THEN SPLIT(c.core_icon_urls, ' | ')[OFFSET(7)] END                          AS unit_icon_8,
    CASE WHEN ARRAY_LENGTH(SPLIT(c.core_icon_urls, ' | ')) > 8
        THEN SPLIT(c.core_icon_urls, ' | ')[OFFSET(8)] END                          AS unit_icon_9,

    c.core_size,
    pt.primary_trait,
    REGEXP_REPLACE(pt.primary_trait, r'^(?i)tft\d+_', '')                           AS primary_trait_display,

    COUNT(*)                                        AS total_games,
    COUNTIF(c.top4)                                 AS total_top4,
    COUNTIF(c.win)                                  AS total_wins,
    ROUND(COUNTIF(c.top4) / COUNT(*) * 100, 2)      AS top4_rate,
    ROUND(COUNTIF(c.win)  / COUNT(*) * 100, 2)      AS win_rate,
    ROUND(AVG(c.placement), 2)                      AS avg_placement,

    CASE
        WHEN COUNT(*) < 15                                       THEN 'N/A'
        WHEN ROUND(COUNTIF(top4) / COUNT(*) * 100, 2) >= 80      THEN 'S'
        WHEN ROUND(COUNTIF(top4) / COUNT(*) * 100, 2) >= 70      THEN 'A'
        WHEN ROUND(COUNTIF(top4) / COUNT(*) * 100, 2) >= 50      THEN 'B'
        ELSE 'C'
    END                                             AS tier_winrate

FROM core_units                 c
LEFT JOIN primary_trait         pt ON c.match_id = pt.match_id
                                   AND c.puuid   = pt.puuid
GROUP BY
    c.tft_set_number, c.patch, c.core_key, c.core_key_display,
    c.core_icon_urls, c.core_size, pt.primary_trait
HAVING COUNT(*) >= 3
ORDER BY top4_rate DESC