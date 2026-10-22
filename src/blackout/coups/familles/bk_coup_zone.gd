class_name BkCoupZone
extends BkCoupActif
## Famille « zone » (GDD §4.2, §4.4) : un effet autour du lanceur (portee cases). Chaque adversaire à
## portée qui remplit params.filtre subit les effets du coup, au départ. Une onde (params.couleur) montre
## la zone à tous ; params.bulle au-dessus du lanceur, params.bulle_cible au-dessus de chaque touché.
##
## Filtres : « bouge » (il a bougé il y a moins de params.bouge_s s : sifflet de Txomin), « immobile »
## (immobile depuis params.immobile_s s : makila d'Amaia), « regarde_vers » (le chasseur regarde le
## lanceur, dans son cône, sans mur entre eux : flash d'Itsasargi) ; aucun : tous.
## Suites : params.si_bouge (cri de Kaio : un touché qui bouge pendant son effet subit si_bouge pendant
## si_bouge_duree s, une fois) ; params.traces (troisième mi-temps de Peio : le lanceur voit les pas des
## touchés pendant traces s).
## Geysers (params.centre = « cachettes », courant des laminak d'Itsaso, touche_cachette) : les
## params.geysers cachettes les plus proches à portée jaillissent après params.geyser_delai s ; le
## chassé caché dedans est éjecté (params.ejecte) et subit les effets, comme ceux à params.geyser_rayon
## cases du geyser.

const ONDE_S: float = 0.6

var touches: Array[BkActor] = []
var _plumes: Dictionary = {}
## Traces de pas des touchés (Peio) : id → {dernier, cote} ; pas posés {pos, dir, cote, age}.
var _suivis: Dictionary = {}
var pas: Array = []
## Geysers {pos, cachette, t (s avant de jaillir), jailli}.
var geysers: Array = []


func filtre() -> String:
	return str(param("filtre", ""))


func geyser_mode() -> bool:
	return str(param("centre", "")) == "cachettes"


## La cible remplit-elle le filtre du coup ?
func passe_filtre(a: BkActor) -> bool:
	match filtre():
		"bouge":
			return a.immobile_t < float(param("bouge_s", 0.3))
		"immobile":
			return a.immobile_t >= float(param("immobile_s", 2.0))
		"regarde_vers":
			var v: Vector2 = lanceur.position - a.position
			var demi: float = deg_to_rad(BkRules.f("cone_deg")) * 0.5 + deg_to_rad(float(param("marge_deg", 10.0)))
			return absf(angle_difference(a.look, v.angle())) <= demi and game.clear_line(a.position, lanceur.position)
	return true


## Adversaires à portée qui remplissent le filtre.
func dans_zone() -> Array[BkActor]:
	var out: Array[BkActor] = []
	for a: BkActor in moteur.adversaires(lanceur, coup):
		if a.position.distance_to(lanceur.position) <= portee_px() and passe_filtre(a):
			out.append(a)
	return out


## Cachettes à portée, les plus proches d'abord (geysers).
func cachettes_proches() -> Array[int]:
	var idx: Array[int] = []
	for i: int in game.cachettes.size():
		if (game.cachettes[i]["pos"] as Vector2).distance_to(lanceur.position) <= portee_px():
			idx.append(i)
	idx.sort_custom(func(x: int, y: int) -> bool:
		return (game.cachettes[x]["pos"] as Vector2).distance_to(lanceur.position) \
			< (game.cachettes[y]["pos"] as Vector2).distance_to(lanceur.position))
	return idx.slice(0, int(param("geysers", 3)))


func possible() -> bool:
	return not geyser_mode() or not cachettes_proches().is_empty()


func raison() -> String:
	return "Pas de cachette à portée" if geyser_mode() else ""


func demarre() -> void:
	bulle_param(lanceur, "bulle", 1.5)
	if geyser_mode():
		for i: int in cachettes_proches():
			geysers.append({"pos": game.cachettes[i]["pos"], "cachette": i,
				"t": float(param("geyser_delai", 0.5)) + 0.15 * geysers.size(), "jailli": 0.0})
		return
	for a: BkActor in dans_zone():
		if effets_sur(a, {"au_sol": bool(param("au_sol", false))}):
			touches.append(a)
			bulle_param(a, "bulle_cible", 1.4)
			_suivis[a.id] = {"dernier": a.position, "cote": 1.0}
	if game.local in touches and not game.local.is_bot:
		game._say(str(param("message", coup.get("nom", ""))), Color("ffd34a"), 1.6)


func maj(dt: float) -> bool:
	t += dt
	var vivant: bool = t < ONDE_S
	# Cri de Kaio : un touché qui bouge pendant son effet perd des plumes (révélé).
	var sb: String = str(param("si_bouge", ""))
	if sb != "":
		for a: BkActor in touches:
			if _plumes.has(a.id) or a.role != BkActor.Role.HIDER:
				continue
			var gene: bool = false
			for e: Dictionary in coup.get("effets", []):
				if BkEffets.actif(a, str(e.get("type", ""))):
					gene = true
			if gene:
				vivant = true
				if a.immobile_t < 0.05 and a.commande.length() > 0.2:
					_plumes[a.id] = true
					moteur.applique_effet(a, sb, float(param("si_bouge_duree", 3.0)), {"plumes": true}, lanceur)
					game.coup_touche(lanceur, coup)
	# Peio : pas des touchés pendant `traces` s.
	var tr: float = float(param("traces", 0.0))
	if tr > 0.0:
		for p: Dictionary in pas:
			p["age"] = float(p["age"]) + dt
		pas = pas.filter(func(p: Dictionary) -> bool: return float(p["age"]) < float(param("pas_vie", 2.0)))
		if t < tr:
			vivant = true
			for a2: BkActor in touches:
				if a2.role != BkActor.Role.HIDER or a2.hidden_in >= 0 or BkCoupRevele.sans_traces(a2):
					continue
				var s: Dictionary = _suivis[a2.id]
				var v: Vector2 = a2.position - (s["dernier"] as Vector2)
				if v.length() >= float(param("pas_ecart", 0.45)) * game.map.tile:
					pas.append({"pos": a2.position, "dir": v.normalized(), "cote": float(s["cote"]), "age": 0.0})
					s["cote"] = -float(s["cote"])
					s["dernier"] = a2.position
		elif not pas.is_empty():
			vivant = true
	# Geysers.
	for g: Dictionary in geysers:
		g["t"] = float(g["t"]) - dt
		if float(g["t"]) <= 0.0 and float(g["jailli"]) <= 0.0:
			g["jailli"] = 1.0
			_jaillit(g)
		elif float(g["jailli"]) > 0.0:
			g["jailli"] = float(g["jailli"]) - dt
		if float(g["t"]) > 0.0 or float(g["jailli"]) > 0.0:
			vivant = true
	return vivant


