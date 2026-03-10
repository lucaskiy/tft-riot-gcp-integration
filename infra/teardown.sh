#!/bin/bash
# =============================================================================
# teardown.sh — Remove TODOS os recursos criados (cuidado!)
# Útil para resetar o ambiente ou controlar custos na learner account
# Execução: bash infra/gcloud/teardown.sh
# =============================================================================

export PROJECT_ID="tft-gcp-integration"
export REGION="us-central1"

echo "⚠️  ATENÇÃO: Isso irá deletar TODOS os recursos do projeto $PROJECT_ID"
read -p "Digite o PROJECT_ID para confirmar: " confirm
if [[ "$confirm" != "$PROJECT_ID" ]]; then
  echo "Abortado."
  exit 0
fi

echo "Deletando Cloud Scheduler..."
gcloud scheduler jobs delete tft-collector-hourly --location=$REGION --quiet

echo "Deletando Cloud Functions..."
gcloud functions delete tft-collector      --region=$REGION --gen2 --quiet
gcloud functions delete tft-match-fetcher  --region=$REGION --gen2 --quiet

echo "Deletando Pub/Sub..."
gcloud pubsub subscriptions delete tft-match-fetcher-sub --quiet
gcloud pubsub topics delete tft-match-ids --quiet
gcloud pubsub topics delete tft-match-ids-dead-letter --quiet

echo "Deletando BigQuery..."
bq rm -r -f $PROJECT_ID:tft_bronze
bq rm -r -f $PROJECT_ID:tft_silver
bq rm -r -f $PROJECT_ID:tft_gold
bq rm -r -f $PROJECT_ID:tft_quality

echo "Deletando GCS..."
gcloud storage rm -r gs://tft-bronze-$PROJECT_ID
gcloud storage rm -r gs://tft-control-$PROJECT_ID

echo "Deletando Secrets..."
gcloud secrets delete riot-api-key --quiet

echo ""
echo "✅ Todos os recursos removidos."