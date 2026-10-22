class_name BkCoupDeplacement
extends BkCoupActif
## Famille « deplacement » (GDD §4.4) : le lanceur bouge ou change d'état selon params.mode ; les effets
## du coup (coups.json → effets) sont posés sur le lanceur lui-même au départ.
##
## - « saut » (Passe-Muraille de Louis) : par-dessus l'obstacle de la case devant (lettres de
##   params.franchit : muret, buisson, grille, cloisons fines), vers la case libre juste derrière.
##   Direction de marche ramenée à l'axe de la grille le plus proche (puis l'autre axe si le regard est en
##   biais). Pendant duree s, le lanceur passe au-dessus (sans collision, hauteur params.hauteur_px).
## - « dash » (Rebond d'urgence de Xabi, Débordement crabe de Karramarro, Le canard de Maïa) : glisse de
##   portee cases en params.glisse_s s (duree sinon), arrêté par ce qui bloque le passage, à travers les
##   persos. params.repousse_mur : collé à un mur (params.mur_cases), à l'opposé du plus proche.
##   Le canard : ses effets (invisible, insensible) durent plus que la glissade.
## - « vitesse » (Take-off de Maïa, Mutxiko d'Amaia) : les effets seuls (rapide, insensible au sol…).
## - « vol » (Battement de plumes de Kaio) : duree s au-dessus des obstacles bas (lettres de
##   params.franchit) ; il se dirige lui-même, plus haut que le sol (params.hauteur_px) ; à la fin il se
##   pose sur la case libre la plus proche.
## - « enfouissement » (Karramarro) : seulement sur le sol meuble (lettres params.sol) ; invisible et
##   indétectable tant qu'il ne bouge pas, duree s au plus ; s'il bouge, il ressort avec un bruit de sable
##   (params.bulle, entendu par le chasseur IA).

## Part minimale de l'autre axe du regard pour essayer aussi cette direction (regard en biais).
const BIAIS_MIN: float = 0.35
## Commande qui compte comme « il bouge » (enfoui), part de la vitesse.
const BOUGE_MIN: float = 0.3

var _de: Vector2 = Vector2.ZERO
var _vers: Vector2 = Vector2.INF
var _fini: bool = false
## Vol d'un perso IA : point visé (il vole droit dessus).
var _cible_vol: Vector2 = Vector2.INF


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
		"dash":
			if bool(param("repousse_mur", false)):
				var mur: Vector2 = mur_proche()
				if mur != Vector2.ZERO:
					dir = -mur
			_de = lanceur.position
			_vers = trajet(dir * portee_px())
			return _vers.distance_to(_de) >= game.map.tile * 0.25
		"enfouissement":
			return str(param("sol", BkMap.MEUBLE)).contains(game.map.at(game.map.to_tile(lanceur.position)))
		"vitesse", "vol":
			return true
	return false


func raison() -> String:
	match mode():
		"saut":
			return "Rien à franchir devant"
		"dash":
			return "Pas de place devant"
		"enfouissement":
			return "Pas de sable ici"
	return ""


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


## Mur collé au lanceur (direction de la grille vers lui, à params.mur_cases cases au plus de son
## bord), Vector2.ZERO s'il n'y en a pas.
func mur_proche() -> Vector2:
	var best: Vector2 = Vector2.ZERO
	var bd: float = float(param("mur_cases", 0.35)) * game.map.tile
	for d: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.DOWN, Vector2.UP]:
		var v: Vector2 = d * game.map.tile
		var reste: float = trajet(v).distance_to(lanceur.position)
		if reste < bd:
			bd = reste
			best = d
	return best


## Durée de la glissade (dash) : params.glisse_s, sinon duree.
func glisse_s() -> float:
	return float(param("glisse_s", duree()))


func demarre() -> void:
	effets_sur(lanceur)
	match mode():
		"saut":
			lanceur.en_coup = true
			lanceur.collision_mask = 0
			lanceur.look = (_vers - _de).angle()
			lanceur.play_once("saut")
		"dash":
			lanceur.en_coup = true
			lanceur.look = dir.angle()
			lanceur.play_once("saut")
		"vol":
			lanceur.en_coup = true
			lanceur.collision_mask = 0
			lanceur.play_once("saut")
		"enfouissement":
			_de = lanceur.position
			bulle_param(lanceur, "bulle_entre", 1.0)


