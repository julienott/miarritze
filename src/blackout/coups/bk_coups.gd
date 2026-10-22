class_name BkCoups
extends Node
## Moteur des coups spéciaux (GDD-BLACKOUT.md §4, cartes #627 et #630), côté règles (hôte). Il remplace
## les pièges et l'onde de détection.
##
## - Données : data/blackout/coups.json, un coup de chassé et un coup de chasseur par perso (`coup`).
## - Bouton unique (BkGame.act_for) : après cachette/fouille et disjoncteur, le coup du rôle (`lance`).
## - Recharge : `recharge` s du coup (BkActor.coup_cd) ; un gâteau basque recharge tout de suite
##   (`recharge_immediate`). Un coup non codé (« pret » faux) est affiché « bientôt » et ne part pas.
## - Familles : un script par famille (src/blackout/coups/familles/, base BkCoupActif) paramétré par les
##   données ; un coup particulier n'ajoute que ses paramètres.
## - Visée commune (`vise`) : direction de marche, aimant de ±aimant_deg vers une cible visible.
## - Effets communs (`applique_effet`, catalogue et garde-fous dans BkEffets, dessin dans BkEffetsRendu).
## - Annonce : l'icône et le nom du coup au-dessus du lanceur (celui du chasseur, vu de tous, GDD §4.2).

const PATH: String = "res://data/blackout/coups.json"
const FAMILLES: Dictionary = {
	"deplacement": preload("res://src/blackout/coups/familles/bk_coup_deplacement.gd"),
	"revele": preload("res://src/blackout/coups/familles/bk_coup_revele.gd"),
	"lance": preload("res://src/blackout/coups/familles/bk_coup_lance.gd"),
	"zone": preload("res://src/blackout/coups/familles/bk_coup_zone.gd"),
	"pose": preload("res://src/blackout/coups/familles/bk_coup_pose.gd"),
}
## Éclair de lancement (placeholder §4.6) : durée (s) et rayon (px).
const ECLAIR_S: float = 0.3
const ECLAIR_R: float = 14.0

static var _data: Dictionary = {}

var game: BkGame
var actifs: Array[BkCoupActif] = []
## Annonces au-dessus d'un lanceur {id, nom, famille, left} et bulles de texte {id, texte, left, duree}.
var annonces: Array = []
var bulles: Array = []
## Usages limités par round (params.par_round) : "id_acteur:id_coup" → nombre.
var usages: Dictionary = {}


static func donnees() -> Dictionary:
	if _data.is_empty():
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		_data = d if d is Dictionary else {}
	return _data


## Coup d'un perso pour un rôle (`chasseur` : son coup de chasseur), {} s'il n'en a pas.
static func coup_de(character: String, chasseur: bool) -> Dictionary:
	var p: Dictionary = (donnees().get("persos", {}) as Dictionary).get(character, {})
	return p.get("chasseur" if chasseur else "chasse", {})


## Codé et actif (sinon « bientôt »).
static func code(c: Dictionary) -> bool:
	return bool(c.get("pret", false)) and FAMILLES.has(str(c.get("famille", "")))


## Coup du rôle actuel de l'acteur ({} pour un fantôme ou un échappé).
func coup(a: BkActor) -> Dictionary:
	match a.role:
		BkActor.Role.HIDER:
			return coup_de(a.character, false)
		BkActor.Role.HUNTER:
			return coup_de(a.character, true)
	return {}


## Part de la recharge restante (1 → 0), pour le bouton.
func fraction(a: BkActor) -> float:
	return clampf(a.coup_cd / maxf(a.coup_cd_max, 0.01), 0.0, 1.0) if a.coup_cd > 0.0 else 0.0


## Le coup de l'acteur peut-il partir (chasse en cours, en jeu, dehors, libre de ses gestes, rechargé) ?
func peut(a: BkActor) -> bool:
	return game.phase == BkGame.Phase.HUNT and (a.role == BkActor.Role.HIDER or a.role == BkActor.Role.HUNTER) \
		and a.hidden_in < 0 and not a.en_coup and not a.frozen and a.coup_cd <= 0.0 \
		and a.search_left <= 0.0 and a.use_left <= 0.0 and not BkEffets.bloque(a) and code(coup(a))


## Lance le coup de `a` (vers `dir`, sinon sa direction de marche). Rend "" s'il est parti, sinon la
## raison : "aucun", "bientot", "attente" (recharge, phase, geste en cours) ou le message de la famille.
func lance(a: BkActor, dir: Vector2 = Vector2.ZERO) -> String:
	var c: Dictionary = coup(a)
	if c.is_empty():
		return "aucun"
	if not code(c):
		return "bientot"
	if not peut(a):
		return "attente"
	var inst: BkCoupActif = _instance(a, c, dir)
	if not inst.possible():
		return inst.raison() if inst.raison() != "" else "impossible"
	_demarre(inst)
	return ""


