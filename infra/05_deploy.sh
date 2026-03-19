#!/bin/bash
# =============================================================================
# 05_deploy.sh — Cloud Functions, Cloud Run Job e Scheduler
# =============================================================================
set -e
source "$(dirname "$0")/env.sh"

echo "========================================="
echo " Deploy — Functions + dbt Runner + Scheduler"
echo "========================================="

# ── tft-collector ─────────────────────────────────────────────────────────────
echo ""
echo "[1/4] tft-collector..."
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
    --set-env-vars="PROJECT_ID=$PROJECT_ID,RIOT_REGION=br1,MASS_REGION=americas,\
BRONZE_BUCKET=$BUCKET_BRONZE,PUBSUB_TOPIC=tft-match-ids,MATCH_COUNT=20,HOURS_BACK=24" \
    --set-secrets="RIOT_API_KEY=riot-api-key:latest"

COLLECTOR_URL=$(gcloud functions describe tft-collector \
    --project=$PROJECT_ID --region=$REGION --gen2 \
    --format="value(serviceConfig.uri)")
echo "✅ tft-collector → $COLLECTOR_URL"

# ── tft-match-fetcher ─────────────────────────────────────────────────────────
echo ""
echo "[2/4] tft-match-fetcher..."
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
    --set-env-vars="PROJECT_ID=$PROJECT_ID,MASS_REGION=americas,BRONZE_BUCKET=$BUCKET_BRONZE" \
    --set-secrets="RIOT_API_KEY=riot-api-key:latest"
echo "✅ tft-match-fetcher"

# ── tft-dlq-reprocessor ───────────────────────────────────────────────────────
echo ""
echo "[3/4] tft-dlq-reprocessor..."
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
    --set-env-vars="PROJECT_ID=$PROJECT_ID,MASS_REGION=americas,BRONZE_BUCKET=$BUCKET_BRONZE" \
    --set-secrets="RIOT_API_KEY=riot-api-key:latest"

for role in roles/run.invoker roles/eventarc.eventReceiver; do
    gcloud projects add-iam-policy-binding $PROJECT_ID \
        --member="serviceAccount:$SA_FETCHER" --role="$role" --quiet
done
echo "✅ tft-dlq-reprocessor"

# ── dbt Runner (Cloud Run Job) ────────────────────────────────────────────────
echo ""
echo "[4/4] dbt Runner..."
gcloud builds submit dbt/ --project=$PROJECT_ID --tag=$DBT_IMAGE

if gcloud run jobs describe tft-dbt-runner --region=$REGION --project=$PROJECT_ID &>/dev/null; then
    gcloud run jobs update tft-dbt-runner \
        --project=$PROJECT_ID --region=$REGION \
        --image=$DBT_IMAGE \
        --service-account=$SA_DBT \
        --memory=1Gi --cpu=1 --task-timeout=30m --max-retries=1 \
        --set-env-vars="PROJECT_ID=$PROJECT_ID,RUN_MODE=daily,FULL_REFRESH=false"
else
    gcloud run jobs create tft-dbt-runner \
        --project=$PROJECT_ID --region=$REGION \
        --image=$DBT_IMAGE \
        --service-account=$SA_DBT \
        --memory=1Gi --cpu=1 --task-timeout=30m --max-retries=1 \
        --set-env-vars="PROJECT_ID=$PROJECT_ID,RUN_MODE=daily,FULL_REFRESH=false"
fi
echo "✅ tft-dbt-runner"

# Subscription que trigga o dbt runner
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")
JOB_URL="https://$REGION-run.googleapis.com/apis/run.googleapis.com/v1/namespaces/$PROJECT_ID/jobs/tft-dbt-runner:run"

gcloud projects add-iam-policy-binding $PROJECT_ID \
    --member="serviceAccount:service-$PROJECT_NUMBER@gcp-sa-pubsub.iam.gserviceaccount.com" \
    --role="roles/run.invoker" --quiet

if ! gcloud pubsub subscriptions describe tft-dbt-runner-sub --project=$PROJECT_ID &>/dev/null; then
    gcloud pubsub subscriptions create tft-dbt-runner-sub \
        --project=$PROJECT_ID \
        --topic=tft-pipeline-events \
        --push-endpoint=$JOB_URL \
        --push-auth-service-account=$SA_DBT \
        --ack-deadline=60 \
        --expiration-period=never
    echo "✅ tft-dbt-runner-sub criada"
fi

# ── Scheduler ─────────────────────────────────────────────────────────────────
gcloud functions add-invoker-policy-binding tft-collector \
    --project=$PROJECT_ID --region=$REGION \
    --member="serviceAccount:$SA_SCHEDULER"

SCHEDULER_ARGS="--project=$PROJECT_ID --location=$REGION \
    --schedule='0 * * * *' --uri=$COLLECTOR_URL --http-method=POST \
    --oidc-service-account-email=$SA_SCHEDULER \
    --oidc-token-audience=$COLLECTOR_URL \
    --message-body='{\"source\": \"scheduler\"}' \
    --time-zone='America/Sao_Paulo' --attempt-deadline=10m"

if gcloud scheduler jobs describe tft-collector-hourly --location=$REGION --project=$PROJECT_ID &>/dev/null; then
    eval "gcloud scheduler jobs update http tft-collector-hourly $SCHEDULER_ARGS"
else
    eval "gcloud scheduler jobs create http tft-collector-hourly $SCHEDULER_ARGS"
fi
echo "✅ Scheduler configurado (0 * * * * America/Sao_Paulo)"

echo ""
echo "========================================="
echo " Deploy concluído!"
echo " Testar: gcloud scheduler jobs run tft-collector-hourly --location=$REGION"
echo " dbt:    gcloud run jobs execute tft-dbt-runner --region=$REGION"
echo "========================================="