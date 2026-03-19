# Ingestion — TFT Data Platform

Três Cloud Functions Python responsáveis por coletar dados da Riot Games API e armazenar no GCS Bronze.

---

## Estrutura de arquivos

```
ingestion/
├── main.py             # Entry points das Cloud Functions
├── riot_client.py      # Riot Games API (PUUIDs, match IDs, match detail)
├── firestore_client.py # Controle de estado dos matches (pending/success/error/abandoned)
├── gcs_client.py       # Upload dos JSONs para o GCS Bronze
├── pubsub_client.py    # Publicação de batches e eventos de pipeline
└── requirements.txt    # Dependências Python
```

---

## Fluxo de dados

```
Cloud Scheduler (0 * * * *)
    └── HTTP POST → tft-collector
            │
            ├── Riot API /tft/league/v1/master        → PUUIDs Master
            ├── Riot API /tft/league/v1/entries/DIAMOND/I → PUUIDs Diamond I
            │
            ├── Para cada PUUID:
            │   └── Riot API /tft/match/v1/matches/by-puuid/{puuid}/ids
            │
            ├── Firestore → filtra IDs já processados (status: success/abandoned)
            ├── Firestore → registra novos IDs como "pending"
            │
            ├── Pub/Sub tft-match-ids → batches de 50 IDs
            │       └── tft-match-fetcher (paralelo, até 10 instâncias)
            │               ├── Riot API /tft/match/v1/matches/{match_id}
            │               ├── GCS Bronze → date=YYYY-MM-DD/{match_id}.json
            │               └── Firestore → status: success / error / abandoned
            │                       └── (em erro) Pub/Sub tft-match-ids → retry
            │                               └── após MAX_RETRIES → DLQ
            │                                       └── tft-dlq-reprocessor
            │                                               └── até MAX_DLQ_ATTEMPTS
            │
            └── Pub/Sub tft-pipeline-events → tft-dbt-runner inicia
```

> ⚠️ O `tft-dbt-runner` é trigado pelo **collector** ao finalizar — não aguarda o `match-fetcher`. Matches processados após o dbt já ter rodado são incluídos na próxima execução incremental.

---

## Módulos

### `main.py`
Entry points das três Cloud Functions. Clientes são inicializados uma vez no módulo (não a cada invocação) aproveitando o reuso de instâncias do Cloud Functions.

| Function | Trigger | Responsabilidade |
|---|---|---|
| `collector` | HTTP (Scheduler) | Coleta PUUIDs e match IDs, publica no Pub/Sub |
| `match_fetcher` | Pub/Sub `tft-match-ids` | Busca JSON da partida, salva no GCS |
| `dlq_reprocessor` | Pub/Sub `tft-match-ids-dead-letter` | Retenta matches que esgotaram retries |

### `riot_client.py`
Wrapper da Riot API com retry em loop (backoff exponencial). Trata automaticamente rate limit (429), timeouts e erros de conexão. Erros 401/403 lançam exceção imediatamente.

**Tiers coletados:** Master + Diamond I por padrão. Challenger e Grandmaster estão comentados em `get_puuids_by_tier` — descomentar para aumentar o volume de dados.

### `firestore_client.py`
Controla o ciclo de vida de cada match para evitar reprocessamento.

| Status | Descrição |
|---|---|
| `pending` | ID coletado, aguardando o match-fetcher |
| `success` | JSON salvo no GCS com sucesso |
| `error` | Falha recuperável — será retentado |
| `abandoned` | Esgotou `MAX_RETRIES` ou `MAX_DLQ_ATTEMPTS` |

### `gcs_client.py`
Salva cada match como um arquivo JSON individual no GCS Bronze, particionado por data de ingestão:
```
gs://tft-bronze-tft-gcp-integration/date=2026-03-19/{match_id}.json
```

### `pubsub_client.py`
Publica batches de 50 match IDs por mensagem Pub/Sub. O tamanho do batch (`BATCH_SIZE`) equilibra paralelismo e overhead de chamadas à API.

---

## Variáveis de ambiente

| Variável | Obrigatória | Padrão | Descrição |
|---|---|---|---|
| `PROJECT_ID` | ✅ | — | ID do projeto GCP |
| `RIOT_API_KEY` | ✅ | — | Chave da Riot API (via Secret Manager) |
| `BRONZE_BUCKET` | ✅ | — | Nome do bucket GCS Bronze |
| `RIOT_REGION` | — | `br1` | Região do servidor Riot (plataforma) |
| `MASS_REGION` | — | `americas` | Região de massa para match history |
| `PUBSUB_TOPIC` | — | `tft-match-ids` | Tópico de match IDs |
| `MATCH_COUNT` | — | `20` | Partidas por jogador por execução |
| `HOURS_BACK` | — | `24` | Janela de tempo para busca de partidas |
| `MAX_DLQ_ATTEMPTS` | — | `2` | Máximo de tentativas via DLQ |

---

## Tratamento de erros

```
Falha na Riot API
    ├── 429 Rate Limit     → aguarda Retry-After + 1s e retenta
    ├── Timeout/conexão    → backoff exponencial (1s, 2s, 4s) até MAX_RETRIES
    ├── 404 Not Found      → match não existe → save_error → possível abandon
    ├── 401/403            → exceção não recuperável → abandon imediato
    └── Outros             → save_error → incrementa retries
                                    ├── retries < MAX_RETRIES → status: error → retry via Pub/Sub
                                    └── retries >= MAX_RETRIES → status: abandoned → vai para DLQ
                                                                        └── dlq_attempts < MAX_DLQ_ATTEMPTS → reset + re-enfileira
                                                                        └── dlq_attempts >= MAX_DLQ_ATTEMPTS → abandoned definitivo + log CRITICAL
```

---

## Monitoramento

```bash
# Logs do collector
gcloud functions logs read tft-collector --region=us-central1 --limit=50

# Logs do match-fetcher
gcloud functions logs read tft-match-fetcher --region=us-central1 --limit=50

# Status dos matches no Firestore
python3 - << 'EOF'
from collections import Counter
from google.cloud import firestore
db = firestore.Client(project="tft-gcp-integration")
status = Counter(d.to_dict().get("status") for d in db.collection("matches").stream())
for k, v in sorted(status.items()): print(f"{k:12} {v:>6}")
EOF

# Inspecionar DLQ
gcloud pubsub subscriptions pull tft-dlq-monitor-sub \
    --project=tft-gcp-integration --limit=10
```

---

## Deploy

```bash
# Deploy de todas as functions
bash infra/05_deploy.sh

# Testar o collector manualmente
gcloud scheduler jobs run tft-collector-hourly --location=us-central1

# Atualizar a Riot API Key
echo -n "RGAPI-xxx" | gcloud secrets versions add riot-api-key \
    --project=tft-gcp-integration --data-file=-
```