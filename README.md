# Miarritze

L'aventure d'un jeune Basque, Louis, à travers Biarritz. Jeu web arcade,
tactile-first, paysage. Voir `DESIGN.md` (le quoi/pourquoi) et `CLAUDE.md`
(architecture et conventions).

**État : Phase 0** — squelette du projet + pipeline d'export web. Aucune
mécanique de jeu encore.

## Prérequis

- **Godot 4.7 (stable)** — éditeur standard, *pas* la version .NET
  (le C# ne s'exporte pas vers le web).
- **Templates d'export web** : dans Godot, `Éditeur → Gérer les modèles
  d'exportation → Télécharger et installer` (version 4.7 correspondante).

## Export web

Depuis l'éditeur : `Projet → Exporter → Web → Exporter le projet` vers
`web/build/index.html`.

En ligne de commande (le binaire `godot` doit être dans le PATH) :

```sh
mkdir -p web/build
godot --headless --export-release "Web" web/build/index.html
```

## Test local

Le build web exige les en-têtes **COOP/COEP** (sinon écran noir).
Un simple `python -m http.server` ne suffit PAS. Deux options :

**Option 1 — serveur intégré de Godot** (le plus simple) :
dans l'éditeur, `Remote Debug → Run in Browser` sert le build avec les
bons en-têtes.

**Option 2 — petit serveur Python avec en-têtes** :

```sh
python3 - <<'EOF'
import http.server, functools

class Handler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {**http.server.SimpleHTTPRequestHandler.extensions_map,
                      ".wasm": "application/wasm"}
    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        super().end_headers()

http.server.ThreadingHTTPServer(
    ("0.0.0.0", 8000),
    functools.partial(Handler, directory="web/build")).serve_forever()
EOF
```

Puis ouvrir `http://localhost:8000` dans **Chromium ou Firefox**
(Safari a des soucis WebGL 2.0 connus).

## Test sur mobile

1. Téléphone et ordinateur sur le **même réseau Wi-Fi**.
2. Trouver l'IP locale du Mac : `ipconfig getifaddr en0`.
3. Sur le téléphone, ouvrir `http://<IP>:8000` dans Chrome.
4. Tenir le téléphone en **paysage** (en portrait, l'écran
   « Tourne ton appareil » s'affiche).

Note : COOP/COEP fonctionnent en HTTP simple sur `localhost`, mais certains
navigateurs exigent HTTPS pour un hôte réseau. Si écran noir sur mobile,
tester via un tunnel HTTPS ou déployer sur le serveur (le `web/.htaccess`
fourni pose les bons en-têtes).

## Déploiement (LAMP)

Copier le contenu de `web/build/` et `web/.htaccess` dans le vhost.
Vérifier que `mod_headers` est actif (`a2enmod headers`).
