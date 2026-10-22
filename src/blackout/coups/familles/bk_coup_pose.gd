class_name BkCoupPose
extends BkCoupActif
## Famille « pose » (GDD §4.4) : un objet posé qui agit tant qu'il est là (duree s), selon params.objet.
## params.position : « pieds » (sous le lanceur) ou « derriere » (une case derrière lui, à l'opposé de sa
## direction de marche).
##
## - « gateau » (Gâteau du partage de Ramuntxo) : le premier qui passe à portee cases le déclenche
##   (params.usages) ; chacun subit les effets du coup dont params.cible est son rôle (« chasseur » :
##   figé à humer le gâteau ; « chasse » : bonus de vitesse). Le lanceur ne le déclenche pas.
## - « seau » (Appât de sardines de Patxi) : zone de params.rayon cases ; le chasseur qui y entre voit
##   pendant effet_duree s de fausses traces de pas qui partent ailleurs et des mouettes fantômes ; le
##   chasseur IA croit entendre quelqu'un là où vont les traces. Compte comme un coup qui touche le
##   chasseur (GDD §2.3). Une fois.
## - « muret » (Bâtisse éclair d'Itsaso) : params.largeur cases de mur, perpendiculaires à la marche,
##   une case derrière ; il bloque la vue et le passage (BkMap.bloque_temporaire) ; les cases occupées
##   par un perso sont sautées.

var pos: Vector2 = Vector2.ZERO
var usages: int = 0
var cases: Array[Vector2i] = []
var _bloc: Dictionary = {}
## Seau : leurre en cours (s restantes), fausses traces et mouettes fantômes.
var leurre: float = 0.0
var faux_pas: Array = []
var faux_but: Vector2 = Vector2.INF
var _dernier_faux: Vector2 = Vector2.INF
var _cote: float = 1.0
var _fini: bool = false


func objet() -> String:
	return str(param("objet", ""))


## Axe de la grille dans la direction de marche.
func axe() -> Vector2i:
	return BkCoupDeplacement.directions(dir)[0] if dir.length() > 0.01 else Vector2i(1, 0)


func possible() -> bool:
	if objet() == "muret":
		cases = cases_muret()
		return not cases.is_empty()
	return true


func raison() -> String:
	return "Pas de place derrière" if objet() == "muret" else ""


## Cases du muret : une ligne de params.largeur cases, une case derrière le lanceur, perpendiculaire à
## sa marche ; seulement du sol libre, sans perso dessus.
func cases_muret() -> Array[Vector2i]:
	var m: BkMap = game.map
	var ax: Vector2i = axe()
	var c0: Vector2i = m.to_tile(lanceur.position) - ax
	var perp: Vector2i = Vector2i(ax.y, ax.x)
	var n: int = int(param("largeur", 3))
	var out: Array[Vector2i] = []
	for i: int in n:
		var c: Vector2i = c0 + perp * (i - (n - 1) / 2)
		if not m.walkable(c) or game.map.cachettes.has(c):
			continue
		var libre: bool = true
		var r: Rect2 = Rect2(Vector2(c) * m.tile, Vector2(m.tile, m.tile))
		for a: BkActor in game.actors:
			if a.role == BkActor.Role.HIDER or a.role == BkActor.Role.HUNTER:
				var proche: Vector2 = Vector2(clampf(a.position.x, r.position.x, r.end.x), clampf(a.position.y, r.position.y, r.end.y))
				if proche.distance_to(a.position) < a.radius:
					libre = false
		if libre:
			out.append(c)
	return out


func demarre() -> void:
	var m: BkMap = game.map
	pos = lanceur.position
	if str(param("position", "pieds")) == "derriere" and objet() != "muret":
		var p: Vector2 = trajet(-dir * float(param("recul", 1.0)) * m.tile)
		pos = p
	match objet():
		"muret":
			_bloc = m.bloque_temporaire(cases)
		"seau":
			pos += Vector2(0, lanceur.feet_dy())


