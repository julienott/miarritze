#!/usr/bin/env python3
"""Génère tools/rig/poses/<id>.json : poses propres des spéciaux, du super
et du finish de chaque perso (SPEC §5.1). Les animations communes restent
dans poses.json ; ici on ne surcharge que sp_*, super, finisher (et win).

Repères d'angles (degrés, relatifs au parent) :
  bras/jambes : 0 = pend vers le bas, 90 = vers l'avant, 180 = vers le haut,
                négatif = vers l'arrière ; avant-bras/tibia relatifs au segment.
  torse : négatif = penché en avant. Accessoires tenus : accf / accb / acc.
Usage : gen_char_poses.py   (réécrit tous les fichiers)
"""
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))


def k(t, use=None, **p):
    key = {"t": t, "p": p}
    if use:
        key["use"] = use
    return key


def anim(frames, fps, keys, hit=None, base="guard", hit_dir=None, loop=False):
    a = {"frames": frames, "fps": fps, "loop": loop, "base": base, "keys": keys}
    if hit is not None:
        a["hit_frame"] = hit
        if hit_dir:
            a["hit_dir"] = hit_dir
    return a


# ------------------------------------------------------------ gabarits

UP_ACTIVE = dict(tor=6, head=-4, uaf=118, faf=50, uab=-30, fab=40, thf=88, shf=-98, thb=-8, shb=0,
                 off={"uaf": [3, -2]})


def throw_front(extra_wind=None, extra_rel=None, frames=8, fps=14):
    """Lancer bras avant (espadrille, sardines, pelote, bouée)."""
    wind = dict(uaf=-55, faf=70, tor=12, head=-4, uab=40, fab=90, thf=20, thb=-30)
    rel = dict(uaf=100, faf=-5, tor=-22, head=14, uab=10, fab=60, thf=40, shf=-26, thb=-34,
               str={"uaf": [1.0, 1.15], "faf": [1.0, 1.25]})
    wind.update(extra_wind or {})
    rel.update(extra_rel or {})
    return anim(frames, fps, [k(0), k(1, **wind), k(2, **dict(wind, uaf=-70, tor=16)), k(3, **rel),
                              k(4, **{kk: v for kk, v in rel.items() if kk != "str"}),
                              k(6, uaf=70, faf=30, tor=-8), k(frames - 1, "guard")], hit=3)


def throw_back_overhead(extra=None):
    """Lancer bras arrière par-dessus la tête (pierre, sardines lourdes)."""
    e = extra or {}
    return anim(8, 12, [k(0), k(1, uab=150, fab=30, tor=14, head=-8, thf=20, thb=-30),
                        k(2, uab=178, fab=10, tor=20, head=-10),
                        k(3, uab=95, fab=0, tor=-26, head=16, uaf=20, faf=100, thf=40, shf=-30, thb=-36,
                          off={"uab": [8, 0]}, str={"uab": [1.0, 1.15]}, **e),
                        k(4, uab=70, fab=20, tor=-24, off={"uab": [6, 0]}),
                        k(6, uab=40, fab=80, tor=-10, off={"uab": [0, 0]}), k(7, "guard")], hit=3)


def charge(extra=None, frames=8):
    """Charge épaule en avant (béret, bélier, plaquage)."""
    e = extra or {}
    lean = dict(tor=-48, head=36, uaf=20, faf=110, uab=-20, fab=90, thf=55, shf=-40, thb=-55, shb=-10,
                squash=[1.08, 0.96])
    lean.update(e)
    return anim(frames, 14, [k(0), k(1, tor=-20, uaf=20, faf=110, uab=10, fab=100),
                             k(2, **lean), k(3, **{kk: v for kk, v in lean.items() if kk != "squash"}),
                             k(5, **dict({kk: v for kk, v in lean.items() if kk != "squash"}, thf=30, thb=-35)),
                             k(frames - 1, "guard")], hit=3)


def slide_low(extra=None):
    e = extra or {}
    low = dict(pel=40, tor=-30, head=18, thf=60, shf=0, thb=20, shb=-70, uaf=40, faf=20, uab=-60, fab=10)
    low.update(e)
    return anim(8, 14, [k(0), k(1, "crouch"), k(2, **low), k(3, **dict(low, pel=48)), k(5, **low),
                        k(7, "crouch")], hit=3, hit_dir="low")


def rise_up(extra=None, extra_b=None):
    e = extra or {}
    act = dict(UP_ACTIVE)
    act.update(e)
    return anim(8, 14, [k(0), k(1, "crouch", uaf=20, faf=100),
                        k(2, "guard", uaf=100, faf=40, thf=70, shf=-80, **(extra_b or {})),
                        k(3, **dict(act, str={"uaf": [1.0, 1.25], "faf": [1.0, 1.3]})),
                        k(4, **act), k(5, **act), k(7, "guard", off={"uaf": [0, 0]})], hit=3, hit_dir="up")


