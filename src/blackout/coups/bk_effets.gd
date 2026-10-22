class_name BkEffets
extends RefCounted
## Effets communs des coups spéciaux (GDD-BLACKOUT.md §4.5, carte #630), côté règles (hôte) : les
## mêmes pour tous les persos, posés sur n'importe quel acteur. L'état vit sur l'acteur
## (`BkActor.effets` : type → {left, duree, params}, `protection`, `gene_reste`) ; le dessin est à part
## (BkEffetsRendu). Les règles du jeu ne lisent que les questions ci-dessous (bloque, vitesse_k…).
##
## Garde-fous (GDD §4.3), appliqués ici quel que soit le coup :
## - un effet gênant (rules.json → effets_genants : figé, renversé, collé, ralenti, commandes inversées,
##   aveuglé, tracté) dure effet_max_genant_s s au plus ; plusieurs effets gênants qui se suivent
##   partagent la même fenêtre de gêne (jamais plus de effet_max_genant_s s d'affilée) ;
## - commandes inversées : effet_inverse_max_s s au plus ;
## - quand la gêne se termine, effet_protection_s s de protection : aucun nouvel effet gênant ;
## - les effets qui ne gênent personne (révélé, insensible, invisible, rapide) ne sont pas plafonnés et
##   passent même pendant la protection ;
## - insensible : refuse tout nouvel effet subi (gênant ou révélé) ; avec params.filtre = "sol", seulement
##   les effets posés au sol (params.au_sol).

## Catalogue (GDD §4.5) ; « rapide » est le bonus de vitesse des fiches (Maïa, Amaia, Ramuntxo, Peio).
const TYPES: PackedStringArray = ["fige", "renverse", "colle", "ralenti", "revele", "inverse", "aveugle",
	"tracte", "insensible", "invisible", "rapide"]
## Bonus : jamais refusés par la protection ni par l'insensibilité.
const BONUS: PackedStringArray = ["insensible", "invisible", "rapide"]
## Effets qui prennent les commandes : le joueur ne se déplace plus lui-même.
const BLOQUANTS: PackedStringArray = ["fige", "renverse", "colle", "tracte"]
## Tracté : on lâche la corde à cette distance du point visé (cases).
const TRACTE_ARRIVEE: float = 0.6


static func est_genant(type: String) -> bool:
	return (BkRules.data().get("effets_genants", []) as Array).has(type)


## Pose un effet sur `a` (chassé ou chasseur en jeu). Rend la durée retenue (s), 0 si l'effet est
## refusé (type inconnu, acteur hors jeu, protection, insensible, fenêtre de gêne épuisée).
static func applique(a: BkActor, type: String, duree: float, params: Dictionary = {}) -> float:
	if not TYPES.has(type) or duree <= 0.0:
		return 0.0
	if a.role != BkActor.Role.HIDER and a.role != BkActor.Role.HUNTER:
		return 0.0
	# Aide d'un coéquipier (bouée de Txomin, params.aide) : ni l'insensibilité ni la protection ne la
	# refusent ; elle reste plafonnée comme tout effet qui prend les commandes.
	var aide: bool = bool(params.get("aide", false))
	if not BONUS.has(type) and a.effets.has("insensible") and not aide:
		var filtre: String = str((a.effets["insensible"]["params"] as Dictionary).get("filtre", ""))
		if filtre == "" or bool(params.get("au_sol", false)):
			return 0.0
	if est_genant(type):
		if a.protection > 0.0 and not aide:
			return 0.0
		var cap: float = BkRules.f("effet_max_genant_s")
		if type == "inverse":
			cap = minf(cap, BkRules.f("effet_inverse_max_s"))
		if not gene_en_cours(a):
			a.gene_reste = BkRules.f("effet_max_genant_s")
		duree = minf(duree, minf(cap, a.gene_reste))
		if duree <= 0.0:
			return 0.0
	var avant: Dictionary = a.effets.get(type, {})
	if not avant.is_empty() and float(avant["left"]) > duree:
		return float(avant["left"])
	a.effets[type] = {"left": duree, "duree": duree, "params": params.duplicate()}
	return duree


## QA (planche des effets) : effet maintenu sans plafond ni protection.
static func force(a: BkActor, type: String, params: Dictionary = {}) -> void:
	a.effets[type] = {"left": 1.0e6, "duree": 1.0e6, "params": params}


## Une image de jeu : les effets s'écoulent ; la fin d'une gêne ouvre la protection.
static func maj(a: BkActor, dt: float) -> void:
	var gene: bool = gene_en_cours(a)
	for type: Variant in a.effets.keys():
		var e: Dictionary = a.effets[type]
		e["left"] = float(e["left"]) - dt
		if float(e["left"]) <= 0.0:
			a.effets.erase(type)
	if gene:
		a.gene_reste = maxf(0.0, a.gene_reste - dt)
		if not gene_en_cours(a):
			a.gene_reste = 0.0
			a.protection = BkRules.f("effet_protection_s")
			return
	a.protection = maxf(0.0, a.protection - dt)


## Retire tout (début de round, chassé trouvé ou délivré).
static func efface(a: BkActor) -> void:
	a.effets.clear()
	a.protection = 0.0
	a.gene_reste = 0.0


static func gene_en_cours(a: BkActor) -> bool:
	for type: Variant in a.effets:
		if est_genant(str(type)):
			return true
	return false


static func actif(a: BkActor, type: String) -> bool:
	return a.effets.has(type)


static func params(a: BkActor, type: String) -> Dictionary:
	return (a.effets.get(type, {}) as Dictionary).get("params", {})


## Le joueur ne se déplace plus lui-même (figé, renversé, collé, tracté).
static func bloque(a: BkActor) -> bool:
	for type: String in BLOQUANTS:
		if a.effets.has(type):
			return true
	return false


## Multiplicateur de vitesse : ralenti (× 1 − k) et rapide (× 1 + k), k par défaut dans rules.json.
static func vitesse_k(a: BkActor) -> float:
	var k: float = 1.0
	if a.effets.has("ralenti"):
		k *= 1.0 - float(params(a, "ralenti").get("k", BkRules.f("effet_ralenti_k")))
	if a.effets.has("rapide"):
		k *= 1.0 + float(params(a, "rapide").get("k", BkRules.f("effet_rapide_k")))
	return k


## Tracté : vitesse (px/s) vers params.vers (Vector2) ; Vector2.ZERO quand c'est fini ou sans cible.
static func traction(a: BkActor) -> Vector2:
	if not a.effets.has("tracte"):
		return Vector2.ZERO
	var vers: Variant = params(a, "tracte").get("vers", null)
	if not vers is Vector2:
		return Vector2.ZERO
	var v: Vector2 = (vers as Vector2) - a.position
	if v.length() < TRACTE_ARRIVEE * BkRules.f("tile_px"):
		a.effets["tracte"]["left"] = 0.0          # retiré par maj (qui ouvre la protection)
		return Vector2.ZERO
	return v.normalized() * BkRules.px("effet_tracte_vitesse")
