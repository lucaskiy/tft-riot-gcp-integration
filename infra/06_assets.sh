#!/bin/bash
# =============================================================================
# 06_assets.sh — Bucket público de assets (ícones de campeões e itens)
# Executa após os dados já estarem no BigQuery
# =============================================================================
set -e
source "$(dirname "$0")/env.sh"

TMP_DIR="/tmp/tft_assets"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "========================================="
echo " Assets — Ícones para o Looker Studio"
echo "========================================="

# ── Bucket público ────────────────────────────────────────────────────────────
echo ""
echo "[1/4] Bucket de assets..."
if ! gsutil ls "gs://$BUCKET_ASSETS" &>/dev/null; then
    gsutil mb -p $PROJECT_ID -l US -b on "gs://$BUCKET_ASSETS"
fi
gsutil iam ch allUsers:objectViewer "gs://$BUCKET_ASSETS"
echo "  ✅ gs://$BUCKET_ASSETS (público)"

# ── Campeões ──────────────────────────────────────────────────────────────────
echo ""
echo "[2/4] Campeões — buscando lista no BigQuery..."

mkdir -p "$TMP_DIR/champions"

UNITS=$(bq query \
    --project_id=$PROJECT_ID --nouse_legacy_sql --format=csv --quiet \
    "SELECT DISTINCT LOWER(character_id) AS id
     FROM \`$PROJECT_ID.tft_silver.dim_units\`
     ORDER BY id" \
    | tail -n +2 | tr -d '"')

UNIT_COUNT=$(echo "$UNITS" | grep -c .)
echo "  $UNIT_COUNT campeões encontrados"
echo ""
echo "[3/4] Baixando imagens de campeões..."

set +e
SUCCESS=0; FAILED=0; SKIPPED=0

for unit in $UNITS; do
    SET_NUM=$(echo "$unit" | sed 's/tft\([0-9]*\)_.*/\1/')
    GCS_PATH="gs://$BUCKET_ASSETS/champions/$unit.png"
    CDN_URL="$CDRAGON_BASE/assets/characters/$unit/hud/${unit}_square.tft_set${SET_NUM}.png"

    if gsutil -q stat "$GCS_PATH" 2>/dev/null; then
        SKIPPED=$((SKIPPED+1)); continue
    fi

    IMG_PATH="$TMP_DIR/champions/$unit.png"
    HTTP_CODE=$(curl -s -A "Mozilla/5.0" -o "$IMG_PATH" -w "%{http_code}" "$CDN_URL")

    if [ "$HTTP_CODE" = "200" ] && [ -s "$IMG_PATH" ]; then
        gsutil -q -h "Cache-Control:public, max-age=604800" \
            -h "Content-Type:image/png" cp "$IMG_PATH" "$GCS_PATH"
        SUCCESS=$((SUCCESS+1))
        echo "  ✅ $unit"
    else
        echo "  ❌ $unit (HTTP $HTTP_CODE)"
        FAILED=$((FAILED+1))
    fi
    sleep 0.2
done
set -e

echo ""
echo "  Campeões: $SUCCESS baixados | $SKIPPED pulados | $FAILED falhas"

# ── Itens ─────────────────────────────────────────────────────────────────────
echo ""
echo "[4/4] Itens..."

mkdir -p "$TMP_DIR/items"
JSON_FILE="$TMP_DIR/tft_data.json"
ITEMS_LIST="$TMP_DIR/items_list.txt"

curl -s "$CDRAGON_JSON" -o "$JSON_FILE"

bq query \
    --project_id=$PROJECT_ID --nouse_legacy_sql --format=csv --quiet \
    "SELECT DISTINCT item
     FROM \`$PROJECT_ID.tft_silver.dim_units\`,
     UNNEST(JSON_VALUE_ARRAY(item_names_json)) AS item
     WHERE item_names_json IS NOT NULL
     ORDER BY item" \
    | tail -n +2 | tr -d '"' > "$ITEMS_LIST"

ITEM_COUNT=$(grep -c . "$ITEMS_LIST")
echo "  $ITEM_COUNT itens únicos encontrados"

python3 "$SCRIPT_DIR/download_items.py" \
    "$JSON_FILE" "$ITEMS_LIST" "$BUCKET_ASSETS" "$CDRAGON_BASE" "$TMP_DIR/items"

# ── Limpeza ───────────────────────────────────────────────────────────────────
rm -rf "$TMP_DIR"

echo ""
echo "========================================="
echo " Assets disponíveis em:"
echo " https://storage.googleapis.com/$BUCKET_ASSETS/champions/{id}.png"
echo " https://storage.googleapis.com/$BUCKET_ASSETS/items/{item}.png"
echo "========================================="