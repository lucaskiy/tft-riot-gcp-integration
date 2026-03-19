#!/bin/bash
set -e

echo "================================================="
echo " TFT dbt Runner"
echo " $(date -u +'%Y-%m-%d %H:%M:%S UTC')"
echo " RUN_MODE    : ${RUN_MODE:-daily}"
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

REFRESH_FLAG=""
if [ "${FULL_REFRESH}" = "true" ]; then
    REFRESH_FLAG="--full-refresh"
    echo "⚠️  Full refresh ativado — tabelas serão recriadas do zero"
fi

run_dbt() {
    local TAG=$1
    echo ""
    echo ">>> dbt run — $TAG"
    dbt run --select "$TAG" --profiles-dir ~/.dbt $REFRESH_FLAG

    echo ""
    echo ">>> dbt test — $TAG"
    dbt test --select "$TAG" --profiles-dir ~/.dbt
}

case "${RUN_MODE:-daily}" in

  daily)
    run_dbt "tag:staging"
    run_dbt "tag:silver"
    # + garante que dependências Silver estejam atualizadas antes do Gold
    dbt run  --select "+tag:gold" --profiles-dir ~/.dbt $REFRESH_FLAG
    dbt test --select "tag:gold"  --profiles-dir ~/.dbt
    ;;

  staging)
    run_dbt "tag:staging"
    ;;

  silver)
    run_dbt "tag:silver"
    ;;

  gold)
    dbt run  --select "+tag:gold" --profiles-dir ~/.dbt $REFRESH_FLAG
    dbt test --select "tag:gold"  --profiles-dir ~/.dbt
    ;;

  full)
    echo ""
    echo ">>> dbt run — todos os modelos"
    dbt run  --profiles-dir ~/.dbt $REFRESH_FLAG
    dbt test --profiles-dir ~/.dbt
    ;;

  *)
    echo "❌ RUN_MODE inválido: ${RUN_MODE}"
    echo "   Valores aceitos: daily | staging | silver | gold | full"
    exit 1
    ;;
esac

echo ""
echo ">>> dbt docs generate"
dbt docs generate --profiles-dir ~/.dbt

echo ""
echo "================================================="
echo " dbt run finalizado com sucesso"
echo " $(date -u +'%Y-%m-%d %H:%M:%S UTC')"
echo "================================================="