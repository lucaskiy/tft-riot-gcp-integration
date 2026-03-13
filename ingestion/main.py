import os
import sys
import time
import json
import base64
import logging
from datetime import datetime, timezone, timedelta

import functions_framework
import riot_client
import firestore_client
import gcs_client
import pubsub_client
from firestore_client import STATUS_ABANDONED

# Cloud Run captura stdout/stderr — força o logging para stdout com flush
logging.basicConfig(
    level=logging.INFO,
    stream=sys.stdout,
    format="%(levelname)s:%(name)s:%(message)s",
    force=True
)
logger = logging.getLogger(__name__)

# ─── CONFIG ──────────────────────────────────────────────────────────────────

PROJECT_ID    = os.environ["PROJECT_ID"]
RIOT_API_KEY  = os.environ["RIOT_API_KEY"]
RIOT_REGION   = os.environ.get("RIOT_REGION", "br1")
MASS_REGION   = os.environ.get("MASS_REGION", "americas")
BRONZE_BUCKET = os.environ["BRONZE_BUCKET"]
PUBSUB_TOPIC  = os.environ.get("PUBSUB_TOPIC", "tft-match-ids")

MATCH_COUNT = int(os.environ.get("MATCH_COUNT", "20"))
HOURS_BACK  = int(os.environ.get("HOURS_BACK", "24"))

# ─── INICIALIZAÇÃO DOS CLIENTES ───────────────────────────────────────────────

def _init_clients():
    riot_client.init(RIOT_API_KEY, RIOT_REGION, MASS_REGION)
    firestore_client.init(PROJECT_ID)
    gcs_client.init(BRONZE_BUCKET)
    pubsub_client.init(PROJECT_ID, PUBSUB_TOPIC)

# ─── CLOUD FUNCTIONS ─────────────────────────────────────────────────────────

@functions_framework.http
def collector(request):
    """
    Job 1 — Collector (trigger: HTTP via Cloud Scheduler)

    Fluxo:
      1. Busca PUUIDs do Challenger, Grandmaster e Master
      2. Coleta match IDs (janela HOURS_BACK horas)
      3. Filtra IDs já tratados no Firestore
      4. Registra IDs novos como pending
      5. Publica em batches no Pub/Sub
    """
    logger.info("=== Collector iniciado ===")
    _init_clients()

    since_ts = int((datetime.now(timezone.utc) - timedelta(hours=HOURS_BACK)).timestamp())
    logger.info(f"Janela: últimas {HOURS_BACK}h | {MATCH_COUNT} partidas/jogador")

    puuids = riot_client.get_puuids_by_tier(MATCH_COUNT, HOURS_BACK)
    if not puuids:
        return {"status": "error", "message": "Nenhum jogador encontrado"}, 500

    all_match_ids = set()
    for i, puuid in enumerate(puuids):
        ids = riot_client.get_match_ids(puuid, since_ts, MATCH_COUNT)
        all_match_ids.update(ids)
        logger.info(f"[{i+1}/{len(puuids)}] {len(ids)} partidas | total único: {len(all_match_ids)}")
        time.sleep(0.5)

    logger.info(f"Total de match IDs únicos: {len(all_match_ids)}")

    new_ids = []
    skipped = 0
    for match_id in all_match_ids:
        if firestore_client.is_already_handled(match_id):
            skipped += 1
            continue
        firestore_client.save_pending(match_id)
        new_ids.append(match_id)

    logger.info(f"Novos: {len(new_ids)} | Ignorados: {skipped}")

    if not new_ids:
        return {"status": "ok", "published": 0, "skipped": skipped}, 200

    total_batches = pubsub_client.publish_all(new_ids)

    # Notifica o pipeline de transformação que há dados novos para processar
    pubsub_client.publish_pipeline_event({
        "event":      "collector_finished",
        "new_ids":    len(new_ids),
        "batches":    total_batches,
        "triggered_at": datetime.now(timezone.utc).isoformat(),
    })

    logger.info("=== Collector finalizado ===")

    return {
        "status":     "ok",
        "total_ids":  len(all_match_ids),
        "new_ids":    len(new_ids),
        "skipped":    skipped,
        "batches":    total_batches,
        "batch_size": pubsub_client.BATCH_SIZE,
    }, 200


