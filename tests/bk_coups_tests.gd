extends RefCounted
## Tests des 24 coups spéciaux de l'étape 4 (GDD-BLACKOUT.md §4.4, cartes #628 et #629) : un test par coup
## (effet attendu sur un cas simple, sur la carte bac à sable) et quelques décisions de l'IA. Lancés par
## tests/bk_tests.gd (même commande) : `r` est le lanceur des tests (make_game, check…).

const DT: float = 1.0 / 60.0

## Lanceur des tests (tests/bk_tests.gd) : appelé dynamiquement (make_game, check, near…).
var r: Variant


func _init(p_runner: SceneTree) -> void:
	r = p_runner


func tests() -> Array[Callable]:
	return [test_fil_ariane, test_sifflet, test_appat, test_prise_au_vol, test_canard, test_take_off,
		test_rebond, test_tir_crayon, test_endurance, test_pierre, test_mutxiko, test_makila, test_vol,
		test_cri, test_enfouissement, test_glissade, test_gateau_partage, test_pot_piment, test_muret,
		test_geysers, test_feinte, test_troisieme_mi_temps, test_flash, test_eclat, test_ia_coups]


# ------------------------------------------------------------------ outils

## Partie de test (BkTests.make_game) : persos, rôles et positions (cases) imposés ; le chasseur est
## l'acteur 0. `places` : [[x, y], …] pour les acteurs 1, 2.
func partie(chasseur: String, chasse: String, places: Array = []) -> BkGame:
	var game: BkGame = await r.make_game()
	game.hunter.character = chasseur
	for i: int in range(1, game.actors.size()):
		game.actors[i].character = chasse
		if i - 1 < places.size():
			game.actors[i].position = pos(game, places[i - 1][0], places[i - 1][1])
	return game


func pos(game: BkGame, x: float, y: float) -> Vector2:
	return Vector2(x + 0.5, y + 0.5) * game.map.tile


## `secs` s de jeu : les acteurs avancent (commande `moves[i]`, rien par défaut ; tractés, glissades),
## puis les coups et les effets.
func vit(game: BkGame, secs: float, moves: Dictionary = {}) -> void:
	for i: int in int(round(secs / DT)):
		for a: BkActor in game.actors:
			a.step(moves.get(a.id, Vector2.ZERO), Vector2.ZERO, DT)
		game.coups.maj(DT)


func case(game: BkGame, a: BkActor) -> Vector2i:
	return game.map.to_tile(a.position)


func inst(game: BkGame) -> BkCoupActif:
	return game.coups.actifs.back() if not game.coups.actifs.is_empty() else null


# ------------------------------------------------------------------ Txomin

## Fil d'Ariane : la bouée vole vers le coéquipier en détresse (jauge ≥ 30 %), le tracte jusqu'à Txomin
## (aide : passe la protection) ; gerbe d'eau sur le chasseur à 4 cases (+2) ; personne à sauver : rien.
func test_fil_ariane() -> void:
	var game: BkGame = await partie("louis", "txomin", [[26, 12], [31, 12]])
	var tx: BkActor = game.actors[1]
	var al: BkActor = game.actors[2]
	tx.look = 0.0
	r.check(game.coups.lance(tx) == "Personne à sauver" and tx.coup_cd <= 0.0, "personne en détresse : rien, recharge gardée")
	al.gauge = 0.5
	al.protection = 1.0
	var s0: int = tx.score
	r.check(game.coups.lance(tx) == "", "la bouée part vers le coéquipier en détresse")
	vit(game, 0.5)
	r.check(BkEffets.actif(al, "tracte") and bool(BkEffets.params(al, "tracte").get("aide", false)), "coéquipier tracté (aide, malgré sa protection)")
	r.check(BkEffets.actif(game.hunter, "aveugle") and str(BkEffets.params(game.hunter, "aveugle").get("masque", "")) == "eau",
		"gerbe d'eau : écran du chasseur masqué")
	r.check(tx.score == s0 + BkRules.score("hider_coup_touche"), "chasseur touché : +2")
	vit(game, 1.0)
	r.check(al.position.distance_to(tx.position) < 1.6 * game.map.tile, "tiré jusqu'à Txomin (%.1f cases)" % (al.position.distance_to(tx.position) / game.map.tile))
	await r.free_game(game)


