class_name BkCoupReflexe
extends BkCoupActif
## Famille « reflexe » (GDD §4.1) : une réaction au bon moment ; appuyé à vide, il part quand même et
## repart en recharge.
##
## - Feinte de passe (Peio) : pas de côté instantané de params.pas_de_cote cases (à gauche ou à droite de
##   la marche : le côté le plus loin du chasseur, sinon le plus dégagé) ; si sa jauge de détection
##   dépasse params.jauge_seuil, elle retombe à zéro (params.jauge_a_zero) et les effets du coup marqués
##   si_jauge (bonus de vitesse) prennent. Une image fantôme reste un instant là où il était.
## - Endurance (Mattin) : les effets du coup (insensible) pendant duree s ; s'il est trouvé pendant ce
##   temps (params.annule_capture), la capture est annulée, une fois par round (params.par_round), et le
##   chasseur est repoussé de params.repousse cases.

var _de: Vector2 = Vector2.INF
var _annulee: bool = false
var _jauge_haute: bool = false


func demarre() -> void:
	var pdc: float = float(param("pas_de_cote", 0.0))
	if pdc > 0.0:
		_pas_de_cote(pdc)
	for e: Dictionary in coup.get("effets", []):
		var p: Dictionary = e.get("params", {})
		if p.has("si_jauge") and not _jauge_haute:
			continue
		effet(lanceur, e)
	bulle_param(lanceur, "bulle", 1.0)


func _pas_de_cote(cases_: float) -> void:
	_de = lanceur.position
	_jauge_haute = lanceur.gauge > float(param("jauge_seuil", 0.7))
	var cote: Vector2 = dir.orthogonal().normalized()
	var h: BkActor = game.hunter
	var a: Vector2 = trajet(cote * cases_ * game.map.tile)
	var b: Vector2 = trajet(-cote * cases_ * game.map.tile)
	var choix: Vector2 = a if a.distance_to(_de) >= b.distance_to(_de) else b
	if h != null and h != lanceur and a.distance_to(_de) > game.map.tile * 0.5 and b.distance_to(_de) > game.map.tile * 0.5:
		choix = a if a.distance_to(h.position) >= b.distance_to(h.position) else b
	lanceur.position = choix
	if _jauge_haute and bool(param("jauge_a_zero", true)):
		lanceur.gauge = 0.0
		lanceur.doubted = false


func maj(dt: float) -> bool:
	t += dt
	return t < maxf(duree(), 0.35) and en_jeu()


## Endurance : capture annulée (une fois par round) pendant duree s ; le chasseur recule d'une case.
func annule_capture() -> bool:
	if not bool(param("annule_capture", false)) or _annulee or t >= duree() or not en_jeu():
		return false
	if not moteur.consomme_usage(lanceur, coup):
		return false
	_annulee = true
	var h: BkActor = game.hunter
	if h != null:
		var v: Vector2 = (h.position - lanceur.position).normalized()
		if v == Vector2.ZERO:
			v = Vector2.from_angle(h.look + PI)
		var col: KinematicCollision2D = KinematicCollision2D.new()
		var pousse: Vector2 = v * float(param("repousse", 1.0)) * game.map.tile
		if h.test_move(h.global_transform, pousse, col):
			pousse = col.get_travel()
		h.position += pousse
	moteur.bulle(lanceur, str(param("bulle_annule", "")), 1.5)
	game.coup_touche(lanceur, coup)
	return true


func dessine(ci: CanvasItem, vue: Dictionary) -> void:
	if _de == Vector2.INF or t > 0.35 or not visible_pour(vue):
		return
	# Image fantôme de la feinte : contour du corps là où il était, qui s'efface.
	var k: float = 1.0 - t / 0.35
	var tile: float = game.map.tile
	var c: Vector2 = _de + Vector2(0, lanceur.feet_dy() - tile * 0.45)
	BkDraw.ellipse(ci, c, tile * 0.22, tile * 0.45, Color(1, 1, 1, 0.3 * k))
	ci.draw_line(_de + Vector2(0, lanceur.feet_dy() - 6), lanceur.position + Vector2(0, lanceur.feet_dy() - 6), Color(1, 1, 1, 0.5 * k), 2.0)


## IA : la feinte quand la jauge monte (urgence : au-dessus du seuil, menace : déjà entamée) ;
## l'endurance quand le chasseur est tout près ou la jauge haute.
func ia_utile(ctx: Dictionary) -> bool:
	var h: BkActor = game.hunter
	if h == null or lanceur.role != BkActor.Role.HIDER:
		return false
	if bool(ctx.get("urgence", false)):
		return true
	if not bool(ctx.get("menace", false)):
		return false
	if bool(param("annule_capture", false)):
		return lanceur.gauge >= 0.4 or h.position.distance_to(lanceur.position) < game.map.tile * 2.5
	return lanceur.gauge >= float(param("jauge_seuil", 0.7)) * 0.8
