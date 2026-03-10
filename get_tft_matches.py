import time
import requests
from datetime import datetime, timezone, timedelta

API_KEY      = "RGAPI-077ae232-6300-4c4e-9cc7-cd0541f39a1b"
REGION       = "br1"
MASS_REGION  = "americas"
COUNT        = 5      # últimas X partidas por jogador
HOURS_BACK   = 2      # janela de tempo

HEADERS = {"X-Riot-Token": API_KEY}

# PUUIDs coletados no passo anterior
# PUUIDS = ['5nigFJK6_30JPh_RK5BLUBQ04b_1wSXMlqzihYwpTom2uS3pcXbxvjS8hPBboaU6yZmzP8hqZCSOAQ', 'sJAAFVG1p29bKfhqASyC557YRi77Bjz4paAkjekq0p-4piPYUOGu-m86ajI-xWpyxn2tGeU96NxQvQ', 'jWi2NCrp0wSRghKWtZBX5ph1bkYKZRpNStOwm_mqQ94lg7qAUQYf3lZVPINr__m56-kFSKglWtVp-Q', 'fttVH0UuzdDj1HwZuwod6pHjAh86CCrrcf2eq5EL6Jksivxw4RcBvcPc-IW14hF6Ie8z_x7mwkctJw', '9cioPm14GuFUNDACj4F5Kfcq_ViiVUPvnQKcXmpo6PM7AgTUGo-BJHNvTfHoS9kqNtfe_nquWWWKwg', '0G0zOHOqSRHUJxgydHR2q702ag2Ro5AA9-VLD6SqrISHS-8yWsv2SVTAj0_UFSfUJ7rO7PvggVUUmQ', 'FWKou4VkaEO-kGcB7xJ28Iw1j9OBrJHR_CDI4IOYgnl_fPNJYuoPyQcDGWpfd20Syrav_c3FIO9Ogg', 'eI2XzNOw6ddQqAMfWnqSNeEawGVt0QEFDlxl3XNkuEJ5Y8bdZJ16MhBNLqz2Zacuy73Noijcpypjww', 'z34drnxeUsM7G0XAvzjS4tCij5Q9Kr2LIp0y_quMntGVHZRIQcJfgu0Ak3a9TobkA1zfxP2oigheJA', 'KnerIN74LA2ymGEelyW18OzEzFfBBSavjtd7ePla1vsCpS3V2q1XRygfN6LuuP9NrJ_y3WgMwNhFPQ', 'u1kCk8Rw6FEcsO0m9UATeQskwfw3FHI5kroP4LYC2x031K0ZmNwlvpQpHnUBg12VdRfu16xln7THlQ', 'H_8NFib8MYacxRU_E0SGeVq6cgNGEDioqN2FnNbnv8iz7NrJpe30DnsTWIrYU4r-Yp766x1Rq2WDjg', 'xmETrk-xoz0Wrcwry62teIdL1f3xCPKYLOlKug8PfjxOLK5PJlksvYZ4DB8J1FJdfvBI5wSZeO0AKQ', 'MWJejtk0XlJESx0GFsC4zK45Lrt988r8T4PfTeqEqcmE8AtuZ29_RhB9gZFTYv7ziF2-VIiS_SCzvw', 'f65231qDwjYQympOi0XVFto-67AiNKGFs2Y58eKxuY4b0fHKRPOeSRgVRlW9VTR8fUavtiGQL0jeXA', 'UieIcCK0EjIjMpnfkx1uxoeeXHB5rCb5lzCv1FZJE03oVr3bIEf4QGLKlyvZOVahZApKGZJ_hs3qAw', '0nXx6e85ZoZ3nXUUODLWvQdMdtnZlI7gGyvwNxjr8ckH2zIycDAmms6BrFcBuitXN2gc-EJ8ajI14g', 'L9oriAJdRWHg-opCd9zVI2P8BNf0_-X8nPHfHGHckWKHSFl2IFpMsnNcMSMKWY8BbpZKrZdoY52d_w', 'kCfg8TPWreXn78wIRZtR6u5Cn2VBc5PEkWHdoq9ZsZBqO_be4jcU4A2jjxNKgi_ns-dUgddk72svuQ', '4RM7Iwx0_4f9vfjpnKLJMqy8wAjkty2BtKCSXIlC_myVVwoCnF3_f6nPvVmXSXtvWmucXc-PJVPscg', '6KCfqQkC6YoNabO0oAA3k0uPCHv1JWNuRN_WFXPXrFg2qYw9J91RFlAsUSYkHlrh4ua4DP4BeiL_UA', '20EsizyjGsIWM7h4Y_2sH8dRvB0fwNIbrHN1-69i4o2XqMu-bigxDzZpSMPcbpMbQl_a56rhp7x-pQ', 'lh8IjdiWk88_Kvg-YW8fAB9E8Gn80ytQJ3cfc1lnsGPDamnt-aCP4vSPbilNMFmlgrwIctA_yRe9aA', 'jRfE8fTVnxqsdh-S4NLZYATRpO7Vk8ZlSZ5qHxpnc1XUk8WriZ-itIy__4vp7rEEULFrRBw-84vziA', 'RV9QA4JfgAjoVFUAVr6ISr7O_uEyYO4WLioCFebHNw3eBLEJuChGW-T6qASjnbcLF8U_3wfqyIVSDw', 'hTWGOTIA4V3tGAT5gSly6xI0abFz3HUO0WTQOKQ8iFoNgDv-qQ906WNjDZb0H36Lkq1yu9US0Uufiw', 'MGx9YnSQdx8hdCWhCWzp9i1R1PsEEL_eeUBpj5dtMyX-JG0GmdiPmBkCHNRMj8smALN4_uQNQl1ccQ', 'Z_3HMGbTBKGfiAFBu4-Mcy2wP364aY_G7J7mjxSanQCsKJy88oSIuU9mKRCJdEL5fhAqNHAiEgWmFw', 'UnoPuxKPYyVB-5pBoJtuFSWHvp_epqKA1cPs8KMgGEJe8epiqd0pFxIeFgN8rlx3CdKGpfwKuVWWCg', 'oic7gBCeuZ-Bm7Xh_lXsKG_GtCrLIyLhD1nsX6gdZwYR6l6nmUpy7zpAxURqlo6nbufqKJJ64Dgi_Q', 'AylJzjUNWc-6rEjWvGfGs6vhKLRDPKnIyCGXXyQfRdB7zx1-8wEjsvNOf5lOBUDNUfxZ8WaODrPi4Q', 'gxt7lgLD5mq0838RQbsMKoPlAG4QJyRbsGfg3XD4RdJdafduZjojvNLqj2_tnVaiLckeRjFHIAdLaQ', 'XlC4548AeU3cgX8c8pNy_S1KzBWZb8_7A7SXHpeAUaIY6ii9Nz2i0ouyRJ5zHLHTh4etAK4YOTtezQ', 'gshhKXL42pFJLeqr75ulgUCbKpEqq20n7xDG_Gd_OrqWvhdzNqc3AmzFhScJg9xLqIaNJXJ1JjOxFw', 'BQpgbgmRwnjwNFkQZ6i2WbfzXl4RQ-5hUfQ0YBmB-oDKzs57yEq_luxnUb4CnrXIlGKUEITHLvmPrA', 'LCz9RSmNfvhDQMOvM9g90uuFb2wXvsjqmZu9LC5tCOk4B9Yt8ieOeCTKMsUg5_ZxVDV5F4AyzZ08cQ', '0LXw3Kj5XrpDgaxUzrY0IORTrB21yGdJDNTgUSfvk6SSwzpOIWp5JhWHBgD-ehEGpm_YkW6fyHVotA', '6U2E4nPua8eKOpVpeP7UWQ9XpsCZ5yl0PTNnGlHkN5KeKOfxjpnuDV6nOmevSzAum5vCjNp_bqhW0Q', 'Byp9ZYtbxmcxsbcAz4Owrtd0xK-S4qb39qVdLUGd-5F4cN5ijiP34_4FWXWLqaljP9EV8pFcTpQl_w', 'xU5gismzcVKgmKlZzqKPrI2uG8jIvUG9UNvSvH9QG0wiZWjV1w-DWu4jkRmBRXmPwJn_6snecAafaw', '7w3WxFx7xG5-O-_4K60AIu0HcOHjgb3MO6HcgiHcJVPj0Q-qj2A82azEIz-XHwpubNh6IB16q9p5Rw', 'OYrKNsIv_ZH-HolmI44kFOKf0OAsE-shGxewEkiJHdBkJtJE46hMOQRD4DUhopH9avJM7Ikm-1I6jA', '7kSYalHJKnNp_WL24Aq7Mi0VqlO4VNGe6erT9vvUMwsns4BxL_V8T7bvxBMQc65wJOujjEQcqHNlPA', 'aYWYuwAR4hPLSOXK2XptIUb9wGwbDA-Jmx52SmtZXTWunLP0jq_MVj2PYLuN5VJSfLB50wivjsF22w', 'yfBvlKY4YguLaPWcE75zH2kQchkX4vUBTJ9VpYByfcHW2Kn2GxGOqSEy2A5MhSL8lhpsq4gBS6gSpQ', 'IIEY7ThgAX3X-NiT-t7lccUQLwhUWZTvw8ejaVu0SRMhxGxsxbLvrw6daRuMHcYpxK4lwqF2kHfrNw', 'jRQj_fxxkH29_tXMsbh_ySJXDsrKQczqPzcWpGfpePepagTWm6HBchFjUzQgLBqJRw_jjDj1rTfz9A', 'c2P0QnMxCD18KwbWHJbPEO41rDxxC63GQ9hvsJhT8Aw413F2hn4jK_obsqT708x6FdDvGKLUrzHSQA', 'mCxGwuc1lCy0Sn3aYHgHUalelmD2tT12DiA-U1FwlxQ03qrPY84TdUHKoLzxHayXdcRnTOXazUZsag', 'INC0nmdOy0KqQsEiHE1BR4SDzgKIyT5zpbYTDOjic0JwuL4hcZs62wOf6VI2SNTq54qyKuM-RtkvOQ']
PUUIDS = ['1FkMqUKm55Cj-TTpasQTbzZpYGt0pnTM0hTO73ZrwWtG3reu8UA6CzEc9FJRw8VScK8Qpet3rbb1Mw']