def spin(frames=12, fps=16, arms=(100, 0, 100, 0), extra_each=None, hit=6):
    """Tournoiement : alternance torse / bras tendus (moulinet, danse, rafale)."""
    keys = [k(0)]
    for t in range(1, frames - 1):
        a = arms
        if t % 2:
            p = dict(uaf=a[0], faf=a[1], uab=a[2] - 120, fab=a[3], tor=-10, head=6)
        else:
            p = dict(uaf=a[0] - 110, faf=a[1] + 40, uab=a[2], fab=a[3], tor=4, head=-4)
        p.update((extra_each or (lambda tt: {}))(t))
        keys.append(k(t, **p))
    keys.append(k(frames - 1, "guard"))
    return anim(frames, fps, keys, hit=hit)


def flurry(frames=12, fps=16, hit=6, fin=None):
    """Super générique : rafale de coups alternés puis coup final."""
    keys = [k(0)]
    for t in range(1, 5):
        if t % 2:
            keys.append(k(t, uaf=95, faf=0, tor=-16, uab=20, fab=110, str={"faf": [1.0, 1.3]}))
        else:
            keys.append(k(t, uab=92, fab=0, uaf=20, faf=110, tor=-26, off={"uab": [9, 0]}))
    keys.append(k(5, "crouch", uaf=20, faf=100, off={"uab": [0, 0]}))
    keys.append(k(6, **dict(UP_ACTIVE, **(fin or {}), str={"uaf": [1.0, 1.3], "faf": [1.0, 1.3]})))
    keys.append(k(8, **dict(UP_ACTIVE, **(fin or {}))))
    keys.append(k(11, "guard", off={"uaf": [0, 0]}))
    return anim(frames, fps, keys, hit=hit, hit_dir="up")


def finisher(arms_a, arms_b, final=None):
    """Finish comique : deux temps de geste répétés puis pose de triomphe."""
    keys = [k(0)]
    for t in (2, 6):
        keys.append(k(t, **arms_a))
    for t in (4, 8):
        keys.append(k(t, **arms_b))
    keys.append(k(10, **(final or dict(uaf=120, faf=60, uab=-30, fab=40, tor=8, head=-10))))
    keys.append(k(11, **(final or dict(uaf=118, faf=50, uab=-30, fab=40, tor=8, head=-10))))
    return anim(12, 10, keys, base="relaxed")


WIN_FIST = dict(uaf=78, faf=96, uab=-20, fab=60, tor=8, head=-8, off={"uaf": [11, 0]})


def win(extra_a=None, extra_b=None):
    a = dict(WIN_FIST, **(extra_a or {}))
    b = dict(a, uaf=82, faf=92, off={"uaf": [11, -2], "tor": [0, -1]})
    b.update(extra_b or {})
    a0 = dict(a, off={**a["off"], "tor": [0, 0]})
    return anim(8, 8, [k(0, **a0), k(4, **b), k(8, **a0)], base="relaxed", loop=True)


# ------------------------------------------------------------ personnages

CHARS = {}

CHARS["louis"] = {
    "sp_neutral": throw_front(),
    "sp_forward": charge(dict(head=40)),
    "sp_down": slide_low(),
    "sp_up": rise_up(dict(thf=110, shf=-110)),
    "super": flurry(),
    "finisher": finisher(dict(uaf=100, faf=60, uab=100, fab=60, tor=-20, head=10),
                         dict(uaf=80, faf=10, uab=80, fab=10, tor=-26, head=14, off={"uab": [8, 0]})),
}

