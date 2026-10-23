class_name BkFoule
extends Node
## PNJ, la foule de la nuit (GDD-BLACKOUT.md §3.8), version de base de la carte #647 : des humains de la
## bibliothèque §8.4 (data/blackout/pnj.json) qui vivent leur vie sur la carte. Jouée par l'hôte.
##
## - Nombre : pnj_nombre (rules.json, réglable par carte) ; sets réels d'abord (assets/blackout/pnj/,
##   set.json sans « placeholder »), complétés par des placeholders ; jamais un des 13 persos jouables.
## - Vie : activité sur place (une de ses 2 activités, en boucle), puis marche vers une autre case ;
##   une part pnj_fixes reste sur place tout le round.
## - Réactions : sursaut quand la lumière se coupe dans leur secteur, puis fuite vers une case éclairée ;
##   sursaut puis fuite (run) loin d'un coup spécial lancé à moins de pnj_fuite_portee cases.
## - Ce sont des BkActor (même BkPerso : tri en profondeur avec le décor, ombre au sol, nuit et lumières,
##   silhouette dans l'ombre vue du chasseur) hors de BkGame.actors : ni chassés ni chasseurs, sans
##   pseudo, sur aucune couche de collision (on les traverse ; eux glissent sur les murs).
## - Vus du chasseur comme un chassé : seulement dans son cône ou son petit cercle, en silhouette dans
##   l'ombre. Le camouflage dans un groupe et les sursauts au passage d'un chassé qui court (§3.8)
##   restent à faire (#647). Animaux : pas encore (placeholders seulement).

const PNJ_JSON: String = "res://data/blackout/pnj.json"
## Premier id d'acteur des PNJ (hors de la plage des joueurs).
const ID_BASE: int = 1000
## Coincé : secondes sans avancer en marchant avant de choisir un autre but.
const COINCE_S: float = 1.5
## Éclairage des PNJ recalculé toutes les LUMIERE_S s (lancers de rayons).
const LUMIERE_S: float = 0.25
## Fuite vers la lumière : cases éclairées cherchées à PEUR_PORTEE cases au plus, PEUR_ESSAIS cases tirées.
const PEUR_PORTEE: float = 12.0
const PEUR_ESSAIS: int = 160
## Sursaut sans planche : durée (s).
const SURSAUT_S: float = 0.6

var game: BkGame
var pnj: Array[BkActor] = []
## Par PNJ : {mode (activite, marche, sursaut, fuite), act, acts, t, path, i, fixe, coince, last}.
var etats: Array[Dictionary] = []
var _cases: Array[Vector2i] = []
var _lumiere_t: float = 0.0


static func _donnees() -> Dictionary:
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(PNJ_JSON))
	return d if d is Dictionary else {}


## Ids des PNJ humains à poser : `n` tirés parmi les sets réels d'abord (dans le désordre), puis les
## placeholders ; on repart du début si la bibliothèque est plus petite que `n`.
static func tirage(n: int) -> Array[String]:
	var humains: Dictionary = _donnees().get("humains", {})
	var persos: Array = BkRules.data().get("characters", [])
	var reels: Array[String] = []
	var places: Array[String] = []
	for id: Variant in humains:
		var s: String = str(id)
		if persos.has(s) or not BkPerso.dossier(s).contains("/pnj/"):
			continue
		if BkPerso.placeholder(s):
			places.append(s)
		else:
			reels.append(s)
	reels.shuffle()
	places.shuffle()
	var tous: Array[String] = reels.duplicate()
	tous.append_array(places)
	var out: Array[String] = []
	if tous.is_empty():
		return out
	for i: int in n:
		out.append(tous[i % tous.size()])
	return out


## Activités d'un PNJ (pnj.json), celles dont le set a une planche ; idle sinon.
static func activites(id: String) -> Array[String]:
	var h: Dictionary = (_donnees().get("humains", {}) as Dictionary).get(id, {})
	var out: Array[String] = []
	for act: Variant in h.get("activites", []):
		if BkPerso.livre(id, str(act)):
			out.append(str(act))
	if out.is_empty():
		out.append("idle")
	return out


