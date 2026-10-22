class_name BkCoupLance
extends BkCoupActif
## Famille « lance » (GDD §4.2, §4.4) : un projectile part droit devant (direction de marche), avec
## l'aimant de ±aimant_deg vers une cible visible (BkCoups.vise), et vole jusqu'à portee cases. Les murs
## et les objets hauts l'arrêtent (couche de vue) ; il passe au-dessus des objets bas. Il touche la
## première cible à params.rayon_touche cases (hors cachette, GDD §4.2) et lui pose les effets du coup.
##
## Paramètres (coups.json → params) :
## - projectile : bouee, ligne, pelote, pierre, pot, faisceau (dessin du placeholder) ;
## - vitesse (cases/s), rayon_touche (cases) ;
## - ricochets : rebonds sur les murs (pelote de Xabi, portee = distance totale) ;
## - chercheuse : part vers la cible visible la plus proche (portee) et la suit (virage_deg_s) ;
## - faisceau : touche d'un coup tout ce qui est sur la ligne (jusqu'au premier mur), sans s'arrêter ;
## - nuage_rayon : à l'arrivée (cible, mur ou portée), nuage de nuage_rayon cases pendant duree s ; les
##   cibles dedans subissent les effets (une fois chacune), params.bulle_nuage au-dessus d'elles ;
## - cible = allie_en_detresse (bouée de Txomin) : vise le coéquipier en détresse (jauge ≥ detresse_jauge
##   ou sous un effet gênant) à portee cases, qu'on voit ; le touché est tracté jusqu'au lanceur (effet
##   d'aide) ; puis gerbe d'eau : chasseur à gerbe_portee cases du lanceur aveuglé (gerbe_effet,
##   gerbe_duree, masque gerbe_masque).
## Effets : params « vers » = « lanceur » (tracté vers lui), avec « distance » (cases) : tiré de cette
## distance seulement (ligne de Patxi).

enum Etat { VOL, NUAGE, FINI }

var etat: Etat = Etat.VOL
var pos: Vector2 = Vector2.ZERO
var vel: Vector2 = Vector2.RIGHT
var parcouru: float = 0.0
var rebonds: int = 0
var suivie: BkActor
var touche: BkActor
## Points du trajet (dessin de la pelote qui ricoche, du faisceau).
var trace: PackedVector2Array = PackedVector2Array()
var nuage_t: float = 0.0
var _dans_nuage: Dictionary = {}
var _fin_t: float = 0.0


func projectile() -> String:
	return str(param("projectile", ""))


func vitesse_px() -> float:
	return float(param("vitesse", 14.0)) * game.map.tile


func rayon_touche() -> float:
	return float(param("rayon_touche", 0.5)) * game.map.tile


func pour_allie() -> bool:
	return str(param("cible", "")) == "allie_en_detresse"


## Cibles possibles du projectile : adversaires libres, ou coéquipiers en détresse (bouée).
func cibles() -> Array[BkActor]:
	if pour_allie():
		var out: Array[BkActor] = []
		for a: BkActor in allies():
			if en_detresse(a):
				out.append(a)
		return out
	return moteur.adversaires(lanceur, coup)


func en_detresse(a: BkActor) -> bool:
	return a.gauge >= float(param("detresse_jauge", 0.3)) or BkEffets.gene_en_cours(a)


## Coéquipier en détresse le plus proche qu'on voit, à portée (bouée).
func allie_a_sauver() -> BkActor:
	var best: BkActor = null
	for a: BkActor in cibles():
		var d: float = a.position.distance_to(lanceur.position)
		if d <= portee_px() and d >= game.map.tile * 1.2 and voit(a) \
				and (best == null or d < best.position.distance_to(lanceur.position)):
			best = a
	return best


## La cible visible la plus proche à portée (pierre traqueuse).
func plus_proche_visible() -> BkActor:
	var best: BkActor = null
	for a: BkActor in cibles():
		var d: float = a.position.distance_to(lanceur.position)
		if d <= portee_px() and voit(a) and (best == null or d < best.position.distance_to(lanceur.position)):
			best = a
	return best