CHARS["maia"] = {
    # Planche dans le dos : l'os `acc` (planche) fait le tour par-dessus l'épaule.
    "sp_neutral": anim(8, 14, [k(0), k(1, acc=-40, uaf=150, faf=20, tor=10, head=-6),
                               k(2, acc=-110, uaf=140, faf=30, tor=4),
                               k(3, acc=-175, uaf=95, faf=0, tor=-24, head=14, thf=40, shf=-30, thb=-34),
                               k(4, acc=-185, uaf=80, faf=10, tor=-26),
                               k(6, acc=-60, uaf=60, faf=60, tor=-8), k(7, "guard")], hit=3),
    "sp_forward": anim(8, 14, [k(0), k(1, "crouch", uaf=60, faf=10, uab=-60, fab=10),
                               k(2, tor=-20, head=14, uaf=80, faf=0, uab=-70, fab=0, thf=70, shf=-70, thb=-40,
                                 shb=-40, root=[0, 4]),
                               k(3, tor=-22, head=16, uaf=85, faf=0, uab=-75, fab=0, thf=72, shf=-72, thb=-42,
                                 shb=-40, root=[0, 4]),
                               k(5, tor=-18, uaf=80, faf=10, uab=-70, fab=10, thf=70, shf=-70, thb=-40, shb=-40,
                                 root=[0, 4]),
                               k(7, "guard", root=[0, 0])], hit=3),
    "sp_down": anim(8, 14, [k(0), k(1, "crouch"), k(2, "crouch", uaf=80, faf=0, uab=70, fab=0, tor=-30,
                                                     off={"uab": [6, 0]}),
                            k(3, "crouch", uaf=90, faf=-10, uab=85, fab=-10, tor=-34, head=20,
                              off={"uab": [8, 0]}),
                            k(5, "crouch", off={"uab": [0, 0]}), k(7, "guard")], hit=3, hit_dir="low"),
    "sp_up": anim(8, 14, [k(0), k(1, "crouch"), k(2, "air", acc=-90, uaf=150, faf=10),
                          k(3, "air", acc=-180, uaf=120, faf=40, tor=10, thf=100, shf=-120),
                          k(4, "air", acc=-270, uaf=100, faf=60), k(5, "air", acc=-360),
                          k(7, "guard", acc=12)], hit=3, hit_dir="up"),
    "super": anim(12, 14, [k(0), k(1, "crouch", uaf=80, faf=0, uab=-70, fab=0)] +
                  [k(t, tor=-18 + (4 if t % 2 else 0), head=12, uaf=85 + (10 if t % 2 else 0), faf=0,
                     uab=-80, fab=0, thf=72, shf=-72, thb=-42, shb=-40, root=[0, 4 - (t % 2)])
                   for t in range(2, 10)] + [k(11, "guard", root=[0, 0])], hit=6),
    "finisher": finisher(dict(uaf=130, faf=60, uab=-10, fab=30, head=-6),
                         dict(uaf=150, faf=-30, uab=-10, fab=30, head=-6)),
}

CHARS["patxi"] = {
    "sp_neutral": throw_front(dict(accf=0), dict(accf=40)),
    # « Viens par ici ! » : la canne part de derrière la tête et fouette vers l'avant.
    "sp_forward": anim(8, 12, [k(0), k(1, uaf=160, faf=30, accf=20, tor=10, head=-8),
                               k(2, uaf=175, faf=40, accf=40, tor=14),
                               k(3, uaf=100, faf=-10, accf=60, tor=-20, head=10, thf=40, shf=-30, thb=-34),
                               k(4, uaf=95, faf=-10, accf=55, tor=-20),
                               k(6, uaf=30, faf=60, accf=20, tor=8, head=-4, thb=-40),
                               k(7, "guard")], hit=3),
    "sp_down": anim(8, 12, [k(0), k(1, "crouch", uaf=-40, faf=70, uab=-50, fab=70),
                            k(3, "crouch", uaf=80, faf=-10, uab=80, fab=-10, tor=-30, off={"uab": [8, 0]}),
                            k(4, "crouch", uaf=70, faf=10, uab=70, fab=10, tor=-28, off={"uab": [7, 0]}),
                            k(7, "guard", off={"uab": [0, 0]})], hit=3, hit_dir="low"),
    "sp_up": anim(8, 14, [k(0), k(1, uaf=150, faf=20, accf=-90)] +
                  [k(t, uaf=150, faf=10, accf=-90 + 90 * t, tor=4, head=-6) for t in range(2, 6)] +
                  [k(7, "guard")], hit=3, hit_dir="up"),
    "super": anim(12, 12, [k(0), k(1, uaf=170, faf=30, accf=40, tor=12), k(2, uaf=100, faf=-10, accf=-40, tor=-20),
                           k(4, uaf=150, faf=20, accf=-20, tor=10, head=-10, thb=-50),
                           k(5, uaf=160, faf=10, accf=60, tor=14)] +
                  [k(t, uaf=150, faf=20, accf=60 + 90 * (t - 5), tor=8, head=-8) for t in range(6, 10)] +
                  [k(11, "guard")], hit=6, hit_dir="up"),
    "finisher": finisher(dict(uaf=110, faf=40, uab=100, fab=40, tor=-14),
                         dict(uaf=90, faf=30, uab=80, fab=30, tor=-20, off={"uab": [6, 0]})),
}

