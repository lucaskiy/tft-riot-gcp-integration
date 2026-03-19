import logging
from datetime import datetime, timezone
from google.cloud import firestore

logger = logging.getLogger(__name__)

STATUS_PENDING   = "pending"
STATUS_SUCCESS   = "success"
STATUS_ERROR     = "error"
STATUS_ABANDONED = "abandoned"

MAX_RETRIES = 3

_db = None


def init(project_id: str):
    global _db
    _db = firestore.Client(project=project_id)


def _get_db() -> firestore.Client:
    if _db is None:
        raise RuntimeError("firestore_client não inicializado — chame init() primeiro")
    return _db


def get_match_doc(match_id: str):
    """Retorna referência ao documento do match. Pública para uso no dlq_reprocessor."""
    return _get_db().collection("matches").document(match_id)


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


def is_already_handled(match_id: str) -> bool:
    """Retorna True se o match já foi processado com sucesso ou abandonado."""
    doc = get_match_doc(match_id).get()
    if not doc.exists:
        return False
    return doc.to_dict().get("status") in (STATUS_SUCCESS, STATUS_ABANDONED)


def save_pending(match_id: str):
    """Registra o match como pendente."""
    get_match_doc(match_id).set({
        "match_id":   match_id,
        "status":     STATUS_PENDING,
        "created_at": _now(),
        "retries":    0,
    })


def save_success(match_id: str):
    """Marca o match como processado com sucesso."""
    get_match_doc(match_id).update({
        "status":       STATUS_SUCCESS,
        "processed_at": _now(),
    })


def save_error(match_id: str, error_msg: str) -> str:
    """Incrementa retries e atualiza status. Retorna o novo status."""
    doc     = get_match_doc(match_id).get()
    retries = doc.to_dict().get("retries", 0) + 1 if doc.exists else 1
    new_status = STATUS_ABANDONED if retries >= MAX_RETRIES else STATUS_ERROR

    get_match_doc(match_id).set({
        "match_id":   match_id,
        "status":     new_status,
        "retries":    retries,
        "last_error": error_msg[:500],
        "updated_at": _now(),
    }, merge=True)

    if new_status == STATUS_ABANDONED:
        logger.critical(f"Match {match_id} abandonado após {retries} tentativas: {error_msg[:200]}")

    return new_status