@functions_framework.cloud_event
def match_fetcher(cloud_event):
    """
    Job 2 — Match Fetcher (trigger: Pub/Sub)

    Recebe um batch de match IDs e processa cada um:
      1. Busca JSON na Riot API
      2. Salva no GCS Bronze (1 arquivo por match)
      3. Atualiza status no Firestore

    Erros recuperáveis: re-publica os IDs que falharam.
    Erros não recuperáveis (401/403): abandona imediatamente.
    Após MAX_RETRIES: marca como abandoned e para.
    """
    _init_clients()

    batch_id  = "UNKNOWN"
    match_ids = []

    try:
        raw       = base64.b64decode(cloud_event.data["message"]["data"]).decode("utf-8").strip()
        payload   = json.loads(raw)
        match_ids = payload.get("match_ids", [])
        batch_id  = payload.get("batch_id", "UNKNOWN")
        logger.info(f"=== Match Fetcher | batch: {batch_id} | {len(match_ids)} IDs ===")

        if not match_ids:
            logger.error(f"Batch {batch_id} vazio — descartando")
            return

    except Exception as e:
        logger.critical(f"Erro ao decodificar mensagem Pub/Sub: {e} — descartando")
        return

    results    = {"success": 0, "error": 0, "abandoned": 0, "skipped": 0}
    failed_ids = []

    for match_id in match_ids:
        try:
            if firestore_client.is_already_handled(match_id):
                results["skipped"] += 1
                continue

            data = riot_client.get_match_detail(match_id)

            if not data:
                status = firestore_client.save_error(match_id, "Partida não encontrada (404)")
                results["abandoned" if status == STATUS_ABANDONED else "error"] += 1
                continue

            gcs_client.save_match(match_id, data)
            firestore_client.save_success(match_id)
            results["success"] += 1

            patch = data.get("info", {}).get("game_variation", "?")
            logger.info(f"  ✅ {match_id} | patch: {patch}")

        except Exception as e:
            error_msg = str(e)

            if "401" in error_msg or "403" in error_msg:
                firestore_client.save_error(match_id, error_msg)
                results["abandoned"] += 1
                logger.critical(f"  ❌ {match_id} não recuperável: {error_msg}")
                continue

            status = firestore_client.save_error(match_id, error_msg)
            if status == STATUS_ABANDONED:
                results["abandoned"] += 1
            else:
                results["error"] += 1
                failed_ids.append(match_id)
                logger.error(f"  ⚠️  {match_id} erro recuperável — vai retentar")

    logger.info(
        f"=== Batch {batch_id} finalizado | "
        f"✅ {results['success']} ok | "
        f"⚠️  {results['error']} erros | "
        f"❌ {results['abandoned']} abandonados | "
        f"⏭️  {results['skipped']} ignorados ==="
    )

    if failed_ids:
        logger.warning(f"Re-publicando {len(failed_ids)} IDs com erro para retry")
        pubsub_client.publish_batch(failed_ids, batch_num=0)


@functions_framework.cloud_event
def dlq_reprocessor(cloud_event):
    """
    Job 3 — DLQ Reprocessor (trigger: Pub/Sub tft-match-ids-dead-letter)

    Lê mensagens que falharam MAX_RETRIES vezes no match_fetcher e tenta
    reprocessar uma última vez. Se falhar novamente, marca como abandoned
    e loga como CRITICAL para alertas.

    Fluxo:
      1. Recebe batch da DLQ
      2. Reseta o contador de retries no Firestore (status → error)
      3. Republica no tópico principal para o match_fetcher tentar novamente
      4. Se o match_id não existir no Firestore, registra e republica mesmo assim
    """
    _init_clients()

    batch_id  = "UNKNOWN"
    match_ids = []

    try:
        raw       = base64.b64decode(cloud_event.data["message"]["data"]).decode("utf-8").strip()
        payload   = json.loads(raw)
        match_ids = payload.get("match_ids", [])
        batch_id  = payload.get("batch_id", "DLQ-UNKNOWN")
        logger.warning(f"=== DLQ Reprocessor | batch: {batch_id} | {len(match_ids)} IDs ===")

        if not match_ids:
            logger.error("Mensagem DLQ vazia — descartando")
            return

    except Exception as e:
        logger.critical(f"Erro ao decodificar mensagem DLQ: {e} — descartando")
        return

    requeued   = 0
    abandoned  = 0

    for match_id in match_ids:
        doc = firestore_client.get_match_doc(match_id).get()

        if doc.exists:
            data    = doc.to_dict()
            retries = data.get("retries", 0)
            status  = data.get("status", "unknown")

            # Se já foi processado com sucesso entre o erro e agora, ignora
            if status == "success":
                logger.info(f"  ⏭️  {match_id} já processado com sucesso — ignorando")
                continue

            logger.warning(
                f"  🔁 {match_id} | status: {status} | retries: {retries} "
                f"| last_error: {data.get('last_error', 'N/A')[:100]}"
            )

        # Reseta o contador de retries para dar mais uma chance
        firestore_client.get_match_doc(match_id).set({
            "match_id":   match_id,
            "status":     "error",
            "retries":    0,
            "last_error": "Reprocessado via DLQ",
            "updated_at": datetime.now(timezone.utc).isoformat(),
        }, merge=True)

        requeued += 1

    if requeued > 0:
        requeue_ids = [
            mid for mid in match_ids
            if not (firestore_client.get_match_doc(mid).get().exists
                    and firestore_client.get_match_doc(mid).get().to_dict().get("status") == "success")
        ]
        pubsub_client.publish_batch(requeue_ids, batch_num=0)
        logger.warning(f"  🔁 {requeued} IDs recolocados na fila principal")

    logger.warning(
        f"=== DLQ Reprocessor finalizado | "
        f"🔁 {requeued} recolocados | "
        f"❌ {abandoned} abandonados ==="
    )