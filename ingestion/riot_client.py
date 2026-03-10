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


def _get(url: str, params: dict = None) -> dict | list | None:
    """GET com retry automático em rate limit."""
    response = requests.get(url, headers=_headers(), params=params, timeout=10)

    if response.status_code == 200:
        return response.json()

    if response.status_code == 429:
        retry_after = int(response.headers.get("Retry-After", 5))
        logger.warning(f"Rate limit atingido. Aguardando {retry_after}s...")
        time.sleep(retry_after + 1)
        return _get(url, params)

    if response.status_code == 404:
        return None

    if response.status_code == 401:
        raise Exception("API Key inválida ou expirada (401) — atualize o secret riot-api-key")

    if response.status_code == 403:
        raise Exception(f"Acesso negado (403) em {url} — API Key sem permissão para este endpoint")

    logger.error(f"Erro {response.status_code} em {url}: {response.text[:200]}")
    return None


def get_puuids_by_tier(match_count: int, hours_back: int) -> list[str]:
    """Retorna todos os PUUIDs do Challenger, Grandmaster e Master."""
    from datetime import datetime, timezone, timedelta

    tiers = {
        "challenger":  f"https://{_riot_region}.api.riotgames.com/tft/league/v1/challenger",
        # "grandmaster": f"https://{_riot_region}.api.riotgames.com/tft/league/v1/grandmaster",
        # "master":      f"https://{_riot_region}.api.riotgames.com/tft/league/v1/master",
    }

    all_puuids = []
    for tier, url in tiers.items():
        data = _get(url)
        if not data:
            logger.warning(f"{tier}: nenhum dado retornado")
            continue
        puuids = [e["puuid"] for e in data.get("entries", []) if e.get("puuid")]
        logger.info(f"{tier.capitalize()}: {len(puuids)} jogadores encontrados")
        all_puuids.extend(puuids)

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