## IA : lance le coup si la famille le juge utile dans ce contexte ({menace, cible_probable}).
func essaie_ia(a: BkActor, ctx: Dictionary) -> bool:
	if not peut(a):
		return false
	var inst: BkCoupActif = _instance(a, coup(a), Vector2.ZERO)
	if not inst.ia_utile(ctx) or not inst.possible():
		return false
	_demarre(inst)
	return true


func _instance(a: BkActor, c: Dictionary, dir: Vector2) -> BkCoupActif:
	var inst: BkCoupActif = (FAMILLES[str(c["famille"])] as GDScript).new()
	inst.init(self, a, c, dir)
	return inst


func _demarre(inst: BkCoupActif) -> void:
	var a: BkActor = inst.lanceur
	a.coup_cd = float(inst.coup.get("recharge", 20.0))
	a.coup_cd_max = a.coup_cd
	actifs.append(inst)
	inst.demarre()
	annonces = annonces.filter(func(n: Dictionary) -> bool: return int(n["id"]) != a.id)
	annonces.append({"id": a.id, "nom": str(inst.coup.get("nom", "")), "famille": str(inst.coup.get("famille", "")),
		"left": BkRules.f("annonce_coup_s"), "eclair": ECLAIR_S})
	game.coup_lance(a, inst.coup)


## Une image de jeu (pendant la chasse) : coups en cours, effets, annonces.
func maj(dt: float) -> void:
	for inst: BkCoupActif in actifs.duplicate():
		if not inst.maj(dt):
			actifs.erase(inst)
	for a: BkActor in game.actors:
		BkEffets.maj(a, dt)
	for n: Dictionary in annonces:
		n["left"] = float(n["left"]) - dt
		n["eclair"] = float(n["eclair"]) - dt
	annonces = annonces.filter(func(n: Dictionary) -> bool: return float(n["left"]) > 0.0)
	for b: Dictionary in bulles:
		b["left"] = float(b["left"]) - dt
	bulles = bulles.filter(func(b: Dictionary) -> bool: return float(b["left"]) > 0.0)


## Début de round : plus de coup en cours ni d'effet ; coups rechargés.
func reset() -> void:
	for inst: BkCoupActif in actifs:
		inst.interrompt()
	actifs.clear()
	annonces.clear()
	bulles.clear()
	usages.clear()
	for a: BkActor in game.actors:
		BkEffets.efface(a)
		a.coup_cd = 0.0
		a.coup_cd_max = 0.0
		a.en_coup = false
		a.saut_px = 0.0


## Gâteau basque (GDD §3.5) : recharge immédiate. Faux si le coup n'était pas en recharge (le gâteau
## reste alors au sol).
func recharge_immediate(a: BkActor) -> bool:
	if a.coup_cd <= 0.0:
		return false
	a.coup_cd = 0.0
	return true


## Bulle de texte au-dessus d'un acteur, vue de tous (« 1, 2, 3… j'arrive ! »).
func bulle(a: BkActor, texte: String, secondes: float) -> void:
	if texte == "":
		return
	bulles.append({"id": a.id, "texte": texte, "left": secondes, "duree": secondes})


## Cibles d'un coup : pour le chasseur, les chassés en jeu (hors cachette sauf touche_cachette, GDD
## §4.2) ; pour un chassé, le chasseur.
func adversaires(lanceur: BkActor, c: Dictionary) -> Array[BkActor]:
	var out: Array[BkActor] = []
	for a: BkActor in game.actors:
		if a == lanceur:
			continue
		if lanceur.role == BkActor.Role.HUNTER and a.role == BkActor.Role.HIDER:
			if a.hidden_in < 0 or bool(c.get("touche_cachette", false)):
				out.append(a)
		elif lanceur.role == BkActor.Role.HIDER and a.role == BkActor.Role.HUNTER:
			out.append(a)
	return out


## Visée commune (GDD §4.2) : droit devant (`dir`), avec un aimant de ±aimant_deg (coups.json) vers la
## cible visible (ligne de vue dégagée, pas invisible) la mieux alignée à `portee` px au plus.
## `vitesse` (px/s, projectile) : on vise là où la cible sera à l'arrivée (elle court).
## Rend {dir: Vector2, cible: BkActor ou null}.
func vise(lanceur: BkActor, dir: Vector2, portee: float, cibles: Array[BkActor], aimant_deg: float = -1.0,
		vitesse: float = 0.0) -> Dictionary:
	var aim: float = deg_to_rad(aimant_deg if aimant_deg >= 0.0 else float(donnees().get("aimant_deg", 20.0)))
	var d0: Vector2 = dir.normalized() if dir.length() > 0.01 else Vector2.from_angle(lanceur.look)
	var best: BkActor = null
	var best_a: float = INF
	for c: BkActor in cibles:
		var v: Vector2 = c.position - lanceur.position
		if v.length() > portee or v.length() < 0.5 or BkEffets.actif(c, "invisible"):
			continue
		var ang: float = absf(angle_difference(d0.angle(), v.angle()))
		if ang > aim or not game.clear_line(lanceur.position, c.position):
			continue
		if ang < best_a:
			best_a = ang
			best = c
	if best == null:
		return {"dir": d0, "cible": null}
	var but: Vector2 = best.position
	if vitesse > 0.0:
		but += best.velocity * (best.position.distance_to(lanceur.position) / vitesse)
	return {"dir": (but - lanceur.position).normalized(), "cible": best}


