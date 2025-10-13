#!/usr/bin/env python3
import os
import sys
import time
import requests


def main() -> int:
    """
    Ein einfacher Smoke-Test: versucht wiederholt, die Odoo-Loginseite aufzurufen.
    Erfolgreich, wenn HTTP 200/OK vor Timeout zurückkommt.
    """
    url = os.environ.get("QS_URL", "http://odoo_qs:8069/web/login")
    timeout_s = int(os.environ.get("SMOKE_TIMEOUT", "60"))
    interval_s = int(os.environ.get("SMOKE_INTERVAL", "3"))

    deadline = time.time() + timeout_s
    attempt = 0

    while time.time() < deadline:
        attempt += 1
        try:
            resp = requests.get(url, timeout=5)
            if resp.ok:
                print(f"[smoke] OK {resp.status_code} for {url}")
                return 0
            print(f"[smoke] Attempt {attempt}: Response {resp.status_code}")
        except requests.RequestException:
            print(f"[smoke] Attempt {attempt}: not reachable yet")

        time.sleep(interval_s)

    print(f"[smoke] FAILED after {attempt} attempts: {url}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
