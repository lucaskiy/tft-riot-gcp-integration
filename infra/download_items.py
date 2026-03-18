#!/usr/bin/env python3
"""
download_items.py
Baixa imagens de itens TFT do Community Dragon para o GCS.
Uso: python3 download_items.py <json_file> <gcs_bucket> <cdn_base> <tmp_dir>
"""

import json
import os
import sys
import subprocess
import time


def icon_to_url(icon_path: str, cdn_base: str) -> str:
    path = icon_path.lower().replace(" ", "").replace(".tex", ".png")
    if path.startswith("assets/"):
        path = path[len("assets/"):]
    return f"{cdn_base}/assets/{path}"


def download_file(url: str, dest: str) -> bool:
    """Usa curl com user-agent de browser para evitar 403."""
    r = subprocess.run([
        "curl", "-s", "-L",
        "-A", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
        "-o", dest,
        "-w", "%{http_code}",
        url
    ], capture_output=True, text=True)
    http_code = r.stdout.strip()
    return http_code == "200" and os.path.exists(dest) and os.path.getsize(dest) > 0


def main():
    if len(sys.argv) != 5:
        print("Uso: python3 download_items.py <json_file> <gcs_bucket> <cdn_base> <tmp_dir>")
        sys.exit(1)

    json_file  = sys.argv[1]
    gcs_bucket = sys.argv[2]
    cdn_base   = sys.argv[3].rstrip("/")
    tmp_dir    = sys.argv[4]

    os.makedirs(tmp_dir, exist_ok=True)

    with open(json_file) as f:
        data = json.load(f)

    # Monta lookup: api_name_lower → icon_path
    item_lookup = {}
    for item in data.get("items", []):
        if not isinstance(item, dict):
            continue
        api_name = item.get("apiName", "").lower()
        icon     = item.get("icon", "")
        if api_name and icon:
            item_lookup[api_name] = icon

    print(f"  {len(item_lookup)} itens no lookup global")

    # Pega itens do set mais recente
    set_data   = sorted(data.get("setData", []), key=lambda s: s.get("number", 0), reverse=True)
    latest_set = set_data[0] if set_data else {}
    set_num    = latest_set.get("number", "?")
    set_items  = [i.lower() for i in latest_set.get("items", []) if isinstance(i, str)]

    print(f"  Set mais recente: {set_num} — {len(set_items)} itens")

    # Cruza set_items com lookup para obter icon paths
    relevant = {api: item_lookup[api] for api in set_items if api in item_lookup}
    print(f"  {len(relevant)} itens com icon encontrado")

    success = failed = skipped = 0

    for api_name, icon_path in relevant.items():
        gcs_path = f"gs://{gcs_bucket}/items/{api_name}.png"
        tmp_file = os.path.join(tmp_dir, f"{api_name}.png")
        cdn_url  = icon_to_url(icon_path, cdn_base)

        # Verifica se já existe no GCS
        r = subprocess.run(["gsutil", "-q", "stat", gcs_path], capture_output=True)
        if r.returncode == 0:
            skipped += 1
            continue

        # Baixa com curl + user-agent de browser
        if not download_file(cdn_url, tmp_file):
            print(f"  ❌ {api_name} — {cdn_url}")
            failed += 1
            continue

        # Sobe para o GCS
        r = subprocess.run([
            "gsutil", "-q",
            "-h", "Cache-Control:public, max-age=604800",
            "-h", "Content-Type:image/png",
            "cp", tmp_file, gcs_path
        ], capture_output=True)

        if r.returncode == 0:
            success += 1
            print(f"  ✅ {api_name}")
        else:
            failed += 1
            print(f"  ❌ {api_name} — {r.stderr.decode()}")

        time.sleep(0.05)

    print(f"\n  Baixadas : {success}")
    print(f"  Puladas  : {skipped} (já existiam)")
    print(f"  Falhas   : {failed}")


if __name__ == "__main__":
    main()