## Pose la foule sur la carte (sous `parent`, le calque trié en profondeur des persos).
func cree(parent: Node2D) -> void:
	var m: BkMap = game.map
	var depart: Vector2 = m.center(m.spawns[0]) if not m.spawns.is_empty() else m.size_px() * 0.5
	for y: int in m.height:
		for x: int in m.width:
			var t: Vector2i = Vector2i(x, y)
			if m.walkable(t) and not m.cachettes.has(t) and not m.exits.has(t) \
					and m.center(t).distance_to(depart) >= BkRules.px("pnj_eloignes"):
				_cases.append(t)
	if _cases.is_empty():
		return
	var ids: Array[String] = tirage(int(BkRules.f("pnj_nombre")))
	var libres: Array[Vector2i] = _cases.duplicate()
	libres.shuffle()
	for i: int in ids.size():
		var a: BkActor = BkActor.new()
		a.character = ids[i]
		a.setup(ID_BASE + i, "", true)
		# Ni chassé ni chasseur, sur aucune couche : rien ne le heurte, il glisse sur les murs.
		a.collision_layer = 0
		a.collision_mask = BkMap.LAYER_MOVE
		a.frozen = false
		a.position = m.center(libres[i % libres.size()])
		a.look = 0.0 if randf() < 0.5 else PI
		parent.add_child(a)
		pnj.append(a)
		var acts: Array[String] = activites(ids[i])
		etats.append({"mode": "activite", "acts": acts, "act": acts.pick_random(),
			"t": randf_range(1.0, BkRules.f("pnj_activite_max")), "path": PackedVector2Array(), "i": 0,
			"fixe": randf() < BkRules.f("pnj_fixes"), "coince": 0.0, "last": a.position})
		a.anim_impose = str(etats[i]["act"])


## Une image de jeu : chaque PNJ fait son activité, marche ou fuit.
func maj(dt: float) -> void:
	for k: int in pnj.size():
		var a: BkActor = pnj[k]
		var e: Dictionary = etats[k]
		match str(e["mode"]):
			"activite":
				a.velocity = Vector2.ZERO
				a.anim_impose = str(e["act"])
				e["t"] = float(e["t"]) - dt
				if float(e["t"]) <= 0.0 and not bool(e["fixe"]):
					_marche(k)
			"sursaut":
				a.velocity = Vector2.ZERO
				e["t"] = float(e["t"]) - dt
				if float(e["t"]) <= 0.0:
					e["mode"] = "fuite" if (e["path"] as PackedVector2Array).size() > 1 else "activite"
					e["t"] = randf_range(BkRules.f("pnj_activite_min"), BkRules.f("pnj_activite_max"))
			"marche", "fuite":
				var fuite: bool = e["mode"] == "fuite"
				a.anim_impose = "run" if fuite else "marcher"
				if _suit(a, e, BkRules.px("pnj_fuite" if fuite else "pnj_marche"), dt):
					_activite(k)


## Vue du joueur local (BkGame._update_view) : le chasseur ne voit un PNJ que dans son cône ou son petit
## cercle, en silhouette s'il est dans l'ombre ; les autres voient toute la foule.
func maj_vue(as_hunter: bool, dt: float) -> void:
	_lumiere_t -= dt
	var lumiere: bool = _lumiere_t <= 0.0
	if lumiere:
		_lumiere_t = LUMIERE_S
	for a: BkActor in pnj:
		if lumiere:
			a.lit = game.eclaire(BkGame.pieds(a))
		var show: bool = true
		if as_hunter:
			show = not BkEffets.actif(game.hunter, "aveugle") and game.sees(game.hunter, a.position, a.radius)
		if a.shown != show:
			a.shown = show
			a.queue_redraw()
		a.silhouette = as_hunter and not a.lit


## Un coup spécial part en `p` (BkGame.coup_lance) : les PNJ proches sursautent et s'enfuient hors du rayon.
func coup(p: Vector2) -> void:
	var r: float = BkRules.px("pnj_fuite_portee")
	for k: int in pnj.size():
		var a: BkActor = pnj[k]
		if a.position.distance_to(p) > r:
			continue
		var loin: Vector2 = (a.position - p).normalized() if a.position.distance_to(p) > 1.0 else Vector2.from_angle(randf() * TAU)
		_sursaut(k, _chemin_vers(a, a.position + loin * BkRules.px("pnj_fuite_distance")))


