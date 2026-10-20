#!/usr/bin/env python3
"""Tests des salons Gordeka (SPEC-GORDEKA §6.2, §11 ; docs/ONLINE_GORDEKA.md) sur
`php -S` local, base jetable (MIARRITZE_DB) et horloge simulée (MIARRITZE_CLOCK_FILE).
Usage : python3 tests/backend/rooms_test.py"""
import json, os, subprocess, sys, tempfile, time, urllib.error, urllib.request

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
PORT = 8098
BASE = f"http://127.0.0.1:{PORT}/api"
ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ"
fails = 0
checks = 0
clock_file = ""
offset = 0


def call(method, path, body=None, query=None):
    url = BASE + path
    if query:
        url += "?" + "&".join(f"{k}={v}" for k, v in query.items())
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method, headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            return r.status, json.loads(r.read() or b"null")
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or b"null")


def check(cond, msg):
    global fails, checks
    checks += 1
    print(("  ok " if cond else "  ✗  ") + msg)
    if not cond:
        fails += 1


def advance(seconds):
    """Avance l'horloge du serveur (salons seulement)."""
    global offset
    offset += seconds
    with open(clock_file, "w") as f:
        f.write(str(offset))


def player(pseudo):
    st, p = call("POST", "/gk/player", {"pseudo": pseudo})
    assert st == 200, (st, p)
    return {"player_id": p["player_id"], "secret": p["secret"]}


def post(path, who, **kw):
    return call("POST", path, {**who, **kw})


def members(view):
    return {m["player_id"]: m for m in view["members"]}