## Coup de sifflet : les chassés qui bougent à 8 cases sont figés 2 s ; les immobiles, rien.
func test_sifflet() -> void:
	var game: BkGame = await partie("txomin", "louis", [[28, 12], [24, 9]])
	var a1: BkActor = game.actors[1]
	var a2: BkActor = game.actors[2]
	a1.immobile_t = 0.0
	a2.immobile_t = 4.0
	r.check(game.coups.lance(game.hunter) == "", "le sifflet part")
	r.check(BkEffets.actif(a1, "fige") and r.near(float(a1.effets["fige"]["left"]), 2.0, 1e-6), "chassé qui bouge : figé 2 s")
	r.check(not BkEffets.actif(a2, "fige"), "chassé immobile : rien")
	await r.free_game(game)


# ------------------------------------------------------------------ Patxi

## Appât de sardines : seau derrière Patxi ; le chasseur qui y entre est leurré (fausses traces vers
## ailleurs, l'IA croit entendre quelqu'un là-bas) et Patxi marque +2 ; le seau disparaît après 4 s.
func test_appat() -> void:
	var game: BkGame = await partie("louis", "patxi", [[30, 12]])
	var px: BkActor = game.actors[1]
	var h: BkActor = game.hunter
	game.brains[h.id] = BkAi.new(game, h, "normal")
	px.look = 0.0
	r.check(game.coups.lance(px) == "", "le seau part")
	var seau: BkCoupPose = inst(game) as BkCoupPose
	r.check(seau != null and seau.pos.x < px.position.x - game.map.tile * 0.5, "seau posé derrière Patxi")
	var s0: int = px.score
	h.position = seau.pos
	vit(game, 0.5)
	r.check(seau.leurre > 0.0 and px.score == s0 + BkRules.score("hider_coup_touche"), "chasseur leurré : +2")
	r.check(seau.faux_but != Vector2.INF and seau.faux_but.distance_to(seau.pos) > 3.5 * game.map.tile, "fausses traces vers ailleurs")
	var ai: BkAi = game.brains[h.id]
	r.check(ai.clue != Vector2.INF and ai.clue.distance_to(seau.faux_but) < 2.0 * game.map.tile, "chasseur IA : il va voir là où vont les traces")
	vit(game, 1.0)
	r.check(not seau.faux_pas.is_empty(), "fausses traces posées (%d)" % seau.faux_pas.size())
	vit(game, 3.0)
	r.check(game.coups.actifs.is_empty(), "leurre fini")
	await r.free_game(game)


## La prise au vol : la ligne part droit devant (8 cases) et tire de 4 cases le chassé accroché.
func test_prise_au_vol() -> void:
	var game: BkGame = await partie("patxi", "louis", [[31, 12]])
	var a1: BkActor = game.actors[1]
	var x0: float = a1.position.x
	r.check(game.coups.lance(game.hunter) == "", "la ligne part")
	vit(game, 0.6)
	r.check(BkEffets.actif(a1, "tracte") or a1.position.x < x0 - game.map.tile, "chassé accroché")
	vit(game, 1.2)
	var tire: float = (x0 - a1.position.x) / game.map.tile
	r.check(tire > 3.0 and tire < 4.6, "tiré d'environ 4 cases (%.1f)" % tire)
	await r.free_game(game)


# ------------------------------------------------------------------ Maïa

