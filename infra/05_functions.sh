#!/bin/bash
# =============================================================================
# 05_functions.sh — Deploy das Cloud Functions e Cloud Scheduler
# Execução: bash infra/gcloud/05_functions.sh
# =============================================================================

set -e

export PROJECT_ID="tft-gcp-integration"
export REGION="us-central1"

SA_COLLECTOR="tft-collector@$PROJECT_ID.iam.gserviceaccount.com"
SA_FETCHER="tft-match-fetcher@$PROJECT_ID.iam.gserviceaccount.com"
SA_SCHEDULER="tft-scheduler@$PROJECT_ID.iam.gserviceaccount.com"

echo "================================================="
echo " TFT Data Platform — Cloud Functions + Scheduler"
echo "================================================="

# -----------------------------------------------------------------------------
# Function 1: tft-collector
# Trigger: HTTP (chamada pelo Cloud Scheduler)
# Responsabilidade: busca PUUIDs do Challenger, coleta match IDs,
#                   deduplica via Firestore, publica IDs novos no Pub/Sub
# -----------------------------------------------------------------------------
echo ""
echo "[1/3] Deploy da função tft-collector..."
gcloud functions deploy tft-collector \
    --project=$PROJECT_ID \
    --region=$REGION \
    --gen2 \
    --runtime=python311 \
    --source=ingestion/ \
    --entry-point=collector \
    --trigger-http \
    --no-allow-unauthenticated \
    --service-account=$SA_COLLECTOR \
    --memory=512MB \
    --timeout=540s \
    --set-env-vars="PROJECT_ID=$PROJECT_ID,RIOT_REGION=br1,MASS_REGION=americas,BRONZE_BUCKET=tft-bronze-$PROJECT_ID,PUBSUB_TOPIC=tft-match-ids,MATCH_COUNT=20,HOURS_BACK=24" \
    --set-secrets="RIOT_API_KEY=riot-api-key:latest"

echo "✅ Função tft-collector deployada"

COLLECTOR_URL=$(gcloud functions describe tft-collector \
    --project=$PROJECT_ID \
    --region=$REGION \
    --gen2 \
    --format="value(serviceConfig.uri)")

echo "   URL: $COLLECTOR_URL"

# -----------------------------------------------------------------------------
# Function 2: tft-match-fetcher
# Trigger: Pub/Sub (disparado por cada mensagem no tópico tft-match-ids)
# Responsabilidade: recebe match_id, busca JSON completo, salva no GCS Bronze,
#                   marca ID como processado no Firestore
# -----------------------------------------------------------------------------
echo ""
echo "[2/3] Deploy da função tft-match-fetcher..."
gcloud functions deploy tft-match-fetcher \
    --project=$PROJECT_ID \
    --region=$REGION \
    --gen2 \
    --runtime=python311 \
    --source=ingestion/ \
    --entry-point=match_fetcher \
    --trigger-topic=tft-match-ids \
    --service-account=$SA_FETCHER \
    --memory=256MB \
    --timeout=120s \
    --max-instances=10 \
    --set-env-vars="PROJECT_ID=$PROJECT_ID,MASS_REGION=americas,BRONZE_BUCKET=tft-bronze-$PROJECT_ID" \
    --set-secrets="RIOT_API_KEY=riot-api-key:latest"

echo "✅ Função tft-match-fetcher deployada"

# -----------------------------------------------------------------------------
# Function 3: tft-dlq-reprocessor
# Trigger: Pub/Sub (tft-match-ids-dead-letter)
# Responsabilidade: retenta matches que falharam MAX_RETRIES vezes
# -----------------------------------------------------------------------------
echo ""
echo "[2b/4] Deploy da função tft-dlq-reprocessor..."
gcloud functions deploy tft-dlq-reprocessor \
    --project=$PROJECT_ID \
    --region=$REGION \
    --gen2 \
    --runtime=python311 \
    --source=ingestion/ \
    --entry-point=dlq_reprocessor \
    --trigger-topic=tft-match-ids-dead-letter \
    --service-account=$SA_FETCHER \
    --memory=256MB \
    --timeout=120s \
    --max-instances=3 \
    --set-env-vars="PROJECT_ID=$PROJECT_ID,MASS_REGION=americas,BRONZE_BUCKET=tft-bronze-$PROJECT_ID" \
    --set-secrets="RIOT_API_KEY=riot-api-key:latest"

# Permissão run.invoker para o reprocessor
gcloud run services add-iam-policy-binding tft-dlq-reprocessor \
    --project=$PROJECT_ID \
    --region=$REGION \
    --member="serviceAccount:$SA_FETCHER" \
    --role="roles/run.invoker"

gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:$SA_FETCHER" \
    --role="roles/eventarc.eventReceiver"

echo "✅ Função tft-dlq-reprocessor deployada"

# Permissões para o match-fetcher ser invocado pelo Eventarc
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")

# run.invoker — SA do próprio match-fetcher (identidade usada pelo trigger Eventarc)
gcloud run services add-iam-policy-binding tft-match-fetcher \
    --project=$PROJECT_ID \
    --region=$REGION \
    --member="serviceAccount:$SA_FETCHER" \
    --role="roles/run.invoker"

# eventarc.eventReceiver — permite receber eventos do Eventarc
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:$SA_FETCHER" \
    --role="roles/eventarc.eventReceiver"

# iam.serviceAccountTokenCreator — permite gerar token OIDC para autenticar a chamada
gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:$SA_FETCHER" \
    --role="roles/iam.serviceAccountTokenCreator"

