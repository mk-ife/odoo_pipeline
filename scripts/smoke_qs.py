import sys, time
import requests

URL = 'http://localhost:8069/web/login'
for i in range(30):
    try:
        r = requests.get(URL, timeout=3)
        if r.status_code == 200:
            print("OK:", URL, r.status_code)
            sys.exit(0)
    except Exception as e:
        pass
    print(f"Warte auf Odoo QS ({i+1}/30)…")
    time.sleep(3)

print("Smoke-Test QS fehlgeschlagen")
sys.exit(1)
