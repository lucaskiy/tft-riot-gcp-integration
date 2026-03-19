#!/bin/bash
# =============================================================================
# 04_pubsub.sh — Tópicos e Subscriptions Pub/Sub
# =============================================================================
set -e
source "$(dirname "$0")/env.sh"

echo "========================================="
echo " Pub/Sub — Tópicos e Subscriptions"
echo "========================================="

create_topic() {
    local NAME=$1 EXTRA="${2:-}"
    if gcloud pubsub topics describe "$NAME" --project=$PROJECT_ID &>/dev/null; then
        echo "  ⚠️  $NAME já existe"
    else
        gcloud pubsub topics create "$NAME" --project=$PROJECT_ID $EXTRA
        echo "  ✅ $NAME criado"
    fi
}

echo ""
echo "[1/3] Tópicos..."
create_topic "tft-match-ids"            "--message-retention-duration=24h"
create_topic "tft-match-ids-dead-letter"
create_topic "tft-pipeline-events"      "--message-retention-duration=1h"

echo ""
echo "[2/3] Subscriptions..."

# match-fetcher sub (com DLQ e retry)
if gcloud pubsub subscriptions describe tft-match-fetcher-sub --project=$PROJECT_ID &>/dev/null; then
    echo "  ⚠️  tft-match-fetcher-sub já existe"
else
    gcloud pubsub subscriptions create tft-match-fetcher-sub \
        --project=$PROJECT_ID \
        --topic=tft-match-ids \
        --ack-deadline=60 \
        --max-delivery-attempts=5 \
        --dead-letter-topic=tft-match-ids-dead-letter \
        --expiration-period=never \
        --min-retry-delay=10s \
        --max-retry-delay=60s
    echo "  ✅ tft-match-fetcher-sub criada"
fi

# DLQ monitor
if gcloud pubsub subscriptions describe tft-dlq-monitor-sub --project=$PROJECT_ID &>/dev/null; then
    echo "  ⚠️  tft-dlq-monitor-sub já existe"
else
    gcloud pubsub subscriptions create tft-dlq-monitor-sub \
        --project=$PROJECT_ID \
        --topic=tft-match-ids-dead-letter \
        --ack-deadline=60 \
        --expiration-period=never \
        --message-retention-duration=7d
    echo "  ✅ tft-dlq-monitor-sub criada"
fi

echo ""
echo "[3/3] Permissões Pub/Sub..."
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")
PUBSUB_SA="service-$PROJECT_NUMBER@gcp-sa-pubsub.iam.gserviceaccount.com"

gcloud pubsub topics add-iam-policy-binding tft-match-ids-dead-letter \
    --project=$PROJECT_ID \
    --member="serviceAccount:$PUBSUB_SA" \
    --role="roles/pubsub.publisher" --quiet

gcloud pubsub subscriptions add-iam-policy-binding tft-match-fetcher-sub \
    --project=$PROJECT_ID \
    --member="serviceAccount:$PUBSUB_SA" \
    --role="roles/pubsub.subscriber" --quiet

echo "✅ Pub/Sub configurado"
echo ""
echo "Próximo: bash infra/05_deploy.sh"