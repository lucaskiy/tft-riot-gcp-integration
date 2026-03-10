#!/bin/bash
# =============================================================================
# 02_storage.sh — Criação dos buckets GCS (camadas Bronze e controle)
# Execução: bash infra/gcloud/02_storage.sh
# =============================================================================

set -e

export PROJECT_ID="tft-gcp-integration"
export REGION="us-central1"

echo "================================================="
echo " TFT GCP Intgration — Storage (GCS)"
echo "================================================="

# -----------------------------------------------------------------------------
# Bucket Bronze — JSONs brutos das partidas
# Estrutura: bronze/patch=14.10/date=2024-05-15/{match_id}.json
# -----------------------------------------------------------------------------
echo ""
echo "[1/2] Criando bucket Bronze..."
gcloud storage buckets create gs://tft-bronze-$PROJECT_ID \
    --project=$PROJECT_ID \
    --location=$REGION \
    --uniform-bucket-level-access \
    --public-access-prevention

# Lifecycle: delete arquivos com mais de 90 dias (controle de custo)
cat > /tmp/lifecycle_bronze.json << 'EOF'
{
  "lifecycle": {
    "rule": [
      {
        "action": { "type": "Delete" },
        "condition": { "age": 90 }
      }
    ]
  }
}
EOF
gcloud storage buckets update gs://tft-bronze-$PROJECT_ID \
    --lifecycle-file=/tmp/lifecycle_bronze.json

echo "✅ Bucket Bronze criado: gs://tft-bronze-$PROJECT_ID"

# -----------------------------------------------------------------------------
# Bucket Control — arquivos de controle (IDs processados, checkpoints)
# Estrutura:
#   control/processed_ids.txt   → match IDs já salvos no Bronze
#   control/last_run.txt        → timestamp da última execução bem-sucedida
# -----------------------------------------------------------------------------
echo ""
echo "[2/2] Criando bucket de controle..."
gcloud storage buckets create gs://tft-control-$PROJECT_ID \
    --project=$PROJECT_ID \
    --location=$REGION \
    --uniform-bucket-level-access \
    --public-access-prevention

# Inicializa arquivos de controle vazios
echo "" | gcloud storage cp - gs://tft-control-$PROJECT_ID/processed_ids.txt
echo "" | gcloud storage cp - gs://tft-control-$PROJECT_ID/last_run.txt

echo "✅ Bucket Control criado: gs://tft-control-$PROJECT_ID"

echo ""
echo "================================================="
echo " Buckets criados:"
echo "   gs://tft-bronze-$PROJECT_ID"
echo "   gs://tft-control-$PROJECT_ID"
echo ""
echo " Próximo passo:"
echo " bash infra/gcloud/03_bigquery.sh"
echo "================================================="