def main():
    global clock_file
    tmp = tempfile.mkdtemp()
    db = os.path.join(tmp, "rooms.sqlite")
    clock_file = os.path.join(tmp, "clock")
    advance(0)
    env = dict(os.environ, MIARRITZE_DB=db, MIARRITZE_CLOCK_FILE=clock_file)
    srv = subprocess.Popen(["php", "-S", f"127.0.0.1:{PORT}", os.path.join(ROOT, "backend", "public", "index.php")],
                           env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        time.sleep(0.8)
        run()
    finally:
        srv.terminate()
    print(f"{checks - fails}/{checks} vérifications OK")
    sys.exit(1 if fails else 0)


def run():
    # --- joueurs, filtre de pseudo
    st, bad = call("POST", "/gk/player", {"pseudo": "merdeux"})
    check(st == 400 and bad.get("reason") == "pseudo_refused", "pseudo grossier refusé")
    st, bad = call("POST", "/gk/player", {"pseudo": "x"})
    check(st == 400 and bad.get("reason") == "bad_pseudo", "pseudo trop court refusé")
    lea, max_, zoe, tom, eva = (player(n) for n in ["Lea", "Max", "Zoe", "Tom", "Eva"])
    st, r = call("POST", "/gk/player", {**tom, "pseudo": "Tomy"})
    check(st == 200 and r["pseudo"] == "Tomy" and r["player_id"] == tom["player_id"], "changement de pseudo")
    st, _ = post("/room/presence", {"player_id": lea["player_id"], "secret": "faux"}, room_id=1)
    check(st == 401, "secret invalide refusé")

    # --- création publique / privée, liste sans privés
    st, pub = post("/room/create", lea, public=True, places=4, map="port_pecheurs", settings={"ia": "normal"},
                   perso="maia", color=0)
    room = pub["room"]
    check(st == 200 and room["name"] == "Salon de Lea" and room["code"] is None and room["places"] == 4
          and room["state"] == "attente" and room["settings"] == {"ia": "normal"}, "création d'un salon public")
    check(members(pub)[lea["player_id"]]["is_admin"] and members(pub)[lea["player_id"]]["color"] == 0,
          "le créateur est admin avec sa couleur")
    rid = room["room_id"]
    st, priv = post("/room/create", eva, public=False, places=6)
    code = priv["room"]["code"]
    check(st == 200 and isinstance(code, str) and len(code) == 4 and all(c in ALPHABET for c in code),
          "salon privé : code de 4 lettres sans I/L/O ni chiffre")
    st, bad = post("/room/create", max_, public=True, places=9)
    check(st == 400 and bad["reason"] == "bad_places", "places hors 4–8 refusées")
    st, lst = call("GET", "/rooms")
    ids = [x["room_id"] for x in lst["rooms"]]
    check(st == 200 and rid in ids and priv["room"]["room_id"] not in ids, "liste : publics seulement")
    check("code" not in json.dumps(lst), "liste : aucun code")
    st, bad = post("/room/join", max_, room_id=priv["room"]["room_id"])
    check(st == 404, "salon privé non rejoignable par id")
    st, j = post("/room/join", max_, code=code.lower())
    check(st == 200 and j["room"]["room_id"] == priv["room"]["room_id"], "rejoindre par code (minuscules acceptées)")
    st, bad = post("/room/join", zoe, code="ABCI")
    check(st == 400, "code avec I refusé")
    post("/room/leave", max_, room_id=priv["room"]["room_id"])
    post("/room/leave", eva, room_id=priv["room"]["room_id"])
    st, bad = post("/room/join", zoe, code=code)
    check(st == 404, "salon privé vide fermé, code libéré")

    # --- couleurs uniques, la plus proche libre
    st, j = post("/room/join", max_, room_id=rid, color=0, perso="louis")
    check(st == 200 and members(j)[max_["player_id"]]["color"] == 1, "couleur prise → la suivante (1)")
    st, j = post("/room/join", zoe, room_id=rid, color=1)
    check(st == 200 and members(j)[zoe["player_id"]]["color"] == 2, "couleur 1 prise → 2 (0 aussi prise)")
    st, bad = post("/room/me", zoe, room_id=rid, color=0)
    check(st == 409 and bad["reason"] == "color_taken", "changer vers une couleur prise refusé")
    st, me = post("/room/me", zoe, room_id=rid, color=7, perso="xabi")
    z = members(me)[zoe["player_id"]]
    check(st == 200 and z["color"] == 7 and z["perso"] == "xabi", "changer perso et couleur")
    st, j = post("/room/join", tom, room_id=rid, color=7)
    check(members(j)[tom["player_id"]]["color"] in (6, 8) and members(j)[tom["player_id"]]["color"] == 8,
          "couleur 7 prise → 8 (à égalité, la suivante)")
    st, j = post("/room/join", tom, room_id=rid)
    check(st == 200 and len(j["members"]) == 4, "rejoindre deux fois : idempotent")

    # --- plein
    st, lst = call("GET", "/rooms")
    entry = [x for x in lst["rooms"] if x["room_id"] == rid][0]
    check(entry["full"] and entry["humans"] == 4 and len(entry["avatars"]) == 4
          and {"perso", "color"} <= set(entry["avatars"][0]), "liste : plein, avatars perso+couleur")
    st, bad = post("/room/join", eva, room_id=rid)
    check(st == 409 and bad["reason"] == "room_full", "salon plein refusé")

    # --- réglages, lancement, rounds
    st, bad = post("/room/settings", max_, room_id=rid, places=6)
    check(st == 403 and bad["reason"] == "not_admin", "réglages : admin seulement")
    st, s = post("/room/settings", lea, room_id=rid, places=6, settings={"ia": "malin", "rounds": 5})
    check(st == 200 and s["room"]["places"] == 6 and s["room"]["settings"]["rounds"] == 5
          and s["room"]["settings_version"] == 2, "réglages admin en attente")
    st, bad = post("/room/settings", lea, room_id=rid, places=4 - 1)
    check(st == 400, "places < 4 refusées")
    st, l = post("/room/launch", lea, room_id=rid, total=5)
    check(st == 200 and l["room"]["state"] == "en_partie" and l["room"]["phase"] == "round", "lancement")
    st, rd = post("/room/round", lea, room_id=rid, round=1, total=5, phase="round")
    check(st == 200 and rd["room"]["round"] == 1 and rd["room"]["total"] == 5, "l'hôte publie round 1/5")
    st, bad = post("/room/settings", lea, room_id=rid, settings={"ia": "facile"})
    check(st == 409 and bad["reason"] == "in_round", "réglages interdits pendant un round")
    st, bad = post("/room/me", max_, room_id=rid, color=11)
    check(st == 409 and bad["reason"] == "in_round", "changer de couleur interdit pendant un round")
    st, lst = call("GET", "/rooms")
    entry = [x for x in lst["rooms"] if x["room_id"] == rid][0]
    check(entry["state"] == "en_partie" and entry["round"] == 1 and entry["total"] == 5, "liste : en partie, round 1/5")

    # --- spectateur en cours de partie
    st, j = post("/room/join", eva, room_id=rid, color=0)
    e = members(j)[eva["player_id"]]
    check(st == 200 and e["status"] == "spectateur" and e["color"] == 2, "arrivée en partie → spectateur")
    st, rd = post("/room/round", lea, room_id=rid, round=1, phase="scores", game={"scores": {"1": 3}})
    check(st == 200 and rd["room"]["phase"] == "scores" and members(rd)[eva["player_id"]]["status"] == "spectateur"
          and rd["room"]["game"]["scores"]["1"] == 3, "scores : spectateur toujours, état de partie publié")
    st, s = post("/room/settings", lea, room_id=rid, settings={"ia": "facile"})
    check(st == 200, "réglages permis entre deux rounds (scores)")
    st, rd = post("/room/round", lea, room_id=rid, round=2, phase="round")
    check(members(rd)[eva["player_id"]]["status"] == "joueur", "round suivant : le spectateur devient joueur")

    # --- signalisation en étoile
    st, s1 = post("/room/signal", lea, room_id=rid, to=max_["player_id"], payload={"kind": "offer", "sdp": "x"})
    st2, s2 = post("/room/signal", lea, room_id=rid, to=zoe["player_id"], payload={"kind": "offer", "sdp": "y"})
    check(st == 200 and st2 == 200, "hôte → clients")
    st, got = call("GET", "/room/signal", query={**max_, "room_id": rid, "after": 0})
    check(st == 200 and len(got["messages"]) == 1 and got["messages"][0]["from"] == lea["player_id"]
          and got["messages"][0]["payload"]["sdp"] == "x", "le client reçoit seulement son offre")
    st, _ = post("/room/signal", max_, room_id=rid, to=lea["player_id"], payload={"kind": "answer", "sdp": "z"})
    st2, got = call("GET", "/room/signal", query={**lea, "room_id": rid, "after": 0})
    check(st == 200 and got["messages"][-1]["from"] == max_["player_id"], "client → hôte")
    st, bad = post("/room/signal", max_, room_id=rid, to=zoe["player_id"], payload={"kind": "ice"})
    check(st == 403 and bad["reason"] == "not_host", "client → client refusé")
    st, bad = post("/room/signal", lea, room_id=rid, to=max_["player_id"], payload={"kind": "chat"})
    check(st == 400, "type de message inconnu refusé")
    st, bad = post("/room/signal", lea, room_id=rid, to=max_["player_id"], payload={"kind": "ice", "c": "a" * 20000})
    check(st == 413, "message trop gros refusé")
    st, bad = post("/room/signal", lea, room_id=rid, to=99999, payload={"kind": "ice"})
    check(st == 404, "destinataire hors salon refusé")

    # --- fin de partie, exclusion
    st, e = post("/room/end", lea, room_id=rid)
    check(st == 200 and e["room"]["state"] == "attente", "fin de partie → retour au salon")
    st, k = post("/room/kick", lea, room_id=rid, target=tom["player_id"])
    check(st == 200 and tom["player_id"] not in members(k), "exclusion")
    st, bad = post("/room/presence", tom, room_id=rid)
    check(st == 403 and bad["reason"] == "banned", "l'exclu voit « l'admin a libéré ta place »")
    st, bad = post("/room/join", tom, room_id=rid)
    check(st == 403 and bad["reason"] == "banned", "l'exclu ne peut pas revenir")
    st, bad = post("/room/kick", max_, room_id=rid, target=zoe["player_id"])
    check(st == 403, "exclure : admin seulement")

    # --- passation d'admin (départ) au plus ancien humain
    st, _ = post("/room/leave", lea, room_id=rid)
    st, p = post("/room/presence", zoe, room_id=rid)
    r = p["room"]
    check(r["admin_id"] == max_["player_id"] and r["admin_seq"] == 1 and r["name"] == "Salon de Max",
          "l'admin part → le plus ancien (Max) devient admin, événement admin_seq")

    # --- coupure 60 s : l'admin non vu est retiré, passation
    advance(30)
    post("/room/presence", zoe, room_id=rid)
    post("/room/presence", eva, room_id=rid)
    advance(31)
    st, p = post("/room/presence", zoe, room_id=rid)
    ids = members(p)
    check(st == 200 and max_["player_id"] not in ids and p["room"]["admin_id"] == zoe["player_id"]
          and p["room"]["admin_seq"] == 2, "admin coupé > 60 s retiré → Zoé (plus ancienne) admin")
    st, bad = post("/room/presence", max_, room_id=rid)
    check(st == 404 and bad["reason"] == "not_member", "le coupé revenu trop tard n'est plus membre")
    st, j = post("/room/join", max_, room_id=rid)
    check(st == 200 and members(j)[max_["player_id"]]["joined_at"] > members(j)[eva["player_id"]]["joined_at"],
          "il peut rejoindre à nouveau (en dernier arrivé)")

    # --- lancement : ≥ 2 humains
    st, solo = post("/room/create", lea, public=True)
    srid = solo["room"]["room_id"]
    st, bad = post("/room/launch", lea, room_id=srid)
    check(st == 409 and bad["reason"] == "too_few", "lancer seul refusé")

    # --- fermeture sans humain
    st, _ = post("/room/leave", lea, room_id=srid)
    st, bad = post("/room/join", tom, room_id=srid)
    check(st == 404, "plus d'humain → salon fermé")
    st, lst = call("GET", "/rooms")
    check(srid not in [x["room_id"] for x in lst["rooms"]], "salon fermé hors de la liste")

    # --- purge : 10 min sans partie lancée (avec des membres présents)
    st, pr = post("/room/create", lea, public=False)
    pcode = pr["room"]["code"]
    prid = pr["room"]["room_id"]
    post("/room/join", tom, code=pcode)
    for _ in range(11):
        advance(50)
        post("/room/presence", lea, room_id=prid)
        post("/room/presence", tom, room_id=prid)
        post("/room/presence", zoe, room_id=rid)
        post("/room/presence", eva, room_id=rid)
        post("/room/presence", max_, room_id=rid)
    st, p = post("/room/presence", lea, room_id=prid)
    check(st == 200, "salon encore ouvert à 9 min 10")
    advance(55)
    st, bad = post("/room/presence", lea, room_id=prid)
    check(st == 410 and bad["reason"] == "closed", "salon sans partie depuis 10 min → fermé")
    st, bad = post("/room/join", eva, code=pcode)
    check(st == 404, "code du salon purgé libéré (introuvable)")
    st, lst = call("GET", "/rooms")
    check(rid not in [x["room_id"] for x in lst["rooms"]], "le salon public inactif est aussi fermé (dernière partie > 10 min)")

    # --- un joueur n'est que dans un salon à la fois
    st, a = post("/room/create", lea, public=True)
    st, b = post("/room/create", lea, public=True)
    st, bad = post("/room/presence", lea, room_id=a["room"]["room_id"])
    check(st == 410, "créer un 2e salon fait quitter le 1er (fermé sans humain)")

    # --- Borroka intact : groupes et /signal des matchs
    st, g = call("POST", "/group", {})
    check(st == 200 and len(g["code"]) == 6, "Borroka : création de groupe toujours OK")


if __name__ == "__main__":
    main()