def get(url, params=None):
    response = requests.get(url, headers=HEADERS, params=params)
    if response.status_code == 429:
        retry = int(response.headers.get("Retry-After", 5))
        print(f"  Rate limit. Aguardando {retry}s...")
        time.sleep(retry + 1)
        return get(url, params)
    if response.status_code == 404:
        return []
    response.raise_for_status()
    return response.json()

# Timestamp de X horas atrás (epoch seconds)
since = int((datetime.now(timezone.utc) - timedelta(hours=HOURS_BACK)).timestamp())

print(f"Buscando partidas desde {datetime.fromtimestamp(since, tz=timezone.utc).strftime('%d/%m/%Y %H:%M')} UTC")
print(f"Parâmetros: últimas {COUNT} partidas | janela de {HOURS_BACK}h")
print(f"Total de PUUIDs: {len(PUUIDS)}\n")

all_match_ids = set()

for i, puuid in enumerate(PUUIDS):
    ids = get(
        f"https://{MASS_REGION}.api.riotgames.com/tft/match/v1/matches/by-puuid/{puuid}/ids",
        params={
            "count": COUNT,
            "start_time": since,
            "queue": 1100,   # 1100 = Ranked TFT
        }
    )

    new = [mid for mid in ids if mid not in all_match_ids]
    all_match_ids.update(ids)

    print(f"[{i+1}/{len(PUUIDS)}] {puuid[:20]}... → {len(ids)} partidas | {len(new)} novas | total único: {len(all_match_ids)}")
    time.sleep(0.5)

print(f"\n✅ Total de match IDs únicos coletados: {len(all_match_ids)}")
print("\nPrimeiros 10 IDs:")
for mid in list(all_match_ids)[:10]:
    print(f"  {mid}")