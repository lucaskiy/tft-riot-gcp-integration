#!/bin/bash
# =============================================================================
# 03_bigquery.sh — Criação dos datasets BigQuery
# Responsabilidade: apenas datasets
# Tabelas Silver e Gold são gerenciadas pelo dbt
# Execução: bash infra/gcloud/03_bigquery.sh
# =============================================================================

set -e

export PROJECT_ID="tft-gcp-integration"
export BQ_LOCATION="US"

echo "================================================="
echo " TFT Data Platform — BigQuery"
echo "================================================="

# -----------------------------------------------------------------------------
# Datasets — única responsabilidade deste script
# As tabelas dentro de cada dataset são criadas pelo dbt
# -----------------------------------------------------------------------------
echo ""
echo "[1/2] Criando datasets..."

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
create_dataset "tft_staging" "Staging — JSON parseado pelo dbt"
create_dataset "tft_silver"  "Dados normalizados — modelos dbt Silver (fact/dim)"
create_dataset "tft_gold"    "Agregações analíticas — modelos dbt Gold"

echo "✅ Datasets verificados"

# -----------------------------------------------------------------------------
# External Table — criada após a primeira ingestão
# -----------------------------------------------------------------------------
echo ""
echo "[2/2] External Table..."
echo "  ℹ️  Execute após a primeira ingestão:"
echo "  bash infra/gcloud/create_external_table.sh"

echo ""
echo "================================================="
echo " BigQuery configurado:"
echo "   tft_bronze  — External Table (GCS) — gerenciado por create_external_table.sh"
echo "   tft_staging — Staging views        — gerenciado pelo dbt"
echo "   tft_silver  — Tabelas fact/dim      — gerenciado pelo dbt"
echo "   tft_gold    — Agregações analíticas — gerenciado pelo dbt"
echo ""
echo " Próximos passos:"
echo "   1. bash infra/gcloud/04_pubsub.sh"
echo "   2. bash infra/gcloud/05_functions.sh"
echo "   3. bash infra/gcloud/create_external_table.sh  (após primeira ingestão)"
echo "   4. cd dbt/tft_dbt && dbt run                   (cria tabelas Silver/Gold)"
echo "================================================="