## Lumière coupée dans un secteur (disjoncteur) : ses PNJ sursautent puis courent vers une case éclairée.
func panne(secteur: String) -> void:
	var m: BkMap = game.map
	var eclairees: Array[Vector2] = []
	var essais: Array[Vector2i] = _cases.duplicate()
	essais.shuffle()
	for t: Vector2i in essais.slice(0, PEUR_ESSAIS):
		if m.secteur_of(t) != secteur and game.eclaire(m.center(t)):
			eclairees.append(m.center(t))
	for k: int in pnj.size():
		var a: BkActor = pnj[k]
		if m.secteur_of(m.to_tile(a.position)) != secteur:
			continue
		var but: Vector2 = Vector2.INF
		for c: Vector2 in eclairees:
			if c.distance_to(a.position) <= PEUR_PORTEE * m.tile and (but == Vector2.INF or c.distance_to(a.position) < but.distance_to(a.position)):
				but = c
		_sursaut(k, game.map.path(a.position, but) if but != Vector2.INF else PackedVector2Array())


func _sursaut(k: int, chemin: PackedVector2Array) -> void:
	var a: BkActor = pnj[k]
	var e: Dictionary = etats[k]
	e["mode"] = "sursaut"
	e["path"] = chemin
	e["i"] = 1 if chemin.size() > 1 else 0
	e["coince"] = 0.0
	var duree: float = a.once_length("sursaut")
	a.play_once("sursaut")
	e["t"] = duree if duree > 0.0 else SURSAUT_S
	a.anim_impose = "idle"


## Chemin vers la case marchable la plus proche de `p` (en reculant vers le PNJ si `p` est dans un mur).
func _chemin_vers(a: BkActor, p: Vector2) -> PackedVector2Array:
	var m: BkMap = game.map
	for i: int in 6:
		var q: Vector2 = p.lerp(a.position, float(i) / 6.0)
		if m.walkable(m.to_tile(q)):
			var c: PackedVector2Array = m.path(a.position, m.center(m.to_tile(q)))
			if c.size() > 1:
				return c
	return PackedVector2Array()


## Marche vers une autre case à pnj_marche_max cases au plus.
func _marche(k: int) -> void:
	var a: BkActor = pnj[k]
	var e: Dictionary = etats[k]
	var portee: float = BkRules.px("pnj_marche_max")
	for essai: int in 8:
		var t: Vector2i = _cases.pick_random()
		if game.map.center(t).distance_to(a.position) > portee:
			continue
		var c: PackedVector2Array = game.map.path(a.position, game.map.center(t))
		if c.size() > 1:
			e["mode"] = "marche"
			e["path"] = c
			e["i"] = 1
			e["coince"] = 0.0
			return
	e["t"] = randf_range(1.0, 3.0)            # rien trouvé : il réessaie bientôt


func _activite(k: int) -> void:
	var e: Dictionary = etats[k]
	e["mode"] = "activite"
	e["act"] = (e["acts"] as Array).pick_random()
	e["t"] = randf_range(BkRules.f("pnj_activite_min"), BkRules.f("pnj_activite_max"))
	pnj[k].velocity = Vector2.ZERO
	pnj[k].anim_impose = str(e["act"])


## Avance sur le chemin ; vrai à l'arrivée (ou coincé trop longtemps).
func _suit(a: BkActor, e: Dictionary, vitesse: float, dt: float) -> bool:
	var chemin: PackedVector2Array = e["path"]
	var i: int = int(e["i"])
	if i >= chemin.size():
		return true
	var wp: Vector2 = chemin[i]
	if a.position.distance_to(wp) < maxf(4.0, vitesse * dt * 1.2):
		i += 1
		e["i"] = i
		if i >= chemin.size():
			a.velocity = Vector2.ZERO
			return true
		wp = chemin[i]
	var dir: Vector2 = (wp - a.position).normalized()
	a.velocity = dir * vitesse
	a.move_and_slide()
	if absf(dir.x) > 0.2:
		a.look = 0.0 if dir.x > 0.0 else PI
	if a.position.distance_to(e["last"]) < vitesse * dt * 0.2:
		e["coince"] = float(e["coince"]) + dt
	else:
		e["coince"] = 0.0
	e["last"] = a.position
	return float(e["coince"]) > COINCE_S
