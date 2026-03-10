import time
import requests

API_KEY = "RGAPI-077ae232-6300-4c4e-9cc7-cd0541f39a1b"
REGION  = "br1"

HEADERS = {"X-Riot-Token": API_KEY}

def get(url):
    response = requests.get(url, headers=HEADERS, params={"queue": "RANKED_TFT"})
    if response.status_code == 429:
        retry = int(response.headers.get("Retry-After", 5))
        print(f"Rate limit atingido. Aguardando {retry}s...")
        time.sleep(retry + 1)
        return get(url)
    response.raise_for_status()
    return response.json()

# 1. Busca todos os jogadores Challenger
print("Buscando Challenger...")
challenger = get(f"https://{REGION}.api.riotgames.com/tft/league/v1/challenger")
entries = challenger["entries"]
print(f"Total de jogadores: {len(entries)}")

# 2. Para cada jogador, troca summonerId → puuid
puuids = []
for i, entry in enumerate(entries):
    puuid = entry["puuid"]
    puuids.append(puuid)
    print(f'{len(puuids)} coletados')
    time.sleep(0.5)

print(f"\n✅ {len(puuids)} PUUIDs coletados")
print(puuids)  # preview dos primeiros 5