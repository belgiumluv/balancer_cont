#!/usr/bin/env python3
import os
import json
import shutil
import sqlite3
from pathlib import Path

import requests

# ---------- пути (можно переопределить через ENV) ----------
DOMAIN_DIR = Path(os.getenv("DOMAIN_DIR", "/server_data"))
DOMAIN_TXT = DOMAIN_DIR / "domain.txt"


def get_public_ip(timeout=5) -> str:
    # можно подключить резервные источники при желании
    url = "https://api.ipify.org?format=text"
    resp = requests.get(url, timeout=timeout)
    resp.raise_for_status()
    return resp.text.strip()


def main():
    domain = "test-node-get-cert.dedyn.io"
    DOMAIN_DIR.mkdir(parents=True, exist_ok=True)
    with open(DOMAIN_TXT, "w", encoding="utf-8") as f:
        f.write(domain)


if __name__ == "__main__":
    main()