func maj(dt: float) -> bool:
	if _fini:
		return false
	t += dt
	if not en_jeu():
		_fin(false)                         # trouvé en plein coup : il s'envole d'où il est
		return false
	match mode():
		"saut":
			var k: float = clampf(t / maxf(duree(), 0.05), 0.0, 1.0)
			lanceur.position = _de.lerp(_vers, k)
			lanceur.saut_px = sin(PI * k) * float(param("hauteur_px", 20.0))
			if k >= 1.0:
				_fin(true)
				return false
		"dash":
			var k2: float = clampf(t / maxf(glisse_s(), 0.05), 0.0, 1.0)
			lanceur.position = _de.lerp(_vers, 1.0 - pow(1.0 - k2, 2.0))
			lanceur.saut_px = sin(PI * k2) * float(param("hauteur_px", 0.0))
			if k2 >= 1.0:
				_fin(true)
				return false
		"vol":
			_vole(dt)
			if t >= duree() and _se_pose(dt):
				return false
			if t >= duree() + float(param("vol_rab_s", 1.0)):
				_fin(true)
				return false
		"enfouissement":
			# Il bouge (ou on le déplace) : il ressort, avec un bruit de sable.
			var bouge: bool = lanceur.commande.length() > BOUGE_MIN or lanceur.position.distance_to(_de) > 2.0
			if bouge or t >= duree() or not BkEffets.actif(lanceur, "invisible"):
				_fin(true)
				return false
		"vitesse":
			return t < duree()
	return true


## Vol : déplacement libre au-dessus des obstacles bas. Un perso IA vole droit sur le point choisi.
func _vole(dt: float) -> void:
	var m: BkMap = game.map
	var move: Vector2 = lanceur.commande
	if lanceur.is_bot and _cible_vol != Vector2.INF:
		var v: Vector2 = _cible_vol - lanceur.position
		move = v.normalized() if v.length() > 4.0 else Vector2.ZERO
	lanceur.saut_px = float(param("hauteur_px", 12.0)) + sin(t * 9.0) * 2.0
	if move.length() < 0.1:
		return
	lanceur.look = rotate_toward(lanceur.look, move.angle(), deg_to_rad(BkRules.f("turn_speed_deg")) * dt)
	var step: Vector2 = move.limit_length(1.0) * lanceur.speed() * dt
	# Axe par axe : on avance tant que le bord du corps reste sur du sol ou un obstacle bas franchissable.
	for axe: Vector2 in [Vector2(step.x, 0.0), Vector2(0.0, step.y)]:
		if axe.length() < 0.001:
			continue
		var bord: Vector2 = lanceur.position + axe + axe.normalized() * lanceur.radius
		if _survolable(m.to_tile(bord)):
			lanceur.position += axe


func _survolable(t2: Vector2i) -> bool:
	var m: BkMap = game.map
	return m.walkable(t2) or str(param("franchit", "")).contains(m.at(t2))


## Fin du vol : posé si la case est libre (sinon il vole encore un peu, vers la case libre la plus proche).
func _se_pose(dt: float) -> bool:
	var m: BkMap = game.map
	var t0: Vector2i = m.to_tile(lanceur.position)
	if m.walkable(t0):
		_fin(true)
		return true
	var best: Vector2i = t0
	var bd: float = INF
	for dy: int in range(-2, 3):
		for dx: int in range(-2, 3):
			var c: Vector2i = t0 + Vector2i(dx, dy)
			if m.walkable(c) and m.center(c).distance_to(lanceur.position) < bd:
				bd = m.center(c).distance_to(lanceur.position)
				best = c
	_cible_vol = m.center(best)
	if lanceur.position.distance_to(_cible_vol) < 3.0:
		lanceur.position = _cible_vol
		_fin(true)
		return true
	# Pilote automatique vers la case libre (même pour un joueur) : glisse en ligne droite.
	lanceur.position = lanceur.position.move_toward(_cible_vol, lanceur.speed() * dt)
	return false


