# #!/bin/bash
# # =============================================================================
# # 06_assets.sh
# # Cria bucket público de assets e baixa imagens do Community Dragon
# # Executa após os dados já estarem no BigQuery (unit_winrate populado)
# # =============================================================================

# set -e

PROJECT_ID="tft-gcp-integration"
REGION="us-central1"
ASSETS_BUCKET="tft-assets-${PROJECT_ID}"
CDN_BASE="https://raw.communitydragon.org/latest/game/assets/characters"
TMP_DIR="/tmp/tft_assets"

# echo "================================================="
# echo " TFT Assets — Download e Upload para GCS"
# echo " Projeto : $PROJECT_ID"
# echo " Bucket  : gs://$ASSETS_BUCKET"
# echo "================================================="

# # -----------------------------------------------------------------------------
# # 1. Criar bucket público de assets
# # -----------------------------------------------------------------------------
# echo ""
# echo "[1/4] Criando bucket de assets..."

# if gsutil ls "gs://$ASSETS_BUCKET" &>/dev/null; then
#     echo "  ⚠️  Bucket gs://$ASSETS_BUCKET já existe"
# else
#     gsutil mb \
#         -p $PROJECT_ID \
#         -l US \
#         -b on \
#         "gs://$ASSETS_BUCKET"
#     echo "  ✅ Bucket criado"
# fi

# # Torna o bucket público para leitura
# gsutil iam ch allUsers:objectViewer "gs://$ASSETS_BUCKET"
# echo "  ✅ Bucket configurado como público"

# # Cache de 7 dias para as imagens
# gsutil web set -m index.html "gs://$ASSETS_BUCKET"

# # -----------------------------------------------------------------------------
# # 2. Buscar lista de units no BigQuery
# # -----------------------------------------------------------------------------
# echo ""
# echo "[2/4] Buscando lista de units no BigQuery..."

# UNITS=$(bq query \
#     --project_id=$PROJECT_ID \
#     --nouse_legacy_sql \
#     --format=csv \
#     --quiet \
#     'SELECT DISTINCT LOWER(character_id) AS id FROM `tft-gcp-integration.tft_gold.unit_winrate` ORDER BY id' \
#     | tail -n +2 | tr -d '"')

# UNIT_COUNT=$(echo "$UNITS" | wc -l)
# echo "  ✅ $UNIT_COUNT units encontradas"

# # -----------------------------------------------------------------------------
# # 3. Baixar imagens do Community Dragon
# # -----------------------------------------------------------------------------
# echo ""
# echo "[3/4] Baixando imagens..."

# mkdir -p "$TMP_DIR/champions"

# SUCCESS=0
# FAILED=0
# SKIPPED=0
# set +e  # desabilita exit imediato no loop

# for unit in $UNITS; do
#     # Extrai o número do set: tft16_ahri → 16
#     SET_NUM=$(echo "$unit" | sed 's/tft\([0-9]*\)_.*/\1/')

#     if [ -z "$SET_NUM" ]; then
#         echo "  ⚠️  Set não identificado para: $unit — ignorando"
#         FAILED=$((FAILED+1))
#         continue
#     fi

#     IMG_PATH="${TMP_DIR}/champions/${unit}.png"
#     GCS_PATH="gs://${ASSETS_BUCKET}/champions/${unit}.png"
#     CDN_URL="${CDN_BASE}/${unit}/hud/${unit}_square.tft_set${SET_NUM}.png"

#     # Verifica se já existe no GCS
#     if gsutil -q stat "$GCS_PATH" 2>/dev/null; then
#         SKIPPED=$((SKIPPED+1))
#         continue
#     fi

#     # Baixa a imagem
#     HTTP_CODE=$(curl -s -o "$IMG_PATH" -w "%{http_code}" "$CDN_URL")

#     if [ "$HTTP_CODE" = "200" ] && [ -s "$IMG_PATH" ]; then
#         gsutil -q \
#             -h "Cache-Control:public, max-age=604800" \
#             -h "Content-Type:image/png" \
#             cp "$IMG_PATH" "$GCS_PATH"
#         SUCCESS=$((SUCCESS+1))
#         echo "  ✅ $unit"
#     else
#         echo "  ❌ $unit (HTTP $HTTP_CODE) — $CDN_URL"
#         FAILED=$((FAILED+1))
#     fi

#     # Rate limiting
#     sleep 0.2
# done

# echo ""
# echo "  Baixadas : $SUCCESS"
# echo "  Puladas  : $SKIPPED (já existiam)"
# echo "  Falhas   : $FAILED"

# # -----------------------------------------------------------------------------
# # 4. Atualiza a URL base na variável de ambiente do dbt runner
# # -----------------------------------------------------------------------------
# echo ""
# echo "[4/4] Atualizando variável ASSETS_BASE_URL no Cloud Run Job..."

# ASSETS_BASE_URL="https://storage.googleapis.com/${ASSETS_BUCKET}/champions"

# gcloud run jobs update tft-dbt-runner \
#     --project=$PROJECT_ID \
#     --region=$REGION \
#     --update-env-vars="ASSETS_BASE_URL=${ASSETS_BASE_URL}" \
#     2>/dev/null || echo "  ⚠️  Cloud Run Job não encontrado — atualize manualmente"

# echo ""
# echo "================================================="
# echo " Concluído!"
# echo " URL base dos assets:"
# echo " $ASSETS_BASE_URL/{character_id}.png"
# echo ""
# echo " Exemplo:"
# echo " ${ASSETS_BASE_URL}/tft16_yasuo.png"
# echo "================================================="

# -----------------------------------------------------------------------------
# 5. Baixar imagens de itens via JSON do Community Dragon
# -----------------------------------------------------------------------------
echo ""
echo "[5/6] Baixando mapeamento de itens do Community Dragon..."

CDRAGON_JSON_URL="https://raw.communitydragon.org/latest/cdragon/tft/en_us.json"
JSON_FILE="$TMP_DIR/tft_data.json"
CDRAGON_BASE="https://raw.communitydragon.org/latest/game"

mkdir -p "$TMP_DIR/items"

# Baixa o JSON completo
curl -s "$CDRAGON_JSON_URL" -o "$JSON_FILE"

if [ ! -s "$JSON_FILE" ]; then
    echo "  ❌ Falha ao baixar o JSON do Community Dragon"
else
    echo "  ✅ JSON baixado"

    echo ""
    echo "[6/6] Baixando imagens de itens..."

    ITEM_SUCCESS=0
    ITEM_FAILED=0
    ITEM_SKIPPED=0

    # Extrai id e icon de cada item usando python
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    python3 "$SCRIPT_DIR/download_items.py" "$JSON_FILE" "$ASSETS_BUCKET" "$CDRAGON_BASE" "$TMP_DIR/items"

fi

echo ""
echo "================================================="
echo " Assets URL base:"
echo " Champions : https://storage.googleapis.com/$ASSETS_BUCKET/champions/{id}.png"
echo " Itens     : https://storage.googleapis.com/$ASSETS_BUCKET/items/{api_name}.png"
echo "================================================="

# Limpeza
rm -rf "$TMP_DIR"