CHARS["xabi"] = {
    # Chistera : grand fouetté du bras avant, de l'arrière vers l'avant.
    "sp_neutral": throw_front(dict(accf=20), dict(accf=30)),
    "sp_forward": anim(8, 14, [k(0), k(1, "crouch", uaf=-50, faf=30, accf=10),
                               k(3, "crouch", uaf=80, faf=-10, accf=-60, tor=-30, head=16, thf=95, shf=-100),
                               k(4, "crouch", uaf=90, faf=0, accf=-70, tor=-30),
                               k(7, "guard")], hit=3, hit_dir="low"),
    "sp_down": anim(8, 12, [k(0), k(1, uaf=170, faf=40, accf=40, tor=14, head=-10),
                            k(3, uaf=110, faf=-10, accf=-60, tor=-24, head=12, thf=40, shf=-30, thb=-36),
                            k(4, uaf=95, faf=-10, accf=-70, tor=-26), k(7, "guard")], hit=3),
    "sp_up": anim(8, 12, [k(0), k(1, uaf=-40, faf=20, accf=30, tor=-6),
                          k(3, uaf=140, faf=10, accf=-40, tor=8, head=-10, thf=50, shf=-40),
                          k(4, uaf=150, faf=10, accf=-50, tor=10), k(7, "guard")], hit=3, hit_dir="up"),
    "super": anim(12, 18, [k(0)] + [k(t, uaf=(-60 if t % 2 else 100), faf=(40 if t % 2 else -5),
                                       accf=(20 if t % 2 else -60), tor=(12 if t % 2 else -22),
                                       head=(-4 if t % 2 else 12)) for t in range(1, 10)] +
                  [k(10, uaf=150, faf=10, accf=-60, tor=10), k(11, "guard")], hit=6),
    "finisher": finisher(dict(uaf=125, faf=50, uab=-20, fab=60, head=-10, tor=8),
                         dict(uaf=40, faf=110, uab=40, fab=110, tor=-20, head=16)),
}

CHARS["mattin"] = {
    "sp_neutral": throw_back_overhead(),
    "sp_forward": charge(dict(tor=-60, head=46, uaf=60, faf=80, uab=40, fab=90)),
    "sp_down": anim(8, 10, [k(0), k(1, uaf=170, faf=20, uab=172, fab=20, tor=10, head=-8, accb=0),
                            k(2, uaf=178, faf=10, uab=178, fab=10, tor=14),
                            k(3, "crouch", uaf=40, faf=0, uab=30, fab=0, tor=-40, head=24, squash=[1.1, 0.9]),
                            k(4, "crouch", uaf=40, faf=0, uab=30, fab=0, tor=-40, head=24),
                            k(7, "guard")], hit=3, hit_dir="low"),
    "sp_up": anim(8, 12, [k(0), k(1, "crouch", uaf=20, faf=40, uab=20, fab=40),
                          k(3, uaf=132, faf=30, uab=150, fab=20, tor=10, head=-6, off={"uaf": [5, -2]}),
                          k(4, uaf=135, faf=25, uab=160, fab=10, tor=12, off={"uaf": [5, -2]}),
                          k(7, "guard", off={"uaf": [0, 0]})], hit=3, hit_dir="up"),
    "super": anim(12, 10, [k(0), k(1, "crouch", uaf=20, faf=40, uab=20, fab=40),
                           k(3, uaf=160, faf=10, uab=160, fab=10, tor=12, off={"uaf": [3, -2]}),
                           k(5, uaf=165, faf=10, uab=165, fab=10, tor=-10, off={"uaf": [3, -2]}),
                           k(7, uaf=160, faf=10, uab=160, fab=10, tor=14, off={"uaf": [3, -2]}),
                           k(9, uaf=90, faf=0, uab=90, fab=0, tor=-30, off={"uab": [6, 0]}),
                           k(11, "guard", off={"uaf": [0, 0], "uab": [0, 0]})], hit=6, hit_dir="up"),
    "finisher": finisher(dict(uaf=90, faf=10, uab=90, fab=10, tor=-30, off={"uab": [6, 0]}),
                         dict(uaf=70, faf=20, uab=70, fab=20, tor=-36, off={"uab": [6, 0]})),
}

CHARS["amaia"] = {
    "sp_neutral": anim(8, 16, [k(0)] + [k(t, uaf=95, faf=0, accf=90 * t, tor=-12, head=8) for t in range(1, 7)] +
                       [k(7, "guard")], hit=3),
    "sp_forward": anim(8, 14, [k(0), k(1, "crouch"),
                               k(2, "air", thf=100, shf=-10, thb=-50, shb=-30, tor=8, uaf=150, faf=20, uab=-40),
                               k(3, "air", thf=105, shf=0, thb=-60, shb=-20, tor=10, uaf=150, faf=20, uab=-50,
                                 str={"shf": [1.0, 1.2]}),
                               k(5, "air", thf=80, shf=-40), k(7, "guard")], hit=3),
    "sp_down": anim(8, 16, [k(0), k(1, "crouch")] +
                    [k(t, "crouch", thf=(85 if t % 2 else 20), shf=(0 if t % 2 else -100), pel=(10 if t % 2 else 0),
                       tor=(-30 if t % 2 else -10), uaf=(150 if t % 2 else 40), faf=20) for t in range(2, 7)] +
                    [k(7, "guard")], hit=3, hit_dir="low"),
    "sp_up": anim(8, 14, [k(0), k(1, "crouch"),
                          k(2, "air", thf=140, shf=-20, thb=60, shb=-60, tor=16, head=-10, uaf=-30, faf=40),
                          k(3, "air", thf=165, shf=0, thb=-20, shb=-10, tor=22, head=-14, uaf=-40, faf=20,
                            str={"shf": [1.0, 1.2]}),
                          k(4, "air", thf=150, shf=-10, thb=10, tor=20), k(7, "guard")], hit=3, hit_dir="up"),
    "super": spin(12, 16, arms=(100, 0, 110, 0), extra_each=lambda t: dict(accf=60 * t, thf=(60 if t % 3 else 20))),
    "finisher": finisher(dict(uaf=130, faf=40, uab=-10, fab=60, thf=60, shf=-80, tor=6),
                         dict(uaf=110, faf=60, uab=10, fab=40, thf=10, shf=-10, thb=60, shb=-80, tor=-4)),
    "win": win(dict(accf=60), dict(accf=120)),
}

