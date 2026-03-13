import json
import time
import sys
import logging
logging.basicConfig(level=logging.INFO, stream=sys.stdout, format='%(levelname)s:%(name)s:%(message)s', force=True)
from datetime import datetime, timezone
from google.cloud import pubsub_v1

logger = logging.getLogger(__name__)

BATCH_SIZE = 50

_publisher  = None
_project_id = None
_topic      = None

def init(project_id: str, topic: str):
    global _publisher, _project_id, _topic
    _project_id = project_id
    _topic      = topic
    _publisher  = pubsub_v1.PublisherClient()


def _topic_path() -> str:
    return _publisher.topic_path(_project_id, _topic)


def publish_pipeline_event(payload: dict):
    """Publica evento no tópico tft-pipeline-events para triggar o dbt."""
    topic_path = _publisher.topic_path(_project_id, "tft-pipeline-events")
    message    = json.dumps(payload).encode("utf-8")
    future     = _publisher.publish(topic_path, message)
    future.result()
    logger.info(f"Evento publicado em tft-pipeline-events: {payload.get('event')}")


def publish_batch(match_ids: list[str], batch_num: int):
    """Publica um batch de match IDs como uma única mensagem."""
    payload = json.dumps({
        "match_ids": match_ids,
        "batch_id":  f"{datetime.now(timezone.utc).strftime('%Y%m%d-%H%M')}-{batch_num}",
        "size":      len(match_ids),
    }).encode("utf-8")

    future = _publisher.publish(_topic_path(), payload)
    future.result()
    logger.info(f"Batch {batch_num} publicado: {len(match_ids)} IDs")


def publish_all(match_ids: list[str]) -> int:
    """Divide em batches de BATCH_SIZE e publica cada um."""
    ids_list = list(match_ids)
    batches  = [ids_list[i:i+BATCH_SIZE] for i in range(0, len(ids_list), BATCH_SIZE)]

    for i, batch in enumerate(batches):
        publish_batch(batch, batch_num=i+1)
        time.sleep(0.1)

    logger.info(f"Total: {len(ids_list)} IDs em {len(batches)} batches")
    return len(batches)