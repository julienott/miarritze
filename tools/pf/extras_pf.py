#!/usr/bin/env python3
"""Aides pixelforge communes : image en base64 (`b64`) et requête par la file asynchrone /v2 avec
relevé et relances (`infer`). Utilisé par tools/gordeka (`import extras_pf as ex`).
"""
import base64
import io
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gen_anims_pf as pf  # noqa: E402


def b64(im):
    b = io.BytesIO()
    im.save(b, "PNG")
    return base64.b64encode(b.getvalue()).decode()


def infer(payload, poll=5, max_s=6 * 3600, relances=2):
    """Comme _infer, mais une tâche tombée sur une panne passagère du moteur
    (ComfyUI injoignable, redémarrage) est redéposée (au plus `relances` fois)."""
    for k in range(relances + 1):
        try:
            return _infer(payload, poll, max_s)
        except RuntimeError as e:
            if k == relances or "injoignable" not in str(e) and "interrupted" not in str(e):
                raise
            print(f"panne passagère, nouvel essai : {e}", flush=True)
            import time as _t
            _t.sleep(30)


def _infer(payload, poll=5, max_s=6 * 3600):
    """Requête pixelforge par la file asynchrone (/v2 + relevé) : survit aux files
    longues et aux redémarrages du serveur (file persistante), contrairement à un
    appel /v1 qui perd sa connexion."""
    import json as _json
    import time as _time
    import urllib.request as _ur
    pf.wait_ready()
    tid = pf._post_json(pf.PF + "/v2/inferences", payload, timeout=300)["task_id"]
    t0 = _time.time()
    while _time.time() - t0 < max_s:
        try:
            r = _json.loads(_ur.urlopen(f"{pf.PF}/v2/inferences/tasks/{tid}", timeout=60).read().decode())
        except Exception:
            _time.sleep(20)                 # redémarrage du serveur (~20 s) : on réessaie
            continue
        if r.get("status") == "succeeded":
            res = r["result"]
            return [Image.open(io.BytesIO(base64.b64decode(x))).convert("RGBA") for x in res["base64_images"]]
        if r.get("status") in ("failed", "canceled", "cancelled", "expired"):
            raise RuntimeError(f"tâche {tid} : {r.get('status')} {str(r.get('error', ''))[:300]}")
        _time.sleep(poll)
    raise TimeoutError(f"tâche {tid} : pas finie après {max_s} s")
