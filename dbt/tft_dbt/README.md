# TFT dbt — Camada Silver

## Setup

```bash
pip install -r requirements.txt

# Autentica com GCP
gcloud auth application-default login

# O profiles.yml fica em ~/.dbt/profiles.yml (fora do projeto — não commitar)
# Conteúdo esperado:
# tft_dbt:
#   target: dev
#   outputs:
#     dev:
#       type: bigquery
#       method: oauth
#       project: tft-gcp-integration
#       dataset: tft_staging
#       location: US
#       threads: 4
#       timeout_seconds: 300

# Testa a conexão
dbt debug
```

## Estrutura dos modelos

```
Bronze (External Table GCS — tft_bronze.raw_matches)
    ↓
staging/stg_matches          — JSON parseado em colunas tipadas (view)
    ↓
silver/silver_matches        — 1 linha por partida (incremental)
silver/silver_participants   — 1 linha por jogador por partida (incremental)
    ↓
silver/silver_traits         — 1 linha por trait por jogador (incremental)
silver/silver_units          — 1 linha por unidade por jogador (incremental)
```

## Tabelas geradas no BigQuery

| Dataset       | Tabela                 | Descrição                        |
|---------------|------------------------|----------------------------------|
| tft_staging   | stg_matches            | JSON parseado (view)             |
| tft_silver    | silver_matches         | 1 linha por partida              |
| tft_silver    | silver_participants    | 1 linha por jogador por partida  |
| tft_silver    | silver_traits          | Traits ativos por jogador        |
| tft_silver    | silver_units           | Unidades em campo por jogador    |

## Tags

Cada modelo possui tags para execução seletiva em produção:

| Tag                  | Modelos                                              |
|----------------------|------------------------------------------------------|
| `staging`            | stg_matches                                          |
| `silver`             | silver_matches, silver_participants, silver_traits, silver_units |
| `gold`               | (futuros modelos gold)                               |
| `daily`              | todos os modelos atuais                              |
| `matches`            | silver_matches                                       |
| `participants`       | silver_participants                                  |
| `traits`             | silver_traits                                        |
| `units`              | silver_units                                         |
| `bronze_to_staging`  | stg_matches                                          |

## Comandos

```bash
# Roda todos os modelos
dbt run

# Roda por camada
dbt run --select tag:staging
dbt run --select tag:silver
dbt run --select tag:gold

# Roda modelos específicos
dbt run --select tag:matches
dbt run --select tag:participants
dbt run --select tag:traits
dbt run --select tag:units

# Roda tudo que é diário
dbt run --select tag:daily

# Roda combinando tags
dbt run --select tag:participants tag:traits

# Roda só dados novos (incremental)
dbt run --select tag:silver

# Reprocessa tudo do zero (full refresh)
dbt run --select tag:silver --full-refresh

# Testa qualidade dos dados
dbt test

# Testa só uma camada
dbt test --select tag:silver

# Gera documentação
dbt docs generate
dbt docs serve
```

## Qualidade de dados

Testes definidos em `models/silver/schema.yml`:

| Modelo              | Campo       | Teste                              |
|---------------------|-------------|------------------------------------|
| stg_matches         | match_id    | not_null, unique                   |
| silver_matches      | match_id    | not_null, unique                   |
| silver_matches      | queue_id    | accepted_values [1100,1090,1130,1160] |
| silver_participants | placement   | not_null, accepted_values [1..8]   |
| silver_participants | level       | accepted_values [1..10]            |
| silver_traits       | trait_name  | not_null                           |
| silver_units        | tier        | accepted_values [1,2,3]            |