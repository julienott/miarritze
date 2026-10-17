"""Karramarro découpé en pièces (modèle « M », 160×160, face à droite) et ses
mouvements en poses clés pour tools/pf/pieces.py.

Pièces : pb pince arrière (+ bras), lb pattes arrière, lf pattes avant,
body corps (yeux, bouche), pf pince avant. Rotation en degrés, sens horaire
à l'écran : la pince avant pointe vers le haut, +80° la couche vers l'avant.
"""
import math

GROUND = 155
PIVOTS = {"pb": (54, 107), "pf": (102, 117), "lb": (66, 114), "lf": (90, 114), "body": (77, 104)}
ORDER = ["pb", "lb", "lf", "body", "pf"]
FRONT = ["lb", "lf", "body", "pb", "pf"]       # pince arrière passée devant le corps
GROUND_PARTS = ("lb", "lf")
# bras dessinés quand une pince s'écarte : épaule sur le corps, largeur, couleur des pattes
ARMS = {"pb": ((62, 104), 5, (158, 42, 31)), "pf": ((94, 112), 5, (158, 42, 31))}
KEEP = ("same orange cartoon crab, same eight thin legs, same two big pincers, eyes on stalks, "
        "side view facing right, not humanoid, not standing upright, no weapon, no object")


def masks(a, xx, yy):
    body = ((xx - 77) / 25.5) ** 2 + ((yy - 104) / 26) ** 2 <= 1
    pb = a & (xx < 60) & (yy < 113) & ~body
    pf = a & (xx >= 102) & (yy <= 126) & ~body
    rest = a & ~pb & ~pf
    legs = rest & ~body & (yy >= 112)
    return {"pb": pb, "lb": legs & (xx < 78), "lf": legs & (xx >= 78), "body": rest & ~legs, "pf": pf}


def P(**kw):
    """Pose : P(pf=dict(rot=80), all=dict(dx=2), air=10, …)."""
    return kw


def merge(*poses):
    out = {}
    for p in poses:
        for k, v in p.items():
            out[k] = {**out.get(k, {}), **v} if isinstance(v, dict) and isinstance(out.get(k), dict) else v
    return out


G = P()
# accroupi : pattes écrasées et écartées, pinces devant le visage
LOW_LEGS = P(lb=dict(sy=0.6, sx=1.2), lf=dict(sy=0.6, sx=1.2))
C = merge(LOW_LEGS, P(pf=dict(rot=10, dy=8), pb=dict(rot=-8, dy=8)))
TUCK = P(lb=dict(sy=0.7, rot=20), lf=dict(sy=0.7, rot=-20))
SHIELD = P(order=FRONT, pf=dict(rot=-14, dx=-6, dy=12), pb=dict(rot=40, dx=24, dy=20))
DOUBLE = P(order=FRONT, pf=dict(rot=80, dx=16, dy=6), pb=dict(rot=72, dx=46, dy=12), all=dict(dx=3))


def walk(n, amp=16, lift=5, low=0.0, cycles=1, lean=0):
    keys = {}
    for i in range(n):
        ph = i / n * 2 * math.pi * cycles
        s, c = math.sin(ph), math.cos(ph)
        bob = -abs(s) * 3
        keys[i] = P(lb=dict(rot=amp * s, dx=3 * s, dy=-max(0, c) * lift, sy=1 - low),
                    lf=dict(rot=-amp * s, dx=-3 * s, dy=-max(0, -c) * lift, sy=1 - low),
                    body=dict(dy=bob), pb=dict(dy=bob, rot=4 * s + lean), pf=dict(dy=bob, rot=-4 * s + lean))
    return keys


def spin(n, turns=1.0, peak=45):
    keys = {}
    for i in range(n):
        u = i / (n - 1)
        keys[i] = P(tilt=-360 * turns * u, tilt_pivot=(77, 110), air=peak * math.sin(math.pi * u),
                    lb=dict(rot=15 * math.sin(i * 2.1)), lf=dict(rot=-15 * math.sin(i * 2.1)),
                    pf=dict(rot=-20), pb=dict(rot=-15))
    return keys


def knockdown():
    seq = [(0, P()), (-20, P(pf=dict(rot=-25), pb=dict(rot=-20))), (-60, P(pf=dict(rot=-35), pb=dict(rot=-30))),
           (-120, P(pf=dict(rot=-30), pb=dict(rot=-25))), (-180, P(lb=dict(rot=12), lf=dict(rot=-12))),
           (-180, P(lb=dict(rot=-12), lf=dict(rot=12), pf=dict(rot=15), pb=dict(rot=-15)))]
    return {i: merge(p, P(tilt=t, tilt_pivot=(60, 120), all=dict(dx=-3 * min(i, 3)))) for i, (t, p) in enumerate(seq)}


