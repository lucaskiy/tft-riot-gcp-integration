# TFT Data Platform — Infraestrutura GCP

Pipeline de dados para análise de Teamfight Tactics consumindo a Riot Games API. Implementa arquitetura Medallion (Bronze → Silver → Gold) no GCP com BigQuery, dbt e Looker Studio.

---

## Arquitetura

```
Cloud Scheduler (hourly)
    └── tft-collector (Cloud Function HTTP)
            ├── Riot API → PUUIDs Master/Diamond I
            ├── Riot API → Match IDs das últimas 24h
            ├── Firestore → filtra IDs já processados
            ├── Pub/Sub tft-match-ids → publica batches de 50 IDs
            └── Pub/Sub tft-pipeline-events → notifica fim da coleta
                    │
                    ├── tft-match-fetcher (Cloud Function Pub/Sub)
                    │       ├── Riot API → JSON completo da partida
                    │       ├── GCS Bronze → salva {date}/{match_id}.json
                    │       └── Firestore → atualiza status (pending/success/error)
                    │
                    ├── tft-dlq-reprocessor (Cloud Function — DLQ)
                    │       └── Retenta matches que falharam MAX_RETRIES vezes
                    │
                    └── tft-dbt-runner (Cloud Run Job)
                            ├── dbt run → stg_matches (view)
                            ├── dbt run → Silver: fact_player_results, fact_traits, fact_units
                            └── dbt run → Gold: unit_winrate, 
                                         item_combo_winrate, 
                                         core_comp_winrate
```

---

## Camadas de dados

| Camada | Dataset BQ | Responsável | Descrição |
|---|---|---|---|
| Bronze | `tft_bronze` | External Table | JSONs brutos no GCS particionados por `date` |
| Staging | `tft_staging` | dbt view | `stg_matches` — JSON parseado em colunas |
| Silver | `tft_silver` | dbt incremental | Tabelas fact/dim normalizadas |
| Gold | `tft_gold` | dbt table | Agregações analíticas para o Looker |

---

## Estrutura de arquivos

```
infra/
├── env.sh                    # Variáveis compartilhadas (PROJECT_ID, SAs, buckets)
├── deploy_all.sh             # Deploy completo (primeira vez)
├── teardown.sh               # Remove todos os recursos
│
├── 01_setup.sh               # APIs, Service Accounts, IAM, Secret (Riot API Key)
├── 02_storage.sh             # Bucket GCS Bronze (lifecycle 90 dias)
├── 03_bigquery.sh            # Datasets BigQuery
├── 04_pubsub.sh              # Tópicos, subscriptions e permissões Pub/Sub
├── 05_deploy.sh              # Cloud Functions + dbt Runner + Scheduler
├── 06_assets.sh              # Bucket público de ícones para o Looker Studio
│
├── create_external_table.sh  # External Table apontando para o GCS Bronze
└── download_items.py         # Script Python — baixa ícones de itens do Community Dragon
```

---

## Como fazer o deploy

### Primeira vez (ambiente do zero)

```bash
# 1. Deploy completo da infraestrutura
bash infra/deploy_all.sh

# 2. Aguardar a primeira execução do Scheduler (ou triggar manualmente)
gcloud scheduler jobs run tft-collector-hourly --location=us-central1

# 3. Após dados no GCS, criar External Table
bash infra/create_external_table.sh

# 4. Rodar o dbt pela primeira vez
cd dbt/tft_dbt && dbt run --full-refresh

# 5. Baixar ícones para o Looker Studio
bash infra/06_assets.sh
```

### Atualizar apenas o código (redeploy)

```bash
# Só functions + dbt Runner
bash infra/05_deploy.sh
```

### Atualizar a Riot API Key

```bash
echo -n "RGAPI-xxx" | gcloud secrets versions add riot-api-key \
    --project=tft-gcp-integration --data-file=-
```

---

## Operação

### Monitorar o pipeline

```bash
# Logs do collector
gcloud logging read \
    "resource.type=cloud_run_revision AND resource.labels.service_name=tft-collector" \
    --project=tft-gcp-integration --freshness=1h --format="value(textPayload)"

# Status das execuções do dbt Runner
gcloud run jobs executions list \
    --job=tft-dbt-runner --project=tft-gcp-integration --region=us-central1

# Contagem de matches por status no Firestore
python3 - << 'EOF'
from collections import Counter
from google.cloud import firestore
db = firestore.Client(project="tft-gcp-integration")
docs = db.collection("matches").stream()
status = Counter(d.to_dict().get("status") for d in docs)
for k, v in sorted(status.items()): print(f"{k}: {v}")
EOF
```

### Triggar o dbt manualmente

```bash
# Execução incremental (padrão)
gcloud run jobs execute tft-dbt-runner \
    --project=tft-gcp-integration --region=us-central1

# Full refresh (recriar todas as tabelas)
gcloud run jobs execute tft-dbt-runner \
    --project=tft-gcp-integration --region=us-central1 \
    --update-env-vars="FULL_REFRESH=true"
```

### Pausar/retomar o Scheduler

```bash
gcloud scheduler jobs pause  tft-collector-hourly --location=us-central1
gcloud scheduler jobs resume tft-collector-hourly --location=us-central1
```

### Inspecionar a DLQ

```bash
gcloud pubsub subscriptions pull tft-dlq-monitor-sub \
    --project=tft-gcp-integration --limit=10
```

---

## Recursos GCP

| Recurso | Nome | Observação |
|---|---|---|
| GCS Bronze | `tft-bronze-tft-gcp-integration` | JSONs particionados por `date=YYYY-MM-DD` |
| GCS Assets | `tft-assets-tft-gcp-integration` | Ícones públicos para o Looker Studio |
| Firestore | `matches` (collection) | Controle de IDs processados |
| Secret | `riot-api-key` | Chave da Riot API |
| Cloud Function | `tft-collector` | HTTP, 540s timeout |
| Cloud Function | `tft-match-fetcher` | Pub/Sub, max 10 instâncias |
| Cloud Function | `tft-dlq-reprocessor` | Pub/Sub DLQ, max 3 instâncias |
| Cloud Run Job | `tft-dbt-runner` | Trigado via Pub/Sub push |
| Scheduler | `tft-collector-hourly` | `0 * * * *` America/Sao_Paulo |