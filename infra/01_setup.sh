#!/bin/bash
# =============================================================================
# 01_setup.sh — APIs, Service Accounts, IAM e Secrets
# =============================================================================
set -e
source "$(dirname "$0")/env.sh"

echo "========================================="
echo " Setup — APIs, SAs, IAM, Secrets"
echo "========================================="

# ── APIs ──────────────────────────────────────────────────────────────────────
echo ""
echo "[1/4] Ativando APIs..."
gcloud services enable \
    bigquery.googleapis.com \
    storage.googleapis.com \
    cloudfunctions.googleapis.com \
    pubsub.googleapis.com \
    cloudscheduler.googleapis.com \
    secretmanager.googleapis.com \
    cloudbuild.googleapis.com \
    run.googleapis.com \
    firestore.googleapis.com \
    artifactregistry.googleapis.com \
    logging.googleapis.com \
    --project=$PROJECT_ID
echo "✅ APIs ativadas"

# ── Firestore ─────────────────────────────────────────────────────────────────
echo ""
echo "[2/4] Firestore..."
if gcloud firestore databases describe --project=$PROJECT_ID &>/dev/null; then
    echo "  ⚠️  Firestore já existe"
else
    gcloud firestore databases create \
        --project=$PROJECT_ID \
        --location=nam5 \
        --type=firestore-native
    echo "  ✅ Firestore criado"
fi

# ── Service Accounts ──────────────────────────────────────────────────────────
echo ""
echo "[3/4] Service Accounts..."

create_sa() {
    local NAME=$1 DISPLAY=$2
    if gcloud iam service-accounts describe "$NAME@$PROJECT_ID.iam.gserviceaccount.com" \
        --project=$PROJECT_ID &>/dev/null; then
        echo "  ⚠️  $NAME já existe"
    else
        gcloud iam service-accounts create "$NAME" \
            --project=$PROJECT_ID \
            --display-name="$DISPLAY"
        echo "  ✅ $NAME criada"
    fi
}

create_sa "tft-collector"     "TFT Collector"
create_sa "tft-match-fetcher" "TFT Match Fetcher"
create_sa "tft-dbt"           "TFT dbt Runner"
create_sa "tft-scheduler"     "TFT Scheduler"

# ── IAM ───────────────────────────────────────────────────────────────────────
echo ""
echo "[4/4] IAM..."

bind() { gcloud projects add-iam-policy-binding $PROJECT_ID --member="serviceAccount:$1" --role="$2" --quiet; }

# Collector
for role in roles/storage.objectAdmin roles/pubsub.publisher \
            roles/secretmanager.secretAccessor roles/datastore.user; do
    bind "$SA_COLLECTOR" "$role"
done

# Match Fetcher
for role in roles/storage.objectAdmin roles/pubsub.subscriber \
            roles/pubsub.publisher roles/secretmanager.secretAccessor \
            roles/datastore.user roles/eventarc.eventReceiver \
            roles/iam.serviceAccountTokenCreator; do
    bind "$SA_FETCHER" "$role"
done

# dbt Runner
for role in roles/storage.objectViewer roles/bigquery.dataEditor \
            roles/bigquery.jobUser roles/run.invoker roles/run.admin \
            roles/artifactregistry.reader roles/eventarc.eventReceiver \
            roles/iam.serviceAccountTokenCreator; do
    bind "$SA_DBT" "$role"
done

echo "✅ IAM configurado"

# ── Secret — Riot API Key ─────────────────────────────────────────────────────
echo ""
echo "Secret riot-api-key..."
if gcloud secrets describe riot-api-key --project=$PROJECT_ID &>/dev/null; then
    echo "  ⚠️  Secret já existe — adicionando nova versão"
    read -s -p "  Riot API Key (RGAPI-...): " RIOT_KEY && echo ""
    echo -n "$RIOT_KEY" | gcloud secrets versions add riot-api-key \
        --project=$PROJECT_ID --data-file=-
else
    read -s -p "  Riot API Key (RGAPI-...): " RIOT_KEY && echo ""
    gcloud secrets create riot-api-key --project=$PROJECT_ID --replication-policy="automatic"
    echo -n "$RIOT_KEY" | gcloud secrets versions add riot-api-key \
        --project=$PROJECT_ID --data-file=-
fi

for SA in "$SA_COLLECTOR" "$SA_FETCHER"; do
    gcloud secrets add-iam-policy-binding riot-api-key \
        --project=$PROJECT_ID \
        --member="serviceAccount:$SA" \
        --role="roles/secretmanager.secretAccessor" &>/dev/null
done