## API commune des effets (côté règles) : pose l'effet `type` sur `cible` pour `duree` s (plafonnée
## par BkEffets, GDD §4.3). `source` : le lanceur ; un coup de chassé qui touche le chasseur rapporte
## hider_coup_touche points (GDD §2.3). Vrai si l'effet a pris.
func applique_effet(cible: BkActor, type: String, duree: float, params: Dictionary = {}, source: BkActor = null) -> bool:
	if BkEffets.applique(cible, type, duree, params) <= 0.0:
		return false
	game.effet_subi(cible, type, source)
	return true


## Capture de `a` annulée par un de ses coups en cours (Endurance de Mattin) ?
func annule_capture(a: BkActor) -> bool:
	for inst: BkCoupActif in actifs:
		if inst.lanceur == a and inst.annule_capture():
			return true
	return false


## IA : un coup en cours demande-t-il à `a` de rester immobile (enfoui) ?
func garde_immobile(a: BkActor) -> bool:
	for inst: BkCoupActif in actifs:
		if inst.lanceur == a and inst.garde_immobile():
			return true
	return false


## Usage limité par round : vrai (et compté) s'il en reste pour `a` et ce coup (params.par_round).
func consomme_usage(a: BkActor, c: Dictionary) -> bool:
	var n: int = int((c.get("params", {}) as Dictionary).get("par_round", 0))
	var k: String = "%d:%s" % [a.id, str(c.get("id", ""))]
	if n > 0 and int(usages.get(k, 0)) >= n:
		return false
	usages[k] = int(usages.get(k, 0)) + 1
	return true


## Instance en cours d'un coup de piste du chasseur `a` : dernier pas vu, Vector2.INF sinon (IA).
func piste_de(a: BkActor) -> Vector2:
	for inst: BkCoupActif in actifs:
		if inst.lanceur == a and inst is BkCoupRevele:
			var p: Vector2 = (inst as BkCoupRevele).derniere_trace()
			if p != Vector2.INF:
				return p
	return Vector2.INF


## Dessin dans le monde (calque non assombri) : coups en cours, éclairs de lancement, annonces et
## bulles. `as_hunter` : le joueur local est le chasseur.
func dessine(ci: CanvasItem, as_hunter: bool) -> void:
	var loc: BkActor = game.local
	var vue: Dictionary = {"chasseur": as_hunter, "local": loc,
		"fantome": loc.role == BkActor.Role.GHOST or loc.role == BkActor.Role.OUT}
	for inst: BkCoupActif in actifs:
		inst.dessine(ci, vue)
	for n: Dictionary in annonces:
		var a: BkActor = game.actors[int(n["id"])]
		if not _visible(a, as_hunter):
			continue
		var head: Vector2 = (a.position + Vector2(0, a.name_y())).round()
		if float(n["eclair"]) > 0.0:
			var k: float = float(n["eclair"]) / ECLAIR_S
			ci.draw_arc(a.position + Vector2(0, a.feet_dy() - 12.0), ECLAIR_R * (1.6 - k), 0, TAU, 24, Color(1, 1, 1, k), 2.0)
		var al: float = clampf(float(n["left"]) * 3.0, 0.0, 1.0)
		var c: Vector2 = head + Vector2(0, -26)
		BkEffetsRendu.icone(ci, c, 7.0, str(n["famille"]), al)
		BkDraw.texte(ci, c + Vector2(0, 17), str(n["nom"]), 8, Color(1, 1, 1, al), 2, 160.0)
	for b: Dictionary in bulles:
		var a2: BkActor = game.actors[int(b["id"])]
		if not _visible(a2, as_hunter):
			continue
		var k2: float = float(b["left"]) / maxf(float(b["duree"]), 0.01)
		var at: Vector2 = (a2.position + Vector2(0, a2.name_y() - 44.0 - 4.0 * (1.0 - k2))).round()
		BkDraw.texte(ci, at, str(b["texte"]), 8, Color(Color("ffd34a"), clampf(k2 * 4.0, 0.0, 1.0)), 2, 200.0)


## Le joueur local voit-il ce lanceur ? Le chasseur, toujours (GDD §4.2) ; un chassé, s'il est dessiné.
func _visible(a: BkActor, _as_hunter: bool) -> bool:
	return a == game.hunter or a == game.local or a.shown