func _fin(arrive: bool) -> void:
	_fini = true
	if arrive and (mode() == "saut" or mode() == "dash"):
		lanceur.position = _vers
	if mode() == "enfouissement":
		if BkEffets.actif(lanceur, "invisible"):
			lanceur.effets.erase("invisible")
		if en_jeu():
			bulle_param(lanceur, "bulle", 1.2)
			bruit(lanceur.position)
	lanceur.saut_px = 0.0
	lanceur.en_coup = false
	lanceur.set_role(lanceur.role)           # collisions selon le rôle
	lanceur.velocity = Vector2.ZERO


func interrompt() -> void:
	if not _fini:
		_fin(en_jeu())


func garde_immobile() -> bool:
	return mode() == "enfouissement" and not _fini


func dessine(ci: CanvasItem, vue: Dictionary) -> void:
	if _fini or not visible_pour(vue):
		return
	var tile: float = game.map.tile
	var pieds: Vector2 = lanceur.position + Vector2(0, lanceur.feet_dy())
	match mode():
		"dash":
			# Traînée : trois silhouettes de poussière sur le trajet.
			for i: int in 3:
				var k: float = clampf(t / maxf(glisse_s(), 0.05) - 0.15 * (i + 1), 0.0, 1.0)
				var p: Vector2 = _de.lerp(_vers, k) + Vector2(0, lanceur.feet_dy())
				BkDraw.ellipse(ci, p.round(), roundf(tile * (0.3 - 0.06 * i)), roundf(tile * 0.1), Color(1, 1, 1, 0.35 - 0.1 * i))
		"vol":
			# Ailes qui battent au-dessus des épaules et ombre au sol.
			BkDraw.ellipse(ci, pieds.round(), roundf(tile * 0.3), roundf(tile * 0.1), Color(0, 0, 0, 0.35))
			var haut: Vector2 = lanceur.position + Vector2(0, lanceur.name_y() + 8.0)
			var b: float = sin(t * 18.0) * 4.0
			for s: float in [-1.0, 1.0]:
				ci.draw_colored_polygon(PackedVector2Array([haut + Vector2(s * 4, 4), haut + Vector2(s * 16, -4 + b),
					haut + Vector2(s * 12, 6 + b * 0.5)]), Color("e8eef2"))
				ci.draw_polyline(PackedVector2Array([haut + Vector2(s * 4, 4), haut + Vector2(s * 16, -4 + b),
					haut + Vector2(s * 12, 6 + b * 0.5), haut + Vector2(s * 4, 4)]), BkDraw.INK, 1.0)
		"enfouissement":
			# Seul son joueur (et les fantômes) voit le petit tas de sable : rien pour les autres.
			if vue.get("local") != lanceur and not bool(vue.get("fantome", false)) and not BkEffetsRendu.qa:
				return
			BkDraw.ellipse(ci, pieds.round(), roundf(tile * 0.42), roundf(tile * 0.16), Color("c9b27e"))
			BkDraw.ellipse(ci, (pieds + Vector2(-3, -2)).round(), roundf(tile * 0.2), roundf(tile * 0.07), Color("e0cc98"))
			var k3: float = clampf(1.0 - t / maxf(duree(), 0.1), 0.0, 1.0)
			ci.draw_arc(pieds + Vector2(0, -tile * 0.9), 5.0, -PI * 0.5, -PI * 0.5 + TAU * k3, 12, Color("ffd34a"), 2.0)