## Le canard : plongeon de 2 cases ; 1,5 s invisible et intouchable, la jauge ne monte pas.
func test_canard() -> void:
	var game: BkGame = await partie("louis", "maia", [[27, 12]])
	var m: BkActor = game.actors[1]
	m.look = 0.0
	var x0: float = m.position.x
	r.check(game.coups.lance(m) == "", "le plongeon part")
	r.check(BkEffets.actif(m, "invisible") and BkEffets.actif(m, "insensible"), "invisible et insensible")
	r.tick(game, 0.6)
	vit(game, 0.6)
	r.check(r.near((m.position.x - x0) / game.map.tile, 2.0, 0.15), "avance de 2 cases (%.2f)" % ((m.position.x - x0) / game.map.tile))
	r.check(m.gauge <= 0.0, "devant le chasseur, la jauge ne monte pas")
	r.check(not game.coups.applique_effet(m, "fige", 1.0), "intouchable")
	vit(game, 1.0)
	r.check(not BkEffets.actif(m, "invisible"), "visible après 1,5 s")
	await r.free_game(game)


## Take-off foudroyant : +80 % de vitesse pendant 4 s.
func test_take_off() -> void:
	var game: BkGame = await partie("maia", "louis")
	var h: BkActor = game.hunter
	var v0: float = h.speed()
	r.check(game.coups.lance(h) == "", "take-off")
	r.check(r.near(h.speed() / v0, 1.8, 1e-3), "vitesse × 1,8")
	vit(game, 4.1)
	r.check(r.near(h.speed(), v0, 1e-3), "fini au bout de 4 s")
	await r.free_game(game)


# ------------------------------------------------------------------ Xabi

## Rebond d'urgence : collé à un mur, dash de 3 cases à l'opposé (même en regardant le mur) ; sinon
## droit devant.
func test_rebond() -> void:
	var game: BkGame = await partie("louis", "xabi", [[21, 11]])
	var x: BkActor = game.actors[1]
	x.position.x = 21.0 * game.map.tile + x.radius + 1.0
	x.look = PI
	var x0: float = x.position.x
	r.check(game.map.at(Vector2i(20, 11)) == "#", "précondition : mur à l'ouest")
	r.check(game.coups.lance(x) == "", "le rebond part")
	vit(game, 0.5)
	r.check(r.near((x.position.x - x0) / game.map.tile, 3.0, 0.1), "3 cases à l'opposé du mur (%.2f)" % ((x.position.x - x0) / game.map.tile))
	r.check(not x.en_coup and x.collision_mask == BkMap.LAYER_MOVE, "posé, collisions rendues")
	x.coup_cd = 0.0
	x.position = pos(game, 27, 11)
	x.look = PI * 0.5
	var y0: float = x.position.y
	game.coups.lance(x)
	vit(game, 0.5)
	r.check(r.near((x.position.y - y0) / game.map.tile, 3.0, 0.1), "loin des murs : droit devant (%.2f)" % ((x.position.y - y0) / game.map.tile))
	await r.free_game(game)


## Le tir crayon : la pelote ricoche sur le mur et colle (2 s) et révèle (3 s) le chassé touché.
func test_tir_crayon() -> void:
	var game: BkGame = await partie("xabi", "louis", [[27, 12]])
	var h: BkActor = game.hunter
	var a1: BkActor = game.actors[1]
	h.position = pos(game, 22, 12)
	h.look = PI
	r.check(game.coups.lance(h) == "", "la pelote part vers le mur")
	var pel: BkCoupLance = inst(game) as BkCoupLance
	vit(game, 1.0)
	r.check(pel.rebonds == 2, "un ricochet (%d restants)" % pel.rebonds)
	r.check(BkEffets.actif(a1, "colle") and BkEffets.actif(a1, "revele"), "chassé derrière le chasseur touché au rebond : collé et révélé")
	r.check(r.near(float(a1.effets["revele"]["duree"]), 3.0, 1e-6) and r.near(float(a1.effets["colle"]["duree"]), 2.0, 1e-6), "collé 2 s, révélé 3 s")
	await r.free_game(game)


