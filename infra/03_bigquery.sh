#!/bin/bash
# =============================================================================
# 03_bigquery.sh — Datasets BigQuery
# Tabelas Silver e Gold são gerenciadas pelo dbt
# =============================================================================
set -e
source "$(dirname "$0")/env.sh"

echo "========================================="
echo " BigQuery — Datasets"
echo "========================================="

create_dataset() {
    local NAME=$1 DESC=$2
    if bq ls --project_id=$PROJECT_ID "$NAME" &>/dev/null; then
        echo "  ⚠️  $NAME já existe"
    else
        bq mk --project_id=$PROJECT_ID --dataset \
            --location=$BQ_LOCATION --description="$DESC" "$NAME"
        echo "  ✅ $NAME criado"
    fi
}

echo ""
create_dataset "tft_bronze"  "Dados brutos via External Table (GCS)"
create_dataset "tft_staging" "Views de staging — dbt"
create_dataset "tft_silver"  "Tabelas fact/dim normalizadas — dbt"
create_dataset "tft_gold"    "Agregações analíticas — dbt"

echo ""
echo "✅ Datasets configurados"
echo ""
echo "Próximo: bash infra/04_pubsub.sh"
echo "Após ingestão: bash infra/create_external_table.sh"