#!/usr/bin/env python3
"""Client Retro Diffusion v2 avec plafond de dépense DUR (SPEC-BORROKA §11.2).

Règles :
- avant toute requête payante : dry run `check_cost` (gratuit) ;
- refus (BudgetExceeded) si cumul + coût > cap_usd de budget.json ;
  aucun flag de contournement : seul Julien modifie cap_usd à la main ;
- contrôle croisé avec GET /v2/inferences/credits : si le solde réel a
  baissé plus que ce que le registre indique, on s'arrête (BudgetMismatch) ;
- cache : une requête identique n'est jamais relancée ;
- registre versionné : tools/rd/ledger.jsonl (une ligne par requête facturée).

Usage CLI :
  python3 tools/rd/client.py --status
  python3 tools/rd/client.py --test        # 1 image rd_fast (≈ 0,03 $)
"""
from __future__ import annotations

import base64
import fcntl
import hashlib
import io
import json
import os
import sys
import time
import urllib.error
import urllib.request
import uuid
from contextlib import contextmanager

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
API = "https://api.retrodiffusion.ai/v2"
BUDGET_PATH = os.path.join(HERE, "budget.json")
LEDGER_PATH = os.path.join(HERE, "ledger.jsonl")
PLAN_PATH = os.path.join(HERE, "plan.json")
CACHE_DIR = os.path.join(HERE, "cache")
MANIFEST_PATH = os.path.join(CACHE_DIR, "manifest.jsonl")
OUT_DIR = os.path.join(HERE, "out")
PENDING_PATH = os.path.join(HERE, "out", "pending.jsonl")
LOCK_PATH = os.path.join(HERE, "out", ".lock")
KEY_PATH = os.path.join(ROOT, ".rd_api_key")

# Tolérance du contrôle croisé (arrondis côté API), en dollars.
MISMATCH_TOLERANCE = 0.02
# Seuil d'un « gros lot » (§0.3) : consigné, revu en autonome (§0.8).
BIG_BATCH_USD = 5.0


class BudgetExceeded(RuntimeError):
    pass


class BudgetMismatch(RuntimeError):
    pass


class RdError(RuntimeError):
    def __init__(self, status: int, code: str, message: str, retry_after: float = 0.0):
        super().__init__(f"{status} {code}: {message}")
        self.status = status
        self.code = code
        self.retry_after = retry_after


# ------------------------------------------------------------------ fichiers

def _ensure_dirs() -> None:
    os.makedirs(CACHE_DIR, exist_ok=True)
    os.makedirs(OUT_DIR, exist_ok=True)


