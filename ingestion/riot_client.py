import time
import sys
import logging
logging.basicConfig(level=logging.INFO, stream=sys.stdout, format='%(levelname)s:%(name)s:%(message)s', force=True)
import requests

logger = logging.getLogger(__name__)

# Injetado pelo main.py na inicialização
_api_key    = None
_riot_region = None
_mass_region = None

def init(api_key: str, riot_region: str, mass_region: str):
    global _api_key, _riot_region, _mass_region
    _api_key     = api_key
    _riot_region = riot_region
    _mass_region = mass_region


def _headers() -> dict:
    return {"X-Riot-Token": _api_key}


def _get(url: str, params: dict = None, _retry: int = 0) -> dict | list | None:
    """GET com retry automático em rate limit e erros de conexão."""
    MAX_RETRIES = 3

    try:
        response = requests.get(url, headers=_headers(), params=params, timeout=30)
    except Exception as e:
        if _retry < MAX_RETRIES:
            wait = 2 ** _retry  # backoff: 1s, 2s, 4s
            logger.warning(f"Erro de conexão ({e.__class__.__name__}) — retry {_retry + 1}/{MAX_RETRIES} em {wait}s")
            time.sleep(wait)
            return _get(url, params, _retry + 1)
        logger.error(f"Falha após {MAX_RETRIES} tentativas em {url}: {e}")
        return None

    if response.status_code == 200:
        return response.json()

    if response.status_code == 429:
        retry_after = int(response.headers.get("Retry-After", 10))
        logger.warning(f"Rate limit atingido. Aguardando {retry_after}s...")
        time.sleep(retry_after + 1)
        return _get(url, params, _retry + 1)

    if response.status_code == 404:
        return None

    if response.status_code == 401:
        raise Exception("API Key inválida ou expirada (401) — atualize o secret riot-api-key")

    if response.status_code == 403:
        raise Exception(f"Acesso negado (403) em {url} — API Key sem permissão para este endpoint")

    logger.error(f"Erro {response.status_code} em {url}: {response.text[:200]}")
    return None


def _get_diamond_puuids(limit: int = 200) -> list[str]:
    """Retorna PUUIDs do Diamante I paginando até atingir o limite."""
    puuids = []
    page   = 1

    while len(puuids) < limit:
        url  = f"https://{_riot_region}.api.riotgames.com/tft/league/v1/entries/DIAMOND/I"
        data = _get(url, params={"page": page})

        if not data:
            break

        page_puuids = [e["puuid"] for e in data if e.get("puuid")]
        if not page_puuids:
            break

        puuids.extend(page_puuids)
        logger.info(f"Diamond I página {page}: {len(page_puuids)} jogadores | total: {len(puuids)}")

        if len(data) < 205:
            # Última página — menos de 205 entradas significa fim da lista
            break

        page += 1
        time.sleep(1.5)

    unique = list(dict.fromkeys(puuids))[:limit]
    logger.info(f"Diamond I: {len(unique)} jogadores selecionados")
    return unique


def get_puuids_by_tier(match_count: int, hours_back: int) -> list[str]:
    """Retorna PUUIDs do Challenger, Grandmaster, Master e Diamante I."""

    tiers = {
        # "challenger":  f"https://{_riot_region}.api.riotgames.com/tft/league/v1/challenger",
        # "grandmaster": f"https://{_riot_region}.api.riotgames.com/tft/league/v1/grandmaster",
        "master":      f"https://{_riot_region}.api.riotgames.com/tft/league/v1/master",
    }

    # Limites por tier para controlar volume de chamadas à API
    TIER_LIMITS = {
        "challenger":  200,
        "grandmaster": 200,
        "master":      200,
    }

    all_puuids = []

    # Challenger, Grandmaster, Master
    for tier, url in tiers.items():
        data = _get(url)
        if not data:
            logger.warning(f"{tier}: nenhum dado retornado")
            continue
        entries = data.get("entries", [])
        entries.sort(key=lambda e: e.get("leaguePoints", 0), reverse=True)
        limit  = TIER_LIMITS.get(tier, 200)
        puuids = [e["puuid"] for e in entries[:limit] if e.get("puuid")]
        logger.info(f"{tier.capitalize()}: {len(entries)} total → usando top {len(puuids)}")
        all_puuids.extend(puuids)

    # Diamante I — paginado
    diamond_puuids = _get_diamond_puuids(limit=200)
    all_puuids.extend(diamond_puuids)

    unique = list(dict.fromkeys(all_puuids))
    logger.info(f"Total único: {len(unique)} jogadores")
    return unique


def get_match_ids(puuid: str, since_ts: int, count: int) -> list[str]:
    """Retorna match IDs das últimas N partidas dentro da janela de tempo."""
    url  = f"https://{_mass_region}.api.riotgames.com/tft/match/v1/matches/by-puuid/{puuid}/ids"
    data = _get(url, params={
        "count":     count,
        "startTime": since_ts,
        "queue":     1100,
    })
    return data if data else []


def get_match_detail(match_id: str) -> dict | None:
    """Retorna JSON completo de uma partida."""
    url = f"https://{_mass_region}.api.riotgames.com/tft/match/v1/matches/{match_id}"
    return _get(url)