CHARS["txomin"] = {
    # Coup de sifflet : la main monte à la bouche, le buste se penche.
    "sp_neutral": anim(8, 12, [k(0), k(1, uaf=30, faf=140, tor=-6, head=4),
                               k(2, uaf=35, faf=150, tor=-16, head=14, squash=[1.04, 0.98]),
                               k(3, uaf=35, faf=150, tor=-20, head=18, uab=-30, fab=40),
                               k(5, uaf=35, faf=150, tor=-18), k(7, "guard")], hit=3),
    "sp_forward": throw_front(dict(uaf=-80, faf=40), dict(uaf=95, faf=-10)),
    "sp_down": anim(8, 12, [k(0), k(1, uaf=160, faf=10, tor=6),
                            k(3, "crouch", uaf=50, faf=-10, tor=-40, head=26),
                            k(4, "crouch", uaf=45, faf=-10, tor=-40, head=26), k(7, "guard")], hit=3, hit_dir="low"),
    "sp_up": anim(8, 12, [k(0), k(1, "crouch"),
                          k(2, "air", uaf=150, faf=10, uab=150, fab=10, tor=-20, off={"uaf": [3, -2]}),
                          k(3, "air", uaf=120, faf=0, uab=120, fab=0, tor=-60, head=40, thf=20, shf=-10, thb=10,
                            shb=-10),
                          k(5, "air", uaf=110, faf=0, uab=110, fab=0, tor=-75, head=46, thf=10, shf=0, thb=5),
                          k(7, "guard", off={"uaf": [0, 0]})], hit=3),
    "super": anim(12, 12, [k(0), k(1, "crouch"), k(3, "air", uaf=150, faf=10, uab=150, fab=10, tor=10,
                                                     off={"uaf": [3, -2]}),
                           k(5, "air", uaf=120, faf=0, uab=120, fab=0, tor=-60, head=40, thf=20, shf=-10),
                           k(7, "air", uaf=110, faf=0, uab=110, fab=0, tor=-80, head=50, thf=0, shf=0, thb=0),
                           k(9, "crouch", squash=[1.1, 0.9]), k(11, "guard", off={"uaf": [0, 0]})], hit=6),
    "finisher": finisher(dict(uaf=80, faf=40, uab=70, fab=40, tor=-40, head=26),
                         dict(uaf=90, faf=20, uab=80, fab=20, tor=-46, head=30, off={"uab": [6, 0]})),
}

