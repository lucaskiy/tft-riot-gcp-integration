#!/bin/bash
# =============================================================================
# 02_storage.sh — Bucket Bronze (GCS)
# =============================================================================
set -e
source "$(dirname "$0")/env.sh"

echo "========================================="
echo " Storage — GCS Bronze"
echo "========================================="

echo ""
echo "[1/1] Criando bucket Bronze..."

if gsutil ls "gs://$BUCKET_BRONZE" &>/dev/null; then
    echo "  ⚠️  Bucket já existe"
else
    gsutil mb \
        -p $PROJECT_ID \
        -l $REGION \
        -b on \
        "gs://$BUCKET_BRONZE"

    # Lifecycle: deleta arquivos com mais de 90 dias
    cat > /tmp/lifecycle_bronze.json << 'EOF'
{
  "lifecycle": {
    "rule": [{ "action": { "type": "Delete" }, "condition": { "age": 90 } }]
  }
}
EOF
    gsutil lifecycle set /tmp/lifecycle_bronze.json "gs://$BUCKET_BRONZE"
    echo "  ✅ Bucket Bronze criado: gs://$BUCKET_BRONZE"
fi

echo ""
echo "Próximo: bash infra/03_bigquery.sh"