#!/bin/bash
# =============================================================================
# deploy_all.sh — Executa todos os scripts de infra em ordem
# Execução: bash infra/gcloud/deploy_all.sh
#
# Ordem:
#   01_setup.sh    → projeto, APIs, service accounts, secrets
#   02_storage.sh  → buckets GCS
#   03_bigquery.sh → datasets e tabelas
#   04_pubsub.sh   → tópicos e subscriptions
#   05_functions.sh→ cloud functions + scheduler
# =============================================================================

set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║   TFT GCP Intgration — Deploy Completo   ║"
echo "╚══════════════════════════════════════════╝"
echo ""
echo "⚠️  Antes de continuar, edite as variáveis em cada script:"
echo "   PROJECT_ID, BILLING_ACCOUNT, REGION"
echo ""
read -p "Deseja continuar? (s/n): " confirm
if [[ "$confirm" != "s" ]]; then
  echo "Abortado."
  exit 0
fi

echo ""
echo "━━━ [1/5] Setup inicial ━━━━━━━━━━━━━━━━━━"
bash "$DIR/01_project_setup.sh"

echo ""
echo "━━━ [2/5] Storage (GCS) ━━━━━━━━━━━━━━━━━"
bash "$DIR/02_storage.sh"

echo ""
echo "━━━ [3/5] BigQuery ━━━━━━━━━━━━━━━━━━━━━━"
bash "$DIR/03_bigquery.sh"

echo ""
echo "━━━ [4/5] Pub/Sub ━━━━━━━━━━━━━━━━━━━━━━━"
bash "$DIR/04_pubsub.sh"

echo ""
echo "━━━ [5/5] Cloud Functions + Scheduler ━━━"
bash "$DIR/05_functions.sh"

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║         ✅ Deploy finalizado!            ║"
echo "╚══════════════════════════════════════════╝"
echo ""
echo "Recursos criados:"
echo "  GCS       → tft-bronze-*, tft-control-*"
echo "  BigQuery  → tft_bronze, tft_silver, tft_gold, tft_quality"
echo "  Pub/Sub   → tft-match-ids + dead letter"
echo "  Functions → tft-collector, tft-match-fetcher"
echo "  Scheduler → a cada 1h"
echo ""
echo "Para testar o pipeline manualmente:"
echo "  gcloud scheduler jobs run tft-collector-hourly --location=us-central1"