CHARS["kaio"] = {
    # Ailes = bras : battements amples, fiente « en cloche » avec la queue levée.
    "sp_neutral": anim(8, 14, [k(0), k(1, uaf=160, uab=150, faf=20, fab=20, tor=-20, pel=-15),
                               k(2, uaf=60, uab=50, faf=40, fab=40, tor=-30, pel=-25, head=20),
                               k(3, uaf=170, uab=160, faf=10, fab=10, tor=-34, pel=-30, head=24),
                               k(5, uaf=90, uab=80, tor=-10, pel=0), k(7, "guard")], hit=3, hit_dir="up"),
    "sp_forward": anim(8, 14, [k(0), k(1, uaf=170, uab=160, faf=10, fab=10),
                               k(2, "air", uaf=-40, faf=10, uab=-50, fab=10, tor=-60, head=44, thf=20, shf=-60),
                               k(3, "air", uaf=-50, faf=10, uab=-60, fab=10, tor=-65, head=48, thf=10, shf=-40,
                                 str={"tor": [1.0, 1.1]}),
                               k(5, "air", uaf=-40, uab=-50, tor=-55), k(7, "guard")], hit=3),
    "sp_down": anim(8, 14, [k(0), k(1, "crouch", head=30), k(2, "crouch", tor=-50, head=40, uaf=100, faf=0),
                            k(3, "crouch", tor=-56, head=46, uaf=110, faf=-10, str={"head": [1.1, 1.0]}),
                            k(5, "crouch", tor=-30, head=20, uaf=40, faf=80), k(7, "guard")], hit=3, hit_dir="low"),
    "sp_up": anim(8, 16, [k(0)] + [k(t, "air", uaf=(170 if t % 2 else 40), uab=(165 if t % 2 else 30),
                                     faf=(10 if t % 2 else 60), fab=(10 if t % 2 else 60), tor=-6,
                                     root=[0, -(2 if t % 2 else 0)]) for t in range(1, 7)] +
                  [k(7, "guard", root=[0, 0])], hit=3, hit_dir="up"),
    "super": anim(12, 16, [k(0)] + [k(t, "air", uaf=(170 if t % 2 else 30), uab=(160 if t % 2 else 20),
                                       faf=(10 if t % 2 else 60), fab=(10 if t % 2 else 60), tor=-30, head=20)
                                     for t in range(1, 11)] + [k(11, "guard")], hit=6),
    "finisher": finisher(dict(uaf=100, faf=30, tor=-30, head=20), dict(uaf=170, faf=10, uab=160, tor=-6, head=-8)),
}

CHARS["karramarro"] = {
    "sp_neutral": anim(8, 12, [k(0), k(1, uaf=60, faf=60, uab=60, fab=60, tor=-6),
                               k(3, uaf=95, faf=0, uab=90, fab=0, tor=-18, head=10, off={"uab": [7, 0]}),
                               k(4, uaf=90, faf=10, uab=85, fab=10, tor=-16, off={"uab": [7, 0]}),
                               k(7, "guard", off={"uab": [0, 0]})], hit=3),
    "sp_forward": anim(8, 16, [k(0), k(1, "crouch", thf=60, shf=-60, thb=-60, shb=-20),
                               k(2, thf=70, shf=-40, thb=-70, shb=-10, tor=-20, root=[0, 4], squash=[1.15, 0.92]),
                               k(3, thf=60, shf=-40, thb=-60, shb=-10, tor=-20, root=[0, 4]),
                               k(5, thf=50, shf=-40, thb=-50, root=[0, 2]), k(7, "guard", root=[0, 0])], hit=3),
    "sp_down": anim(8, 10, [k(0), k(1, "crouch", uaf=150, faf=120, uab=150, fab=120, tor=-30, head=20),
                            k(3, "crouch", uaf=155, faf=125, uab=155, fab=125, tor=-34, head=24),
                            k(5, "crouch", uaf=150, faf=120, uab=150, fab=120, tor=-30),
                            k(7, "guard")], hit=3),
    "sp_up": rise_up(dict(uab=150, fab=20)),
    "super": anim(12, 16, [k(0)] + [k(t, uaf=(95 if t % 2 else 60), faf=(0 if t % 2 else 60),
                                       uab=(60 if t % 2 else 95), fab=(60 if t % 2 else 0), tor=-16,
                                       off={"uab": [7, 0]}) for t in range(1, 9)] +
                  [k(9, **dict(UP_ACTIVE, uab=150)), k(11, "guard", off={"uab": [0, 0], "uaf": [0, 0]})], hit=6),
    "finisher": finisher(dict(uaf=95, faf=0, tor=-16, head=10), dict(uaf=100, faf=10, tor=-10, head=4)),
}

CHARS["ramuntxo"] = {
    # Piment d'Espelette : souffle de feu, buste en avant, main devant la bouche.
    "sp_neutral": anim(8, 12, [k(0), k(1, tor=10, head=-12, uaf=40, faf=120),
                               k(3, tor=-24, head=18, uaf=80, faf=40, uab=-30, fab=30, squash=[1.05, 0.98]),
                               k(4, tor=-26, head=20, uaf=80, faf=40),
                               k(5, tor=-22, head=18, uaf=80, faf=40), k(7, "guard")], hit=3),
    # Jambon de Bayonne : grand coup par-dessus la tête, louche tendue.
    "sp_forward": anim(8, 12, [k(0), k(1, uaf=170, faf=30, accf=30, tor=12, head=-8),
                               k(3, uaf=100, faf=-10, accf=-30, tor=-26, head=14, thf=40, shf=-30, thb=-36,
                                 str={"uaf": [1.0, 1.2], "faf": [1.0, 1.2]}),
                               k(4, uaf=90, faf=-10, accf=-40, tor=-26), k(7, "guard")], hit=3),
    "sp_down": anim(8, 10, [k(0), k(2, "crouch", uaf=70, faf=10, uab=70, fab=10, tor=-34, off={"uab": [6, 0]}),
                            k(4, "crouch", uaf=60, faf=0, uab=60, fab=0, tor=-38, off={"uab": [6, 0]}),
                            k(7, "guard", off={"uab": [0, 0]})], hit=3, hit_dir="low"),
    "sp_up": anim(8, 14, [k(0), k(1, "crouch", uaf=-20, faf=40),
                          k(3, uaf=150, faf=-10, accf=-90, tor=8, head=-8, off={"uaf": [3, -2]}),
                          k(4, uaf=160, faf=-10, accf=-100, tor=10), k(7, "guard", off={"uaf": [0, 0]})],
                  hit=3, hit_dir="up"),
    "super": anim(12, 12, [k(0)] + [k(t, uaf=70 + 30 * ((t % 4) - 1.5), faf=60 - 20 * (t % 2), accf=60 * t,
                                       uab=60, fab=60, tor=-10) for t in range(1, 10)] +
                  [k(10, uaf=150, faf=-10, accf=-90, tor=10), k(11, "guard")], hit=6),
    "finisher": finisher(dict(uaf=140, faf=20, uab=140, fab=20, tor=6, off={"uaf": [3, -2]}),
                         dict(uaf=120, faf=40, accf=-90, uab=120, fab=40, tor=-14, off={"uaf": [3, -2]})),
}

