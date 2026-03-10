#!/bin/bash
# =============================================================================
# 03_bigquery.sh — Criação dos datasets BigQuery (Silver e Gold)
# Execução: bash infra/gcloud/03_bigquery.sh
# =============================================================================

set -e

export PROJECT_ID="tft-gcp-integration"
export REGION="us-central1"
export BQ_LOCATION="US"

echo "================================================="
echo " TFT Data Platform — BigQuery"
echo "================================================="

# -----------------------------------------------------------------------------
# Datasets
# -----------------------------------------------------------------------------
echo ""
echo "[1/3] Criando datasets..."

create_dataset() {
    local NAME=$1
    local DESC=$2
    if bq ls --project_id=$PROJECT_ID "$NAME" &>/dev/null; then
        echo "  ⚠️  $NAME já existe, ignorando"
    else
        bq mk \
            --project_id=$PROJECT_ID \
            --dataset \
            --location=$BQ_LOCATION \
            --description="$DESC" \
            "$NAME"
        echo "  ✅ $NAME criado"
    fi
}

create_dataset "tft_bronze"  "Dados brutos vindos do GCS Bronze via External Tables"
create_dataset "tft_silver"  "Dados normalizados e limpos — modelos dbt Silver"
create_dataset "tft_gold"    "Agregações analíticas — modelos dbt Gold"
create_dataset "tft_quality" "Resultados dos testes de qualidade de dados"

echo "✅ Datasets verificados: tft_bronze, tft_silver, tft_gold, tft_quality"

# -----------------------------------------------------------------------------
# External Table — aponta para o GCS Bronze
# Permite ao dbt ler os JSONs brutos direto do bucket
# -----------------------------------------------------------------------------
echo ""
echo "[2/3] External Table ignorada — bucket ainda vazio"
echo "  ℹ️  Execute após a primeira ingestão:"
echo "  bash infra/gcloud/create_external_table.sh"


# -----------------------------------------------------------------------------
# Tabelas Silver — criadas pelo dbt, mas definimos aqui para documentação
# -----------------------------------------------------------------------------
echo ""
echo "[3/3] Criando tabelas Silver (esqueleto para documentação)..."

bq mk \
    --project_id=$PROJECT_ID \
    --table \
    --description="Uma linha por partida" \
    tft_silver.fact_matches \
    match_id:STRING,patch:STRING,game_datetime:TIMESTAMP,game_length:FLOAT,game_variation:STRING,ingested_at:TIMESTAMP

bq mk \
    --project_id=$PROJECT_ID \
    --table \
    --description="Resultado de cada jogador por partida" \
    tft_silver.fact_player_results \
    match_id:STRING,puuid:STRING,placement:INTEGER,level:INTEGER,last_round:INTEGER,total_damage_to_players:INTEGER,time_eliminated:FLOAT

bq mk \
    --project_id=$PROJECT_ID \
    --table \
    --description="Augments escolhidos por jogador" \
    tft_silver.dim_augments \
    match_id:STRING,puuid:STRING,slot:INTEGER,augment_id:STRING

bq mk \
    --project_id=$PROJECT_ID \
    --table \
    --description="Traits ativas por jogador na partida" \
    tft_silver.dim_traits \
    match_id:STRING,puuid:STRING,trait_id:STRING,num_units:INTEGER,tier_current:INTEGER,tier_total:INTEGER

bq mk \
    --project_id=$PROJECT_ID \
    --table \
    --description="Unidades usadas por jogador" \
    tft_silver.dim_units \
    match_id:STRING,puuid:STRING,character_id:STRING,tier:INTEGER,rarity:INTEGER

echo "✅ Tabelas Silver criadas"

echo ""
echo "================================================="
echo " BigQuery configurado:"
echo "   tft_bronze  — External Tables (GCS)"
echo "   tft_silver  — Modelos dbt normalizados"
echo "   tft_gold    — Modelos dbt analíticos"
echo "   tft_quality — Resultados de qualidade"
echo ""
echo " Próximo passo:"
echo " bash infra/gcloud/04_pubsub.sh"
echo "================================================="