func maj(dt: float) -> bool:
	if _fini:
		return false
	t += dt
	match objet():
		"gateau":
			if t >= duree():
				return _termine()
			for a: BkActor in game.actors:
				if a == lanceur or a.hidden_in >= 0 or a.position.distance_to(pos) > portee_px():
					continue
				var role: String = "chasseur" if a.role == BkActor.Role.HUNTER else ("chasse" if a.role == BkActor.Role.HIDER else "")
				if role == "":
					continue
				var pris: bool = false
				for e: Dictionary in coup.get("effets", []):
					if str((e.get("params", {}) as Dictionary).get("cible", "")) == role and effet(a, e):
						pris = true
				if pris:
					moteur.bulle(a, str(param("bulle_chasseur" if role == "chasseur" else "bulle_chasse", "")), 1.5)
					usages += 1
					if usages >= int(param("usages", 1)):
						return _termine()
		"seau":
			var h: BkActor = game.hunter
			if leurre > 0.0:
				leurre -= dt
				_trace_fausse(dt)
				for p: Dictionary in faux_pas:
					p["age"] = float(p["age"]) + dt
				return leurre > 0.0
			if t >= duree():
				return _termine()
			if h != null and h.role == BkActor.Role.HUNTER and h.position.distance_to(pos) <= float(param("rayon", 1.5)) * game.map.tile:
				_declenche(h)
		"muret":
			if t >= duree():
				return _termine()
	return true


## Seau : le chasseur entre dans la zone : fausses traces vers une case libre loin du lanceur.
func _declenche(h: BkActor) -> void:
	leurre = float(param("effet_duree", 3.0))
	game.chasseur_touche(lanceur)
	game.coup_touche(lanceur, coup)
	moteur.bulle(h, str(param("bulle", "")), 1.5)
	var m: BkMap = game.map
	var loin: Vector2 = (pos - lanceur.position).normalized()
	if loin == Vector2.ZERO:
		loin = Vector2.from_angle(h.look)
	var best: Vector2 = Vector2.INF
	var bs: float = -INF
	var t0: Vector2i = m.to_tile(pos)
	for dy: int in range(-6, 7):
		for dx: int in range(-6, 7):
			var c: Vector2i = t0 + Vector2i(dx, dy)
			var d: float = Vector2(dx, dy).length()
			if d < 4.0 or d > 6.5 or not m.walkable(c):
				continue
			var s: float = m.center(c).distance_to(lanceur.position) / m.tile + (Vector2(dx, dy).normalized().dot(loin)) * 2.0
			if s > bs:
				bs = s
				best = m.center(c)
	faux_but = best if best != Vector2.INF else pos
	_dernier_faux = pos
	if game.brains.has(h.id):
		(game.brains[h.id] as BkAi).on_noise(faux_but)


## Fausses traces : une empreinte de plus en plus loin, vers faux_but, au rythme d'un marcheur.
func _trace_fausse(dt: float) -> void:
	if faux_but == Vector2.INF or _dernier_faux.distance_to(faux_but) < 4.0:
		return
	var v: Vector2 = (faux_but - _dernier_faux).normalized()
	var p: Vector2 = _dernier_faux + v * BkRules.px("speed_hider") * dt
	if p.distance_to(_dernier_faux) > 0.0 and (faux_pas.is_empty() or p.distance_to((faux_pas.back() as Dictionary)["pos"]) >= 0.45 * game.map.tile):
		faux_pas.append({"pos": p, "dir": v, "cote": _cote, "age": 0.0})
		_cote = -_cote
	_dernier_faux = p


func _termine() -> bool:
	_fini = true
	if objet() == "muret":
		game.map.libere_temporaire(_bloc)
	return false


func interrompt() -> void:
	if not _fini:
		_termine()


