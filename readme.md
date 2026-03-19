# TFT Data Platform

Pipeline de dados completo para análise de **Teamfight Tactics**, consumindo a Riot Games API e expondo os resultados em um dashboard interativo no Looker Studio.

**[→ Acessar o Dashboard](https://lookerstudio.google.com/u/1/reporting/94e0ba28-e016-4016-8a65-104c2a7e900a/page/ygPsF)**

---

## O que o projeto faz

Coleta automaticamente partidas de jogadores do tier Master e Diamond I no servidor BR, processa os dados em camadas e disponibiliza análises de win rate por composição, campeão e build de itens — atualizadas a cada hora.

---

## Arquitetura

```
Riot Games API
      │
      ▼
tft-collector (Cloud Function)          ← roda a cada hora via Cloud Scheduler
      │
      ├── match IDs novos ──────────────► tft-match-fetcher (Cloud Function)
      │                                         │
      │                                         ▼
      │                                   GCS Bronze (JSON brutos)
      │                                         │
      └── coleta finalizada ─────────────► tft-dbt-runner (Cloud Run Job)
                                                 │
                                                 ▼
                                         BigQuery (Silver → Gold)
                                                 │
                                                 ▼
                                         Looker Studio (Dashboard)
```

---

## Stack

| Camada | Tecnologia |
|---|---|
| Ingestão | Python + Cloud Functions |
| Orquestração | Cloud Scheduler + Pub/Sub |
| Armazenamento raw | Google Cloud Storage |
| Controle de estado | Firestore |
| Transformação | dbt + BigQuery |
| Dashboard | Looker Studio |
| Ícones | GCS público (Community Dragon) |

---

## Camadas de dados

```
Bronze  →  JSON brutos da Riot API (GCS)
Staging →  JSON parseado em colunas (BigQuery view)
Silver  →  Tabelas normalizadas por partida, jogador, trait e unidade
Gold    →  Win rates, tier lists e builds agregados por patch
```

---

## Dashboard

O dashboard permite analisar o meta do TFT com filtros por patch, campeão e tier de performance. As principais visões são:

- **Campeões** — win rate e top4 rate por campeão e tier de estrelas
- **Composições** — melhores composições com ícones dos campeões
- **Builds** — melhores combinações de itens por campeão

**[→ Abrir Dashboard](https://lookerstudio.google.com/u/1/reporting/94e0ba28-e016-4016-8a65-104c2a7e900a/page/ygPsF)**

---

## Estrutura do repositório

```
├── ingestion/       # Cloud Functions — coleta de dados da Riot API
├── dbt/             # Transformações BigQuery — staging, silver e gold
├── infra/           # Scripts de infraestrutura GCP
└── README.md        # Este arquivo
```

Cada diretório tem seu próprio README com detalhes de implementação, variáveis de ambiente e comandos operacionais.

---

## Como rodar

```bash
# 1. Deploy da infraestrutura
bash infra/deploy_all.sh

# 2. Após a primeira ingestão
bash infra/create_external_table.sh
dbt run --full-refresh

# 3. Ícones para o Looker
bash infra/06_assets.sh
```