func possible() -> bool:
	if pour_allie():
		suivie = allie_a_sauver()
		return suivie != null
	return true


func raison() -> String:
	return "Personne à sauver" if pour_allie() else ""


func demarre() -> void:
	pos = lanceur.position
	trace = PackedVector2Array([pos])
	rebonds = int(param("ricochets", 0))
	if pour_allie():
		vel = (suivie.position - pos).normalized()
	elif bool(param("chercheuse", false)):
		suivie = plus_proche_visible()
		vel = (suivie.position - pos).normalized() if suivie != null else dir
	else:
		vel = moteur.vise(lanceur, dir, portee_px(), cibles(), -1.0, 0.0 if projectile() == "faisceau" else vitesse_px())["dir"]
	lanceur.look = vel.angle()
	if projectile() == "faisceau":
		_faisceau()


## Faisceau : d'un coup, jusqu'au premier mur (ou la portée) ; tout ce qui est sur la ligne est touché.
func _faisceau() -> void:
	var fin: Vector2 = _mur_entre(pos, pos + vel * portee_px())
	trace.append(fin)
	var seg: float = pos.distance_to(fin)
	for a: BkActor in cibles():
		if BkEffets.actif(a, "invisible"):
			continue
		var v: Vector2 = a.position - pos
		var long: float = v.dot(vel)
		if long < 0.0 or long > seg:
			continue
		if absf(v.cross(vel)) <= rayon_touche():
			effets_sur(a)
	etat = Etat.FINI
	_fin_t = float(param("trace_s", 0.5))


## Premier mur (couche de vue) entre a et b, b s'il n'y en a pas.
func _mur_entre(a: Vector2, b: Vector2) -> Vector2:
	var q: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(a, b, BkMap.LAYER_SIGHT)
	var hit: Dictionary = game.get_world_2d().direct_space_state.intersect_ray(q)
	return hit["position"] if not hit.is_empty() else b


func maj(dt: float) -> bool:
	t += dt
	match etat:
		Etat.VOL:
			_vole(dt)
		Etat.NUAGE:
			nuage_t += dt
			var r: float = float(param("nuage_rayon", 2.0)) * game.map.tile
			for a: BkActor in moteur.adversaires(lanceur, coup):
				if not _dans_nuage.has(a.id) and a.position.distance_to(pos) <= r:
					_dans_nuage[a.id] = true
					if effets_sur(a, {"au_sol": true}):
						moteur.bulle(a, str(param("bulle_nuage", "")), 3.0)
						bruit(a.position)
			if nuage_t >= duree():
				etat = Etat.FINI
				_fin_t = 0.4
		Etat.FINI:
			_fin_t -= dt
			return _fin_t > 0.0
	return true


func _vole(dt: float) -> void:
	# Pierre traqueuse : elle tourne vers sa cible tant qu'elle la voit.
	if suivie != null and (bool(param("chercheuse", false)) or pour_allie()):
		if suivie.role == BkActor.Role.HIDER and suivie.hidden_in < 0 and not BkEffets.actif(suivie, "invisible"):
			var want: float = (suivie.position - pos).angle()
			var turn: float = deg_to_rad(float(param("virage_deg_s", 720.0))) * dt
			vel = Vector2.from_angle(rotate_toward(vel.angle(), want, turn))
	var pas: float = minf(vitesse_px() * dt, portee_px() - parcouru)
	var but: Vector2 = pos + vel * pas
	var q: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(pos, but, BkMap.LAYER_SIGHT)
	var hit: Dictionary = game.get_world_2d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		var hp: Vector2 = hit["position"]
		parcouru += pos.distance_to(hp)
		if rebonds > 0:
			rebonds -= 1
			var n: Vector2 = hit["normal"]
			vel = vel.bounce(n).normalized()
			pos = hp + n * 2.0
			trace.append(pos)
		else:
			pos = hp - vel * 2.0
			trace.append(pos)
			_arrive()
			return
	else:
		parcouru += pas
		pos = but
	if _teste_cibles():
		return
	if parcouru >= portee_px() - 0.5:
		trace.append(pos)
		_arrive()