MOVES = {
    "idle": dict(mode="guide", prompt="the cartoon crab stands in guard with both pincers raised, bobbing gently",
                 keys={0: G, 2: merge(P(lb=dict(sy=0.92), lf=dict(sy=0.92)), P(pf=dict(rot=6, dy=2), pb=dict(rot=-5, dy=2))),
                       4: G, 6: P(lb=dict(sy=1.04), lf=dict(sy=1.04), pf=dict(rot=-5, dy=-2), pb=dict(rot=4, dy=-2)), 7: G}),
    "walk": dict(mode="guide", lora="walk", keys=walk(8),
                 prompt="the cartoon crab scuttles sideways, its thin legs stepping in alternation, body bobbing"),
    "run": dict(mode="guide", lora="walk", keys=walk(8, amp=24, lift=7, low=0.15, cycles=2, lean=18),
                prompt="the cartoon crab scuttles sideways very fast, body low, legs a blur of quick steps, pincers forward"),
    "crouch": dict(mode="guide", keys={0: G, 3: C, 5: C},
                   prompt="the cartoon crab lowers its body flat to the ground by folding its legs, pincers in front of its face"),
    "jump": dict(mode="guide", keys={0: G, 1: C, 2: merge(TUCK, P(air=30, pf=dict(rot=-10), pb=dict(rot=8))),
                                     4: merge(TUCK, P(air=46, pf=dict(rot=-14), pb=dict(rot=10))),
                                     6: merge(P(air=12), P(lb=dict(sy=0.9), lf=dict(sy=0.9))), 7: C},
                 prompt="the cartoon crab crouches, jumps straight up with its legs tucked, then lands on its legs"),
    "jump_fwd": dict(mode="guide", keys={0: G, 1: merge(C, P(tilt=8)), 2: merge(TUCK, P(air=34, tilt=14, pf=dict(rot=30), pb=dict(rot=25))),
                                         4: merge(TUCK, P(air=30, tilt=10, pf=dict(rot=35), pb=dict(rot=30))), 5: P(air=6)},
                     prompt="the cartoon crab leaps forward through the air with its legs tucked under its body, pincers forward"),
    "block": dict(mode="guide", keys={0: G, 1: SHIELD, 3: SHIELD},
                  prompt="the cartoon crab brings both big pincers together in front of its face like a shield"),
    "crouch_block": dict(mode="guide", keys={0: C, 1: merge(LOW_LEGS, SHIELD, P(pf=dict(dy=8), pb=dict(dy=12))), 3: merge(LOW_LEGS, SHIELD, P(pf=dict(dy=8), pb=dict(dy=12)))},
                         prompt="the cartoon crab stays flat on the ground with both pincers together in front of its face like a shield"),
    "punch_1": dict(mode="guide", lora="attack",
                    keys={0: G, 1: P(pf=dict(rot=-12, dx=-3, dy=1)), 3: P(pf=dict(rot=80, dx=18, dy=7), body=dict(dx=2)), 4: P(pf=dict(rot=80, dx=17, dy=7)), 5: P(pf=dict(rot=12, dx=1))},
                    prompt="the cartoon crab jabs its front pincer far forward, snapping it, then pulls it back to guard"),
    "punch_2": dict(mode="guide", lora="attack",
                    keys={0: G, 1: P(pb=dict(rot=-15, dx=-4)), 3: P(order=FRONT, pb=dict(rot=78, dx=50, dy=14), pf=dict(rot=-25, dx=-6), all=dict(dx=4)),
                          4: P(order=FRONT, pb=dict(rot=76, dx=48, dy=14), pf=dict(rot=-25, dx=-6), all=dict(dx=4)), 5: P(pb=dict(rot=10, dx=4))},
                    prompt="the cartoon crab swings its back pincer forward in a straight punch, fully extended, snapping shut"),
    "punch_3": dict(mode="guide", lora="attack",
                    keys={0: G, 1: P(pf=dict(rot=-20, dx=-4), pb=dict(rot=-15, dx=-4)), 3: DOUBLE, 4: DOUBLE, 5: P(pf=dict(rot=15), pb=dict(rot=10))},
                    prompt="the cartoon crab swings both pincers forward together and snaps them shut in a big double strike"),
    "kick": dict(mode="guide", lora="attack",
                 keys={0: G, 1: P(pf=dict(rot=-22, dx=-4)), 3: P(pf=dict(rot=122, dx=16, dy=4), body=dict(dx=2), all=dict(dx=2)), 4: P(pf=dict(rot=118, dx=15, dy=4)), 5: P(pf=dict(rot=20))},
                 prompt="the cartoon crab swings its front pincer low and forward in a hook at belly height, snapping it shut"),
    "kick_high": dict(mode="guide", lora="attack",
                      keys={0: G, 1: P(pf=dict(rot=-40, dx=-6, dy=-10)), 3: P(pf=dict(rot=95, dx=18, dy=-4), all=dict(dx=3)), 4: P(pf=dict(rot=100, dx=17, dy=0)), 5: P(pf=dict(rot=10))},
                      prompt="the cartoon crab raises its front pincer high and chops it down forward at head height"),
    "crouch_punch": dict(mode="guide", lora="attack",
                         keys={0: C, 1: merge(C, P(pf=dict(rot=-25, dx=-8, dy=6))), 3: merge(C, P(pf=dict(rot=100, dx=18, dy=12))), 4: merge(C, P(pf=dict(rot=98, dx=17, dy=12))), 5: C},
                         prompt="the cartoon crab flat on the ground jabs one pincer forward low along the ground"),
    "sweep": dict(mode="guide", lora="attack",
                  keys={0: C, 1: merge(C, P(lf=dict(sy=0.6, sx=1.2, rot=15))), 3: merge(C, P(lf=dict(sy=0.6, sx=1.5, rot=-40, dx=10), pf=dict(rot=110, dx=16, dy=14), tilt=6)),
                        4: merge(C, P(lf=dict(sy=0.6, sx=1.5, rot=-38, dx=9), pf=dict(rot=108, dx=15, dy=14), tilt=6)), 5: C},
                  prompt="the cartoon crab flat on the ground sweeps its legs and front pincer far forward along the ground"),
    "uppercut": dict(mode="guide", lora="attack",
                     keys={0: G, 1: C, 3: P(air=16, pf=dict(rot=-28, dx=4, dy=-16), pb=dict(rot=-10), lb=dict(sy=1.08), lf=dict(sy=1.08)),
                           4: P(air=14, pf=dict(rot=-26, dx=4, dy=-15), pb=dict(rot=-10)), 5: G},
                     prompt="the cartoon crab springs up on its legs and thrusts its front pincer straight up above its head"),
    "jump_punch": dict(mode="guide", lora="attack",
                       keys={0: merge(TUCK, P(air=40)), 1: merge(TUCK, P(air=40, pf=dict(rot=138, dx=12, dy=4))), 2: merge(TUCK, P(air=40, pf=dict(rot=136, dx=12, dy=4))), 3: merge(TUCK, P(air=40, pf=dict(rot=40)))},
                       prompt="the cartoon crab in mid-air with legs tucked thrusts one pincer diagonally down and forward"),
    "throw": dict(mode="guide",
                  keys={0: G, 2: DOUBLE, 3: DOUBLE, 5: P(order=FRONT, pf=dict(rot=-60, dx=-10, dy=-14), pb=dict(rot=-40, dx=-6, dy=-14), tilt=-10),
                        6: P(pf=dict(rot=-70, dx=-12, dy=-12), pb=dict(rot=-50, dx=-8, dy=-12), tilt=-12), 7: G},
                  prompt="the cartoon crab grabs forward with both pincers then flings them up and back over its shell, alone"),
    "thrown": dict(mode="pieces", keys=spin(6)),
    "hit_high": dict(mode="guide", keys={0: G, 1: P(tilt=-12, all=dict(dx=-5), pf=dict(rot=-25), pb=dict(rot=-20)), 2: P(tilt=-10, all=dict(dx=-7), pf=dict(rot=-20), pb=dict(rot=-18)), 3: P(tilt=-4, all=dict(dx=-6))},
                     prompt="the cartoon crab gets bopped, eyes squeezed shut, body tilts backward and staggers back, cartoon, no injury"),
    "hit_low": dict(mode="guide", keys={0: G, 1: P(order=FRONT, tilt=12, all=dict(dx=-4), pf=dict(rot=-150, dx=-20, dy=18), pb=dict(rot=130, dx=18, dy=16)),
                                       2: P(order=FRONT, tilt=10, all=dict(dx=-6), pf=dict(rot=-150, dx=-20, dy=18), pb=dict(rot=130, dx=18, dy=16)), 3: P(tilt=4, all=dict(dx=-5))},
                    prompt="the cartoon crab bends forward holding its belly with both pincers, eyes squeezed shut, cartoon, no injury"),
    "knockdown": dict(mode="pieces", keys=knockdown()),
    "dizzy": dict(mode="guide", keys={i: P(tilt=8 * math.sin(i * math.pi / 3), tilt_pivot=(77, GROUND), pf=dict(rot=25 + 10 * math.sin(i), dy=8), pb=dict(rot=-20, dy=8),
                                            lb=dict(sy=0.94), lf=dict(sy=0.94)) for i in range(6)},
                  prompt="the cartoon crab is dizzy and wobbling in place with swirly eyes, pincers drooping"),
    "win": dict(mode="guide",
                keys={i: P(order=FRONT, all=dict(dx=4 * math.sin(i * math.pi / 2)),
                           pf=dict(rot=-40 if i % 2 else -25, dx=-14 if i % 2 else -6, dy=-12),
                           pb=dict(rot=40 if i % 2 else 22, dx=16 if i % 2 else 6, dy=-12),
                           lb=dict(rot=8 * math.sin(i * math.pi / 2)), lf=dict(rot=-8 * math.sin(i * math.pi / 2))) for i in range(8)},
                prompt="the cartoon crab dances happily side to side clapping its two pincers together above its head, big smile"),
    "intro": dict(mode="guide", keys={0: P(sink=80), 2: P(sink=35), 4: G, 5: P(tilt=6), 6: P(tilt=-6), 7: G},
                  prompt="the cartoon crab pops up from the sand, shakes itself, then raises both pincers into a fighting guard"),
    "sp_neutral": dict(mode="guide", keys={0: G, 2: P(body=dict(sx=1.1, sy=1.08), pf=dict(rot=-10, dy=-4), pb=dict(rot=8, dy=-4)),
                                           4: P(body=dict(sx=1.06, sy=1.04, dx=3), tilt=6, pf=dict(rot=-20, dy=-6), pb=dict(rot=12, dy=-6)),
                                           6: P(body=dict(dx=3), tilt=5, pf=dict(rot=-20, dy=-6), pb=dict(rot=12, dy=-6)), 7: G},
                       prompt="the cartoon crab puffs its cheeks and blows forward, mouth open in a round O, pincers raised"),
    "sp_forward": dict(mode="guide", lora="walk",
                       keys={k: merge(v, P(tilt=8, pf=dict(rot=40, dx=6), pb=dict(rot=40, dx=10))) for k, v in walk(8, amp=26, lift=6, low=0.2, cycles=2).items()},
                       prompt="the cartoon crab dashes sideways in a lightning fast scuttle, body low, legs blurred"),
    "sp_down": dict(mode="guide", lora="attack",
                    keys={0: G, 1: merge(LOW_LEGS, SHIELD), 4: merge(LOW_LEGS, SHIELD), 5: merge(LOW_LEGS, DOUBLE), 6: merge(LOW_LEGS, DOUBLE), 7: G},
                    prompt="the cartoon crab hides behind both pincers held together, then snaps both pincers forward"),
    "sp_up": dict(mode="guide", keys={0: G, 1: C, 3: P(air=40, pf=dict(rot=-28, dx=2, dy=-14), pb=dict(rot=20, dx=10, dy=-12), lb=dict(sy=1.08), lf=dict(sy=1.08)),
                                      5: P(air=36, pf=dict(rot=-20, dy=-12), pb=dict(rot=14, dy=-10)), 7: G},
                  prompt="the cartoon crab springs straight up thrusting both pincers high above its head, snapping them"),
    "super": dict(mode="guide",
                  keys={0: G, 2: DOUBLE, 3: DOUBLE, 5: P(order=FRONT, pf=dict(rot=-45, dx=-4, dy=-16), pb=dict(rot=-20, dx=12, dy=-16), air=6),
                        6: P(order=FRONT, pf=dict(rot=-50, dx=-4, dy=-18), pb=dict(rot=-25, dx=12, dy=-18), air=10),
                        8: DOUBLE, 10: P(order=FRONT, pf=dict(rot=-45, dx=-4, dy=-16), pb=dict(rot=-20, dx=12, dy=-16), air=8), 11: G},
                  prompt="the cartoon crab grabs forward with both pincers, lifts up and tosses upward like flipping a pancake, alone"),
    "finisher": dict(mode="guide",
                     keys={i: P(tilt=5 * math.sin(i * math.pi / 2), tilt_pivot=(77, GROUND),
                                pf=dict(rot=(70 if 4 <= i < 9 and i % 2 == 0 else 50) if 4 <= i < 9 else (-8 if i % 2 else 4), dx=12 if 4 <= i < 9 else 0, dy=4 if 4 <= i < 9 else 0),
                                pb=dict(rot=-8 if i % 2 == 0 else 6)) for i in range(12)},
                     prompt="the cartoon crab snaps its pincers proudly, pinches the air in front of it and wiggles happily, big grin"),
}