CHARS["itsaso"] = {
    "sp_neutral": anim(8, 12, [k(0), k(1, uaf=20, faf=100, uab=20, fab=100, tor=6),
                               k(3, uaf=95, faf=-10, uab=95, fab=-10, tor=-16, head=10, off={"uab": [7, 0]}),
                               k(4, uaf=95, faf=-5, uab=90, fab=-5, tor=-16, off={"uab": [7, 0]}),
                               k(7, "guard", off={"uab": [0, 0]})], hit=3),
    # Ressac : le corps se dissout en flaque (aplati) puis se reforme.
    "sp_forward": anim(8, 14, [k(0), k(1, "crouch", squash=[1.2, 0.75]), k(2, "crouch", squash=[1.5, 0.4]),
                               k(3, "crouch", squash=[1.6, 0.3]), k(4, "crouch", squash=[1.4, 0.5]),
                               k(5, "crouch", squash=[1.1, 0.85]), k(7, "guard")], hit=3, hit_dir="low"),
    "sp_down": anim(8, 10, [k(0), k(2, "crouch", uaf=40, faf=-20, uab=40, fab=-20, tor=-36, off={"uab": [6, 0]}),
                            k(3, "crouch", uaf=30, faf=-30, uab=30, fab=-30, tor=-40, head=20, off={"uab": [6, 0]}),
                            k(5, "crouch", uaf=40, faf=-20, uab=40, fab=-20, tor=-36),
                            k(7, "guard", off={"uab": [0, 0]})], hit=3, hit_dir="low"),
    "sp_up": anim(8, 12, [k(0), k(1, "crouch", uaf=20, faf=20, uab=20, fab=20),
                          k(3, uaf=150, faf=10, uab=155, fab=10, tor=8, head=-10, off={"uaf": [3, -2]},
                            squash=[0.92, 1.1]),
                          k(4, uaf=155, faf=10, uab=160, fab=10, tor=10, off={"uaf": [3, -2]}),
                          k(7, "guard", off={"uaf": [0, 0]})], hit=3, hit_dir="up"),
    "super": anim(12, 10, [k(0)] + [k(t, uaf=110 + (30 if t % 2 else 0), faf=(10 if t % 2 else 40),
                                       uab=-60 + (40 if t % 2 else 0), fab=20, tor=(4 if t % 2 else -8),
                                       head=(-6 if t % 2 else 4)) for t in range(1, 11)] + [k(11, "guard")], hit=6),
    "finisher": finisher(dict(uaf=110, faf=20, uab=-60, fab=20, tor=4),
                         dict(uaf=140, faf=0, uab=-80, fab=10, tor=8, head=-8)),
}