func dessine(ci: CanvasItem, vue: Dictionary) -> void:
	if _fini:
		return
	var tile: float = game.map.tile
	match objet():
		"gateau":
			# Gâteau sur une assiette rose (distinct des gâteaux-recharges), petit drapeau basque.
			var gp: Vector2 = (pos + Vector2(0, lanceur.feet_dy())).round()
			BkDraw.ellipse(ci, gp + Vector2(0, 2), 9, 3, Color("ff8fc8"))
			BkDraw.ellipse(ci, gp, 7, 4, Color("b5772a"))
			BkDraw.ellipse(ci, gp + Vector2(0, -1), 6, 3, Color("e7b45a"))
			ci.draw_line(gp + Vector2(3, -2), gp + Vector2(3, -12), BkDraw.INK, 1.0)
			ci.draw_rect(Rect2(gp + Vector2(4, -12), Vector2(6, 4)), Color("c62828"))
			ci.draw_rect(Rect2(gp + Vector2(4, -10), Vector2(6, 1)), Color("2e7d32"))
			var k: float = clampf(1.0 - t / maxf(duree(), 0.1), 0.0, 1.0)
			ci.draw_arc(gp, portee_px(), 0.0, TAU, 32, Color(1, 0.6, 0.8, 0.25 + 0.2 * k), 1.0)
		"seau":
			if leurre <= 0.0:
				# Le seau se voit de tous (un objet posé au sol, comme les gâteaux).
				var sp: Vector2 = pos.round()
				ci.draw_arc(sp, float(param("rayon", 1.5)) * tile, 0.0, TAU, 32, Color(0.6, 0.85, 1.0, 0.35), 1.0)
				ci.draw_rect(Rect2(sp - Vector2(6, 10), Vector2(12, 10)), BkDraw.INK)
				ci.draw_rect(Rect2(sp - Vector2(5, 9), Vector2(10, 8)), Color("9aa4b0"))
				ci.draw_rect(Rect2(sp - Vector2(5, 9), Vector2(10, 2)), Color("cfd8e0"))
				for i: int in 3:
					ci.draw_rect(Rect2(sp + Vector2(-8 + i * 6, 1 + (i % 2)), Vector2(4, 1)), Color("c8d4e0"))
			elif vue.get("local") == game.hunter or bool(vue.get("fantome", false)) or BkEffetsRendu.qa:
				# Ce que voit le chasseur leurré : des pas qui partent et des mouettes qui s'envolent.
				BkCoupRevele.dessine_pas(ci, faux_pas, float(param("effet_duree", 3.0)) + 1.0, 3.0)
				var k2: float = clampf(leurre / maxf(float(param("effet_duree", 3.0)), 0.1), 0.0, 1.0)
				for j: int in 3:
					var bp: Vector2 = (pos + Vector2(-10 + j * 10, -tile * (1.6 - k2) - j * 4)).round()
					ci.draw_polyline(PackedVector2Array([bp + Vector2(-4, -1), bp, bp + Vector2(4, -1)]), Color(1, 1, 1, k2), 1.0)
				BkDraw.texte(ci, pos + Vector2(0, -tile * (1.8 - k2)), "kaio !", 8, Color(1, 1, 1, k2), 2, 60.0)
		"muret":
			# Muret de pierre qui jaillit du sol, puis s'effrite à la fin.
			var monte: float = clampf(t / 0.25, 0.0, 1.0)
			var reste: float = clampf((duree() - t) / 0.3, 0.0, 1.0)
			var h: float = roundf(tile * 0.5 * monte * reste) + 2.0
			for c: Vector2i in cases:
				var r: Rect2 = Rect2(Vector2(c) * tile, Vector2(tile, tile))
				var face: Rect2 = Rect2(r.position + Vector2(0, tile - h), Vector2(tile, h))
				ci.draw_rect(Rect2(r.position + Vector2(0, tile * 0.5 - h * 0.5), Vector2(tile, tile * 0.5 + h * 0.5)), BkDraw.INK)
				ci.draw_rect(Rect2(r.position + Vector2(1, tile * 0.5 - h * 0.5 + 1), Vector2(tile - 2, tile * 0.5 - 2)), Color("9a9488"))
				ci.draw_rect(Rect2(face.position + Vector2(1, 0), Vector2(tile - 2, h - 1)), Color("6e695f"))
				for k3: int in 3:
					ci.draw_rect(Rect2(r.position + Vector2(4 + k3 * 10, tile * 0.5 - h * 0.5 + 4 + (k3 % 2) * 5), Vector2(6, 1)), Color("c8c2b4"))


## IA du chassé en danger : le seau et le muret entre lui et le chasseur (direction : à l'opposé du
## chasseur), le gâteau quand le chasseur approche (à 6 cases).
func ia_utile(ctx: Dictionary) -> bool:
	var h: BkActor = game.hunter
	if h == null or lanceur.role != BkActor.Role.HIDER:
		return false
	if not (bool(ctx.get("menace", false)) or bool(ctx.get("urgence", false))):
		return false
	var d: float = h.position.distance_to(lanceur.position)
	match objet():
		"gateau":
			return d <= game.map.tile * 6.0 and d >= game.map.tile * 2.0
		"seau", "muret":
			if d > game.map.tile * 8.0:
				return false
			dir = (lanceur.position - h.position).normalized()
			return possible()
	return false