# ------------------------------------------------------------------ Mattin

## Endurance : 4 s insensible ; trouvé pendant ce temps, la capture est annulée et le chasseur reculé
## d'une case, une fois par round.
func test_endurance() -> void:
	var game: BkGame = await partie("louis", "mattin", [[26, 12]])
	var mt: BkActor = game.actors[1]
	var h: BkActor = game.hunter
	r.check(game.coups.lance(mt) == "", "Endurance")
	r.check(BkEffets.actif(mt, "insensible") and not game.coups.applique_effet(mt, "renverse", 2.0), "insensible à tout")
	var hx: float = h.position.x
	game._found(mt)
	r.check(mt.role == BkActor.Role.HIDER and mt.gauge == 0.0, "capture annulée")
	r.check(r.near((hx - h.position.x) / game.map.tile, 1.0, 0.05), "chasseur repoussé d'une case (%.2f)" % ((hx - h.position.x) / game.map.tile))
	r.check(int(game._st["captures_annulees"]) == 1, "comptée")
	game._found(mt)
	r.check(mt.role == BkActor.Role.GHOST, "une seule fois par round")
	await r.free_game(game)


## La pierre traqueuse : elle roule vers le chassé visible le plus proche (même pas devant) et le renverse.
func test_pierre() -> void:
	var game: BkGame = await partie("mattin", "louis", [[24, 15], [33, 12]])
	var h: BkActor = game.hunter
	h.look = -PI * 0.5
	r.check(game.coups.lance(h) == "", "la pierre part")
	var pi_: BkCoupLance = inst(game) as BkCoupLance
	r.check(pi_.suivie == game.actors[1], "elle vise le plus proche visible")
	vit(game, 1.5)
	r.check(BkEffets.actif(game.actors[1], "renverse"), "renversé")
	r.check(not BkEffets.actif(game.actors[2], "renverse"), "l'autre, rien")
	await r.free_game(game)


# ------------------------------------------------------------------ Amaia

## Mutxiko : +30 % 4 s, insensible aux effets au sol (le reste passe), sans traces pour Cache-Cache !
func test_mutxiko() -> void:
	var game: BkGame = await partie("louis", "amaia", [[28, 12]])
	var am: BkActor = game.actors[1]
	var v0: float = am.speed()
	r.check(game.coups.lance(am) == "", "Mutxiko")
	r.check(r.near(am.speed() / v0, 1.3, 1e-3), "+30 %")
	r.check(not game.coups.applique_effet(am, "revele", 2.0, {"au_sol": true}), "effet au sol refusé")
	game.hunter.coup_cd = 0.0
	game.coups.lance(game.hunter)
	var pis: BkCoupRevele = inst(game) as BkCoupRevele
	var n0: int = pis.pas.size()
	vit(game, 1.0, {am.id: Vector2.DOWN})
	r.check(pis.cible == am and pis.pas.size() == n0, "pas de traces de pas")
	r.check(game.coups.applique_effet(am, "fige", 1.0), "effet qui n'est pas au sol : il passe")
	await r.free_game(game)


## Sonnerie du makila : les chassés immobiles depuis 2 s à 8 cases tintent et brillent (révélés 2 s).
func test_makila() -> void:
	var game: BkGame = await partie("amaia", "louis", [[29, 12], [24, 15]])
	game.actors[1].immobile_t = 3.0
	game.actors[2].immobile_t = 0.5
	r.check(game.coups.lance(game.hunter) == "", "le makila sonne")
	r.check(BkEffets.actif(game.actors[1], "revele") and r.near(float(game.actors[1].effets["revele"]["left"]), 2.0, 1e-6), "immobile : révélé 2 s")
	r.check(not BkEffets.actif(game.actors[2], "revele"), "il bougeait : rien")
	r.check(game.coups.bulles.any(func(b: Dictionary) -> bool: return int(b["id"]) == game.actors[1].id), "« ding ! »")
	await r.free_game(game)


