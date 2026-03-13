#!/bin/bash
# =============================================================================
# 04_pubsub.sh — Criação dos tópicos e subscriptions Pub/Sub
# Tópicos:
#   tft-match-ids          — match IDs para o match-fetcher
#   tft-match-ids-dead-letter — DLQ do match-fetcher
#   tft-pipeline-events    — evento do collector para triggar o dbt
# Execução: bash infra/gcloud/04_pubsub.sh
# =============================================================================

set -e

export PROJECT_ID="tft-gcp-integration"

echo "================================================="
echo " TFT Data Platform — Pub/Sub"
echo "================================================="

create_topic() {
    local NAME=$1
    local EXTRA_ARGS="${2:-}"
    if gcloud pubsub topics describe "$NAME" --project=$PROJECT_ID &>/dev/null; then
        echo "  ⚠️  Tópico $NAME já existe, ignorando"
    else
        gcloud pubsub topics create "$NAME" --project=$PROJECT_ID $EXTRA_ARGS
        echo "  ✅ Tópico $NAME criado"
    fi
}

create_subscription() {
    local NAME=$1
    if gcloud pubsub subscriptions describe "$NAME" --project=$PROJECT_ID &>/dev/null; then
        echo "  ⚠️  Subscription $NAME já existe, ignorando"
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
        echo "  ✅ Subscription $NAME criada"
    fi
}

# -----------------------------------------------------------------------------
# Tópicos
# -----------------------------------------------------------------------------
echo ""
echo "[1/3] Criando tópicos..."
create_topic "tft-match-ids"           "--message-retention-duration=24h"
create_topic "tft-match-ids-dead-letter"
create_topic "tft-pipeline-events"     "--message-retention-duration=1h"

# -----------------------------------------------------------------------------
# Subscriptions
# -----------------------------------------------------------------------------
echo ""
echo "[2/3] Criando subscriptions..."
create_subscription "tft-match-fetcher-sub"

# tft-pipeline-events → subscription criada pelo 05_functions.sh
# após o deploy do Cloud Run Job (precisa da URL do job)

# DLQ monitor — permite inspecionar mensagens que falharam manualmente
if gcloud pubsub subscriptions describe tft-dlq-monitor-sub --project=$PROJECT_ID &>/dev/null; then
    echo "  ⚠️  tft-dlq-monitor-sub já existe, ignorando"
else
    gcloud pubsub subscriptions create tft-dlq-monitor-sub \
        --project=$PROJECT_ID \
        --topic=tft-match-ids-dead-letter \
        --ack-deadline=60 \
        --expiration-period=never \
        --message-retention-duration=7d
    echo "  ✅ tft-dlq-monitor-sub criada"
fi

# DLQ reprocessor — subscription da Cloud Function que retenta automaticamente
# (a subscription em si é criada pelo Eventarc no 05_functions.sh via --trigger-topic)

# -----------------------------------------------------------------------------
# Permissões
# -----------------------------------------------------------------------------
echo ""
echo "[3/3] Configurando permissões..."
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")

gcloud pubsub topics add-iam-policy-binding tft-match-ids-dead-letter \
    --project=$PROJECT_ID \
    --member="serviceAccount:service-$PROJECT_NUMBER@gcp-sa-pubsub.iam.gserviceaccount.com" \
    --role="roles/pubsub.publisher"

gcloud pubsub subscriptions add-iam-policy-binding tft-match-fetcher-sub \
    --project=$PROJECT_ID \
    --member="serviceAccount:service-$PROJECT_NUMBER@gcp-sa-pubsub.iam.gserviceaccount.com" \
    --role="roles/pubsub.subscriber"

echo "✅ Permissões configuradas"

echo ""
echo "================================================="
echo " Pub/Sub configurado:"
echo "   tft-match-ids             → match IDs para o fetcher"
echo "   tft-match-ids-dead-letter → DLQ"
echo "   tft-pipeline-events       → trigger do dbt runner"
echo "   tft-match-fetcher-sub     → subscription do fetcher"
echo "   tft-dlq-monitor-sub       → monitoramento manual da DLQ"
echo ""
echo " Próximo passo:"
echo " bash infra/gcloud/05_functions.sh"
echo "================================================="