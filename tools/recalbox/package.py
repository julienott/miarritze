#!/usr/bin/env python3
"""Empaquette les exports Recalbox pour le site (/recalbox/).

Produit dans <sortie> :
  MiarritzeBorroka-recalbox-arm64-<version>.zip   Raspberry Pi 4/5 (Recalbox 64 bits)
  MiarritzeBorroka-recalbox-x86_64-<version>.zip  PC
  MiarritzeBorroka-<version>.pck                  mise à jour légère (même moteur)
  manifest.json                                   lu par src/autoload/updater.gd

Chaque .zip se décompresse tel quel à la racine de la partition share :
  roms/ports/miarritze/        lanceur, exécutable, .pck, gamelist.xml, media/
  system/.emulationstation/systemlist.xml
  LISEZMOI.txt

Usage : package.py <dossier_export> <dossier_sortie> <build> <version> <version_godot> [url_de_base]
  dossier_export : contient arm64/MiarritzeBorroka.arm64 et x86_64/MiarritzeBorroka.x86_64,
                   chacun avec son MiarritzeBorroka.pck (presets « Recalbox » et « Recalbox x86_64 »).
"""
import filecmp
import os
import shutil
import subprocess
import sys
import zipfile

NAME = "MiarritzeBorroka"
ARCHS = ("arm64", "x86_64")
GAME_DIR = "roms/ports/miarritze/"
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))

README = """Miarritze Borroka pour Recalbox ({arch}) — version {version}

Installation : décompresser ce fichier à la racine du dossier « share »
de la Recalbox (par le réseau : \\\\RECALBOX\\share, ou la clé/le disque
SHARE sur un ordinateur), puis redémarrer la Recalbox. Le jeu est dans
« Ports ».

Si share/system/.emulationstation/systemlist.xml existait déjà, n'y
ajouter que le bloc <system> du fichier fourni.

Quitter le jeu : maintenir Select (ou Hotkey) + Start une seconde.
Mises à jour : automatiques au lancement quand la Recalbox est connectée.
Aide : https://miarritze.ijulien.com/recalbox/
"""


def add(zf: zipfile.ZipFile, arcname: str, path: str, executable: bool = False) -> None:
    info = zipfile.ZipInfo.from_file(path, arcname)
    # Droits Unix pour ceux qui décompressent sur un système de fichiers Linux.
    info.external_attr = (0o755 if executable else 0o644) << 16
    info.compress_type = zipfile.ZIP_DEFLATED
    with open(path, "rb") as f:
        zf.writestr(info, f.read(), compresslevel=9)


def main() -> None:
    if len(sys.argv) < 6:
        sys.exit(__doc__)
    export_dir, out, build, version, godot = sys.argv[1:6]
    base_url = sys.argv[6] if len(sys.argv) > 6 else ""
    os.makedirs(out, exist_ok=True)

    pck_src = os.path.join(export_dir, "arm64", NAME + ".pck")
    packages = []
    for arch in ARCHS:
        binary = os.path.join(export_dir, arch, f"{NAME}.{arch}")
        pck = os.path.join(export_dir, arch, NAME + ".pck")
        if not (os.path.isfile(binary) and os.path.isfile(pck)):
            sys.exit(f"export manquant : {binary} / {pck}")
        # Un seul .pck publié pour toutes les architectures : ils doivent être identiques.
        if not filecmp.cmp(pck, pck_src, shallow=False):
            sys.exit(f"{pck} diffère de {pck_src} : un .pck commun est impossible")
        zip_name = f"{NAME}-recalbox-{arch}-{version}.zip"
        with zipfile.ZipFile(os.path.join(out, zip_name), "w") as zf:
            add(zf, GAME_DIR + f"{NAME}.sh", os.path.join(HERE, f"{NAME}.sh"), executable=True)
            add(zf, GAME_DIR + f"{NAME}.{arch}", binary, executable=True)
            # Bibliothèques des extensions (WebRTC natif : jeu en ligne), posées par l'export.
            libs = sorted(f for f in os.listdir(os.path.join(export_dir, arch)) if f.endswith(".so"))
            if not any(f.startswith("libwebrtc_native") for f in libs):
                sys.exit(f"WebRTC natif absent de l'export {arch}")
            for lib in libs:
                add(zf, GAME_DIR + lib, os.path.join(export_dir, arch, lib))
            # Le même .pck pour toutes les architectures : celui qui est publié seul.
            add(zf, GAME_DIR + f"{NAME}.pck", pck_src)
            add(zf, GAME_DIR + "gamelist.xml", os.path.join(HERE, "gamelist.xml"))
            add(zf, GAME_DIR + "media/titre.png", os.path.join(HERE, "media", "titre.png"))
            add(zf, GAME_DIR + "media/icone.png", os.path.join(ROOT, "assets", "ui", "app_icon.png"))
            zf.writestr(GAME_DIR + "VERSION", version + "\n")
            add(zf, "system/.emulationstation/systemlist.xml", os.path.join(HERE, "systemlist.xml"))
            zf.writestr("LISEZMOI.txt", README.format(arch=arch, version=version))
        packages.append(f"{arch}={zip_name}")

    pck_name = f"{NAME}-{version}.pck"
    shutil.copyfile(pck_src, os.path.join(out, pck_name))

    subprocess.run([
        sys.executable, os.path.join(ROOT, "tools", "release", "manifest.py"), out,
        "--platform", "linux-arm64 + linux-x86_64 (Recalbox)",
        "--build", build, "--version", version, "--godot", godot, "--base-url", base_url,
        "--pck", pck_name,
        *[arg for p in packages for arg in ("--package", p)],
    ], check=True)


if __name__ == "__main__":
    main()
