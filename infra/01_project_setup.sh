#!/bin/bash
# =============================================================================
# 01_setup.sh — Configuração inicial do projeto GCP
# Execução: bash infra/gcloud/01_setup.sh
# =============================================================================

set -e

# -----------------------------------------------------------------------------
# CONFIGURAÇÃO
# -----------------------------------------------------------------------------
export PROJECT_ID="tft-gcp-integration"
export REGION="us-central1"
export BILLING_ACCOUNT="${BILLING_ACCOUNT:-$(gcloud billing accounts list --format='value(ACCOUNT_ID)' --limit=1)}"

echo "================================================="
echo " TFT Data Platform — Setup Inicial GCP"
echo " Projeto : $PROJECT_ID"
echo " Região  : $REGION"
echo "================================================="

# -----------------------------------------------------------------------------
# 1. APIs necessárias
# -----------------------------------------------------------------------------
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
    logging.googleapis.com \
    monitoring.googleapis.com

echo "✅ APIs ativadas"

# -----------------------------------------------------------------------------
# 2. Firestore — controle de IDs processados
# -----------------------------------------------------------------------------
echo ""
echo "[2/4] Criando banco Firestore..."
if gcloud firestore databases describe --project=$PROJECT_ID &>/dev/null; then
    echo "  ⚠️  Firestore já existe, ignorando"
else
    gcloud firestore databases create \
        --project=$PROJECT_ID \
        --location=nam5 \
        --type=firestore-native
    echo "  ✅ Firestore criado"
fi

# -----------------------------------------------------------------------------
# 3. Service Accounts
# -----------------------------------------------------------------------------
echo ""
echo "[3/4] Criando Service Accounts..."

create_sa() {
    local NAME=$1
    local DISPLAY=$2
    if gcloud iam service-accounts describe "$NAME@$PROJECT_ID.iam.gserviceaccount.com" \
        --project=$PROJECT_ID &>/dev/null; then
        echo "  ⚠️  $NAME já existe, ignorando"
    else
        gcloud iam service-accounts create "$NAME" \
            --project=$PROJECT_ID \
            --display-name="$DISPLAY"
        echo "  ✅ $NAME criada"
    fi
}

create_sa "tft-collector"     "TFT Collector — busca PUUIDs e match IDs"
create_sa "tft-match-fetcher" "TFT Match Fetcher — busca JSON das partidas"
create_sa "tft-dbt"           "TFT dbt — transformações BigQuery"
create_sa "tft-scheduler"     "TFT Scheduler — invoca Cloud Functions"

echo "✅ Service Accounts verificadas"

# -----------------------------------------------------------------------------
# 4. Permissões mínimas por SA
# -----------------------------------------------------------------------------
echo ""
echo "[4/4] Atribuindo permissões..."

SA_COLLECTOR="tft-collector@$PROJECT_ID.iam.gserviceaccount.com"
SA_FETCHER="tft-match-fetcher@$PROJECT_ID.iam.gserviceaccount.com"
SA_DBT="tft-dbt@$PROJECT_ID.iam.gserviceaccount.com"

# Collector: GCS + Pub/Sub + Secret Manager + Firestore
for role in roles/storage.objectAdmin roles/pubsub.publisher roles/secretmanager.secretAccessor roles/datastore.user; do
    gcloud projects add-iam-policy-binding $PROJECT_ID \
        --member="serviceAccount:$SA_COLLECTOR" \
        --role="$role"
done

# Match Fetcher: GCS + Pub/Sub + Secret Manager + Firestore
for role in roles/storage.objectAdmin roles/pubsub.subscriber roles/secretmanager.secretAccessor roles/datastore.user; do
    gcloud projects add-iam-policy-binding $PROJECT_ID \
        --member="serviceAccount:$SA_FETCHER" \
        --role="$role"
done

# dbt: GCS + BigQuery
for role in roles/storage.objectViewer roles/bigquery.dataEditor roles/bigquery.jobUser; do
    gcloud projects add-iam-policy-binding $PROJECT_ID \
        --member="serviceAccount:$SA_DBT" \
        --role="$role"
done

echo "✅ Permissões atribuídas"

# -----------------------------------------------------------------------------
# 5. Secret Manager — Riot API Key
# -----------------------------------------------------------------------------
echo ""
echo "[5/5] Configurando secret riot-api-key..."

SA_COLLECTOR="tft-collector@$PROJECT_ID.iam.gserviceaccount.com"
SA_FETCHER="tft-match-fetcher@$PROJECT_ID.iam.gserviceaccount.com"

if gcloud secrets describe riot-api-key --project=$PROJECT_ID &>/dev/null; then
    echo "  ⚠️  Secret já existe, adicionando nova versão..."
    read -s -p "  Cole sua Riot API Key (RGAPI-...): " RIOT_KEY
    echo ""
    echo -n "$RIOT_KEY" | gcloud secrets versions add riot-api-key         --project=$PROJECT_ID         --data-file=-
    echo "  ✅ Nova versão adicionada"
else
    echo "  Criando secret..."
    read -s -p "  Cole sua Riot API Key (RGAPI-...): " RIOT_KEY
    echo ""
    gcloud secrets create riot-api-key         --project=$PROJECT_ID         --replication-policy="automatic"
    echo -n "$RIOT_KEY" | gcloud secrets versions add riot-api-key         --project=$PROJECT_ID         --data-file=-
    echo "  ✅ Secret criado"
fi

# Permissões no secret para as SAs
gcloud secrets add-iam-policy-binding riot-api-key     --project=$PROJECT_ID     --member="serviceAccount:$SA_COLLECTOR"     --role="roles/secretmanager.secretAccessor" &>/dev/null

gcloud secrets add-iam-policy-binding riot-api-key     --project=$PROJECT_ID     --member="serviceAccount:$SA_FETCHER"     --role="roles/secretmanager.secretAccessor" &>/dev/null

echo "✅ Permissões do secret configuradas"

echo ""
echo "================================================="
echo " Setup concluído! Próximo passo:"
echo " bash infra/gcloud/02_storage.sh"
echo "================================================="