## Une cible sur le chemin ? Elle subit les effets ; le projectile s'arrête (ou crée son nuage).
func _teste_cibles() -> bool:
	for a: BkActor in cibles():
		if BkEffets.actif(a, "invisible") or a.position.distance_to(pos) > rayon_touche():
			continue
		touche = a
		if pour_allie():
			_bouee(a)
		else:
			effets_sur(a, _extra(a))
		trace.append(pos)
		_arrive()
		return true
	return false


## Paramètres calculés des effets : tracté « vers » le lanceur (de « distance » cases au plus).
func _extra(a: BkActor) -> Dictionary:
	var out: Dictionary = {}
	for e: Dictionary in coup.get("effets", []):
		var p: Dictionary = e.get("params", {})
		if str(p.get("vers", "")) == "lanceur":
			var v: Vector2 = lanceur.position - a.position
			var d: float = v.length() - game.map.tile * 0.8
			if p.has("distance"):
				d = minf(d, float(p["distance"]) * game.map.tile)
			out["vers"] = a.position + v.normalized() * maxf(d, 0.0)
	return out


## Bouée de Txomin : le coéquipier est tracté jusqu'à lui (aide), puis la gerbe d'eau masque l'écran du
## chasseur s'il est tout près.
func _bouee(a: BkActor) -> void:
	var extra: Dictionary = _extra(a)
	extra["aide"] = true
	effets_sur(a, extra)
	moteur.bulle(a, str(param("bulle", "")), 1.2)
	var h: BkActor = game.hunter
	if h != null and h.position.distance_to(lanceur.position) <= float(param("gerbe_portee", 4.0)) * game.map.tile:
		moteur.applique_effet(h, str(param("gerbe_effet", "aveugle")), float(param("gerbe_duree", 3.0)),
			{"masque": str(param("gerbe_masque", "eau"))}, lanceur)


func _arrive() -> void:
	if float(param("nuage_rayon", 0.0)) > 0.0:
		etat = Etat.NUAGE
		nuage_t = 0.0
		_dans_nuage.clear()
	else:
		etat = Etat.FINI
		_fin_t = float(param("trace_s", 0.35))


func interrompt() -> void:
	etat = Etat.FINI
	_fin_t = 0.0


