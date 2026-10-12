#!/usr/bin/env python3
"""Tests de l'API PHP (SPEC §9) sur un serveur `php -S` local et une base
jetable (MIARRITZE_DB). Usage : python3 tests/backend/api_test.py"""
import json, os, subprocess, sys, tempfile, time, urllib.error, urllib.request

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", ".."))
PORT = 8099
BASE = f"http://127.0.0.1:{PORT}/api"
fails = 0


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
    global fails
    if not cond:
        fails += 1
        print("  ✗", msg)


def main():
    db = os.path.join(tempfile.mkdtemp(), "test.sqlite")
    env = dict(os.environ, MIARRITZE_DB=db)
    srv = subprocess.Popen(["php", "-S", f"127.0.0.1:{PORT}", os.path.join(ROOT, "backend", "public", "index.php")],
                           env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        time.sleep(0.8)
        st, g = call("POST", "/group", {})
        check(st == 200 and len(g["code"]) == 6, "création de groupe")
        code = g["code"]
        st, bad = call("POST", "/group/join", {"code": code, "pseudo": "merdeux"})
        check(st == 400, "filtre anti-gros-mots au join")
        st, a = call("POST", "/group/join", {"code": code, "pseudo": "Louis"})
        st2, b = call("POST", "/group/join", {"code": code, "pseudo": "Maia"})
        check(st == 200 and st2 == 200 and a["secret"] and b["secret"], "deux joueurs rejoignent")
        st, dup = call("POST", "/group/join", {"code": code, "pseudo": "Louis"})
        check(st == 409, "pseudo déjà pris")
        A = {"player_id": a["player_id"], "secret": a["secret"]}
        B = {"player_id": b["player_id"], "secret": b["secret"]}
        st, _ = call("POST", "/presence", {"player_id": a["player_id"], "secret": "faux"})
        check(st == 401, "secret invalide refusé")
        st, p = call("POST", "/profile", {**A, "fighter": "maia", "costume": 3, "banner": 2, "title": "", "emote": 1,
                                          "stats": {"wins": 1}})
        check(st == 200 and p["fighter"] == "maia" and p["costume"] == 0, "costume non débloqué ramené à 0")
        st, _ = call("POST", "/profile", {**A, "fighter": "inconnu"})
        check(st == 400, "perso hors roster refusé")
        call("POST", "/presence", {**A, "status": "lobby"})
        st, pres = call("POST", "/presence", {**B, "status": "lobby"})
        check(st == 200 and len(pres["members"]) == 2, "présence : 2 membres en ligne")
        st, inv = call("POST", "/match/invite", {**A, "to": b["player_id"]})
        check(st == 200, "invitation")
        mid = inv["match_id"]
        st, pres = call("POST", "/presence", {**B, "status": "lobby"})
        check(len(pres["invites"]) == 1 and pres["invites"][0]["from"]["pseudo"] == "Louis", "invitation reçue")
        st, r = call("POST", "/match/respond", {**B, "match_id": mid, "accept": True})
        check(st == 200 and r["match"]["state"] == "accepted", "invitation acceptée")
        call("POST", "/match/stage", {**A, "match_id": mid, "stage": "grande_plage"})
        st, s2 = call("POST", "/match/stage", {**B, "match_id": mid, "stage": "port_pecheurs"})
        check(s2["match"]["state"] == "signaling" and s2["match"]["stage"] in ("grande_plage", "port_pecheurs"),
              "tirage de la map entre les deux propositions")
        check(s2["match"]["seed"] > 0, "graine partagée")
        st, _ = call("POST", "/signal", {**A, "match_id": mid, "payload": {"kind": "offer", "sdp": "v=0"}})
        call("POST", "/signal", {**A, "match_id": mid, "payload": {"kind": "ice", "c": ["x", 0, "cand"]}})
        st, msgs = call("GET", "/signal", query={"player_id": B["player_id"], "secret": B["secret"], "match_id": mid, "after": 0})
        check(st == 200 and [m["payload"]["kind"] for m in msgs["messages"]] == ["offer", "ice"], "signalisation A → B")
        st, _ = call("POST", "/signal", {**A, "match_id": mid, "payload": {"kind": "evil"}})
        check(st == 400, "message de signalisation invalide refusé")
        st, rep = call("POST", "/match/report", {**A, "match_id": mid, "winner": 0, "checksum": 1234, "rounds": [2, 1]})
        check(rep["state"] == "waiting", "premier rapport en attente")
        st, rep = call("POST", "/match/report", {**B, "match_id": mid, "winner": 0, "checksum": 1234, "rounds": [2, 1]})
        check(rep["rated"] and rep["rating"] < 1000, "rapports concordants : Elo mis à jour (perdant)")
        st, lb = call("GET", "/leaderboard", query={"code": code, "type": "rating"})
        check(lb[0]["pseudo"] == "Louis" and lb[0]["rating"] == 1016 and lb[0]["wins"] == 1, "classement : Louis 1016")
        # Revanche : nouveau match compté, même map, idempotent pour les deux joueurs.
        st, r1 = call("POST", "/match/rematch", {**A, "match_id": mid})
        st2, r2 = call("POST", "/match/rematch", {**B, "match_id": mid})
        check(r1["match"]["match_id"] == r2["match"]["match_id"] and r1["match"]["match_id"] != mid,
              "revanche : même nouveau match pour les deux")
        check(r1["match"]["seed"] == r2["match"]["seed"] and r1["match"]["stage"] == s2["match"]["stage"], "revanche : graine et map partagées")
        rid = r1["match"]["match_id"]
        call("POST", "/match/report", {**A, "match_id": rid, "winner": 1, "checksum": 9, "rounds": [0, 2]})
        st, rr = call("POST", "/match/report", {**B, "match_id": rid, "winner": 1, "checksum": 9, "rounds": [0, 2]})
        check(rr["rated"], "revanche comptée")
        st, again = call("POST", "/match/report", {**A, "match_id": rid, "winner": 1, "checksum": 9, "rounds": [0, 2]})
        st, lb2 = call("GET", "/leaderboard", query={"code": code, "type": "rating"})
        check(sum(r["wins"] + r["losses"] for r in lb2) == 4, "Elo jamais appliqué deux fois (%s)" % lb2)
        # Rapports discordants : pas d'Elo.
        st, inv2 = call("POST", "/match/invite", {**B, "to": a["player_id"]})
        mid2 = inv2["match_id"]
        call("POST", "/match/respond", {**A, "match_id": mid2, "accept": True})
        call("POST", "/match/report", {**A, "match_id": mid2, "winner": 0, "checksum": 1, "rounds": [2, 0]})
        st, rep = call("POST", "/match/report", {**B, "match_id": mid2, "winner": 1, "checksum": 2, "rounds": [0, 2]})
        check(not rep["rated"] and not rep["agree"], "rapports discordants : match nul technique, sans Elo")
        # Match rapide.
        st, q1 = call("POST", "/match/queue", A)
        check(q1["waiting"], "file d'attente : premier en attente")
        st, q2 = call("POST", "/match/queue", B)
        check(not q2["waiting"] and q2["match"]["state"] == "accepted", "match rapide apparié")
        st, _ = call("POST", "/tower/score", {**A, "fighter": "louis", "difficulty": "facile", "score": 99999999})
        check(st == 400, "score de pyramide implausible refusé")
        st, _ = call("POST", "/tower/score", {**A, "fighter": "louis", "difficulty": "facile", "score": 17548})
        st, lb = call("GET", "/leaderboard", query={"code": code, "type": "tower"})
        check(st == 200 and lb[0]["score"] == 17548, "classement pyramide")
        st, cfg = call("GET", "/net/config")
        check(st == 200 and cfg["ice_servers"][0]["urls"][0].startswith("stun:"), "config ICE")
        st, _ = call("POST", "/net/report", {"kind": "ice_failed", "browser": "Safari 18"})
        check(st == 200, "télémétrie d'échec réseau")
        codes = [call("POST", "/presence", {**A, "status": "lobby"})[0] for _ in range(25)]
        check(429 in codes, "limite de débit sur la présence (20/min)")
    finally:
        srv.terminate()
    print("api_test :", "OK" if fails == 0 else f"{fails} échecs")
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