CHARS["peio"] = {
    # Drop : coup de pied vers le haut, ballon lâché du bras arrière.
    "sp_neutral": anim(8, 12, [k(0), k(1, uab=60, fab=40, accb=0, thf=-30, shf=-40),
                               k(3, thf=130, shf=-10, uab=40, fab=60, tor=12, head=-10, thb=-10,
                                 str={"shf": [1.0, 1.2]}),
                               k(4, thf=120, shf=-20, tor=10), k(7, "guard")], hit=3, hit_dir="up"),
    "sp_forward": charge(dict(tor=-66, head=48, uaf=100, faf=0, uab=90, fab=0, off={"uab": [8, 0]})),
    "sp_down": anim(8, 12, [k(0), k(1, uaf=20, faf=90, tor=8),
                            k(3, uaf=92, faf=0, tor=-22, head=10, thf=40, shf=-30, thb=-36,
                              off={"uaf": [3, 0]}, str={"uaf": [1.0, 1.2], "faf": [1.0, 1.25]}),
                            k(4, uaf=90, faf=0, tor=-22, off={"uaf": [3, 0]}), k(7, "guard", off={"uaf": [0, 0]})],
                    hit=3),
    "sp_up": anim(8, 12, [k(0), k(1, "crouch"),
                          k(3, "air", uaf=150, faf=10, uab=150, fab=10, tor=6, head=-10, off={"uaf": [3, -2]}),
                          k(4, "air", uaf=155, faf=10, uab=155, fab=10, tor=8), k(7, "guard", off={"uaf": [0, 0]})],
                  hit=3, hit_dir="up"),
    "super": anim(12, 12, [k(0)] + [k(t, tor=-70, head=50, uaf=100, faf=0, uab=95, fab=0,
                                       thf=(60 if t % 2 else 10), shf=(-60 if t % 2 else -10),
                                       thb=(-10 if t % 2 else -60), shb=(-10 if t % 2 else -40),
                                       off={"uab": [8, 0]}) for t in range(1, 11)] +
                  [k(11, "guard", off={"uab": [0, 0]})], hit=6),
    "finisher": finisher(dict(uaf=150, faf=-20, uab=150, fab=-20, tor=6, off={"uaf": [3, -2]}),
                         dict(uaf=90, faf=60, uab=90, fab=60, tor=-10, off={"uaf": [0, 0]})),
}

CHARS["itsasargi"] = {
    # Faisceau : la lanterne (main arrière) est brandie vers l'avant.
    "sp_neutral": anim(8, 10, [k(0), k(1, uab=60, fab=30, accb=-60, tor=-6),
                               k(3, uab=92, fab=0, accb=-92, tor=-14, head=8, off={"uab": [8, 0]}),
                               k(5, uab=92, fab=0, accb=-92, tor=-14, off={"uab": [8, 0]}),
                               k(7, "guard", off={"uab": [0, 0]})], hit=3),
    "sp_forward": anim(8, 10, [k(0), k(2, "crouch", uaf=140, faf=120, uab=140, fab=120, tor=-20, squash=[1.1, 0.9]),
                               k(4, "crouch", uaf=150, faf=120, uab=150, fab=120, tor=-24, squash=[1.2, 0.8]),
                               k(7, "guard")], hit=3),
    "sp_down": anim(8, 10, [k(0), k(1, uaf=40, faf=140, uab=40, fab=140, tor=6, head=-10),
                            k(3, uaf=45, faf=150, uab=45, fab=150, tor=14, head=-16, squash=[1.05, 1.0]),
                            k(5, uaf=45, faf=150, tor=12), k(7, "guard")], hit=3),
    "sp_up": anim(8, 10, [k(0), k(1, uab=170, fab=0, accb=-170, tor=8),
                          k(3, uab=120, fab=0, accb=-120, tor=0, off={"uab": [6, 0]}),
                          k(5, uab=60, fab=0, accb=-60, tor=-12, off={"uab": [6, 0]}),
                          k(7, "guard", off={"uab": [0, 0]})], hit=3, hit_dir="up"),
    "super": anim(12, 8, [k(0), k(2, uab=172, fab=0, accb=-172, tor=10, head=-10),
                          k(6, uab=175, fab=0, accb=-175, tor=12, head=-12),
                          k(9, uab=100, fab=0, accb=-100, tor=-10, off={"uab": [8, 0]}),
                          k(11, "guard", off={"uab": [0, 0]})], hit=6),
    "finisher": finisher(dict(uab=172, fab=0, accb=-172, tor=8, head=-10),
                         dict(uab=150, fab=10, accb=-150, tor=4, head=-6)),
}

CHARS["hondar"] = {}


def common_with(name, **bones):
    """Animation commune de poses.json avec des os ajoutés à chaque clé
    (ex. accessoire tenu replié pendant l'uppercut pour rester dans la cellule)."""
    with open(os.path.join(HERE, "poses.json")) as f:
        a = json.load(f)["anims"][name]
    for key in a["keys"]:
        key["p"] = {**key["p"], **bones}
    return a


CHARS["patxi"]["uppercut"] = common_with("uppercut", accf=120)
CHARS["ramuntxo"]["uppercut"] = common_with("uppercut", accf=160)


def main():
    for fid, anims in CHARS.items():
        anims = dict(anims)
        anims.setdefault("win", win())
        path = os.path.join(HERE, f"{fid}.json")
        with open(path, "w") as f:
            json.dump({"_doc": "Généré par gen_char_poses.py — ne pas éditer à la main.",
                       "anims": anims}, f, indent=1, ensure_ascii=False)
        print(path)


if __name__ == "__main__":
    main()
