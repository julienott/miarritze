class_name BkCoupRevele
extends BkCoupActif
## Famille « revele » (GDD §4.4) : de l'information pour le lanceur, selon params.rendu. Codé à
## l'étape 3 : « piste » (Cache-Cache ! de Louis). Les autres rendus (cibles qui brillent, révélation à
## travers les murs par l'effet « revele ») viendront à l'étape 4.
##
## Piste : bulle params.bulle au-dessus du lanceur (vue de tous) ; la cible (params.cible =
## « plus_proche » : l'adversaire libre le plus proche, hors cachette sauf touche_cachette) laisse pendant
## duree s un pas tous les params.pas_ecart cases ; chaque pas clignote (params.clignote_hz) et
## s'estompe en params.pas_vie s. Visible du lanceur (et des fantômes, spectateurs).

var cible: BkActor
## Pas posés : {pos, dir (Vector2), cote (±1), age (s)}.
var pas: Array = []
var _dernier: Vector2 = Vector2.INF
var _cote: float = 1.0


func rendu() -> String:
	return str(param("rendu", ""))


func possible() -> bool:
	return rendu() == "piste"


func demarre() -> void:
	moteur.bulle(lanceur, str(param("bulle", "")), float(param("bulle_s", 2.0)))
	cible = plus_proche()
	if cible != null:
		_pose(cible.position, Vector2.from_angle(cible.look))
		if cible == game.local and not cible.is_bot:
			game._say("Le chasseur suit tes pas !", Color("ffd34a"), 2.0)


## L'adversaire libre le plus proche du lanceur (BkCoups.adversaires), null s'il n'y en a pas.
func plus_proche() -> BkActor:
	var best: BkActor = null
	for a: BkActor in moteur.adversaires(lanceur, coup):
		if best == null or a.position.distance_to(lanceur.position) < best.position.distance_to(lanceur.position):
			best = a
	return best


func _pose(p: Vector2, d: Vector2) -> void:
	pas.append({"pos": p, "dir": d.normalized() if d.length() > 0.01 else Vector2.RIGHT, "cote": _cote, "age": 0.0})
	_cote = -_cote
	_dernier = p


func maj(dt: float) -> bool:
	t += dt
	for p: Dictionary in pas:
		p["age"] = float(p["age"]) + dt
	var vie: float = float(param("pas_vie", 3.0))
	pas = pas.filter(func(p: Dictionary) -> bool: return float(p["age"]) < vie)
	if t < duree() and cible != null and cible.role == BkActor.Role.HIDER and cible.hidden_in < 0:
		var v: Vector2 = cible.position - _dernier
		if v.length() >= float(param("pas_ecart", 0.5)) * game.map.tile:
			_pose(cible.position, v)
	return t < duree() or not pas.is_empty()


## Dernier pas posé (IA du chasseur), Vector2.INF s'il n'y en a pas.
func derniere_trace() -> Vector2:
	return (pas.back() as Dictionary)["pos"] if not pas.is_empty() else Vector2.INF


func dessine(ci: CanvasItem, vue: Dictionary) -> void:
	if not (vue.get("local") == lanceur or bool(vue.get("fantome", false))):
		return
	var vie: float = float(param("pas_vie", 3.0))
	var hz: float = float(param("clignote_hz", 3.0))
	for p: Dictionary in pas:
		var age: float = float(p["age"])
		# S'estompe en fin de vie ; clignote : plein, puis à moitié, hz fois par seconde.
		var a: float = clampf(1.0 - pow(age / vie, 2.0), 0.0, 1.0)
		if fmod(age * hz, 1.0) >= 0.5:
			a *= 0.5
		# Empreinte de pied (semelle et orteils, alternée gauche/droite) sur un halo, aux pieds du perso.
		var d: Vector2 = p["dir"]
		var side: Vector2 = d.orthogonal() * 3.0 * float(p["cote"])
		var c: Vector2 = ((p["pos"] as Vector2) + Vector2(0, 6) + side).round()
		var col: Color = Color(1.0, 0.86, 0.35, a)
		ci.draw_circle(c, 6.0, Color(1.0, 0.8, 0.3, a * 0.25))
		var semelle: Vector2 = (c - d * 1.5).round()
		var orteil: Vector2 = (c + d * 3.0).round()
		ci.draw_rect(Rect2(semelle - Vector2(3, 3), Vector2(6, 6)), Color(BkDraw.INK, a * 0.9))
		ci.draw_rect(Rect2(orteil - Vector2(2, 2), Vector2(4, 4)), Color(BkDraw.INK, a * 0.9))
		ci.draw_rect(Rect2(semelle - Vector2(2, 2), Vector2(4, 4)), col)
		ci.draw_rect(Rect2(orteil - Vector2(1, 1), Vector2(2, 2)), col)


func ia_utile(ctx: Dictionary) -> bool:
	return rendu() == "piste" and bool(ctx.get("cible_probable", false))