func _jaillit(g: Dictionary) -> void:
	var c: Dictionary = game.cachettes[int(g["cachette"])]
	c["jiggle"] = maxf(float(c["jiggle"]), 0.5)
	var occ: int = int(c["occupant"])
	if occ >= 0:
		var a: BkActor = game.actors[occ]
		if a.role == BkActor.Role.HIDER and bool(param("ejecte", true)):
			game._leave_cachette(a, true)
			if effets_sur(a, {"au_sol": true}):
				touches.append(a)
			bulle_param(a, "bulle_cible", 1.4)
	var r: float = float(param("geyser_rayon", 0.8)) * game.map.tile
	for b: BkActor in moteur.adversaires(lanceur, {}):
		if not touches.has(b) and b.position.distance_to(g["pos"]) <= r:
			if effets_sur(b, {"au_sol": true}):
				touches.append(b)


func dessine(ci: CanvasItem, vue: Dictionary) -> void:
	var col: Color = couleur(Color("ffd34a"))
	if t < ONDE_S and visible_pour(vue) and not geyser_mode():
		var k: float = t / ONDE_S
		var r: float = portee_px() * (0.25 + 0.75 * k)
		ci.draw_arc(lanceur.position, r, 0.0, TAU, 48, Color(col, 0.8 * (1.0 - k)), 3.0)
		ci.draw_arc(lanceur.position, r * 0.8, 0.0, TAU, 40, Color(col, 0.4 * (1.0 - k)), 1.0)
		if filtre() == "regarde_vers":
			ci.draw_circle(lanceur.position + Vector2(0, -12), 18.0 * (1.0 - k) + 4.0, Color(1, 1, 0.85, 0.85 * (1.0 - k)))
	# Plumes qui tombent (Kaio) : dessinées par l'effet inversé ; traces (Peio) pour le lanceur.
	if not pas.is_empty() and (vue.get("local") == lanceur or bool(vue.get("fantome", false))):
		BkCoupRevele.dessine_pas(ci, pas, float(param("pas_vie", 2.0)), float(param("clignote_hz", 3.0)))
	for g: Dictionary in geysers:
		var p: Vector2 = g["pos"]
		if float(g["t"]) > 0.0:
			# Le sol frémit : petites gouttes autour de la cachette.
			for i: int in 4:
				var ang: float = TAU * i / 4.0 + t * 5.0
				ci.draw_rect(Rect2((p + Vector2.from_angle(ang) * 12.0 + Vector2(0, 10)).round(), Vector2(2, 2)), Color("9fe2ff"))
		elif float(g["jailli"]) > 0.0:
			var k2: float = float(g["jailli"])
			var h: float = game.map.tile * 1.6 * sin(PI * clampf(1.0 - k2, 0.0, 1.0) * 0.5 + PI * 0.5 * (1.0 - k2))
			var base: Vector2 = p + Vector2(0, game.map.tile * 0.4)
			var w: float = 7.0
			ci.draw_rect(Rect2(base + Vector2(-w, -h), Vector2(w * 2.0, h)), Color(col, 0.75 * k2 + 0.2))
			ci.draw_rect(Rect2(base + Vector2(-w * 0.4, -h), Vector2(w * 0.8, h)), Color(1, 1, 1, 0.6 * k2 + 0.2))
			BkDraw.ellipse(ci, base + Vector2(0, -h), w * 1.6, 5.0, Color(1, 1, 1, 0.8 * k2 + 0.2))
			BkDraw.ellipse(ci, base, w * 2.2, 4.0, Color(col, 0.5))


## IA. Chasseur : cible vue à portée, ou indice récent (ctx.vers) à portée (geysers : une cachette près
## de l'indice). Chassé (flash) : le chasseur à portée le regarde.
func ia_utile(ctx: Dictionary) -> bool:
	if lanceur.role == BkActor.Role.HIDER:
		return not dans_zone().is_empty() and (bool(ctx.get("menace", false)) or bool(ctx.get("urgence", false)))
	if not bool(ctx.get("cible_probable", false)):
		return false
	var cible: BkActor = ctx.get("cible", null)
	var vers: Vector2 = ctx.get("vers", Vector2.INF)
	if geyser_mode():
		if vers == Vector2.INF:
			return false
		for i: int in cachettes_proches():
			if (game.cachettes[i]["pos"] as Vector2).distance_to(vers) <= game.map.tile * 4.0:
				return true
		return false
	if cible != null and cible.position.distance_to(lanceur.position) <= portee_px() * 0.9:
		return filtre() != "immobile"
	return vers != Vector2.INF and vers.distance_to(lanceur.position) <= portee_px() * 0.8