# ------------------------------------------------------------------ Kaio

## Battement de plumes : 3 s de vol au-dessus du muret (pas des murs), puis il se pose sur une case libre.
func test_vol() -> void:
	var game: BkGame = await partie("louis", "kaio", [[24, 17]])
	var k: BkActor = game.actors[1]
	r.check(game.map.at(Vector2i(24, 16)) == "m", "précondition : muret en (24, 16)")
	r.check(game.coups.lance(k) == "", "envol")
	vit(game, 1.0, {k.id: Vector2.UP})
	r.check(case(game, k).y <= 15, "au-dessus du muret (%s)" % case(game, k))
	k.position = pos(game, 21, 11)
	vit(game, 0.5, {k.id: Vector2.LEFT})
	r.check(case(game, k).x == 21, "le mur l'arrête (%s)" % case(game, k))
	vit(game, 2.5)
	r.check(not k.en_coup and game.map.walkable(case(game, k)) and k.collision_mask == BkMap.LAYER_MOVE, "posé sur une case libre")
	await r.free_game(game)


## Cri strident : commandes inversées 2 s à 5 cases ; qui bouge pendant ce temps est révélé 3 s.
func test_cri() -> void:
	var game: BkGame = await partie("kaio", "louis", [[27, 12], [24, 9]])
	var a1: BkActor = game.actors[1]
	var a2: BkActor = game.actors[2]
	r.check(game.coups.lance(game.hunter) == "", "cri")
	r.check(BkEffets.actif(a1, "inverse") and BkEffets.actif(a2, "inverse") and r.near(float(a1.effets["inverse"]["left"]), 2.0, 1e-6),
		"commandes inversées 2 s")
	var x0: float = a1.position.x
	vit(game, 0.5, {a1.id: Vector2.RIGHT})
	r.check(a1.position.x < x0, "inversé : il part à l'opposé")
	r.check(BkEffets.actif(a1, "revele") and not BkEffets.actif(a2, "revele"), "qui bouge perd des plumes (révélé), pas l'immobile")
	await r.free_game(game)


# ------------------------------------------------------------------ Karramarro

## L'enfouissement : seulement sur le sable ; invisible tant qu'il ne bouge pas ; s'il bouge, il ressort
## avec un bruit de sable.
func test_enfouissement() -> void:
	var game: BkGame = await partie("louis", "karramarro", [[30, 12]])
	var kr: BkActor = game.actors[1]
	r.check(game.coups.lance(kr) == "Pas de sable ici" and kr.coup_cd <= 0.0, "hors du sable : rien")
	kr.position = pos(game, 46, 12)
	r.check(game.map.meuble(Vector2i(46, 12)), "précondition : sable")
	r.check(game.coups.lance(kr) == "", "il s'enfouit")
	vit(game, 2.0)
	r.check(BkEffets.actif(kr, "invisible") and game.coups.garde_immobile(kr), "enfoui, invisible ; l'IA reste immobile")
	vit(game, 0.2, {kr.id: Vector2.RIGHT})
	r.check(not BkEffets.actif(kr, "invisible") and game.coups.actifs.is_empty(), "il bouge : il ressort")
	r.check(game.coups.bulles.any(func(b: Dictionary) -> bool: return str(b["texte"]).contains("frr")), "bruit de sable")
	await r.free_game(game)


## Débordement crabe : glissade très rapide de 4 cases dans sa direction.
func test_glissade() -> void:
	var game: BkGame = await partie("karramarro", "louis")
	var h: BkActor = game.hunter
	var x0: float = h.position.x
	r.check(game.coups.lance(h) == "", "glissade")
	vit(game, 0.4)
	r.check(r.near((h.position.x - x0) / game.map.tile, 4.0, 0.1), "4 cases en 0,35 s (%.2f)" % ((h.position.x - x0) / game.map.tile))
	await r.free_game(game)


