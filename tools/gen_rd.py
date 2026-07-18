#!/usr/bin/env python3
"""Génération de décors via l'API Retro Diffusion (modèle pixel art dédié).

Usage : python3 gen_rd.py <nom> "<prompt>" [--size WxH] [--style STYLE]
Écrit <scratchpad>/rd/<nom>_<i>.png pour revue avant intégration.
La clé vit dans .rd_api_key (gitignoré).
"""
import base64, json, os, sys, urllib.request

ROOT = os.path.join(os.path.dirname(__file__), "..")
SCRATCH = "/private/tmp/claude-501/-Users-julien-Dev-miarritze/67304e46-0e41-4582-88cc-ff9cd5e3783a/scratchpad/rd"

# Ancrage stylistique commun : palette chaude, ambiance côte basque.
BASE_STYLE = ("pixel art, side view video game background, sunny basque coast, "
              "warm limited palette, teal ocean, cream and red basque houses, "
              "clean silhouettes, no text, no characters, no UI")


def generate(name: str, prompt: str, width: int = 320, height: int = 180,
             num: int = 1, style: str = "default") -> list:
    with open(os.path.join(ROOT, ".rd_api_key")) as f:
        key = f.read().strip()
    body = {
        "prompt": "%s, %s" % (prompt, BASE_STYLE),
        "width": width,
        "height": height,
        "num_images": num,
        "prompt_style": style,
    }
    req = urllib.request.Request(
        "https://api.retrodiffusion.ai/v1/inferences",
        data=json.dumps(body).encode(),
        headers={"X-RD-Token": key, "Content-Type": "application/json"},
        method="POST")
    with urllib.request.urlopen(req, timeout=180) as resp:
        data = json.loads(resp.read())
    os.makedirs(SCRATCH, exist_ok=True)
    paths = []
    for i, b64 in enumerate(data.get("base64_images", [])):
        path = os.path.join(SCRATCH, "%s_%d.png" % (name, i))
        with open(path, "wb") as f:
            f.write(base64.b64decode(b64))
        paths.append(path)
    print("coût:", data.get("credit_cost"), "| reste:", data.get("remaining_credits", "?"))
    return paths


if __name__ == "__main__":
    args = sys.argv[1:]
    name, prompt = args[0], args[1]
    width, height = 320, 180
    style = "default"
    num = 1
    for a in args[2:]:
        if a.startswith("--size"):
            width, height = map(int, a.split("=")[1].split("x"))
        elif a.startswith("--style"):
            style = a.split("=")[1]
        elif a.startswith("--num"):
            num = int(a.split("=")[1])
    for p in generate(name, prompt, width, height, num, style):
        print(p)
