#!/bin/bash
set -e

echo "================================================="
echo " TFT dbt Runner"
echo " $(date -u +'%Y-%m-%d %H:%M:%S UTC')"
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
      threads: 4
      timeout_seconds: 300
PROFILE

echo ""
echo "[1/4] Rodando Staging..."
dbt run --select tag:staging --profiles-dir ~/.dbt
echo "✅ Staging concluído"

echo ""
echo "[2/4] Rodando Silver..."
dbt run --select tag:silver --profiles-dir ~/.dbt
echo ""
echo "      Testando Silver..."
dbt test --select tag:silver --profiles-dir ~/.dbt
echo "✅ Silver concluído e validado"

echo ""
echo "[3/4] Rodando Gold..."
dbt run --select tag:gold --profiles-dir ~/.dbt
echo ""
echo "      Testando Gold..."
dbt test --select tag:gold --profiles-dir ~/.dbt
echo "✅ Gold concluído e validado"

echo ""
echo "[4/4] Gerando documentação..."
dbt docs generate --profiles-dir ~/.dbt
echo "✅ Documentação gerada"

echo ""
echo "================================================="
echo " dbt run finalizado com sucesso"
echo " $(date -u +'%Y-%m-%d %H:%M:%S UTC')"
echo "================================================="