# ------------------------------------------------------------------ Ramuntxo

## Gâteau du partage : un chassé qui passe gagne +30 % 3 s (un usage) ; le chasseur qui passe s'arrête
## 1,5 s pour le humer (+2 au poseur).
func test_gateau_partage() -> void:
	var game: BkGame = await partie("louis", "ramuntxo", [[30, 12], [33, 12]])
	var rm: BkActor = game.actors[1]
	var a2: BkActor = game.actors[2]
	r.check(game.coups.lance(rm) == "", "gâteau posé")
	vit(game, 0.5)
	r.check(game.coups.actifs.size() == 1 and not BkEffets.actif(rm, "rapide"), "le poseur ne le déclenche pas")
	a2.position = rm.position
	vit(game, 0.1)
	r.check(BkEffets.actif(a2, "rapide") and r.near(float(a2.effets["rapide"]["duree"]), 3.0, 1e-6), "chassé : +30 % 3 s")
	r.check(game.coups.actifs.is_empty(), "un usage : il disparaît")
	rm.coup_cd = 0.0
	game.coups.lance(rm)
	var s0: int = rm.score
	game.hunter.position = rm.position + Vector2(game.map.tile, 0)
	vit(game, 0.1)
	r.check(BkEffets.actif(game.hunter, "fige") and r.near(float(game.hunter.effets["fige"]["duree"]), 1.5, 1e-6), "chasseur : il hume 1,5 s")
	r.check(rm.score == s0 + BkRules.score("hider_coup_touche"), "+2 au poseur")
	await r.free_game(game)


## Pot de piment : lancé devant, nuage rouge de 2 cases ; les chassés dedans toussent, révélés 3 s.
func test_pot_piment() -> void:
	var game: BkGame = await partie("ramuntxo", "louis", [[29, 12], [30, 13]])
	r.check(game.coups.lance(game.hunter) == "", "le pot part")
	var pot: BkCoupLance = inst(game) as BkCoupLance
	vit(game, 0.8)
	r.check(pot.etat == BkCoupLance.Etat.NUAGE, "nuage")
	r.check(BkEffets.actif(game.actors[1], "revele") and BkEffets.actif(game.actors[2], "revele"), "les deux chassés dans le nuage : révélés")
	r.check(bool(BkEffets.params(game.actors[1], "revele").get("toux", false)), "par la toux")
	r.check(game.coups.bulles.any(func(b: Dictionary) -> bool: return str(b["texte"]).contains("kof")), "« kof kof ! »")
	vit(game, 4.6)
	r.check(game.coups.actifs.is_empty(), "le nuage se dissipe après 4 s")
	await r.free_game(game)


# ------------------------------------------------------------------ Itsaso

## Bâtisse éclair : muret de 3 cases derrière Itsaso, qui bloque la vue, le passage et la grille des IA
## pendant 4 s, puis disparaît proprement.
func test_muret() -> void:
	var game: BkGame = await partie("louis", "itsaso", [[30, 12]])
	var it: BkActor = game.actors[1]
	var m: BkMap = game.map
	it.look = 0.0
	r.check(game.coups.lance(it) == "", "le muret jaillit")
	var mur: BkCoupPose = inst(game) as BkCoupPose
	r.check(mur.cases.size() == 3 and mur.cases.has(Vector2i(29, 12)) and mur.cases.has(Vector2i(29, 11)) and mur.cases.has(Vector2i(29, 13)),
		"3 cases derrière elle (%s)" % str(mur.cases))
	await r.physics_frame
	r.check(not m.walkable(Vector2i(29, 12)) and m.astar.is_point_solid(Vector2i(29, 12)), "passage et grille des IA bloqués")
	r.check(not game.clear_line(pos(game, 27, 12), pos(game, 31, 12)), "vue bloquée")
	var a2: BkActor = game.actors[2]
	a2.position = pos(game, 27, 12)
	vit(game, 0.5, {a2.id: Vector2.RIGHT})
	r.check(a2.position.x < 29.0 * m.tile, "on ne passe pas")
	vit(game, 3.6)
	await r.physics_frame
	r.check(game.coups.actifs.is_empty() and m.walkable(Vector2i(29, 12)) and not m.astar.is_point_solid(Vector2i(29, 12)),
		"après 4 s : passage rendu")
	r.check(game.clear_line(pos(game, 27, 12), pos(game, 31, 12)), "vue rendue")
	# Une case occupée par un perso est sautée.
	it.coup_cd = 0.0
	a2.position = pos(game, 29, 11)
	game.coups.lance(it)
	r.check(not (inst(game) as BkCoupPose).cases.has(Vector2i(29, 11)), "case occupée sautée")
	await r.free_game(game)


