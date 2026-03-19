#!/bin/bash
# =============================================================================
# create_external_table.sh — External Table BigQuery apontando para o GCS Bronze
# Executa após a primeira ingestão de dados
# =============================================================================
set -e
source "$(dirname "$0")/env.sh"

echo "Criando External Table tft_bronze.raw_matches..."

if bq show --project_id=$PROJECT_ID tft_bronze.raw_matches &>/dev/null; then
    echo "⚠️  External Table já existe — recriando..."
    bq rm -f --project_id=$PROJECT_ID tft_bronze.raw_matches
fi

cat > /tmp/external_table_def.json << EOJSON
{
  "sourceFormat": "NEWLINE_DELIMITED_JSON",
  "sourceUris": ["gs://${BUCKET_BRONZE}/*.json"],
  "schema": {
    "fields": [
      {"name": "metadata", "type": "JSON", "mode": "NULLABLE"},
      {"name": "info",     "type": "JSON", "mode": "NULLABLE"}
    ]
  },
  "hivePartitioningOptions": {
    "mode": "CUSTOM",
    "sourceUriPrefix": "gs://${BUCKET_BRONZE}/{date:DATE}",
    "requirePartitionFilter": false
  }
}
EOJSON

bq mk \
    --project_id=$PROJECT_ID \
    --location=$BQ_LOCATION \
    --external_table_definition=/tmp/external_table_def.json \
    tft_bronze.raw_matches

echo "✅ External Table criada: tft_bronze.raw_matches"
echo ""
bq query --project_id=$PROJECT_ID --use_legacy_sql=false \
    "SELECT date, COUNT(*) AS total
     FROM \`${PROJECT_ID}.tft_bronze.raw_matches\`
     GROUP BY date ORDER BY date DESC LIMIT 5"