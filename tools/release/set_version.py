#!/usr/bin/env python3
"""Injecte le numéro de build et la version dans project.godot (CI seulement).

Usage : set_version.py <build> <version> [project.godot]

Ajoute `config/build` et `config/version` sous `config/name` dans la section
[application]. Lancé dans la copie de travail de la CI : le project.godot
versionné reste sans numéro (« dev »). src/autoload/updater.gd compare
`application/config/build` au `build` du manifeste publié.
"""
import sys


def main() -> None:
    build, version = int(sys.argv[1]), sys.argv[2]
    path = sys.argv[3] if len(sys.argv) > 3 else "project.godot"
    with open(path) as f:
        text = f.read()
    line = 'config/name="Miarritze Borroka"\n'
    if line not in text:
        sys.exit("config/name introuvable dans " + path)
    if "\nconfig/build=" in text:
        sys.exit("config/build déjà présent dans " + path)
    text = text.replace(line, line + f'config/build={build}\nconfig/version="{version}"\n', 1)
    with open(path, "w") as f:
        f.write(text)


if __name__ == "__main__":
    main()