## Courant des laminak : geysers sur les cachettes à 10 cases ; le chassé caché est éjecté et révélé 2 s.
func test_geysers() -> void:
	var game: BkGame = await partie("itsaso", "louis", [[33, 13]])
	var h: BkActor = game.hunter
	h.position = pos(game, 32, 12)
	var a1: BkActor = game.actors[1]
	var ci: int = -1
	for i: int in game.cachettes.size():
		if game.cachettes[i]["tile"] == Vector2i(35, 14):
			ci = i
	r.check(ci >= 0, "précondition : cachette en (35, 14)")
	game._enter_cachette(a1, ci)
	r.check(game.coups.lance(h) == "", "les geysers jaillissent")
	vit(game, 1.0)
	r.check(a1.hidden_in < 0 and BkEffets.actif(a1, "revele"), "éjecté de sa cachette et révélé")
	r.check(float(game.cachettes[ci]["lock"]) > 0.0, "cachette fermée un moment")
	await r.free_game(game)


# ------------------------------------------------------------------ Peio

## Feinte de passe : pas de côté de 2 cases ; jauge > 70 % : elle retombe à 0 et +30 % 2 s ; sinon
## seulement le pas de côté.
func test_feinte() -> void:
	var game: BkGame = await partie("louis", "peio", [[28, 12]])
	var p: BkActor = game.actors[1]
	p.look = 0.0
	p.gauge = 0.8
	var y0: float = p.position.y
	r.check(game.coups.lance(p) == "", "feinte")
	r.check(r.near(absf(p.position.y - y0) / game.map.tile, 2.0, 0.1), "pas de côté de 2 cases (%.2f)" % (absf(p.position.y - y0) / game.map.tile))
	r.check(p.gauge == 0.0 and BkEffets.actif(p, "rapide"), "jauge à 0, +30 %")
	BkEffets.efface(p)
	p.coup_cd = 0.0
	p.position = pos(game, 28, 12)
	p.gauge = 0.4
	game.coups.lance(p)
	r.check(r.near(p.gauge, 0.4, 1e-6) and not BkEffets.actif(p, "rapide"), "jauge basse : pas de bonus (appuyé à vide, il part quand même)")
	r.check(p.coup_cd > 0.0, "et repart en recharge")
	await r.free_game(game)


## Troisième mi-temps : ralentis de 30 % 3 s à 7 cases ; Peio voit leurs pas 3 s.
func test_troisieme_mi_temps() -> void:
	var game: BkGame = await partie("peio", "louis", [[29, 12], [24, 9]])
	var a1: BkActor = game.actors[1]
	var v0: float = a1.speed()
	r.check(game.coups.lance(game.hunter) == "", "cri de guerre")
	r.check(r.near(a1.speed() / v0, 0.7, 1e-3) and BkEffets.actif(game.actors[2], "ralenti"), "ralentis de 30 %")
	var z: BkCoupZone = inst(game) as BkCoupZone
	vit(game, 1.0, {a1.id: Vector2.DOWN})
	r.check(z.pas.size() >= 3, "Peio voit ses pas (%d)" % z.pas.size())
	await r.free_game(game)