## IA : chassé en danger, chasseur qui tient une cible (glissade, take-off), selon le mode.
func ia_utile(ctx: Dictionary) -> bool:
	var h: BkActor = game.hunter
	var cible: BkActor = ctx.get("cible", null)
	var menace: bool = bool(ctx.get("menace", false)) or bool(ctx.get("urgence", false))
	match mode():
		"saut":
			return menace and _ia_saut()
		"dash":
			if lanceur.role == BkActor.Role.HUNTER:
				# Glissade : jaillir sur une cible vue, ou vers l'indice récent (angle mort), à portée.
				var but: Vector2 = cible.position if cible != null else ctx.get("vers", Vector2.INF)
				if but == Vector2.INF or not bool(ctx.get("cible_probable", false)):
					return false
				var v: Vector2 = but - lanceur.position
				if v.length() > portee_px() * 1.2 or v.length() < game.map.tile * 1.5:
					return false
				dir = v.normalized()
				return possible()
			return menace and h != null and _ia_fuite()
		"vitesse":
			if lanceur.role == BkActor.Role.HUNTER:
				# Take-off : rattraper une cible vue, ou filer vers un indice lointain.
				var vers: Vector2 = ctx.get("vers", Vector2.INF)
				if cible != null:
					return cible.position.distance_to(lanceur.position) > game.map.tile * 2.0
				return bool(ctx.get("cible_probable", false)) and vers != Vector2.INF \
					and vers.distance_to(lanceur.position) > game.map.tile * 4.0
			return menace
		"vol":
			return menace and h != null and _ia_vol()
		"enfouissement":
			return menace and possible()
	return false


## IA du saut : un obstacle à franchir qui casse la ligne de vue du chasseur, ou qui éloigne de lui d'au
## moins une demi-case.
func _ia_saut() -> bool:
	if game.hunter == null:
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


## IA de la glissade d'un chassé (dash, plongeon) : la direction qui l'éloigne le plus du chasseur ou
## casse sa ligne de vue (au moins une case de gagnée). Collé à un mur (Xabi), la direction est imposée.
func _ia_fuite() -> bool:
	var h: Vector2 = game.hunter.position
	var loin: Vector2 = (lanceur.position - h).normalized()
	if loin == Vector2.ZERO:
		loin = Vector2.from_angle(lanceur.look)
	var essais: Array[Vector2] = [loin, loin.rotated(PI * 0.5), loin.rotated(-PI * 0.5), loin.rotated(PI * 0.25),
		loin.rotated(-PI * 0.25)]
	if bool(param("repousse_mur", false)) and mur_proche() != Vector2.ZERO:
		essais = [-mur_proche()]
	var best: Vector2 = Vector2.ZERO
	var bs: float = -INF
	for d: Vector2 in essais:
		var fin: Vector2 = trajet(d * portee_px())
		var gain: float = (fin.distance_to(h) - lanceur.position.distance_to(h)) / game.map.tile
		var s: float = gain + (4.0 if not game.clear_line(h, fin) else 0.0)
		if fin.distance_to(lanceur.position) >= game.map.tile and s >= 1.0 and s > bs:
			bs = s
			best = d
	if best == Vector2.ZERO:
		return false
	dir = best
	return true


## IA du vol : une case libre à 3 à 5 cases, plus loin du chasseur, qu'on atteint en ligne droite en
## survolant (le plus souvent au-dessus d'un obstacle bas que le chasseur doit contourner).
func _ia_vol() -> bool:
	var m: BkMap = game.map
	var h: Vector2 = game.hunter.position
	var t0: Vector2i = m.to_tile(lanceur.position)
	var best: Vector2 = Vector2.INF
	var bs: float = -INF
	for dy: int in range(-5, 6):
		for dx: int in range(-5, 6):
			var c: Vector2i = t0 + Vector2i(dx, dy)
			var n: float = Vector2(dx, dy).length()
			if n < 2.5 or n > 5.5 or not m.walkable(c):
				continue
			var p: Vector2 = m.center(c)
			var survole: int = 0
			var ok: bool = true
			for i: int in range(1, 12):
				var tt: Vector2i = m.to_tile(lanceur.position.lerp(p, i / 12.0))
				if not _survolable(tt):
					ok = false
					break
				if not m.walkable(tt):
					survole += 1
			if not ok:
				continue
			var s: float = (p.distance_to(h) - lanceur.position.distance_to(h)) / m.tile + (3.0 if survole > 0 else 0.0) \
				+ (4.0 if not game.clear_line(h, p) else 0.0)
			if s > bs:
				bs = s
				best = p
	if best == Vector2.INF or bs < 2.0:
		return false
	_cible_vol = best
	dir = (best - lanceur.position).normalized()
	return true