echo "✅ Secret configurado"
echo ""
echo "Próximo: bash infra/02_storage.sh"#!/bin/bash
# =============================================================================
# 01_setup.sh — APIs, Service Accounts, IAM e Secrets
# =============================================================================
set -e
source "$(dirname "$0")/env.sh"

echo "========================================="
echo " Setup — APIs, SAs, IAM, Secrets"
echo "========================================="

# ── APIs ──────────────────────────────────────────────────────────────────────
echo ""
echo "[1/4] Ativando APIs..."
gcloud services enable \
    bigquery.googleapis.com \
    storage.googleapis.com \
    cloudfunctions.googleapis.com \
    pubsub.googleapis.com \
    cloudscheduler.googleapis.com \
    secretmanager.googleapis.com \
    cloudbuild.googleapis.com \
    run.googleapis.com \
    firestore.googleapis.com \
    artifactregistry.googleapis.com \
    logging.googleapis.com \
    --project=$PROJECT_ID
echo "✅ APIs ativadas"

# ── Firestore ─────────────────────────────────────────────────────────────────
echo ""
echo "[2/4] Firestore..."
if gcloud firestore databases describe --project=$PROJECT_ID &>/dev/null; then
    echo "  ⚠️  Firestore já existe"
else
    gcloud firestore databases create \
        --project=$PROJECT_ID \
        --location=nam5 \
        --type=firestore-native
    echo "  ✅ Firestore criado"
fi

# ── Service Accounts ──────────────────────────────────────────────────────────
echo ""
echo "[3/4] Service Accounts..."

create_sa() {
    local NAME=$1 DISPLAY=$2
    if gcloud iam service-accounts describe "$NAME@$PROJECT_ID.iam.gserviceaccount.com" \
        --project=$PROJECT_ID &>/dev/null; then
        echo "  ⚠️  $NAME já existe"
    else
        gcloud iam service-accounts create "$NAME" \
            --project=$PROJECT_ID \
            --display-name="$DISPLAY"
        echo "  ✅ $NAME criada"
    fi
}

create_sa "tft-collector"     "TFT Collector"
create_sa "tft-match-fetcher" "TFT Match Fetcher"
create_sa "tft-dbt"           "TFT dbt Runner"
create_sa "tft-scheduler"     "TFT Scheduler"

# ── IAM ───────────────────────────────────────────────────────────────────────
echo ""
echo "[4/4] IAM..."

bind() { gcloud projects add-iam-policy-binding $PROJECT_ID --member="serviceAccount:$1" --role="$2" --quiet; }

# Collector
for role in roles/storage.objectAdmin roles/pubsub.publisher \
            roles/secretmanager.secretAccessor roles/datastore.user; do
    bind "$SA_COLLECTOR" "$role"
done

# Match Fetcher
for role in roles/storage.objectAdmin roles/pubsub.subscriber \
            roles/pubsub.publisher roles/secretmanager.secretAccessor \
            roles/datastore.user roles/eventarc.eventReceiver \
            roles/iam.serviceAccountTokenCreator; do
    bind "$SA_FETCHER" "$role"
done

# dbt Runner
for role in roles/storage.objectViewer roles/bigquery.dataEditor \
            roles/bigquery.jobUser roles/run.invoker roles/run.admin \
            roles/artifactregistry.reader roles/eventarc.eventReceiver \
            roles/iam.serviceAccountTokenCreator; do
    bind "$SA_DBT" "$role"
done

echo "✅ IAM configurado"

# ── Secret — Riot API Key ─────────────────────────────────────────────────────
echo ""
echo "Secret riot-api-key..."
if gcloud secrets describe riot-api-key --project=$PROJECT_ID &>/dev/null; then
    echo "  ⚠️  Secret já existe — adicionando nova versão"
    read -s -p "  Riot API Key (RGAPI-...): " RIOT_KEY && echo ""
    echo -n "$RIOT_KEY" | gcloud secrets versions add riot-api-key \
        --project=$PROJECT_ID --data-file=-
else
    read -s -p "  Riot API Key (RGAPI-...): " RIOT_KEY && echo ""
    gcloud secrets create riot-api-key --project=$PROJECT_ID --replication-policy="automatic"
    echo -n "$RIOT_KEY" | gcloud secrets versions add riot-api-key \
        --project=$PROJECT_ID --data-file=-
fi

for SA in "$SA_COLLECTOR" "$SA_FETCHER"; do
    gcloud secrets add-iam-policy-binding riot-api-key \
        --project=$PROJECT_ID \
        --member="serviceAccount:$SA" \
        --role="roles/secretmanager.secretAccessor" &>/dev/null
done

echo "✅ Secret configurado"
echo ""
echo "Próximo: bash infra/02_storage.sh"