# SA do próprio match-fetcher (usada pelo trigger Eventarc como identidade de chamada)
gcloud run services add-iam-policy-binding tft-match-fetcher \
    --project=$PROJECT_ID \
    --region=$REGION \
    --member="serviceAccount:$SA_FETCHER" \
    --role="roles/run.invoker"

echo "✅ Permissões Pub/Sub + Eventarc → match-fetcher configuradas"

# -----------------------------------------------------------------------------
# Cloud Scheduler — dispara o Collector a cada hora
# -----------------------------------------------------------------------------
echo ""
echo "[3/3] Criando Cloud Scheduler..."

gcloud functions add-invoker-policy-binding tft-collector \
    --project=$PROJECT_ID \
    --region=$REGION \
    --member="serviceAccount:$SA_SCHEDULER"

if gcloud scheduler jobs describe tft-collector-hourly --location=$REGION --project=$PROJECT_ID &>/dev/null; then
    echo "  ⚠️  Scheduler já existe, atualizando..."
    gcloud scheduler jobs update http tft-collector-hourly \
        --project=$PROJECT_ID \
        --location=$REGION \
        --schedule="0 * * * *" \
        --uri=$COLLECTOR_URL \
        --http-method=POST \
        --oidc-service-account-email=$SA_SCHEDULER \
        --oidc-token-audience=$COLLECTOR_URL \
        --message-body='{"source": "scheduler"}' \
        --time-zone="America/Sao_Paulo" \
        --attempt-deadline=10m
else
    gcloud scheduler jobs create http tft-collector-hourly \
        --project=$PROJECT_ID \
        --location=$REGION \
        --schedule="0 * * * *" \
        --uri=$COLLECTOR_URL \
        --http-method=POST \
        --oidc-service-account-email=$SA_SCHEDULER \
        --oidc-token-audience=$COLLECTOR_URL \
        --message-body='{"source": "scheduler"}' \
        --time-zone="America/Sao_Paulo" \
        --attempt-deadline=10m
fi

echo "✅ Scheduler configurado: a cada hora (America/Sao_Paulo)"

# -----------------------------------------------------------------------------
# dbt Runner — Cloud Run Job trigado pelo tft-pipeline-events
# -----------------------------------------------------------------------------
echo ""
echo "[4/4] Deploy do dbt Runner..."

IMAGE="gcr.io/$PROJECT_ID/tft-dbt-runner"
SA_DBT="tft-dbt@$PROJECT_ID.iam.gserviceaccount.com"

# Build e push da imagem Docker
echo "  Building imagem Docker..."
gcloud builds submit dbt/     --project=$PROJECT_ID     --tag=$IMAGE

# Cria ou atualiza o Cloud Run Job
if gcloud run jobs describe tft-dbt-runner --region=$REGION --project=$PROJECT_ID &>/dev/null; then
    echo "  ⚠️  Job já existe, atualizando..."
    gcloud run jobs update tft-dbt-runner         --project=$PROJECT_ID         --region=$REGION         --image=$IMAGE         --service-account=$SA_DBT         --memory=1Gi         --cpu=1         --task-timeout=30m         --max-retries=1         --set-env-vars="PROJECT_ID=$PROJECT_ID"
else
    gcloud run jobs create tft-dbt-runner         --project=$PROJECT_ID         --region=$REGION         --image=$IMAGE         --service-account=$SA_DBT         --memory=1Gi         --cpu=1         --task-timeout=30m         --max-retries=1         --set-env-vars="PROJECT_ID=$PROJECT_ID,RUN_MODE=daily,FULL_REFRESH=false"
fi

echo "  ✅ Cloud Run Job tft-dbt-runner configurado"

# Subscription que trigga o Job quando o Collector publica em tft-pipeline-events
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")
JOB_URL="https://$REGION-run.googleapis.com/apis/run.googleapis.com/v1/namespaces/$PROJECT_ID/jobs/tft-dbt-runner:run"

gcloud projects add-iam-policy-binding $PROJECT_ID     --member="serviceAccount:service-$PROJECT_NUMBER@gcp-sa-pubsub.iam.gserviceaccount.com"     --role="roles/run.invoker"

if gcloud pubsub subscriptions describe tft-dbt-runner-sub --project=$PROJECT_ID &>/dev/null; then
    echo "  ⚠️  Subscription tft-dbt-runner-sub já existe, ignorando"
else
    gcloud pubsub subscriptions create tft-dbt-runner-sub         --project=$PROJECT_ID         --topic=tft-pipeline-events         --push-endpoint=$JOB_URL         --push-auth-service-account=$SA_DBT         --ack-deadline=60         --expiration-period=never
    echo "  ✅ Subscription tft-dbt-runner-sub criada"
fi

echo "✅ dbt Runner configurado"

echo ""
echo "================================================="
echo " Deploy concluído:"
echo "   tft-collector      → HTTP trigger (Scheduler)"
echo "   tft-match-fetcher  → Pub/Sub (tft-match-ids)"
echo "   tft-dbt-runner     → Pub/Sub (tft-pipeline-events)"
echo "   Scheduler          → 0 * * * * (a cada hora)"
echo ""
echo " Testar manualmente:"
echo " gcloud scheduler jobs run tft-collector-hourly --location=$REGION"
echo " gcloud run jobs execute tft-dbt-runner --region=$REGION"
echo ""
echo " Ver logs:"
echo " gcloud functions logs read tft-collector --region=$REGION --limit=50"
echo " gcloud functions logs read tft-match-fetcher --region=$REGION --limit=50"
echo "================================================="