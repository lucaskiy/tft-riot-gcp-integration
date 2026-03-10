import json
import sys
import logging
logging.basicConfig(level=logging.INFO, stream=sys.stdout, format='%(levelname)s:%(name)s:%(message)s', force=True)
from datetime import datetime, timezone
from google.cloud import storage

logger = logging.getLogger(__name__)

_gcs    = None
_bucket = None

def init(bucket_name: str):
    global _gcs, _bucket
    _gcs    = storage.Client()
    _bucket = bucket_name


def save_match(match_id: str, data: dict):
    """Salva 1 arquivo JSON por match no GCS Bronze, particionado por date."""
    if _gcs is None:
        raise RuntimeError("gcs_client não inicializado — chame init() primeiro")

    date = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    path = f"date={date}/{match_id}.json"

    blob = _gcs.bucket(_bucket).blob(path)
    blob.upload_from_string(
        json.dumps(data, ensure_ascii=False),
        content_type="application/json"
    )
    logger.info(f"Salvo no Bronze: {path}")