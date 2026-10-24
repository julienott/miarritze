#!/usr/bin/env python3
"""Client pixelforge (service de génération d'images et d'animations, local et gratuit) :
adresse du service, jeton, appel JSON (/v1, /v2, /mcp), attente du service et dépôt d'image.
Utilisé par tools/blackout et tools/producer (`import gen_anims_pf as pf` : pf.PF, pf.AUTH,
pf._post_json). Service : PF_URL (défaut https://stellar.tailbeda4d.ts.net) ; jeton PF_TOKEN ou
.pf_token à la racine (gitignoré).
"""
import hashlib
import io
import json
import os
import time
import urllib.error
import urllib.request

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))

PF = os.environ.get("PF_URL", "https://stellar.tailbeda4d.ts.net")
# Jeton Bearer : PF_TOKEN, sinon le fichier .pf_token à la racine (gitignoré).
_tok_path = os.path.join(ROOT, ".pf_token")
PF_TOKEN = os.environ.get("PF_TOKEN") or (open(_tok_path).read().strip() if os.path.exists(_tok_path) else "")
AUTH = {"Authorization": f"Bearer {PF_TOKEN}"} if PF_TOKEN else {}


# Julien 24/10 : toute tâche part en file de nuit (01:00–08:00 Paris), jamais autrement ; Julien bascule lui-même
# la file depuis l'interface de pixelforge s'il veut autre chose.
PRIORITE_FILE = "night"


def _de_nuit(payload):
    if isinstance(payload, dict) and payload.get("prompt_style"):
        payload = {**payload, "priority": PRIORITE_FILE}
        if payload.get("then"):
            payload["then"] = [_de_nuit(t) if t.get("prompt_style") else {**t, "priority": PRIORITE_FILE}
                               for t in payload["then"]]
    return payload


def _post_json(url, payload, timeout=900):
    if "/inferences" in url:
        payload = _de_nuit(payload)
    req = urllib.request.Request(url, json.dumps(payload).encode(), {
        "Content-Type": "application/json", "Accept": "application/json, text/event-stream", **AUTH})
    try:
        raw = urllib.request.urlopen(req, timeout=timeout).read().decode()
    except urllib.error.HTTPError as e:     # message du serveur dans l'erreur (sinon « 500 » muet)
        raise RuntimeError(f"HTTP {e.code} : {e.read().decode(errors='replace')[:600]}") from None
    lines = [ln[6:] if ln.startswith("data: ") else ln for ln in raw.splitlines()]
    return json.loads([ln for ln in lines if ln.startswith("{")][-1])


def wait_ready(max_s=3600):
    """Attend que le service réponde (redémarrage, déploiement) au plus max_s secondes."""
    t = time.time()
    while True:
        try:
            st = json.loads(urllib.request.urlopen(PF + "/v2/status", timeout=15).read())
            if st.get("status") == "ok":
                return
        except Exception:
            pass
        if time.time() - t > max_s:
            raise RuntimeError("pixelforge injoignable")
        time.sleep(30)


def upload(img, cache):
    """Dépose l'image (fond blanc, Wan préfère un fond uni) ; URL mise en cache par empreinte."""
    bg = Image.new("RGBA", img.size, (255, 255, 255, 255))
    bg.alpha_composite(img.convert("RGBA"))
    buf = io.BytesIO()
    bg.convert("RGB").save(buf, "PNG")
    data = buf.getvalue()
    key = hashlib.sha1(data).hexdigest()
    if key in cache:
        return cache[key]
    bnd = "----pf" + key[:16]
    body = (f"--{bnd}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"{key}.png\"\r\n"
            "Content-Type: image/png\r\n\r\n").encode() + data + f"\r\n--{bnd}--\r\n".encode()
    req = urllib.request.Request(PF + "/api/upload", body, {"Content-Type": f"multipart/form-data; boundary={bnd}", **AUTH})
    cache[key] = json.loads(urllib.request.urlopen(req, timeout=120).read())["url"]
    return cache[key]
