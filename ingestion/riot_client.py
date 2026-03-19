import time
import logging
import requests

logger = logging.getLogger(__name__)

# Injetado pelo main.py na inicialização
_api_key     = None
_riot_region = None
_mass_region = None

# Constantes
MAX_RETRIES        = 3
DIAMOND_PAGE_SIZE  = 205   # Riot retorna até 205 entradas por página


def init(api_key: str, riot_region: str, mass_region: str):
    global _api_key, _riot_region, _mass_region
    _api_key     = api_key
    _riot_region = riot_region
    _mass_region = mass_region


def _headers() -> dict:
    return {"X-Riot-Token": _api_key}


def _get(url: str, params: dict = None) -> dict | list | None:
    """GET com retry em loop (backoff exponencial) para rate limit e erros de conexão."""
    for attempt in range(MAX_RETRIES):
        try:
            response = requests.get(url, headers=_headers(), params=params, timeout=30)
        except Exception as e:
            wait = 2 ** attempt
            logger.warning(f"Erro de conexão ({e.__class__.__name__}) — tentativa {attempt + 1}/{MAX_RETRIES} em {wait}s")
            time.sleep(wait)
            continue

        if response.status_code == 200:
            return response.json()

        if response.status_code == 429:
            retry_after = int(response.headers.get("Retry-After", 10))
            logger.warning(f"Rate limit — aguardando {retry_after}s")
            time.sleep(retry_after + 1)
            continue

        if response.status_code == 404:
            return None

        if response.status_code == 401:
            raise Exception("API Key inválida ou expirada (401) — atualize o secret riot-api-key")

        if response.status_code == 403:
            raise Exception(f"Acesso negado (403) em {url}")

        logger.error(f"Erro {response.status_code} em {url}: {response.text[:200]}")
        return None

    logger.error(f"Falha após {MAX_RETRIES} tentativas: {url}")
    return None


def _get_diamond_puuids(limit: int) -> list[str]:
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

        if len(data) < DIAMOND_PAGE_SIZE:
            break

        page += 1
        time.sleep(1.5)

    unique = list(dict.fromkeys(puuids))[:limit]
    logger.info(f"Diamond I: {len(unique)} jogadores selecionados")
    return unique


def get_puuids_by_tier(match_count: int, hours_back: int) -> list[str]:
    """
    Retorna PUUIDs dos tiers configurados.
    Challenger e Grandmaster estão comentados — ativar conforme volume desejado.
    """
    tiers = {
        # "challenger":  f"https://{_riot_region}.api.riotgames.com/tft/league/v1/challenger",
        # "grandmaster": f"https://{_riot_region}.api.riotgames.com/tft/league/v1/grandmaster",
        "master": f"https://{_riot_region}.api.riotgames.com/tft/league/v1/master",
    }

    TIER_LIMITS = {
        "challenger":  200,
        "grandmaster": 200,
        "master":      200,
    }

    all_puuids = []

    for tier, url in tiers.items():
        data = _get(url)
        if not data:
            logger.warning(f"{tier}: nenhum dado retornado")
            continue
        entries = data.get("entries", [])
        entries.sort(key=lambda e: e.get("leaguePoints", 0), reverse=True)
        limit  = TIER_LIMITS.get(tier, 200)
        puuids = [e["puuid"] for e in entries[:limit] if e.get("puuid")]
        logger.info(f"{tier.capitalize()}: {len(entries)} total → top {len(puuids)}")
        all_puuids.extend(puuids)

    diamond_puuids = _get_diamond_puuids(limit=200)
    all_puuids.extend(diamond_puuids)

    unique = list(dict.fromkeys(all_puuids))
    logger.info(f"Total único: {len(unique)} jogadores")
    return unique


def get_match_ids(puuid: str, since_ts: int, count: int) -> list[str]:
    """Retorna match IDs das últimas N partidas dentro da janela de tempo."""
    url  = f"https://{_mass_region}.api.riotgames.com/tft/match/v1/matches/by-puuid/{puuid}/ids"
    data = _get(url, params={"count": count, "startTime": since_ts, "queue": 1100})
    return data if data else []


def get_match_detail(match_id: str) -> dict | None:
    """Retorna JSON completo de uma partida."""
    url = f"https://{_mass_region}.api.riotgames.com/tft/match/v1/matches/{match_id}"
    return _get(url)