# ------------------------------------------------------------------ Itsasargi

## Feu à occultation : chasseur à 6 cases qui regarde vers lui : écran noir 2 s (+2) ; s'il regarde
## ailleurs, rien.
func test_flash() -> void:
	var game: BkGame = await partie("louis", "itsasargi", [[28, 12]])
	var ia: BkActor = game.actors[1]
	var h: BkActor = game.hunter
	h.look = PI
	r.check(game.coups.lance(ia) == "" and not BkEffets.actif(h, "aveugle"), "chasseur de dos : rien")
	ia.coup_cd = 0.0
	h.look = 0.0
	var s0: int = ia.score
	game.coups.lance(ia)
	r.check(BkEffets.actif(h, "aveugle") and r.near(float(h.effets["aveugle"]["left"]), 2.0, 1e-6), "il regarde : écran noir 2 s")
	r.check(ia.score == s0 + BkRules.score("hider_coup_touche"), "+2")
	await r.free_game(game)


## Éclat révélateur : faisceau de 10 cases ; tous les chassés sur la ligne sont révélés 3 s et ralentis.
func test_eclat() -> void:
	var game: BkGame = await partie("itsasargi", "louis", [[28, 12], [32, 12]])
	r.check(game.coups.lance(game.hunter) == "", "faisceau")
	for a: BkActor in [game.actors[1], game.actors[2]]:
		r.check(BkEffets.actif(a, "revele") and BkEffets.actif(a, "ralenti"), "%s : révélé et ralenti" % a.display_name)
	await r.free_game(game)


# ------------------------------------------------------------------ IA

## Quelques décisions de l'IA : le chasseur lance sur une cible vue à portée (pas sans cible) ; la
## bouée part vers un coéquipier en détresse ; la feinte en urgence ; le gâteau quand le chasseur
## approche ; l'enfouissement seulement sur le sable ; les geysers près d'un indice.
func test_ia_coups() -> void:
	var game: BkGame = await partie("xabi", "louis", [[29, 12], [24, 19]])
	var h: BkActor = game.hunter
	var a1: BkActor = game.actors[1]
	r.check(not game.coups.essaie_ia(h, {"cible_probable": true}), "chasseur sans cible : pelote gardée")
	r.check(game.coups.essaie_ia(h, {"cible_probable": true, "cible": a1, "vers": a1.position}), "cible vue à portée : pelote")
	h.character = "itsaso"
	h.coup_cd = 0.0
	r.check(not game.coups.essaie_ia(h, {"cible_probable": true, "vers": pos(game, 2, 2)}), "geysers : indice loin des cachettes, rien")
	h.position = pos(game, 32, 12)
	r.check(game.coups.essaie_ia(h, {"cible_probable": true, "vers": pos(game, 34, 13)}), "geysers : indice près d'une cachette")
	# Chassés.
	var a2: BkActor = game.actors[2]
	a1.character = "txomin"
	a2.position = pos(game, 32, 12)
	r.check(not game.coups.essaie_ia(a1, {"menace": false}), "bouée : personne en détresse")
	a2.gauge = 0.4
	r.check(game.coups.essaie_ia(a1, {"menace": false}), "bouée : coéquipier en détresse")
	a1.character = "peio"
	a1.coup_cd = 0.0
	r.check(game.coups.essaie_ia(a1, {"menace": true, "urgence": true}), "feinte en urgence")
	a1.character = "karramarro"
	a1.coup_cd = 0.0
	r.check(not game.coups.essaie_ia(a1, {"menace": true}), "enfouissement hors du sable : non")
	a1.character = "ramuntxo"
	a1.coup_cd = 0.0
	h.position = a1.position + Vector2(4.0 * game.map.tile, 0)
	r.check(game.coups.essaie_ia(a1, {"menace": true}), "gâteau quand le chasseur approche")
	await r.free_game(game)
