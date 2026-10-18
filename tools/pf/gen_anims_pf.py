#!/usr/bin/env python3
"""Génère les animations d'un combattant avec pixelforge (Wan 2.2, local,
gratuit) depuis sa fiche tools/specs/fighters/<id>.yaml, avec relances
automatiques : chaque essai passe les contrôles de gen_anims.raw_checks
(immobile, halo, coup invisible) et deux contrôles propres à Wan (le perso
change en cours d'animation, image qui saute) ; raté, il est relancé avec
une autre graine. Si tous les essais ratent, on garde le moins mauvais.

Usage : gen_anims_pf.py <id> [anim …] [--essais N] [--qualite high] [--refaire] [--dry]
  (sans anim : toutes ; une anim déjà réussie n'est pas refaite sans --refaire)
Poses clés : un mouvement de la fiche peut donner « poses » (une consigne
anglaise par pose, générées par Kontext, bien plus fidèle que Wan) et
« sequence » (indices des poses, « g » = garde) au lieu d'une animation Wan.
Départ : tools/rd/out/<id>/neutral_160.png (perso de 160×160 tourné à droite).
Sorties : tools/rd/out/<id>/pf/<anim>_s<graine>.png (planche en ligne, cases
de 160) ; tools/rd/out/<id>/anims.json pour build_rd_anims.py ; journal
tools/rd/out/<id>/gen_log.jsonl ; planche de recette tests/out/pf/<id>.png.
Service : PF_URL (défaut https://stellar.tailbeda4d.ts.net) ; jeton PF_TOKEN ou .pf_token.
"""
import base64
import glob
import hashlib
import io
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request

import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "rd"))
sys.path.insert(0, os.path.join(ROOT, "tools", "specs"))
import gen_anims as ga  # noqa: E402
import spec as fiche  # noqa: E402

PF = os.environ.get("PF_URL", "https://stellar.tailbeda4d.ts.net")
# Jeton Bearer : PF_TOKEN, sinon le fichier .pf_token à la racine (gitignoré).
_tok_path = os.path.join(ROOT, ".pf_token")
PF_TOKEN = os.environ.get("PF_TOKEN") or (open(_tok_path).read().strip() if os.path.exists(_tok_path) else "")
AUTH = {"Authorization": f"Bearer {PF_TOKEN}"} if PF_TOKEN else {}
CELL = 160
# Action pixelforge : « custom » partout. « attack » invente des armes
# (pistolet, canon, lance-flammes) et « walking » reste immobile (essais du
# 2026-10-16). Une fiche peut forcer « pf_action » pour un mouvement.
ACTIONS = {}
SIDE = ("the same cartoon character, side view facing right, camera fixed, keep the same character, "
        "same colors, same face, no weapon, no gun, no object, no effects")
IDENT_MAX = 40      # écart de couleur moyenne toléré avec l'image de départ
JUMP_MAX = 0.65     # part de la silhouette qui change d'une image à la suivante
FOREIGN_MAX = 220  # pixels gris/blancs/bleus apparus (objet inventé ; seuil calé sur 14 essais)
EXTRA = 2          # images demandées en plus (la fin de Wan reste souvent figée)


def _post_json(url, payload, timeout=900):
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


def animate(url, action, prompt, n, seed, quality="high"):
    r = _post_json(PF + "/mcp", {"jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": {
        "name": "animate_sprite", "arguments": {"action": action, "prompt": prompt, "image_url": url,
                                                "width": CELL, "height": CELL, "frames": n, "seed": seed,
                                                "quality": quality,
                                                "wait": True}}})
    txt = json.dumps(r)
    urls = sorted(set(re.findall(r"https://[^\\\s\"')\]]+_frame\d+\.png", txt)))
    if not urls:
        raise RuntimeError("pixelforge : " + txt[:300])
    return [Image.open(io.BytesIO(urllib.request.urlopen(urllib.request.Request(u, headers=AUTH), timeout=120).read())).convert("RGBA") for u in urls]


