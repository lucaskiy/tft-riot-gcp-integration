#!/bin/bash
# =============================================================================
# deploy_all.sh — Deploy completo do ambiente (primeira vez)
# =============================================================================
set -e
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║   TFT Data Platform — Deploy Completo    ║"
echo "╚══════════════════════════════════════════╝"
echo ""
read -p "Continuar? (s/n): " confirm
[[ "$confirm" != "s" ]] && echo "Abortado." && exit 0

bash "$DIR/01_setup.sh"
bash "$DIR/02_storage.sh"
bash "$DIR/03_bigquery.sh"
bash "$DIR/04_pubsub.sh"
bash "$DIR/05_deploy.sh"

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║            ✅ Deploy concluído!           ║"
echo "╚══════════════════════════════════════════╝"
echo ""
echo "Próximos passos manuais:"
echo "  1. Aguardar primeira ingestão de dados"
echo "  2. bash infra/create_external_table.sh"
echo "  3. dbt run --full-refresh"
echo "  4. bash infra/06_assets.sh   (ícones para o Looker)"