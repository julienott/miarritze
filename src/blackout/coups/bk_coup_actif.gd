class_name BkCoupActif
extends RefCounted
## Un coup spécial lancé (GDD-BLACKOUT.md §4), base des familles (src/blackout/coups/familles/) : le
## moteur (BkCoups) crée une instance de la famille du coup, lui demande s'il est `possible` (sinon la
## recharge n'est pas consommée), le `demarre`, puis le fait vivre (`maj`) et le dessine (`dessine`)
## jusqu'à ce que `maj` rende faux. Une famille est réutilisable : tout ce qui change d'un coup à
## l'autre vient des données (data/blackout/coups.json : portee, duree, effets, params).

var moteur: BkCoups
var game: BkGame
var lanceur: BkActor
var coup: Dictionary = {}
## Direction du lancer : direction de marche (regard), ou choisie par l'IA.
var dir: Vector2 = Vector2.RIGHT
## Secondes depuis le départ.
var t: float = 0.0


func init(p_moteur: BkCoups, p_lanceur: BkActor, p_coup: Dictionary, p_dir: Vector2) -> void:
	moteur = p_moteur
	game = p_moteur.game
	lanceur = p_lanceur
	coup = p_coup
	dir = p_dir.normalized() if p_dir.length() > 0.01 else Vector2.from_angle(p_lanceur.look)


## Paramètre propre à la famille (coups.json → params).
func param(cle: String, defaut: Variant = null) -> Variant:
	return (coup.get("params", {}) as Dictionary).get(cle, defaut)


func duree() -> float:
	return float(coup.get("duree", 0.0))


func portee_px() -> float:
	return float(coup.get("portee", 0.0)) * game.map.tile


## Le coup peut-il partir maintenant ? Faux : rien ne se passe et la recharge n'est pas consommée.
func possible() -> bool:
	return true


## Pourquoi il ne part pas (message du joueur local), si `possible` est faux.
func raison() -> String:
	return ""


func demarre() -> void:
	pass


## Une image de jeu ; faux quand le coup est fini.
func maj(_dt: float) -> bool:
	return false


## Dessin dans le monde (calque non assombri). `vue` : {chasseur (le joueur local est le chasseur),
## fantome (spectateur), local (BkActor)}.
func dessine(_ci: CanvasItem, _vue: Dictionary) -> void:
	pass


## IA : faut-il lancer maintenant ? `ctx` : {menace (chassé en danger), cible_probable (chasseur)}.
## Peut choisir `dir`.
func ia_utile(_ctx: Dictionary) -> bool:
	return false


## Fin forcée (fin de round) : remettre le lanceur dans un état normal.
func interrompt() -> void:
	pass


## IA : le coup demande au lanceur de rester immobile (enfoui).
func garde_immobile() -> bool:
	return false


## Capture du lanceur annulée par ce coup (Endurance de Mattin) ? Appelé par BkCoups.annule_capture.
func annule_capture() -> bool:
	return false


# ---------------------------------------------------------------- outils communs des familles

## Le lanceur est-il encore en jeu (chassé ou chasseur) ?
func en_jeu(a: BkActor = null) -> bool:
	var x: BkActor = a if a != null else lanceur
	return x.role == BkActor.Role.HIDER or x.role == BkActor.Role.HUNTER


## Pose un effet de la liste du coup (coups.json → effets[i]) sur `cible`, lancé par le lanceur ;
## `extra` complète ses params (vers…). Compté dans les statistiques du coup s'il prend.
func effet(cible: BkActor, e: Dictionary, extra: Dictionary = {}) -> bool:
	var p: Dictionary = (e.get("params", {}) as Dictionary).duplicate()
	p.merge(extra, true)
	var ok: bool = moteur.applique_effet(cible, str(e.get("type", "")), float(e.get("duree", 0.0)), p, lanceur)
	if ok:
		game.coup_touche(lanceur, coup)
	return ok


## Tous les effets du coup sur `cible` ; vrai si au moins un a pris.
func effets_sur(cible: BkActor, extra: Dictionary = {}) -> bool:
	var ok: bool = false
	for e: Dictionary in coup.get("effets", []):
		if effet(cible, e, extra):
			ok = true
	return ok


## Le joueur local voit-il ce que fait le lanceur ? Un coup du chasseur se voit toujours (GDD §4.2) ;
## celui d'un chassé, le chasseur ne le voit que s'il voit le chassé (pas de fuite d'information).
func visible_pour(vue: Dictionary) -> bool:
	if lanceur.role == BkActor.Role.HUNTER or not bool(vue.get("chasseur", false)):
		return true
	return lanceur.shown


## Bruit (sable, toux) : le chasseur IA qui l'entend (mouettes_ouie cases) va voir.
func bruit(pos: Vector2) -> void:
	var h: BkActor = game.hunter
	if h != null and game.brains.has(h.id) and h.position.distance_to(pos) <= BkRules.px("mouettes_ouie"):
		(game.brains[h.id] as BkAi).on_noise(pos)


## Point atteint par le lanceur s'il glisse de `v` (px) : il s'arrête contre ce qui bloque le passage.
func trajet(v: Vector2) -> Vector2:
	var col: KinematicCollision2D = KinematicCollision2D.new()
	if lanceur.test_move(lanceur.global_transform, v, col):
		return lanceur.position + col.get_travel()
	return lanceur.position + v


## Coéquipiers libres (chassés hors cachette) du lanceur.
func allies() -> Array[BkActor]:
	var out: Array[BkActor] = []
	for a: BkActor in game.actors:
		if a != lanceur and a.role == BkActor.Role.HIDER and a.hidden_in < 0 and lanceur.role == BkActor.Role.HIDER:
			out.append(a)
	return out


## Ligne de vue dégagée vers une cible visible (pas invisible).
func voit(a: BkActor) -> bool:
	return not BkEffets.actif(a, "invisible") and game.clear_line(lanceur.position, a.position)


## Petite bulle de texte au-dessus d'un acteur (BkCoups.bulle), si params[cle] est écrit.
func bulle_param(a: BkActor, cle: String, secondes: float = 1.2) -> void:
	moteur.bulle(a, str(param(cle, "")), secondes)


## Couleur du coup (params.couleur), sinon `defaut`.
func couleur(defaut: Color) -> Color:
	var c: Variant = param("couleur", null)
	return Color(str(c)) if c is String else defaut
