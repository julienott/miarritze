class_name BkCoupDeplacement
extends BkCoupActif
## Famille « deplacement » (GDD §4.4) : le lanceur bouge ou change d'état selon params.mode. Codé à
## l'étape 3 : « saut » (Passe-Muraille de Louis). Les autres modes (dash, plongeon, vol,
## enfouissement, glissade, vitesse) viendront à l'étape 4 ; d'ici là leurs coups sont « bientôt ».
##
## Saut : par-dessus l'obstacle de la case devant (lettres de params.franchit : muret, buisson, grille,
## cloisons fines), vers la case libre juste derrière. Direction de marche ramenée à l'axe de la grille le
## plus proche (puis l'autre axe si le regard est en biais). Pendant duree s, le lanceur passe au-dessus
## (sans collision, hauteur params.hauteur_px) et joue jump_hide ; il casse ainsi la ligne de vue.

## Part minimale de l'autre axe du regard pour essayer aussi cette direction (regard en biais).
const BIAIS_MIN: float = 0.35

var _de: Vector2 = Vector2.ZERO
var _vers: Vector2 = Vector2.INF
var _fini: bool = false


func mode() -> String:
	return str(param("mode", ""))


func possible() -> bool:
	match mode():
		"saut":
			_vers = Vector2.INF
			for d: Vector2i in directions(dir):
				var v: Vector2 = saut_vers(d)
				if v != Vector2.INF:
					_de = lanceur.position
					_vers = v
					return true
	return false


func raison() -> String:
	return "Rien à franchir devant" if mode() == "saut" else ""


## Directions de la grille à essayer pour un regard `v` : l'axe dominant, puis l'autre s'il compte.
static func directions(v: Vector2) -> Array[Vector2i]:
	var hx: Vector2i = Vector2i(int(signf(v.x)), 0)
	var vy: Vector2i = Vector2i(0, int(signf(v.y)))
	var a: Vector2 = v.normalized()
	var x_dabord: bool = absf(a.x) >= absf(a.y)
	var out: Array[Vector2i] = []
	out.append(hx if x_dabord else vy)
	var autre: Vector2i = vy if x_dabord else hx
	if absf(a.y if x_dabord else a.x) >= BIAIS_MIN and autre != Vector2i.ZERO:
		out.append(autre)
	return out


## Point d'arrivée d'un saut dans la direction `d`, Vector2.INF si la case devant n'est pas un obstacle
## franchissable ou si la case derrière n'est pas libre. On garde sa place le long de l'obstacle,
## sans toucher les bords de la case d'arrivée.
func saut_vers(d: Vector2i) -> Vector2:
	var m: BkMap = game.map
	var t0: Vector2i = m.to_tile(lanceur.position)
	var t1: Vector2i = t0 + d
	var t2: Vector2i = t0 + d * 2
	if not str(param("franchit", "")).contains(m.at(t1)) or m.walkable(t1) or not m.walkable(t2):
		return Vector2.INF
	var c2: Vector2 = m.center(t2)
	var p: Vector2 = lanceur.position
	var marge: float = maxf(0.0, m.tile * 0.5 - lanceur.radius - 1.0)
	if d.x != 0:
		return Vector2(c2.x, clampf(p.y, c2.y - marge, c2.y + marge))
	return Vector2(clampf(p.x, c2.x - marge, c2.x + marge), c2.y)


func demarre() -> void:
	lanceur.en_coup = true
	lanceur.collision_mask = 0
	lanceur.look = (_vers - _de).angle()
	lanceur.play_once("saut")


func maj(dt: float) -> bool:
	if _fini:
		return false
	t += dt
	var k: float = clampf(t / maxf(duree(), 0.05), 0.0, 1.0)
	if lanceur.role != BkActor.Role.HIDER and lanceur.role != BkActor.Role.HUNTER:
		_fin(false)                         # trouvé en plein saut : il s'envole d'où il est
		return false
	lanceur.position = _de.lerp(_vers, k)
	lanceur.saut_px = sin(PI * k) * float(param("hauteur_px", 20.0))
	if k >= 1.0:
		_fin(true)
		return false
	return true


func _fin(arrive: bool) -> void:
	_fini = true
	if arrive:
		lanceur.position = _vers
	lanceur.saut_px = 0.0
	lanceur.en_coup = false
	lanceur.set_role(lanceur.role)           # collisions selon le rôle
	lanceur.velocity = Vector2.ZERO


func interrompt() -> void:
	if not _fini:
		_fin(lanceur.role == BkActor.Role.HIDER or lanceur.role == BkActor.Role.HUNTER)


## IA (chassé en danger) : un obstacle à franchir qui casse la ligne de vue du chasseur, ou qui
## éloigne de lui d'au moins une demi-case.
func ia_utile(ctx: Dictionary) -> bool:
	if mode() != "saut" or not bool(ctx.get("menace", false)) or game.hunter == null:
		return false
	var h: Vector2 = game.hunter.position
	var best: Vector2i = Vector2i.ZERO
	var bs: float = -INF
	for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var v: Vector2 = saut_vers(d)
		if v == Vector2.INF:
			continue
		var gain: float = (v.distance_to(h) - lanceur.position.distance_to(h)) / game.map.tile
		var s: float = gain + (10.0 if not game.clear_line(h, v) else 0.0)
		if (s >= 10.0 or gain >= 0.5) and s > bs:
			bs = s
			best = d
	if best == Vector2i.ZERO:
		return false
	dir = Vector2(best)
	return true