def keyframes(img, poses, seed, quality="high"):
    """Poses clés par Kontext (style pf_anim__keyframes) : une case de 160 par pose."""
    buf = io.BytesIO()
    img.save(buf, "PNG")
    r = _post_json(PF + "/v1/inferences", {
        "prompt_style": "pf_anim__keyframes", "input_image": base64.b64encode(buf.getvalue()).decode(),
        "poses": poses, "facing": "right", "seed": seed, "quality": quality})
    sheet = Image.open(io.BytesIO(base64.b64decode(r["base64_images"][0]))).convert("RGBA")
    cols = min(len(poses), 8)
    return [sheet.crop(((k % cols) * CELL, (k // cols) * CELL, (k % cols + 1) * CELL, (k // cols + 1) * CELL))
            for k in range(len(poses))]


def sequence(guard, poses, n, order=None):
    """Enchaîne garde et poses clés sur n images. order : indices des poses,
    « g » pour la garde (par défaut : garde, poses, la dernière tenue, garde)."""
    if order:
        return [guard if k == "g" else poses[int(k)] for k in order][:n]
    seq = [guard] + poses
    while len(seq) < n - 1:
        seq.insert(len(poses), poses[-1] if len(poses) < 3 else poses[len(poses) // 2])
    return (seq + [guard])[:n]


def trim_frozen(frames, n):
    """Retire la fin figée (images identiques) puis garde n images réparties."""
    def diff(a, b):
        ma, mb = np.array(a)[..., 3] > 127, np.array(b)[..., 3] > 127
        return (ma != mb).sum() / max(ma.sum(), 1)
    k = len(frames)
    while k > n and diff(frames[k - 1], frames[k - 2]) < 0.02:
        k -= 1
    frames = frames[:k]
    if len(frames) > n:
        frames = [frames[round(i * (len(frames) - 1) / (n - 1))] for i in range(n)]
    return frames


def wan_checks(frames, keys=False):
    arr = [np.array(f) for f in frames]
    def mean_col(a):
        op = a[..., 3] > 127
        return a[op][:, :3].mean(0) if op.any() else np.zeros(3)
    c0 = mean_col(arr[0])
    ident = max(np.abs(mean_col(a) - c0).sum() for a in arr)
    m = [a[..., 3] > 127 for a in arr]
    jump = max((m[i] != m[i + 1]).sum() for i in range(len(m) - 1)) / max(m[0].sum(), 1)
    def odd(a):
        # gris, blancs et bleus : objets que Wan invente (pistolet, bâton, lame)
        px = a[a[..., 3] > 127][:, :3].astype(float) / 255
        mx, mn = px.max(1), px.min(1)
        sat = (mx - mn) / np.maximum(mx, 1e-6)
        return int((((px[:, 2] > px[:, 0] + 0.05) & (sat > 0.15)) | ((sat < 0.18) & (mx > 0.3))).sum())
    foreign = max(odd(a) for a in arr[1:]) - odd(arr[0])
    errs = []
    if foreign > FOREIGN_MAX:
        errs.append(f"objet étranger ({foreign} px gris/blancs/bleus)")
    if ident > IDENT_MAX:
        errs.append(f"change de perso (couleur {ident:.0f})")
    if jump > JUMP_MAX and not keys:   # des poses clés sautent par nature
        errs.append(f"image qui saute ({jump:.0%})")
    return errs


def start_image(od, start, done):
    if start == "neutral":
        return Image.open(os.path.join(od, "neutral_160.png")).convert("RGBA")
    return Image.open(ga.start_image(os.path.basename(od), start, done)).convert("RGBA")


def contact_sheet(fid, done, verdicts):
    font = ImageFont.truetype(os.path.join(ROOT, "assets", "fonts", "press_start_2p.ttf"), 10)
    rows = []
    for name, path in done.items():
        if "/pf/" not in path:
            continue
        fr = ga.frames_of(path)
        row = Image.new("RGBA", (12 * 124 + 4, 144), (24, 16, 28, 255))
        v = verdicts.get(name, "")
        ImageDraw.Draw(row).text((4, 4), f"{name}  {v}"[:120], font=font,
                                 fill=(120, 230, 120) if v in ("", "OK") else (244, 198, 62))
        for i, f in enumerate(fr[:12]):
            bg = Image.new("RGBA", f.size, (214, 236, 246, 255))
            bg.alpha_composite(f)
            row.paste(bg.resize((120, 120), Image.NEAREST), (4 + i * 124, 20))
        rows.append(row)
    if not rows:
        return None
    W = Image.new("RGBA", (rows[0].width, len(rows) * 148), (60, 50, 70, 255))
    for i, r in enumerate(rows):
        W.paste(r, (0, i * 148))
    out = os.path.join(ROOT, "tests", "out", "pf")
    os.makedirs(out, exist_ok=True)
    p = os.path.join(out, f"{fid}.png")
    W.save(p)
    return p


def main():
    fid = sys.argv[1]
    s = fiche.load(fid)
    mv = fiche.moves(fid)
    names = [a for a in sys.argv[2:] if not a.startswith("--") and not a.isdigit()] or list(mv)
    opt = lambda k, d: type(d)(sys.argv[sys.argv.index(k) + 1]) if k in sys.argv else d
    retries = opt("--essais", 4)
    quality = opt("--qualite", "high")    # standard | high | max (pixelforge)
    od = ga.out_dir(fid)
    pd = os.path.join(od, "pf")
    os.makedirs(pd, exist_ok=True)
    reg_path, log_path = os.path.join(od, "anims.json"), os.path.join(od, "gen_log.jsonl")
    up_path = os.path.join(pd, "uploads.json")
    done = json.load(open(reg_path)) if os.path.exists(reg_path) else {}
    ups = json.load(open(up_path)) if os.path.exists(up_path) else {}
    ok_path = os.path.join(pd, "verdicts.json")
    verdicts = json.load(open(ok_path)) if os.path.exists(ok_path) else {}
    meta_path = os.path.join(ROOT, "assets", "fighters", fid, "anims.json")
    game = json.load(open(meta_path))["anims"] if os.path.exists(meta_path) else {}
    # ordre : d'abord les mouvements dont d'autres partent
    names.sort(key=lambda a: 0 if any(st != "neutral" and st[0] == a for *_, st in mv.values()) else 1)
    for name in names:
        _, n, gesture, start = mv[name]
        if name in done and "/pf/" in done[name] and verdicts.get(name) == "OK" and "--refaire" not in sys.argv:
            print(f"{name}: déjà réussi, gardé")
            continue
        if start != "neutral" and start[0] not in done:
            print(f"{name}: départ {start[0]} pas encore généré, ignoré")
            continue
        m = s["mouvements"][name]
        poses = m.get("poses")        # poses clés (Kontext) à la place de Wan
        action = "keyframes" if poses else (m.get("pf_action") or ACTIONS.get(m["mode"], "custom"))
        prompt = f"{gesture}, {SIDE}"
        if "--dry" in sys.argv:
            print(f"{name}: {action} {n} images, départ {start}")
            continue
        wait_ready()
        url = upload(start_image(od, start, done), ups)
        json.dump(ups, open(up_path, "w"), indent=1)
        g = game.get(name, {})
        hit_dir = g.get("hit_dir") if "hit_frame" in g else None
        best = None
        attempt, failures = 0, 0
        while attempt <= retries:
            seed = int(hashlib.sha1(f"{fid}:{name}".encode()).hexdigest()[:6], 16) + attempt
            t = time.time()
            try:
                if poses:
                    guard = start_image(od, start, done)
                    frames = sequence(guard, keyframes(guard, poses, seed, quality), n, m.get("sequence"))
                else:
                    frames = trim_frozen(animate(url, action, prompt, n + EXTRA, seed, quality), n)
            except Exception as e:  # service coupé : on attend, l'essai ne compte pas
                failures += 1
                print(f"{name} essai {attempt}: erreur {e}", flush=True)
                if failures > 5:
                    break
                wait_ready()
                url = upload(start_image(od, start, done), {})
                continue
            path = os.path.join(pd, f"{name}_s{seed}.png")
            sheet = Image.new("RGBA", (CELL * len(frames), CELL), (0, 0, 0, 0))
            for i, f in enumerate(frames):
                sheet.paste(f, (i * CELL, 0))
            sheet.save(path)
            errs = ga.raw_checks(path, hit_dir) + wan_checks(frames, bool(poses))
            with open(log_path, "a") as fh:
                fh.write(json.dumps({"anim": name, "outil": "pixelforge", "action": action, "essai": attempt,
                                     "graine": seed, "fichier": path, "defauts": errs,
                                     "secondes": round(time.time() - t, 1)}, ensure_ascii=False) + "\n")
            print(f"{name} essai {attempt} (graine {seed}, {time.time() - t:.0f} s): "
                  f"{'OK' if not errs else ' ; '.join(errs)}", flush=True)
            if best is None or len(errs) < len(best[1]):
                best = (path, errs)
            if not errs:
                break
            attempt += 1
        if best:
            done[name] = best[0]
            verdicts[name] = "OK" if not best[1] else "À REVOIR : " + " ; ".join(best[1])
            json.dump(done, open(reg_path, "w"), indent=1)
            json.dump(verdicts, open(ok_path, "w"), indent=1, ensure_ascii=False)
    p = contact_sheet(fid, done, verdicts)
    bad = [k for k, v in verdicts.items() if v != "OK"]
    print(f"planche : {p}" if p else "")
    print(f"réussis : {len(verdicts) - len(bad)}/{len(verdicts)}" + (f" ; à revoir : {', '.join(bad)}" if bad else ""))


if __name__ == "__main__":
    main()