@contextmanager
def _locked():
    """Verrou inter-processus : deux générations parallèles ne peuvent pas
    lire le même cumul et dépasser ensemble le plafond."""
    _ensure_dirs()
    with open(LOCK_PATH, "w") as handle:
        fcntl.flock(handle, fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(handle, fcntl.LOCK_UN)


def _read_json(path: str, default):
    if not os.path.exists(path):
        return default
    with open(path) as f:
        return json.load(f)


def _write_json(path: str, data) -> None:
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")
    os.replace(tmp, path)


def _append_jsonl(path: str, row: dict) -> None:
    with open(path, "a") as f:
        f.write(json.dumps(row, ensure_ascii=False) + "\n")


def _read_jsonl(path: str) -> list[dict]:
    if not os.path.exists(path):
        return []
    with open(path) as f:
        return [json.loads(line) for line in f if line.strip()]


def budget() -> dict:
    data = _read_json(BUDGET_PATH, None)
    if data is None:
        data = {"cap_usd": 50.0, "start_balance": None}
        _write_json(BUDGET_PATH, data)
    return data


def spent() -> float:
    return round(sum(float(r.get("balance_cost", 0.0)) for r in _read_jsonl(LEDGER_PATH)), 4)


def remaining() -> float:
    return round(float(budget()["cap_usd"]) - spent(), 4)


# ------------------------------------------------------------------ HTTP

def _key() -> str:
    if not os.path.exists(KEY_PATH):
        raise RdError(0, "no_key", ".rd_api_key absente")
    with open(KEY_PATH) as f:
        return f.read().strip()


def _http(method: str, path: str, body: dict | None = None,
          extra_headers: dict | None = None, timeout: float = 120.0) -> dict:
    headers = {"X-RD-Token": _key(), "Content-Type": "application/json"}
    headers.update(extra_headers or {})
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(API + path, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read() or b"{}")
    except urllib.error.HTTPError as err:
        raw = err.read()
        code, message = "http_error", raw[:300].decode("utf-8", "replace")
        try:
            env = json.loads(raw).get("error", {})
            code, message = env.get("code", code), env.get("message", message)
        except (ValueError, AttributeError):
            pass
        retry = float(err.headers.get("Retry-After", "0") or 0)
        raise RdError(err.code, code, message, retry) from None


def credits() -> float:
    """Solde réel du compte en dollars."""
    return float(_http("GET", "/inferences/credits").get("balance", 0.0))


# ------------------------------------------------------------------ contrôles

def _cross_check(current_balance: float) -> None:
    b = budget()
    if b.get("start_balance") is None:
        b["start_balance"] = current_balance
        b["start_balance_at"] = time.strftime("%Y-%m-%dT%H:%M:%S")
        _write_json(BUDGET_PATH, b)
        return
    real_drop = float(b["start_balance"]) - current_balance
    if real_drop > spent() + MISMATCH_TOLERANCE:
        raise BudgetMismatch(
            f"le solde réel a baissé de {real_drop:.3f} $ mais le registre "
            f"n'indique que {spent():.3f} $ : arrêt (dépense hors client ?)")


def check_cost(payload: dict) -> float:
    body = dict(payload)
    body["check_cost"] = True
    return float(_http("POST", "/inferences", body).get("balance_cost", 0.0))


def _cache_key(payload: dict) -> str:
    canon = json.dumps({k: v for k, v in payload.items() if k != "check_cost"},
                       sort_keys=True, ensure_ascii=False)
    return hashlib.sha1(canon.encode()).hexdigest()


def _cached(key: str) -> list[str] | None:
    paths = []
    i = 0
    while True:
        for ext in ("png", "gif"):
            p = os.path.join(CACHE_DIR, f"{key}_{i}.{ext}")
            if os.path.exists(p):
                paths.append(p)
                break
        else:
            break
        i += 1
    return paths or None


# ------------------------------------------------------------------ génération

def generate(payload: dict, label: str, dry_run: bool = False) -> list[str]:
    """Génère (ou relit du cache) et renvoie les chemins des images.

    `label` : nom lisible pour le registre (ex. "louis/pose_explore").
    `dry_run` : affiche seulement le coût, n'envoie rien.
    """
    _ensure_dirs()
    key = _cache_key(payload)
    hit = _cached(key)
    if hit:
        print(f"[rd] cache : {label} ({len(hit)} image(s))")
        return hit
    with _locked():
        cost = check_cost(payload)
        print(f"[rd] {label} : coût {cost:.3f} $ | dépensé {spent():.3f} $ "
              f"| restant {remaining():.3f} $")
        if dry_run:
            return []
        if spent() + cost > float(budget()["cap_usd"]) + 1e-9:
            raise BudgetExceeded(
                f"refus : {label} coûterait {cost:.3f} $, le cumul passerait à "
                f"{spent() + cost:.3f} $ > plafond {budget()['cap_usd']} $")
        _cross_check(credits())
        idem = str(uuid.uuid4())
        _append_jsonl(PENDING_PATH, {"idem": idem, "label": label, "key": key,
                                     "at": time.strftime("%Y-%m-%dT%H:%M:%S")})
        accepted = _submit(payload, idem)
        result = _poll(accepted["task_id"], payload)
        real_cost = float(result.get("balance_cost", cost))
        _append_jsonl(LEDGER_PATH, {
            "at": time.strftime("%Y-%m-%dT%H:%M:%S"),
            "label": label,
            "style": payload.get("prompt_style", ""),
            "size": f"{payload.get('width')}x{payload.get('height')}",
            "num_images": payload.get("num_images", 1),
            "balance_cost": real_cost,
            "cumul": round(spent() + real_cost, 4),
            "task_id": accepted["task_id"],
        })
    paths = []
    for i, b64 in enumerate(result.get("base64_images", [])):
        raw = base64.b64decode(b64)
        ext = "gif" if raw[:3] == b"GIF" else "png"
        p = os.path.join(CACHE_DIR, f"{key}_{i}.{ext}")
        with open(p, "wb") as f:
            f.write(raw)
        paths.append(p)
    light = {k: (f"<{len(v)} chars>" if isinstance(v, str) and len(v) > 200 else v)
             for k, v in payload.items()}
    light = {k: (f"<{len(v)} images>" if isinstance(v, list) and k == "reference_images" else v)
             for k, v in light.items()}
    _append_jsonl(MANIFEST_PATH, {"key": key, "label": label, "payload": light,
                                  "cost": real_cost, "task_id": accepted["task_id"],
                                  "at": time.strftime("%Y-%m-%dT%H:%M:%S"),
                                  "files": [os.path.basename(p) for p in paths]})
    return paths


def _submit(payload: dict, idem: str) -> dict:
    for attempt in range(5):
        try:
            return _http("POST", "/inferences", payload, {"Idempotency-Key": idem})
        except RdError as err:
            if err.status == 429 or err.status in (502, 503, 504):
                wait = err.retry_after or (5.0 * (attempt + 1))
                print(f"[rd] {err.code}, nouvel essai dans {wait:.0f} s")
                time.sleep(wait)
                continue
            raise
    raise RdError(0, "submit_failed", "admission impossible après 5 essais")


def _poll(task_id: str, payload: dict, retried: bool = False) -> dict:
    deadline = time.time() + 900
    while time.time() < deadline:
        task = _http("GET", f"/inferences/tasks/{task_id}")
        status = task.get("status")
        if status in ("pending", "running", "accepted", "queued"):
            time.sleep(2)
            continue
        if status == "succeeded":
            return task["result"]
        err = task.get("error") or {}
        code = err.get("code", "failed") if isinstance(err, dict) else str(err)
        # Une animation en échec est relancée UNE fois à l'identique (doc RD).
        # Les échecs sont remboursés : pas d'écriture au registre.
        if not retried and "animation" in str(payload.get("prompt_style", "")):
            print(f"[rd] tâche échouée ({code}), relance unique")
            time.sleep(60 if code == "provider_busy" else 3)
            again = _submit(payload, str(uuid.uuid4()))
            return _poll(again["task_id"], payload, retried=True)
        raise RdError(0, code, f"tâche {task_id} échouée : {err}")
    raise RdError(0, "poll_timeout", f"tâche {task_id} trop longue")


# ------------------------------------------------------------------ utilitaires

def b64_png(path_or_image, rgb: bool = True) -> str:
    """Encode une image (chemin ou PIL.Image) en base64 PNG brut (sans data:)."""
    from PIL import Image
    img = Image.open(path_or_image) if isinstance(path_or_image, str) else path_or_image
    if rgb and img.mode != "RGB":
        bg = Image.new("RGB", img.size, (255, 255, 255))
        if img.mode in ("RGBA", "LA", "P"):
            rgba = img.convert("RGBA")
            bg.paste(rgba, mask=rgba.split()[3])
        else:
            bg.paste(img.convert("RGB"))
        img = bg
    buf = io.BytesIO()
    img.save(buf, "PNG")
    return base64.b64encode(buf.getvalue()).decode()


def status() -> str:
    b = budget()
    rows = _read_jsonl(LEDGER_PATH)
    plan = _read_json(PLAN_PATH, {})
    planned = sum(float(v) for v in plan.values()) if isinstance(plan, dict) else 0.0
    lines = [
        f"Plafond      : {float(b['cap_usd']):.2f} $",
        f"Dépensé      : {spent():.3f} $ ({len(rows)} requête(s) facturée(s))",
        f"Restant      : {remaining():.3f} $",
        f"Planifié     : {planned:.2f} $ (tools/rd/plan.json)",
        f"Projection   : {spent() + planned:.2f} $ / {float(b['cap_usd']):.2f} $",
    ]
    if b.get("start_balance") is not None:
        lines.append(f"Solde initial: {float(b['start_balance']):.3f} $")
    by_label: dict[str, float] = {}
    for r in rows:
        head = r["label"].split("/")[0]
        by_label[head] = by_label.get(head, 0.0) + float(r["balance_cost"])
    for head, total in sorted(by_label.items()):
        lines.append(f"  - {head:<20} {total:.3f} $")
    return "\n".join(lines)


def _selftest() -> None:
    paths = generate({
        "prompt": "a red basque beret on sand, single object",
        "prompt_style": "rd_fast__default",
        "width": 64, "height": 64, "num_images": 1, "seed": 7,
    }, "phase0/test_client")
    print("\n".join(paths))


if __name__ == "__main__":
    if "--status" in sys.argv:
        print(status())
        if "--real" in sys.argv:
            print(f"Solde réel   : {credits():.3f} $")
    elif "--test" in sys.argv:
        _selftest()
    else:
        print(__doc__)
