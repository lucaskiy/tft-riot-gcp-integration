#!/bin/bash
set -e

echo "================================================="
echo " TFT dbt Runner"
echo " $(date -u +'%Y-%m-%d %H:%M:%S UTC')"
echo " RUN_MODE  : ${RUN_MODE:-daily}"
echo " FULL_REFRESH: ${FULL_REFRESH:-false}"
echo "================================================="

cd /app/tft_dbt

mkdir -p ~/.dbt
cat > ~/.dbt/profiles.yml << PROFILE
tft_dbt:
  target: prod
  outputs:
    prod:
      type: bigquery
      method: oauth
      project: ${PROJECT_ID}
      dataset: tft_staging
      location: US
      threads: 1
      timeout_seconds: 300
PROFILE

# Flags opcionais
REFRESH_FLAG=""
if [ "${FULL_REFRESH}" = "true" ]; then
    REFRESH_FLAG="--full-refresh"
    echo "⚠️  Full refresh ativado — tabelas serão recriadas do zero"
fi

# Seleciona os modelos pelo RUN_MODE
case "${RUN_MODE:-daily}" in

  daily)
    echo ""
    echo "[1/4] Rodando Staging (tag:daily)..."
    dbt run --select tag:staging --profiles-dir ~/.dbt $REFRESH_FLAG

    echo ""
    echo "[2/4] Rodando Silver (tag:daily)..."
    dbt run --select tag:silver --profiles-dir ~/.dbt $REFRESH_FLAG
    echo "      Testando Silver..."
    dbt test --select tag:silver --profiles-dir ~/.dbt

    echo ""
    echo "[3/4] Rodando Gold (tag:daily)..."
    # Usa + para garantir que dependências Silver estejam atualizadas antes do Gold
    dbt run --select +tag:gold --profiles-dir ~/.dbt $REFRESH_FLAG
    echo "      Testando Gold..."
    dbt test --select tag:gold --profiles-dir ~/.dbt
    ;;

  staging)
    echo ""
    echo "[1/1] Rodando apenas Staging..."
    dbt run --select tag:staging --profiles-dir ~/.dbt $REFRESH_FLAG
    dbt test --select tag:staging --profiles-dir ~/.dbt
    ;;

  silver)
    echo ""
    echo "[1/2] Rodando apenas Silver..."
    dbt run --select tag:silver --profiles-dir ~/.dbt $REFRESH_FLAG
    dbt test --select tag:silver --profiles-dir ~/.dbt
    ;;

  gold)
    echo ""
    echo "[1/2] Rodando apenas Gold..."
    dbt run --select tag:gold --profiles-dir ~/.dbt $REFRESH_FLAG
    dbt test --select tag:gold --profiles-dir ~/.dbt
    ;;

  full)
    echo ""
    echo "[1/4] Rodando todos os modelos..."
    dbt run --profiles-dir ~/.dbt $REFRESH_FLAG
    dbt test --profiles-dir ~/.dbt
    ;;

  *)
    echo "❌ RUN_MODE inválido: ${RUN_MODE}"
    echo "   Valores aceitos: daily | staging | silver | gold | full"
    exit 1
    ;;
esac

echo ""
echo "[4/4] Gerando documentação..."
dbt docs generate --profiles-dir ~/.dbt

echo ""
echo "================================================="
echo " dbt run finalizado com sucesso"
echo " $(date -u +'%Y-%m-%d %H:%M:%S UTC')"
echo "================================================="