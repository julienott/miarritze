#!/usr/bin/env python3
"""Écrit le manifest.json d'une version native (Steam Deck, Recalbox).

C'est ce fichier que lit src/autoload/updater.gd au lancement du jeu :
`build` (entier croissant, comparé au build qui tourne), `godot` (si le
moteur change, on télécharge le paquet complet au lieu du seul .pck), et
pour chaque fichier téléchargeable `url`, `sha256` et `size`.

Usage :
  manifest.py <dossier> --platform "linux-x86_64 (Steam Deck)" --build 57 \
      --version 57-a1b2c3d --godot 4.7.2 [--base-url https://…/steamdeck] \
      --pck MiarritzeBorroka-57-a1b2c3d.pck \
      --package MiarritzeBorroka-57-a1b2c3d.tar.gz          # un seul paquet
      --package arm64=…-arm64.zip --package x86_64=…-x86_64.zip   # un par architecture

Un seul paquet sans architecture -> champ `package` ; sinon `packages`
indexé par l'architecture Godot (Engine.get_architecture_name()).
"""
import argparse
import datetime
import hashlib
import json
import os


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("out")
    parser.add_argument("--platform", required=True)
    parser.add_argument("--build", type=int, required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--godot", required=True)
    parser.add_argument("--base-url", default="")
    parser.add_argument("--pck", required=True)
    parser.add_argument("--package", action="append", required=True)
    args = parser.parse_args()

    base = args.base_url.rstrip("/")
    # « 4.7 » -> « 4.7.0 » : le jeu compare major.minor.patch.
    godot = args.godot if args.godot.count(".") >= 2 else args.godot + ".0"

    def entry(name: str) -> dict:
        path = os.path.join(args.out, name)
        sha = hashlib.sha256()
        with open(path, "rb") as f:
            for chunk in iter(lambda: f.read(1 << 20), b""):
                sha.update(chunk)
        return {
            "url": f"{base}/{name}" if base else name,
            "sha256": sha.hexdigest(),
            "size": os.path.getsize(path),
        }

    manifest = {
        "name": "Miarritze Borroka",
        "platform": args.platform,
        "build": args.build,
        "version": args.version,
        "godot": godot,
        "date": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    }
    if len(args.package) == 1 and "=" not in args.package[0]:
        manifest["package"] = entry(args.package[0])
    else:
        manifest["packages"] = {}
        for item in args.package:
            arch, _, name = item.partition("=")
            if not name:
                parser.error(f"--package {item} : attendu <architecture>=<fichier>")
            manifest["packages"][arch] = entry(name)
    manifest["pck"] = entry(args.pck)

    with open(os.path.join(args.out, "manifest.json"), "w") as f:
        json.dump(manifest, f, indent=2)
    print(json.dumps(manifest, indent=2))


if __name__ == "__main__":
    main()