func dessine(ci: CanvasItem, vue: Dictionary) -> void:
	if not visible_pour(vue) and etat == Etat.VOL:
		return
	var tile: float = game.map.tile
	var col: Color = couleur(Color("ffffff"))
	match projectile():
		"faisceau":
			if trace.size() >= 2:
				var k: float = clampf(_fin_t / maxf(float(param("trace_s", 0.5)), 0.01), 0.0, 1.0)
				var a: Vector2 = trace[0]
				var b: Vector2 = trace[1]
				var n: Vector2 = (b - a).orthogonal().normalized() * rayon_touche()
				ci.draw_colored_polygon(PackedVector2Array([a, b + n, b - n]), Color(col, 0.35 * k))
				ci.draw_line(a, b, Color(1, 1, 1, 0.9 * k), 3.0)
				ci.draw_line(a, b, Color(col, k), 1.0)
		"ligne":
			if etat == Etat.VOL or _fin_t > 0.0:
				var bout: Vector2 = pos if etat == Etat.VOL else (touche.position if touche != null and BkEffets.actif(touche, "tracte") else pos)
				ci.draw_line(lanceur.position + Vector2(0, -10), bout, Color("f0e6c8"), 1.0)
				ci.draw_arc(bout, 3.0, 0.0, PI * 1.5, 6, Color("c8ccd4"), 2.0)
		"bouee":
			if etat == Etat.VOL or _fin_t > 0.0:
				var bp: Vector2 = pos if etat == Etat.VOL else (touche.position if touche != null else pos)
				ci.draw_line(lanceur.position + Vector2(0, -8), bp, Color("f0e6c8"), 1.0)
				ci.draw_arc(bp, 6.0, 0.0, TAU, 16, BkDraw.INK, 5.0)
				ci.draw_arc(bp, 6.0, 0.0, TAU, 16, Color("e8392c"), 3.0)
				for i: int in 4:
					var ang: float = TAU * i / 4.0 + t * 6.0
					ci.draw_line(bp + Vector2.from_angle(ang) * 4.5, bp + Vector2.from_angle(ang) * 7.5, Color.WHITE, 2.0)
		"pelote", "pierre":
			if etat == Etat.VOL:
				# Traînée qui suit les ricochets.
				var pts: PackedVector2Array = trace.duplicate()
				pts.append(pos)
				if pts.size() >= 2:
					ci.draw_polyline(pts, Color(col, 0.35), 1.0)
				var rr: float = 4.0 if projectile() == "pelote" else 6.0
				ci.draw_circle(pos, rr + 1.0, BkDraw.INK)
				ci.draw_circle(pos, rr, col)
				var ang2: float = parcouru / maxf(rr, 1.0)
				ci.draw_line(pos, pos + Vector2.from_angle(ang2) * rr, BkDraw.INK, 1.0)
		"pot":
			if etat == Etat.VOL:
				var arc: float = sin(PI * clampf(parcouru / maxf(portee_px(), 1.0), 0.0, 1.0)) * tile * 0.6
				var pp: Vector2 = (pos + Vector2(0, -arc)).round()
				ci.draw_rect(Rect2(pp - Vector2(5, 5), Vector2(10, 10)), BkDraw.INK)
				ci.draw_rect(Rect2(pp - Vector2(4, 4), Vector2(8, 8)), Color("c62828"))
				ci.draw_rect(Rect2(pp - Vector2(4, 6), Vector2(8, 2)), Color("6b4a2a"))
	if etat == Etat.NUAGE or (etat == Etat.FINI and float(param("nuage_rayon", 0.0)) > 0.0 and _fin_t > 0.0):
		var r: float = float(param("nuage_rayon", 2.0)) * tile
		var k2: float = 1.0 if etat == Etat.NUAGE else clampf(_fin_t / 0.4, 0.0, 1.0)
		k2 *= clampf(nuage_t * 4.0, 0.0, 1.0)
		for i2: int in 7:
			var ang3: float = TAU * i2 / 7.0 + nuage_t * 0.6
			var c3: Vector2 = pos + Vector2.from_angle(ang3) * r * 0.55
			ci.draw_circle(c3, r * 0.5, Color(col, 0.22 * k2))
		ci.draw_circle(pos, r * 0.6, Color(col, 0.25 * k2))
		ci.draw_arc(pos, r, 0.0, TAU, 32, Color(col, 0.6 * k2), 1.0)


## IA. Chasseur : une cible vue à portée (direction vers elle) ; le faisceau et le pot partent aussi vers
## un indice récent (ctx.vers). Chassé (bouée) : un coéquipier en détresse à sauver.
func ia_utile(ctx: Dictionary) -> bool:
	if pour_allie():
		return possible()
	var cible: BkActor = ctx.get("cible", null)
	if cible != null and cible.position.distance_to(lanceur.position) <= portee_px() * 0.95 and voit(cible):
		dir = (cible.position - lanceur.position).normalized()
		return true
	var vers: Vector2 = ctx.get("vers", Vector2.INF)
	if bool(param("sans_cible_ok", false)) and bool(ctx.get("cible_probable", false)) and vers != Vector2.INF \
			and vers.distance_to(lanceur.position) <= portee_px() and vers.distance_to(lanceur.position) > game.map.tile:
		dir = (vers - lanceur.position).normalized()
		return true
	return false
