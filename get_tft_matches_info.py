import time
import json
import requests

API_KEY     = "RGAPI-35617a7c-f7cd-475d-8f9f-27db4d06b9d0"
MASS_REGION = "americas"

HEADERS = {"X-Riot-Token": API_KEY}

# Match IDs coletados no passo anterior
MATCH_IDS = [
    "BR1_3212627560",
    "BR1_3213102703",
    "BR1_3212110569",
    "BR1_3211348609",
    "BR1_3207769781",
    "BR1_3211343853",
    "BR1_3210361695",
    "BR1_3211716807",
    "BR1_3213051821",
    "BR1_3213047232"
]

def get(url):
    response = requests.get(url, headers=HEADERS)
    if response.status_code == 429:
        retry = int(response.headers.get("Retry-After", 5))
        print(f"  Rate limit. Aguardando {retry}s...")
        time.sleep(retry + 1)
        return get(url)
    if response.status_code == 404:
        return None
    response.raise_for_status()
    return response.json()

print(f"Total de partidas para buscar: {len(MATCH_IDS)}\n")

matches = []
failed  = []

for i, match_id in enumerate(MATCH_IDS):
    print(f"[{i+1}/{len(MATCH_IDS)}] Buscando {match_id}...", end=" ")

    data = get(f"https://{MASS_REGION}.api.riotgames.com/tft/match/v1/matches/{match_id}")

    if data:
        matches.append(data)
        participants = data["info"]["participants"]
        patch        = data["info"].get("game_variation", data["info"].get("tft_set_core_name", "?"))
        duration     = int(data["info"].get("game_length", 0) // 60)
        print(f"✅  {len(participants)} jogadores | patch: {patch} | {duration}min")
    else:
        failed.append(match_id)
        print("❌  não encontrado")

    time.sleep(0.5)

# Salva resultado em JSON local (futuramente será o GCS Bronze)
output_file = "matches_raw.json"
with open(output_file, "w", encoding="utf-8") as f:
    json.dump(matches, f, ensure_ascii=False, indent=2)

print(f"\n✅ {len(matches)} partidas salvas em {output_file}")

if failed:
    print(f"⚠️  {len(failed)} IDs falharam: {failed}")