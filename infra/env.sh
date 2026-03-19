#!/bin/bash
# =============================================================================
# env.sh — Variáveis compartilhadas entre todos os scripts de infra
# Source: source "$(dirname "$0")/env.sh"
# =============================================================================

export PROJECT_ID="tft-gcp-integration"
export REGION="us-central1"
export BQ_LOCATION="US"

# Buckets
export BUCKET_BRONZE="tft-bronze-${PROJECT_ID}"
export BUCKET_ASSETS="tft-assets-${PROJECT_ID}"

# Service Accounts
export SA_COLLECTOR="tft-collector@${PROJECT_ID}.iam.gserviceaccount.com"
export SA_FETCHER="tft-match-fetcher@${PROJECT_ID}.iam.gserviceaccount.com"
export SA_DBT="tft-dbt@${PROJECT_ID}.iam.gserviceaccount.com"
export SA_SCHEDULER="tft-scheduler@${PROJECT_ID}.iam.gserviceaccount.com"

# Docker
export DBT_IMAGE="gcr.io/${PROJECT_ID}/tft-dbt-runner"

# Community Dragon
export CDRAGON_BASE="https://raw.communitydragon.org/latest/game"
export CDRAGON_JSON="https://raw.communitydragon.org/latest/cdragon/tft/en_us.json"