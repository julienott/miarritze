extends SceneTree
## Tests headless de Blackout : détection progressive (jauge, seuils), ressenti du chassé, mesures
## de tension (frôlements, vu puis perdu), une partie IA contre IA courte, et la partie en N rounds
## (tirage en sac, versus, podium), la partie rapide (réglages → règles), le profil (persistance),
## la carte bac à sable (cases de vue et de passage), les persos en pixel art (planches et repli),
## la lumière et l'ombre (éclairé derrière un mur, jauge 3 fois plus lente, silhouette), les
## disjoncteurs (coupure de 15 s, recharge, rallumage par le chasseur, priorité du bouton), le menu
## debug et les coups spéciaux (données, recharge et gâteaux, plafond des effets et protection, aimant de
## visée, Passe-Muraille, Cache-Cache !, pièges et onde retirés), les éléments livrés joués dans leur cas
## (effets subis, interagir, lancements, victoire et défaite, fantôme commun), les PNJ sur la carte, plus les 24 autres coups
## (tests/bk_coups_tests.gd, un test par coup).
## godot --headless --path . --fixed-fps 60 --script res://tests/bk_tests.gd [-- --only=nom]

const GAME: String = "res://src/blackout/bk_game.tscn"
const DT: float = 1.0 / 60.0

var _failures: int = 0
var _passed: int = 0
var _only: String = ""
var _saved: Dictionary = {}
var _saved_cfg: Dictionary = {}
## Tests des coups de l'étape 4 (gardés en vie pendant l'exécution).
var _coups_tests: RefCounted


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			_only = arg.trim_prefix("--only=")
	_saved = BkRules.data().duplicate(true)
	_saved_cfg = BkGame.config.duplicate(true)
	_run.call_deferred()


func _run() -> void:
	var tests: Array[Callable] = [test_jauge_remplissage, test_jauge_decroissance, test_jauge_sans_detection,
		test_frisson_intensite, test_frisson_coeur, test_frisson_local, test_frolements, test_vu_perdu, test_capture_pas_frolement, test_poursuite, test_poursuite_tous_vus, test_vue_objet_bas,
		test_options_partie, test_partie_ia_courte, test_rounds_pour, test_sac, test_versus_saute_en_ia,
		test_rounds_fixes_podium, test_partie_rapide_options, test_profil_persiste, test_pseudo, test_roster,
		test_persos_px32, test_sets_pnj_boss, test_cases_vue_passage, test_bac_a_sable, test_regles_carte,
		test_eclaire_mur, test_ombre_facteur, test_ombre_capture_silhouette, test_disjoncteur,
		test_disjoncteur_priorite, test_disjoncteur_ia, test_menu_debug, test_coups_donnees, test_recharge,
		test_plafond_protection, test_aimant, test_passe_muraille, test_cache_cache, test_pieges_retires,
		test_elements_livres_et_replis, test_effets_animes, test_gestes_et_fin, test_fantome_commun, test_foule_pnj]
	# Les 24 coups de l'étape 4 (un test par coup) : tests/bk_coups_tests.gd.
	_coups_tests = preload("res://tests/bk_coups_tests.gd").new(self)
	tests.append_array(_coups_tests.tests())
	for t: Callable in tests:
		if _only != "" and not t.get_method().contains(_only):
			continue
		BkRules._data = _saved.duplicate(true)
		BkGame.config = _saved_cfg.duplicate(true)
		var before: int = _failures
		var start: int = Time.get_ticks_msec()
		await t.call()
		if _failures == before:
			_passed += 1
		print("[%s] %s (%d ms)" % ["OK " if _failures == before else "ÉCHEC", t.get_method(), Time.get_ticks_msec() - start])
	print("\n%d réussis, %d échecs" % [_passed, _failures])
	quit(1 if _failures > 0 else 0)


func check(cond: bool, message: String) -> void:
	if not cond:
		_failures += 1
		printerr("    ✗ " + message)


func near(a: float, b: float, eps: float) -> bool:
	return absf(a - b) <= eps


## Secondes pour remplir la jauge (vu en continu à `d` px, part visible `vis`).
func fill_time(d: float, vis: float) -> float:
	var g: float = 0.0
	var t: float = 0.0
	while g < 1.0 and t < 10.0:
		g = BkGame.next_gauge(g, vis, d, DT)
		t += DT
	return t


# ------------------------------------------------------------------ options de partie

## Catalogue des options validées (futur menu de création de partie) : chaque clé existe dans
## rules.json, les choix sont bornés et seules les clés déclarées sont acceptées.
func test_options_partie() -> void:
	var opts: Array = BkRules.options_partie()
	check(not opts.is_empty(), "options_partie.json vide ou illisible")
	for o: Dictionary in opts:
		for r: Dictionary in o.get("reglages", []):
			check(BkRules.data().has(str(r["cle"])), "clé inconnue de rules.json : " + str(r["cle"]))
	BkRules.appliquer_options({"gateaux_nombre": 99, "idee_gateaux": 0, "pas_une_option": 5})
	check(near(BkRules.f("gateaux_nombre"), 8.0, 0.001), "curseur non borné")
	check(not BkRules.on("idee_gateaux"), "on/off non appliqué")
	check(not BkRules.data().has("pas_une_option"), "clé non déclarée acceptée")


# ------------------------------------------------------------------ jauge de détection

func test_jauge_remplissage() -> void:
	BkRules._data["idee_detection"] = 1.0
	var tile: float = BkRules.f("tile_px")
	var near_px: float = BkRules.px("near_radius")
	var far_px: float = BkRules.px("cone_range")
	var t_near: float = fill_time(near_px, 1.0)
	var t_far: float = fill_time(far_px, 1.0)
	check(near(t_near, BkRules.f("detection_temps_pres"), 2.0 * DT), "tout près : pleine en %.2f s (attendu %.2f)" % [t_near, BkRules.f("detection_temps_pres")])
	check(near(t_far, BkRules.f("detection_temps_loin"), 2.0 * DT), "au bout du cône : pleine en %.2f s (attendu %.2f)" % [t_far, BkRules.f("detection_temps_loin")])
	# Plus près = plus vite, de façon monotone ; dans le petit cercle, la vitesse la plus forte.
	var last: float = 0.0
	for k: int in 8:
		var tk: float = fill_time(near_px + (far_px - near_px) * k / 7.0, 1.0)
		check(tk >= last - 1e-6, "remplissage monotone avec la distance (%d)" % k)
		last = tk
	check(near(fill_time(0.5 * tile, 1.0), t_near, DT), "dans le petit cercle : vitesse maximale")
	# Vu en partie : plus lent, d'autant plus que la part vue est petite.
	var t_part: float = fill_time(far_px * 0.5, 1.0 / 3.0)
	check(t_part > fill_time(far_px * 0.5, 2.0 / 3.0) and fill_time(far_px * 0.5, 2.0 / 3.0) > fill_time(far_px * 0.5, 1.0),
		"vu en partie : plus lent")
	check(near(BkGame.detection_rate(far_px, 0.0) * BkRules.f("detection_temps_loin"), BkRules.f("detection_partiel"), 1e-4),
		"part vue nulle : vitesse × detection_partiel")


func test_jauge_decroissance() -> void:
	BkRules._data["idee_detection"] = 1.0
	var dec: float = BkRules.f("detection_decroissance")
	var g: float = 0.8
	var t: float = 0.0
	while g > 0.0 and t < 10.0:
		g = BkGame.next_gauge(g, 0.0, 0.0, DT)
		t += DT
	check(near(t, 0.8 / dec, 2.0 * DT), "hors de vue : redescend en %.2f s (attendu %.2f)" % [t, 0.8 / dec])
	check(g == 0.0, "jamais sous zéro")
	# Redescente plus lente que la montée de près : un frôlement laisse le temps de voir le « ? ».
	check(dec < 1.0 / BkRules.f("detection_temps_pres"), "redescend plus lentement qu'elle ne monte de près")
	# Seuil du « ? » franchi avant la capture, à toute distance.
	var g2: float = BkGame.next_gauge(0.0, 1.0, BkRules.px("near_radius"), DT)
	check(g2 < BkRules.f("detection_doute"), "le « ? » n'est pas immédiat (une image ne suffit pas)")
	check(BkRules.f("detection_doute") > 0.0 and BkRules.f("detection_doute") < 1.0, "seuil du « ? » entre 0 et 1")


func test_jauge_sans_detection() -> void:
	BkRules._data["idee_detection"] = 0.0
	var t: float = fill_time(BkRules.px("cone_range"), 1.0 / 3.0)
	check(near(t, BkRules.f("capture_time"), 2.0 * DT), "règle d'avant : capture en capture_time à toute distance (%.2f s)" % t)
	var g: float = BkGame.next_gauge(0.5, 0.0, 0.0, 0.1)
	check(near(g, 0.5 - 0.1 * BkRules.f("capture_decay") / BkRules.f("capture_time"), 1e-5), "règle d'avant : vidage rapide")


# ------------------------------------------------------------------ ressenti du chassé

func test_frisson_intensite() -> void:
	var tile: float = BkRules.f("tile_px")
	check(BkFrisson.intensity(BkRules.px("frisson_portee") + tile, 0.0) == 0.0, "rien au-delà de frisson_portee")
	check(near(BkFrisson.intensity(0.0, 0.0), 1.0, 1e-5), "maximum au contact")
	var last: float = 2.0
	for k: int in 10:
		var v: float = BkFrisson.intensity(tile * k, 0.0)
		check(v <= last + 1e-6, "décroît avec la distance (%d cases)" % k)
		last = v
	check(BkFrisson.intensity(BkRules.px("frisson_portee") + tile, 0.2) >= 0.7, "en train d'être vu : au moins fort, même de loin")


func test_frisson_coeur() -> void:
	var s: AudioStreamWAV = BkFrisson.heartbeat_stream()
	check(s.data.size() > 4000 and s.get_length() > 0.3, "battement de cœur généré (%.2f s)" % s.get_length())


## En partie : le chassé local ressent le chasseur proche ; le chasseur, lui, jamais.
func test_frisson_local() -> void:
	BkRules._data["idee_frisson"] = 1.0
	var game: BkGame = await make_game()
	var me: BkActor = game.actors[1]
	game.local = me
	me.position = game.hunter.position + Vector2(-2.5 * game.map.tile, 0)
	for i: int in 30:
		game.frisson._process(DT)
	check(game.frisson.level > 0.5, "chassé à 2,5 cases du chasseur : frisson fort (%.2f)" % game.frisson.level)
	check(game.frisson.search_near == 0.0, "pas de « il fouille à côté » sans fouille")
	game.hunter.search_left = 1.0
	game.frisson._process(DT)
	check(game.frisson.search_near > 0.0, "le chasseur fouille à côté : « Il fouille à côté ! »")
	game.hunter.search_left = 0.0
	me.position = game.hunter.position + Vector2(-(BkRules.f("frisson_portee") + 2.0) * game.map.tile, 0)
	for i: int in 60:
		game.frisson._process(DT)
	check(game.frisson.level < 0.05, "loin : plus de frisson (%.2f)" % game.frisson.level)
	game.local = game.hunter
	for i: int in 60:
		game.frisson._process(DT)
	check(game.frisson.level == 0.0, "le chasseur n'a pas de frisson")
	await free_game(game)


# ------------------------------------------------------------------ mesures de tension

## Case du chasseur des tests (carte bac à sable) : au milieu de la Place, une ligne dégagée d'au moins
## 8 cases devant lui, vers l'est.
const CHASSEUR: Vector2i = Vector2i(24, 12)


## Partie posée sur la carte, sans boucle de jeu : on place les acteurs et on appelle la capture et
## les mesures à la main. Chasseur = acteur 0 en CHASSEUR regardant vers l'est. `pleine_lumiere` :
## une grande source (secteur « T ») sur le chasseur éclaire tout ce qu'il voit, pour tester la
## détection comme avant la lumière (GDD §3.2 : un chassé éclairé est détecté à la vitesse normale).
func make_game(pleine_lumiere: bool = true) -> BkGame:
	var game: BkGame = (load(GAME) as PackedScene).instantiate()
	BkGame.config["players"] = 3
	root.add_child(game)
	game.set_physics_process(false)
	await physics_frame
	await physics_frame
	game._stats = true
	game.phase = BkGame.Phase.HUNT
	game.hunter = game.actors[0]
	for a: BkActor in game.actors:
		a.set_role(BkActor.Role.HUNTER if a == game.hunter else BkActor.Role.HIDER)
		a.character = "louis"                  # coups codés à l'étape 3 : ceux de Louis
		a.frozen = false
		a.gauge = 0.0
		a.position = Vector2(-5000, -5000)
	game._st.merge(BkGame.tension_keys(), true)
	game._tens.clear()
	game.hunter.position = tile_pos(game, CHASSEUR.x, CHASSEUR.y)
	game.hunter.look = 0.0
	if pleine_lumiere:
		game.map.lumieres.append(source(CHASSEUR, 30.0, "T"))
	return game


## Source de lumière de test (même format que BkMap.lumieres).
func source(t: Vector2i, rayon: float, secteur: String) -> Dictionary:
	return {"pos": t, "rayon": rayon, "secteur": secteur, "type": "lampadaire", "couleur": Color.BLACK,
		"mur": Vector2i.ZERO}


func tile_pos(game: BkGame, x: float, y: float) -> Vector2:
	return Vector2(x + 0.5, y + 0.5) * game.map.tile


## Case à `k` cases devant le chasseur des tests.
func devant(game: BkGame, k: float) -> Vector2:
	return tile_pos(game, CHASSEUR.x + k, CHASSEUR.y)


## `secs` s de jeu : capture puis mesures (comme dans _physics_process).
func tick(game: BkGame, secs: float) -> void:
	var n: int = int(round(secs / DT))
	for i: int in n:
		game.hunt_elapsed += DT
		game._update_capture(DT)
		game.track_tension(DT)


func free_game(game: BkGame) -> void:
	game.queue_free()
	await process_frame


func test_frolements() -> void:
	var game: BkGame = await make_game()
	var h: BkActor = game.actors[1]
	# Dans le dos du chasseur, à 1,95 case : hors du petit cercle, hors du cône.
	h.position = game.hunter.position + Vector2(-1.95 * game.map.tile, 0)
	check(not game.sees(game.hunter, h.position, h.radius), "précondition : pas vu dans le dos")
	tick(game, 0.5)
	check(int(game._st["frolements_2"]) == 0, "épisode ouvert, pas encore compté")
	h.position = game.hunter.position + Vector2(-2.3 * game.map.tile, 0)    # dans l'hystérésis
	tick(game, 0.2)
	check(int(game._st["frolements_2"]) == 0, "hystérésis : pas de comptage entre 2 et 2,5 cases")
	h.position = game.hunter.position + Vector2(-4.0 * game.map.tile, 0)
	tick(game, 0.2)
	check(int(game._st["frolements_2"]) == 1, "frôlement à moins de 2 cases compté (%d)" % int(game._st["frolements_2"]))
	check(int(game._st["frolements_3"]) == 1, "il compte aussi à moins de 3 cases (%d)" % int(game._st["frolements_3"]))
	check(int(game._st["vus"]) == 0, "jamais vu")
	# Un deuxième passage à 2,8 cases : frôlement à 3, pas à 2.
	h.position = game.hunter.position + Vector2(-2.8 * game.map.tile, 0)
	tick(game, 0.3)
	h.position = game.hunter.position + Vector2(-5.0 * game.map.tile, 0)
	tick(game, 0.1)
	check(int(game._st["frolements_2"]) == 1 and int(game._st["frolements_3"]) == 2, "frôlement à 3 cases seulement")
	await free_game(game)


func test_vu_perdu() -> void:
	BkRules._data["idee_detection"] = 1.0
	var game: BkGame = await make_game()
	var h: BkActor = game.actors[1]
	h.position = devant(game, 5)                 # devant, à 5 cases
	check(game.sees(game.hunter, h.position, h.radius), "précondition : vu devant")
	tick(game, 0.4)
	check(h.role == BkActor.Role.HIDER and h.gauge > BkRules.f("detection_doute"), "jauge entamée, pas encore trouvé (%.2f)" % h.gauge)
	check(game.hunter_alert > BkRules.f("detection_doute"), "le « ? » s'affiche au-dessus du chasseur")
	h.position = game.hunter.position + Vector2(-5.0 * game.map.tile, 0)     # sorti du cône
	tick(game, BkGame.TENSION_VU_GRACE + 0.1)
	check(int(game._st["vus"]) == 1 and int(game._st["vu_perdu"]) == 1, "vu puis perdu compté (%d/%d)" % [game._st["vu_perdu"], game._st["vus"]])
	check(h.gauge > 0.0, "la jauge redescend doucement (%.2f)" % h.gauge)
	tick(game, 2.0)
	check(h.gauge == 0.0 and h.ouf_t > 0.0, "jauge vide, « ouf ! » du chassé qui s'en tire")
	check(int(game._st["doutes"]) == 1 and int(game._st["doutes_perdus"]) == 1, "doute compté puis perdu")
	check(int(game._st["evasions_de_vue"]) == 1, "évasion comptée")
	await free_game(game)


func test_capture_pas_frolement() -> void:
	BkRules._data["idee_detection"] = 1.0
	var game: BkGame = await make_game()
	var h: BkActor = game.actors[1]
	h.position = game.hunter.position + Vector2(1.0 * game.map.tile, 0)      # tout près, devant
	tick(game, BkRules.f("detection_temps_pres") + 0.1)
	check(h.role == BkActor.Role.GHOST, "trouvé de près en detection_temps_pres")
	check(game.alert_bang > 0.0, "« ! » au-dessus du chasseur")
	h.position = game.hunter.position + Vector2(-6.0 * game.map.tile, 0)
	tick(game, 0.2)
	check(int(game._st["frolements_2"]) == 0 and int(game._st["vu_perdu"]) == 0, "une capture n'est ni un frôlement ni un vu-perdu")
	await free_game(game)


# ------------------------------------------------------------------ poursuite (désactivée par défaut)

func test_poursuite() -> void:
	BkRules._data["idee_detection"] = 1.0
	check(not BkRules.on("idee_poursuite"), "poursuite désactivée par défaut (c'est Julien qui décide)")
	BkRules._data["idee_poursuite"] = 1.0
	BkRules._data["poursuite_mult_chasseur"] = 1.15
	BkRules._data["poursuite_mult_chasse"] = 1.25
	var game: BkGame = await make_game()
	var h: BkActor = game.actors[1]
	var base_h: float = h.speed()
	var base_c: float = game.hunter.speed()
	h.position = devant(game, 5)
	tick(game, 0.1)
	check(h.chase_left == 0.0, "pas de poursuite avant le « ? »")
	tick(game, 0.25)
	check(h.gauge >= BkRules.f("poursuite_seuil") and h.role == BkActor.Role.HIDER, "précondition : « ? » atteint, pas trouvé")
	check(h.chase_left > 0.0 and game.hunter.chase_left > 0.0, "« ? » : poursuite des deux")
	check(near(h.speed(), base_h * 1.25, 0.01) and near(game.hunter.speed(), base_c * 1.15, 0.01), "vitesses de poursuite (chassé ×1,25, chasseur ×1,15)")
	check(int(game._st["poursuites"]) == 1, "une poursuite comptée")
	h.position = game.hunter.position + Vector2(-6.0 * game.map.tile, 0)        # il s'échappe
	for i: int in int((BkRules.f("poursuite_duree_s") + 0.2) / DT):
		h.step(Vector2.ZERO, Vector2.ZERO, DT)
		game.hunter.step(Vector2.ZERO, Vector2.ZERO, DT)
		game.hunt_elapsed += DT
		game._update_capture(DT)
	check(h.chase_left == 0.0 and near(h.speed(), base_h, 0.01), "après poursuite_duree_s : vitesse normale")
	check(int(game._st["poursuites"]) == 1, "pas de nouvelle poursuite sans nouveau repérage")
	await free_game(game)


## Précision de Julien : pendant la poursuite, tous les chassés que voit le chasseur en profitent.
func test_poursuite_tous_vus() -> void:
	BkRules._data["idee_detection"] = 1.0
	BkRules._data["idee_poursuite"] = 1.0
	for tous: float in [1.0, 0.0]:
		BkRules._data["poursuite_tous_vus"] = tous
		var game: BkGame = await make_game()
		var h1: BkActor = game.actors[1]
		var h2: BkActor = game.actors[2]
		h1.position = devant(game, 5)
		h2.position = game.hunter.position + Vector2(-6.0 * game.map.tile, 0)    # dans son dos
		tick(game, 0.35)
		check(h1.chase_left > 0.0 and h2.chase_left == 0.0, "seul le chassé vu part en poursuite")
		h2.position = devant(game, 7)                                      # entre dans le champ
		tick(game, DT)
		if tous > 0.5:
			check(h2.chase_left > 0.0, "tous_vus : le chassé qui entre dans le champ en profite aussi")
		else:
			check(h2.chase_left == 0.0, "chassé repéré seul : l'autre n'en profite pas")
		await free_game(game)


# ------------------------------------------------------------------ partie IA contre IA

func test_partie_ia_courte() -> void:
	for k: String in ["idee_detection", "idee_mouvement", "idee_frisson"]:
		BkRules._data[k] = 1.0
	BkRules._data["phase_draw"] = 0.5
	BkRules._data["phase_hide"] = 3.0
	BkRules._data["phase_hunt"] = 25.0
	BkRules._data["phase_end"] = 0.5
	BkRules._data["exits_open_at"] = 10.0
	BkGame.config["players"] = 6
	var game: BkGame = (load(GAME) as PackedScene).instantiate()
	game._bots_only = true
	game._stats = true
	root.add_child(game)
	var frames: int = 0
	while game.round_no < 3 and frames < 60 * 90:
		await physics_frame
		frames += 1
	check(game.round_no >= 3, "deux rounds complets joués (%d images)" % frames)
	check(game.hunter != null and game.actors.size() == 6, "six joueurs, un chasseur")
	var keys: Dictionary = BkGame.tension_keys()
	for k: String in keys:
		check(game.last_stats.has(k), "mesure présente : " + k)
	check(float(game.last_stats.get("chasse_s", 0.0)) > 0.0, "temps de chasse mesuré")
	await free_game(game)


## Vue du chasseur (#607) : la ligne de l'œil vers les pieds passe sous un objet bas posé juste devant
## le chassé, celle vers la tête au-dessus ; un objet plus haut que l'œil cache tout.
func test_vue_objet_bas() -> void:
	var d: BkDecor = BkDecor.new()
	var box: PackedVector2Array = PackedVector2Array([Vector2(280, -20), Vector2(320, -20), Vector2(320, 20), Vector2(280, 20)])
	d.instances = [{"polys": [box], "poly_bb": Rect2(280, -20, 40, 40), "view_h": 0.6 * BkPerso.hauteur_px()}]
	d.low_view = [0]
	var eye: float = BkGame.eye_height()
	var a: Vector2 = Vector2.ZERO
	var b: Vector2 = Vector2(340, 0)
	check(d.low_blocks(a, b, eye, BkRules.f("vue_pieds") * BkPerso.hauteur_px()), "objet bas : pieds cachés")
	check(not d.low_blocks(a, b, eye, BkRules.f("vue_tete") * BkPerso.hauteur_px()), "objet bas : tête vue")
	check(not d.low_blocks(a, Vector2(0, 300), eye, 0.0), "ligne qui ne traverse pas l'objet : rien de caché")
	d.instances[0]["view_h"] = eye + 1.0
	check(d.low_blocks(a, b, eye, BkRules.f("vue_tete") * BkPerso.hauteur_px()), "objet plus haut que l'œil : tête cachée")
	check(BkRules.f("vue_oeil") >= BkRules.f("vue_tete"), "l'œil du chasseur est au moins à hauteur de tête")
	d.free()


# ------------------------------------------------------------------ partie en N rounds

func test_rounds_pour() -> void:
	check(BkGame.rounds_pour({"players": 6, "rounds": 0}) == 6, "par défaut : un round par joueur")
	check(BkGame.rounds_pour({"players": 2, "rounds": 0}) == int(BkRules.f("rounds_min")), "au moins rounds_min")
	check(BkGame.rounds_pour({"players": 6, "rounds": 40}) == int(BkRules.f("rounds_max")), "au plus rounds_max")
	check(BkGame.rounds_pour({"players": 6, "rounds": 5}) == 5, "choix du menu")
	check(BkGame.rounds_pour({"players": 6}, true) == 0, "IA contre IA : sans fin")
	check(BkGame.rounds_pour({"players": 6}, true, 40) == 40, "--bk-rounds l'emporte")


## Tirage en sac : chacun est chasseur une fois par tour de sac, jamais deux rounds de suite.
func test_sac() -> void:
	var game: BkGame = await make_game()
	var n: int = game.actors.size()
	game.round_no = 2
	game._sac.clear()
	var ids: Array[int] = []
	for i: int in n * 4:
		ids.append(game._draw_hunter().id)
	var tous: Array[int] = []
	for i: int in n:
		tous.append(i)
	for tour: int in 4:
		var t: Array[int] = ids.slice(tour * n, tour * n + n)
		t.sort()
		check(t == tous, "tour de sac %d : chacun une fois (%s)" % [tour, str(ids.slice(tour * n, tour * n + n))])
	for i: int in range(1, ids.size()):
		check(ids[i] != ids[i - 1], "jamais deux fois de suite le même chasseur (%d)" % i)
	await free_game(game)


func _phases_courtes() -> void:
	BkRules._data["phase_draw"] = 0.2
	BkRules._data["phase_versus"] = 0.4
	BkRules._data["phase_hide"] = 0.3
	BkRules._data["phase_hunt"] = 1.0
	BkRules._data["phase_end"] = 0.2


## IA contre IA : pas de versus (personne ne regarde), et pas de fin de partie.
func test_versus_saute_en_ia() -> void:
	_phases_courtes()
	BkGame.config["players"] = 4
	var game: BkGame = (load(GAME) as PackedScene).instantiate()
	game._bots_only = true
	root.add_child(game)
	var vu: bool = false
	var frames: int = 0
	while game.round_no < 3 and frames < 60 * 20:
		await physics_frame
		frames += 1
		vu = vu or game.phase == BkGame.Phase.VERSUS
	check(not vu, "pas de versus en IA contre IA")
	check(game.rounds_total == 0 and game.round_no >= 3, "IA contre IA : les rounds s'enchaînent sans fin")
	await free_game(game)


## Partie de 3 rounds : tirage, versus, cachette, chasse, scores, trois fois, puis le podium.
func test_rounds_fixes_podium() -> void:
	_phases_courtes()
	BkGame.config["players"] = 4
	BkGame.config["rounds"] = 3
	var game: BkGame = (load(GAME) as PackedScene).instantiate()
	game._local_bot = true
	root.add_child(game)
	var versus: int = 0
	var t_versus: float = 0.0
	var last: BkGame.Phase = game.phase
	var chasseurs: Array[int] = []
	var frames: int = 0
	while game.phase != BkGame.Phase.PODIUM and frames < 60 * 30:
		await physics_frame
		frames += 1
		if game.phase == BkGame.Phase.VERSUS:
			t_versus += DT
			if last != BkGame.Phase.VERSUS:
				versus += 1
				chasseurs.append(game.hunter.id)
				check(game.versus != null, "écran versus ouvert")
				check(last == BkGame.Phase.DRAW, "le versus suit le tirage")
		if last == BkGame.Phase.VERSUS and game.phase != BkGame.Phase.VERSUS:
			check(game.phase == BkGame.Phase.HIDE, "la cachette suit le versus")
			check(game.versus == null, "écran versus refermé")
		last = game.phase
	check(game.rounds_total == 3, "3 rounds choisis (%d)" % game.rounds_total)
	check(game.phase == BkGame.Phase.PODIUM and game.round_no == 3, "podium après le 3e round (round %d)" % game.round_no)
	check(versus == 3, "un versus par round (%d)" % versus)
	check(near(t_versus / 3.0, BkRules.f("phase_versus"), 3.0 * DT), "versus de phase_versus s (%.2f)" % (t_versus / 3.0))
	check(chasseurs.size() == 3 and chasseurs[0] != chasseurs[1] and chasseurs[1] != chasseurs[2], "trois chasseurs différents")
	check(game.podium != null, "écran du podium")
	var rangs: Array[BkActor] = BkPodium.classement(game.actors)
	for i: int in range(1, rangs.size()):
		check(rangs[i - 1].score >= rangs[i].score, "podium trié par points")
	await free_game(game)


# ------------------------------------------------------------------ partie rapide

## Les réglages de l'écran passent dans la partie : joueurs, rounds (qui suivent les joueurs tant
## qu'on n'y a pas touché), options du catalogue posées sur rules.json et bornées.
func test_partie_rapide_options() -> void:
	var scr: GDScript = load("res://src/blackout/menus/bk_partie_rapide.gd")
	scr.reinitialiser()
	var ecran: Control = (load("res://src/blackout/menus/bk_partie_rapide.tscn") as PackedScene).instantiate()
	root.add_child(ecran)
	await process_frame
	var choix: Dictionary = scr.choix
	check(int(choix["players"]) == int(BkRules.f("joueurs_defaut")) and int(choix["rounds"]) == int(choix["players"]),
		"défauts : 6 joueurs, autant de rounds")
	var interrupteurs: int = ecran.find_children("*", "CheckButton", true, false).size()
	var on_off: int = 0
	for o: Dictionary in BkRules.options_partie():
		for r: Dictionary in o.get("reglages", []):
			if str(r.get("type", "")) == "on_off":
				on_off += 1
	check(interrupteurs == on_off and on_off > 0, "un interrupteur par option (%d/%d)" % [interrupteurs, on_off])
	ecran.regler_joueurs(8)
	check(int(choix["rounds"]) == 8, "les rounds suivent les joueurs")
	ecran.regler_joueurs(2)
	check(int(choix["players"]) == int(BkRules.f("joueurs_min")), "au moins joueurs_min joueurs")
	ecran.regler_rounds(10)
	ecran.regler_joueurs(5)
	check(int(choix["rounds"]) == 10, "rounds touchés : ils ne suivent plus les joueurs")
	ecran.regler_rounds(99)
	check(int(choix["rounds"]) == int(BkRules.f("rounds_max")), "rounds bornés")
	ecran.regler_option("idee_gateaux", 0.0)
	ecran.regler_option("gateaux_nombre", 99.0)
	ecran.regler_option("delivrance_temps", 2.5)
	BkGame.config["visite"] = "chasse"
	ecran.preparer()
	check(not BkRules.on("idee_gateaux"), "option coupée dans la partie")
	check(near(BkRules.f("gateaux_nombre"), 8.0, 1e-4), "curseur borné à son max")
	check(near(BkRules.f("delivrance_temps"), 2.5, 1e-4), "curseur posé sur rules.json")
	check(int(BkGame.config["players"]) == 5 and int(BkGame.config["rounds"]) == int(BkRules.f("rounds_max")),
		"joueurs et rounds dans la config de la partie")
	check(str(BkGame.config["visite"]) == "", "une partie rapide n'est jamais une visite")
	scr.reinitialiser()
	ecran.queue_free()
	await process_frame


# ------------------------------------------------------------------ profil

## Le profil garde le perso (relu depuis user://profiles.json), rien d'autre (GDD §7.1) ; les anciens
## profils (Borroka, ou Blackout avec couleur et emote) se chargent toujours. Le fichier du joueur est
## remis tel quel à la fin.
func test_profil_persiste() -> void:
	await process_frame
	var p: Node = root.get_node("/root/Profiles")
	var path: String = "user://profiles.json"
	var avant: String = FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
	var profils: Array[Dictionary] = p.profiles.duplicate(true)
	var actif: int = p.active_index
	p.profiles.clear()
	p.active_index = -1
	check(BkProfil.creer("Lea") == "", "profil créé")
	BkProfil.regler(BkProfil.PERSO, "itsasargi")
	p._load()
	check(BkProfil.perso() == "itsasargi", "perso relu du fichier (%s)" % BkProfil.perso())
	check(not BkProfil.actif().has("gk_couleur") and not BkProfil.actif().has("gk_emote"), "ni couleur ni emote")
	check(not BkProfil.actif().has("group_code") or str(BkProfil.actif()["group_code"]) == "", "aucun code de groupe")
	check(BkProfil.creer("lea") != "", "même pseudo refusé sur l'appareil")
	# Ancien profil de Borroka, et profil Blackout d'avant le 22/10 (couleur, emote) : ils se chargent.
	p.profiles.append({"pseudo": "Ancien", "fighter": "txomin"})
	p.profiles.append({"pseudo": "Avant", "gk_perso": "maia", "gk_couleur": 7, "gk_emote": 4})
	p.save()
	p._load()
	BkProfil.migrer()
	check(p.profiles.size() == 3, "trois profils relus (%d)" % p.profiles.size())
	check(str(p.profiles[1].get(BkProfil.PERSO, "")) == "txomin", "migration : le perso de Borroka est gardé")
	check(str(p.profiles[2].get(BkProfil.PERSO, "")) == "maia", "profil d'avant : son perso est gardé")
	p.select(2)
	BkProfil.vers_partie()
	check(str(BkGame.config["character"]) == "maia" and str(BkGame.config["name"]) == "Avant",
		"le profil actif joue la partie")
	check(not BkGame.config.has("color") and not BkGame.config.has("emote"), "la partie n'a ni couleur ni emote")
	# Remise en état.
	p.profiles = profils
	p.active_index = actif
	if avant != "":
		var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		f.store_string(avant)
		f.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_pseudo() -> void:
	await process_frame
	check(BkProfil.erreur_pseudo("Léa_9") == "", "pseudo accepté (accents, chiffres, _)")
	check(BkProfil.erreur_pseudo("a") != "", "trop court")
	check(BkProfil.erreur_pseudo("abcdefghijklmnop") != "", "trop long")
	check(BkProfil.erreur_pseudo("le roi") != "", "pas d'espace")
	check(BkProfil.erreur_pseudo("x!y") != "", "caractères interdits")
	check(BkProfil.gros_mot("PuT4in") and BkProfil.gros_mot("Mérde"), "gros mots repérés (leet, accents)")
	check(not BkProfil.gros_mot("Louis") and not BkProfil.gros_mot("Itsaso"), "pseudos normaux acceptés")
	check(BkProfil.erreur_pseudo("fuck_12") != "", "gros mot refusé")


## Reboot visuel du 21/10/2026 (style Party Hard) : l'ancien décor est dans archive/2026-10-21-flat-cartoon ;
## les vérifications d'images ne valent que lorsque le nouveau décor est livré.
func decor_livre() -> bool:
	return FileAccess.file_exists("res://assets/blackout/decor/index.json")


# ------------------------------------------------------------------ roster, persos, carte bac à sable

## 13 persos (GDD §8.2), Itsasargi compris, un nom pour chacun ; plus de couleurs de joueur.
func test_roster() -> void:
	var chars: Array = BkRules.data().get("characters", [])
	var noms: Array = BkRules.data().get("bot_names", [])
	check(chars.size() == 13 and chars.has("itsasargi"), "13 persos dont Itsasargi (%d)" % chars.size())
	check(noms.size() == chars.size(), "un nom par perso")
	check(not BkRules.data().has("colors") and not BkRules.data().has("color_names"), "plus de couleurs de joueur")
	check(not BkRules.data().has("idee_chatouille") and not BkRules.data().has("emote_duration"),
		"ni chatouille ni emotes dans les règles")
	for o: Dictionary in BkRules.options_partie():
		check(str(o.get("id", "")) != "chatouille", "plus d'option chatouille")
	var couleurs: Dictionary = BkRules.data().get("perso_couleurs", {})
	for c: Variant in chars:
		check(couleurs.has(str(c)), "couleur de repli pour %s" % c)


## Persos px32 : planches livrées lues (images, cadence, pieds), repli capsule de 64×64 (pieds à 60)
## pour un perso ou un élément sans planche, perso de 32 px de haut.
func test_persos_px32() -> void:
	var a: Dictionary = BkPerso.element("louis", "idle")
	if BkPerso.has_sheets("louis"):
		check(not a.has("repli") and int(a["n"]) >= 1, "planche idle de Louis lue (%d images)" % int(a["n"]))
		var cell: Vector2 = a["cell"]
		var tex: Texture2D = a["tex"]
		check(is_equal_approx(cell.x * float(a["n"]), float(tex.get_width())), "images × largeur = planche")
		check(float((a["feet"] as Vector2).y) < cell.y, "pieds dans la case")
	var r: Dictionary = BkPerso.element("perso_de_test", "run")
	check(r.has("repli") and int(r["n"]) == 4 and (r["cell"] as Vector2) == Vector2(64, 64), "repli : course en 4 images de 64×64")
	check((r["feet"] as Vector2).y == float(BkPerso.PIEDS_Y), "repli : pieds à y = 60")
	var img: Image = (r["tex"] as Texture2D).get_image()
	var haut: int = 0
	for y: int in 64:
		for x: int in 64:
			if img.get_pixel(x, y).a > 0.5:
				haut = maxi(haut, 64 - y)
				break
	check(haut >= 28 and haut <= 36, "repli : silhouette d'environ 32 px de haut (%d)" % haut)
	check(BkPerso.element("perso_de_test", "lift").is_empty(), "pas de planche lift : envol fait par le code")
	check(is_equal_approx(BkPerso.hauteur_px(), BkRules.f("tile_px")), "un perso = une case (32 px)")
	check(int(BkRules.f("tile_px")) == 32, "cases de 32 px")


## Sets des PNJ, animaux et boss (GDD §3.8, §5, §8.3, §8.4) : chacun a un set chargeable par BkPerso,
## vrai (pixelforge) ou placeholder (tools/blackout/placeholders_sets.py) ; boss en case de 128.
func test_sets_pnj_boss() -> void:
	var pnj: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/blackout/pnj.json"))
	var ids: Array = []
	for fam: String in ["humains", "animaux"]:
		for id: Variant in (pnj[fam] as Dictionary):
			ids.append(["pnj" if fam == "humains" else "animaux", str(id)])
	var boss: Array = BkRules.data().get("boss", [])
	check(boss.size() >= 7, "liste des boss dans rules.json (%d)" % boss.size())
	for b: Variant in boss:
		ids.append(["boss", str(b)])
	var places: int = 0
	for it: Array in ids:
		var id: String = it[1]
		var dir: String = BkPerso.dossier(id)
		check(dir.contains("/%s/%s/" % [it[0], id]), "%s : set dans assets/blackout/%s/ (%s)" % [id, it[0], dir])
		var prof: Dictionary = BkPerso.element(id, "profile")
		var idle: Dictionary = BkPerso.element(id, "idle")
		check(not prof.is_empty() and not idle.is_empty() and not idle.has("repli"), "%s : profil et idle chargés" % id)
		if idle.is_empty():
			continue
		var tex: Texture2D = idle["tex"]
		var cell: Vector2 = idle["cell"]
		check(is_equal_approx(cell.x * float(idle["n"]), float(tex.get_width())), "%s : images × largeur = planche" % id)
		var gros: bool = it[0] == "boss" and not id.begins_with("intxixu")
		check(cell == (Vector2(128, 128) if gros else Vector2(64, 64)), "%s : case de %d" % [id, int(cell.x)])
		check((idle["feet"] as Vector2).y == (120.0 if gros else 60.0), "%s : pieds en bas de case" % id)
		var els: Array = ["run"]
		if it[0] == "pnj":
			els = ["run", "marcher", "sursaut"] + Array(pnj["humains"][id]["activites"])
		elif it[0] == "boss":
			els = ["run", "etourdi", "cri", "pouvoir_1", "pouvoir_2"]
		for el: Variant in els:
			check(not BkPerso.element(id, str(el)).is_empty(), "%s : élément %s" % [id, el])
		if BkPerso.placeholder(id):
			places += 1
	print("  sets PNJ, animaux, boss : %d, dont %d placeholders" % [ids.size(), places])


## Types de cases (GDD §10.1, §10.2) : murs et cloisons fines bloquent vue et passage ; murets,
## buissons, grilles et fenêtres bloquent le passage mais pas la vue ; sol meuble marchable.
func test_cases_vue_passage() -> void:
	var game: BkGame = await make_game()
	var m: BkMap = game.map
	var vus: Dictionary = {"#": false, "|": false, "-": false, "c": false, "H": false,
		"m": true, "b": true, "g": true, "f": true, "t": true, "r": true}
	for ch: String in vus:
		var t: Vector2i = _case(m, ch)
		check(t != Vector2i(-1, -1), "case « %s » présente dans le bac à sable" % ch)
		if t == Vector2i(-1, -1):
			continue
		check(not m.walkable(t), "« %s » : on ne passe pas (grille A*)" % ch)
		check(m.blocks_move(t) and m.blocks_view(t) != bool(vus[ch]), "« %s » : règle de vue" % ch)
		# Vue réelle : une ligne qui traverse la case de part en part (le long de son axe libre).
		var c: Vector2 = m.center(t)
		var d: Vector2 = Vector2(m.tile, 0) if ch != "-" else Vector2(0, m.tile)
		if ch == "|" or (ch == "g" and m.at(t + Vector2i(0, 1)) == "g") or (ch == "f" and m.at(t + Vector2i(0, 1)) == "#") \
				or (ch == "m" and m.at(t + Vector2i(0, 1)) == "m"):
			d = Vector2(m.tile, 0)
		elif ch == "g" or ch == "f" or ch == "m":
			d = Vector2(0, m.tile)
		check(game.clear_line(c - d * 0.9, c + d * 0.9) == bool(vus[ch]), "« %s » : la vue %s" % [ch, "passe" if vus[ch] else "s'arrête"])
		# Passage réel : un corps lancé à travers la case est arrêté.
		var a: BkActor = game.actors[1]
		a.set_role(BkActor.Role.HIDER)
		a.position = c - d * 1.0
		var arret: bool = a.test_move(a.global_transform, d * 2.0)
		check(arret, "« %s » : un perso ne traverse pas" % ch)
	# Cloison fine : sa forme est une bande mince (un perso s'en approche plus près qu'un mur).
	var tc: Vector2i = _case(m, "|")
	var bande: Rect2 = m.thin_rect(Rect2i(tc, Vector2i.ONE))
	check(bande.size.x < m.tile * 0.5 and is_equal_approx(bande.size.y, m.tile), "cloison fine : bande mince (%s)" % bande)
	# Sol meuble.
	var tm: Vector2i = _case(m, ":")
	check(m.walkable(tm) and m.meuble(tm) and not m.meuble(m.spawns[0]), "sable : sol meuble marchable")
	await free_game(game)


func _case(m: BkMap, ch: String) -> Vector2i:
	for y: int in m.height:
		for x: int in m.width:
			if m.at(Vector2i(x, y)) == ch:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


## Carte bac à sable (tools/blackout/make_bac_a_sable.py), carte par défaut et seule de la partie
## rapide : ~3 × 2 écrans, tout le sol atteignable, cachettes accessibles, 2 sorties ouvertes à chaque
## round, un disjoncteur par secteur, lampadaires, gâteaux et mouettes à leurs places ; deux rounds IA.
func test_bac_a_sable() -> void:
	var cartes: Array = load("res://src/blackout/menus/bk_partie_rapide.gd").CARTES
	var ids: Array = cartes.map(func(c: Array) -> String: return str(c[0]))
	check(ids == ["bac_a_sable"], "partie rapide : le bac à sable seul (%s)" % str(ids))
	check(str(BkGame.config["map"]) == "bac_a_sable", "carte par défaut : bac à sable")
	BkRules._data["phase_draw"] = 0.5
	BkRules._data["phase_hide"] = 3.0
	BkRules._data["phase_hunt"] = 25.0
	BkRules._data["phase_end"] = 0.5
	BkRules._data["exits_open_at"] = 10.0
	BkGame.config["players"] = 6
	var game: BkGame = (load(GAME) as PackedScene).instantiate()
	game._bots_only = true
	game._stats = true
	root.add_child(game)
	await physics_frame
	var m: BkMap = game.map
	var ecran: Vector2 = Vector2(BkEchelle.taille_jeu())
	var sz: Vector2 = m.size_px() / ecran
	check(m.map_id == "bac_a_sable" and sz.x >= 2.5 and sz.x <= 3.5 and sz.y >= 1.8 and sz.y <= 2.5,
		"environ 3 × 2 écrans (%.1f × %.1f)" % [sz.x, sz.y])
	var start: Vector2i = m.spawns[0]
	var n_walk: int = 0
	var reach: int = 0
	for y: int in m.height:
		for x: int in m.width:
			if m.walkable(Vector2i(x, y)):
				n_walk += 1
				if not m.path(m.center(start), m.center(Vector2i(x, y))).is_empty():
					reach += 1
	check(n_walk > 0 and reach == n_walk, "tout le sol atteignable (%d / %d)" % [reach, n_walk])
	check(m.cachettes.size() >= 10, "au moins 10 cachettes (%d)" % m.cachettes.size())
	for c: Vector2i in m.cachettes:
		var free: int = 0
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			free += int(m.walkable(c + d))
		check(free >= 2, "cachette %s : au moins deux côtés libres" % c)
	check(m.exit_groups.size() == 2 and game.open_exit_zones.size() == 2, "2 sorties, ouvertes à chaque round (%d)" % game.open_exit_zones.size())
	check(m.secteurs.size() == 3 and m.disjoncteurs.size() == m.secteurs.size(), "un disjoncteur par secteur")
	for d: Dictionary in m.disjoncteurs:
		check(m.walkable(d["pos"]) and m.at((d["pos"] as Vector2i) + (d["mur"] as Vector2i)) == "#", "disjoncteur %s contre un mur" % d["pos"])
	for sct: Dictionary in m.secteurs:
		var n_src: int = m.lumieres.filter(func(l: Dictionary) -> bool: return str(l["secteur"]) == str(sct["id"])).size()
		check(n_src >= 2, "des sources de lumière dans le secteur %s (%d)" % [sct["id"], n_src])
	check(m.lumieres.any(func(l: Dictionary) -> bool: return str(l["type"]) == "neon"), "au moins un néon")
	check(game.gateaux.size() == int(BkRules.f("gateaux_nombre")), "gâteaux posés (%d)" % game.gateaux.size())
	for g: Dictionary in game.gateaux:
		check(m.gateaux_places.has(m.to_tile(g["pos"])), "gâteau sur une place de la carte")
	check(not game.mouettes.is_empty() and m.mouettes_places.has(m.to_tile(game.mouettes[0]["pos"])), "mouettes à leurs places")
	var frames: int = 0
	while game.round_no < 3 and frames < 60 * 90:
		await physics_frame
		frames += 1
	check(game.round_no >= 3, "deux rounds IA joués sur le bac à sable (%d images)" % frames)
	await free_game(game)


## Réglages propres à une carte (zones.json → « regles ») : posés pour la partie, retirés après. Les
## anciennes cartes (archivées, GDD §10.1) se chargent encore par `--bk-map`.
func test_regles_carte() -> void:
	BkRules._data["exits_open_at"] = 10.0
	BkGame.config["players"] = 4
	BkGame.config["map"] = "port_pecheurs"
	var game: BkGame = (load(GAME) as PackedScene).instantiate()
	game._bots_only = true
	root.add_child(game)
	await physics_frame
	check(game.map.map_id == "port_pecheurs" and game.map.zones.size() == 14, "ancienne carte encore lisible")
	check(is_equal_approx(BkRules.f("exits_open_at"), 110.0), "réglage propre à la carte : sorties à 110 s")
	await free_game(game)
	check(is_equal_approx(BkRules.f("exits_open_at"), 10.0), "réglage de la carte retiré à la fin de la partie")


# ------------------------------------------------------------------ lumière et ombre (#625)

## Règle « éclairé » (GDD §3.2) : pieds dans le rayon d'une source allumée, sans mur plein entre elle et
## eux ; une grille ou un objet bas laisse passer la lumière ; une source éteinte n'éclaire plus.
func test_eclaire_mur() -> void:
	var game: BkGame = await make_game(false)
	var m: BkMap = game.map
	game.map.lumieres.clear()
	# Source dans le couloir de la maison (12, 10) ; mur plein en (12, 9) entre elle et la cuisine.
	game.map.lumieres.append(source(Vector2i(12, 10), 3.0, "T"))
	check(m.at(Vector2i(12, 9)) == "#" and m.walkable(Vector2i(12, 8)) and m.walkable(Vector2i(12, 11)), "précondition : mur entre (12, 10) et (12, 8)")
	check(game.eclaire(m.center(Vector2i(14, 10))), "à 2 cases, rien entre : éclairé")
	check(not game.eclaire(m.center(Vector2i(12, 8))), "à 2 cases derrière un mur plein : dans l'ombre")
	check(not game.eclaire(m.center(Vector2i(16, 10))), "à 4 cases (rayon 3) : dans l'ombre")
	# Les pieds comptent, pas le centre du corps.
	var a: BkActor = game.actors[1]
	a.position = m.center(Vector2i(12, 11))
	check(game.eclaire(BkGame.pieds(a)), "pieds d'un acteur dans la zone : éclairé")
	# Une grille laisse passer la lumière (jardin de la Place : grille en (26, 4)).
	game.map.lumieres.append(source(Vector2i(25, 4), 3.0, "U"))
	check(m.at(Vector2i(26, 4)) == "g" and game.eclaire(m.center(Vector2i(27, 4))), "à travers une grille : éclairé")
	# Une source dont le secteur est coupé n'éclaire plus.
	game.pannes["T"] = 5.0
	check(not game.eclaire(m.center(Vector2i(14, 10))), "secteur coupé : dans l'ombre")
	await free_game(game)


## Dans l'ombre, la jauge monte ombre_facteur (3) fois moins vite ; elle redescend pareil.
func test_ombre_facteur() -> void:
	BkRules._data["idee_detection"] = 1.0
	check(near(BkRules.f("ombre_facteur"), 3.0, 1e-6), "ombre_facteur = 3 (GDD §3.2)")
	for d: float in [BkRules.px("near_radius"), BkRules.px("cone_range") * 0.6, BkRules.px("cone_range")]:
		var lit: float = BkGame.next_gauge(0.0, 1.0, d, 0.05, true)
		var dark: float = BkGame.next_gauge(0.0, 1.0, d, 0.05, false)
		check(near(lit / dark, 3.0, 1e-4), "à %.0f px : 3 fois moins vite dans l'ombre (%.3f)" % [d, lit / dark])
	check(near(BkGame.next_gauge(0.5, 0.0, 0.0, 0.1, false), BkGame.next_gauge(0.5, 0.0, 0.0, 0.1, true), 1e-6),
		"hors de vue : la jauge redescend pareil")
	BkRules._data["idee_detection"] = 0.0
	check(near(BkGame.next_gauge(0.0, 1.0, 64.0, 0.05, true) / BkGame.next_gauge(0.0, 1.0, 64.0, 0.05, false), 3.0, 1e-4),
		"règle d'avant (sans détection progressive) : facteur 3 aussi")


## Dans la partie : un chassé vu dans l'ombre se remplit 3 fois moins vite qu'éclairé, et le chasseur
## (joueur local) ne voit de lui qu'une silhouette, sans pseudo ; éclairé, son sprite normal.
func test_ombre_capture_silhouette() -> void:
	BkRules._data["idee_detection"] = 1.0
	var game: BkGame = await make_game(false)
	game.map.lumieres.clear()
	game.local = game.hunter
	var h: BkActor = game.actors[1]
	h.position = devant(game, 4)
	check(game.sees(game.hunter, h.position, h.radius), "précondition : vu devant")
	tick(game, 0.1)
	var g_ombre: float = h.gauge
	check(not h.lit, "sans source : dans l'ombre")
	game._update_view()
	check(h.silhouette, "vu du chasseur : silhouette")
	h.perso._process(0.0)
	check(h.perso.material == BkPerso.silhouette_material(), "silhouette : shader monochrome sur le sprite")
	# La même chose sous une lampe.
	h.gauge = 0.0
	game.map.lumieres.append(source(game.map.to_tile(h.position), 2.0, "T"))
	tick(game, 0.1)
	check(h.lit, "sous la lampe : éclairé")
	check(near(h.gauge / maxf(g_ombre, 1e-6), 3.0, 0.15), "jauge 3 fois plus haute éclairé (%.3f / %.3f)" % [h.gauge, g_ombre])
	game._update_view()
	h.perso._process(0.0)
	check(not h.silhouette and h.perso.material == null, "éclairé : son sprite normal")
	# Les chassés voient tout normalement.
	game.local = h
	game.pannes["T"] = 5.0
	tick(game, DT)
	game._update_view()
	check(not h.lit and not h.silhouette, "vu d'un chassé : jamais de silhouette")
	await free_game(game)


# ------------------------------------------------------------------ disjoncteurs (#626)

## Placer un acteur sur la case d'un boîtier et avancer le jeu de `secs` s (boîtiers et pas).
func avance_boitiers(game: BkGame, secs: float) -> void:
	for i: int in int(round(secs / DT)):
		game._update_boitiers(DT)
		for a: BkActor in game.actors:
			a.step(Vector2.ZERO, Vector2.ZERO, DT)


## Un chassé actionne (1 s, immobile) : le secteur est coupé 15 s, toutes ses sources éteintes ; boîtier
## en recharge 30 s ; le chasseur le rallume de la même façon ; la lumière revient seule au bout de 15 s.
func test_disjoncteur() -> void:
	var game: BkGame = await make_game(false)
	var m: BkMap = game.map
	var i: int = 1                                      # boîtier du secteur B (la Place)
	var b: Dictionary = game.boitiers[i]
	check(str(b["secteur"]) == "B", "précondition : boîtier de la Place")
	var lampe: Dictionary = m.lumieres.filter(func(l: Dictionary) -> bool: return str(l["secteur"]) == "B")[0]
	var sous_lampe: Vector2 = BkLumieres.centre(m, lampe) + Vector2(0, 8)
	check(game.eclaire(sous_lampe), "précondition : sous un lampadaire de la Place, éclairé")
	var h: BkActor = game.actors[1]
	h.position = m.center(b["pos"])
	check(game.action_label(h) == "Actionner", "près du boîtier : « Actionner » (%s)" % game.action_label(h))
	game.act_for(h)
	check(near(h.use_left, BkRules.f("disjoncteur_temps"), 1e-6), "action de disjoncteur_temps s")
	var avant: Vector2 = h.position
	h.step(Vector2.RIGHT, Vector2.ZERO, DT)
	check(h.position == avant, "immobile pendant l'action")
	avance_boitiers(game, BkRules.f("disjoncteur_temps") * 0.5)
	check(game.pannes.is_empty(), "pas de coupure avant la fin de l'action")
	avance_boitiers(game, BkRules.f("disjoncteur_temps") * 0.5 + 2.0 * DT)
	check(near(float(game.pannes.get("B", 0.0)), BkRules.f("disjoncteur_duree"), 0.1), "secteur coupé %.1f s" % float(game.pannes.get("B", 0.0)))
	check(not game.eclaire(sous_lampe), "toutes les sources du secteur éteintes")
	check(game.eclaire(BkLumieres.centre(m, m.lumieres[0]) + Vector2(0, 8)), "les autres secteurs restent allumés")
	check(near(float(b["cd"]), BkRules.f("disjoncteur_cooldown"), 0.1), "boîtier en recharge %.1f s" % float(b["cd"]))
	check(int(game._st["coupures"]) == 1, "coupure comptée")
	# Un chassé ne peut pas recouper un secteur coupé ni un boîtier en recharge.
	check(game.action_label(h) != "Actionner", "plus d'« Actionner » pour un chassé")
	# La lumière revient seule au bout de disjoncteur_duree s.
	avance_boitiers(game, BkRules.f("disjoncteur_duree") - 1.0)
	check(not game.pannes.is_empty(), "encore coupé juste avant la fin")
	avance_boitiers(game, 1.2)
	check(game.pannes.is_empty() and game.eclaire(sous_lampe), "lumière revenue au bout de %d s" % int(BkRules.f("disjoncteur_duree")))
	check(float(b["cd"]) > 0.0 and game.action_label(h) != "Actionner", "boîtier encore en recharge (%.1f s)" % float(b["cd"]))
	avance_boitiers(game, BkRules.f("disjoncteur_cooldown") - BkRules.f("disjoncteur_duree"))
	check(game.action_label(h) == "Actionner", "recharge finie au bout de %d s : on peut recouper" % int(BkRules.f("disjoncteur_cooldown")))
	# Le chasseur rallume un secteur coupé.
	game.act_for(h)
	avance_boitiers(game, BkRules.f("disjoncteur_temps") + 2.0 * DT)
	check(game.pannes.has("B"), "recoupé")
	var c: BkActor = game.hunter
	c.position = m.center(b["pos"])
	check(game.action_label(c) == "Actionner", "chasseur près d'un secteur coupé : « Actionner »")
	game.act_for(c)
	avance_boitiers(game, BkRules.f("disjoncteur_temps") + 2.0 * DT)
	check(game.pannes.is_empty() and game.eclaire(sous_lampe), "le chasseur a rallumé")
	check(int(game._st["rallumages"]) == 1, "rallumage compté")
	check(game.action_label(c) == "Cache-Cache !", "secteur allumé : le chasseur n'a rien à actionner, son coup")
	await free_game(game)


## Priorité du bouton (GDD §6) : cachette > disjoncteur > pouvoir ; rien hors de la chasse.
func test_disjoncteur_priorite() -> void:
	var game: BkGame = await make_game(false)
	var h: BkActor = game.actors[1]
	var b: Dictionary = game.boitiers[0]
	h.position = game.map.center(b["pos"])
	check(game.action_label(h) == "Actionner", "près du boîtier seul : Actionner")
	# Une cachette posée à côté du boîtier passe avant.
	game.cachettes.append({"tile": b["pos"], "pos": game.map.center(b["pos"]) + Vector2(game.map.tile, 0)})
	game._reset_cachettes()
	check(game.action_label(h) == "Entrer", "cachette à portée : Entrer d'abord (%s)" % game.action_label(h))
	game.cachettes.pop_back()
	h.position = game.map.center(Vector2i(24, 18))
	check(game.action_label(h) == "Passe-Muraille" and game.action_est_coup(h), "loin de tout : le coup spécial")
	# Chasseur : la fouille passe avant le coup ; loin de tout, le bouton lance le coup.
	var c: BkActor = game.hunter
	c.position = game.map.center(Vector2i(24, 18))
	check(game.action_label(c) == "Cache-Cache !", "chasseur loin de tout : son coup")
	game.cachettes.append({"tile": Vector2i(25, 18), "pos": game.map.center(Vector2i(25, 18))})
	game._reset_cachettes()
	check(game.action_label(c) == "Fouiller" and not game.action_est_coup(c), "cachette à portée : Fouiller d'abord")
	game.cachettes.pop_back()
	game.act_for(c)
	check(c.coup_cd > 0.0 and game.coups.actifs.size() == 1, "le bouton lance le coup (recharge %.0f s)" % c.coup_cd)
	game.phase = BkGame.Phase.HIDE
	h.position = game.map.center(b["pos"])
	check(game.action_label(h) != "Actionner", "pendant la cachette : pas de disjoncteur")
	await free_game(game)


## IA : un chassé éclairé dans le secteur du chasseur va couper ; le chasseur IA va rallumer.
func test_disjoncteur_ia() -> void:
	BkRules._data["ai"]["normal"]["disjoncteur"] = 1.0
	var game: BkGame = await make_game(false)
	var m: BkMap = game.map
	var h: BkActor = game.actors[1]
	var ai: BkAi = BkAi.new(game, h, "normal")
	var b: Dictionary = game.boitiers[1]
	h.position = m.center(Vector2i(31, 4))            # sur la Place, près du boîtier B (30, 1)
	h.lit = true
	game.hunter.position = m.center(Vector2i(36, 18))  # chasseur sur la Place aussi
	ai._think_hider()
	check(ai.plan_switch == 1, "chassé éclairé, chasseur dans le secteur : il va au disjoncteur")
	h.position = m.center(b["pos"])
	ai._think_hider()
	check(ai.want_action, "arrivé au boîtier : il l'actionne")
	# Chasseur IA : un secteur coupé, il y va et l'actionne.
	game.pannes["B"] = 10.0
	var hai: BkAi = BkAi.new(game, game.hunter, "normal")
	hai._think_hunter()
	check(hai.plan_switch == 1 and not hai.path.is_empty(), "le chasseur IA part rallumer")
	game.hunter.position = m.center(b["pos"])
	hai._think_hunter()
	check(hai.want_action, "le chasseur IA actionne le boîtier")
	await free_game(game)


# ------------------------------------------------------------------ menu debug (#634)

## Menu debug de la partie rapide : rôle imposé à chaque round, perso choisi, sans chrono, retour à la
## partie rapide ; une partie rapide normale remet tout à zéro.
func test_menu_debug() -> void:
	var scr: GDScript = load("res://src/blackout/menus/bk_partie_rapide.gd")
	scr.reinitialiser()
	var ecran: Control = (load("res://src/blackout/menus/bk_partie_rapide.tscn") as PackedScene).instantiate()
	root.add_child(ecran)
	await process_frame
	scr.debug_choix = {"perso": "patxi", "role": "hunter", "boss": "", "chrono": false, "seul": false}
	ecran.preparer_debug()
	var cfg: Dictionary = BkGame.config
	check(bool(cfg["debug"]) and str(cfg["debug_role"]) == "hunter" and str(cfg["character"]) == "patxi"
		and bool(cfg["sans_chrono"]) and str(cfg["map"]) == "bac_a_sable" and str(cfg["visite"]) == "", "debug posé sur la partie")
	BkRules._data["phase_draw"] = 0.1
	BkRules._data["phase_hide"] = 0.1
	BkRules._data["phase_hunt"] = 0.5
	BkGame.config["players"] = 4
	var game: BkGame = (load(GAME) as PackedScene).instantiate()
	root.add_child(game)
	for i: int in 40:
		await physics_frame
	check(game.debug and game.hunter == game.local and game.local.character == "patxi", "chasseur imposé, perso choisi")
	check(game.phase == BkGame.Phase.HUNT and game.rounds_total == 0, "pas de versus, partie sans fin")
	check(not game.versus_actif() and not game.peut_terminer(), "debug : ni versus ni podium")
	check(game.phase_t > BkRules.f("phase_hunt") - 0.01, "sans chrono : le chrono ne descend pas (%.2f)" % game.phase_t)
	game._debug_key("L")
	check(game.lumieres.debug, "touche L : zones de lumière")
	game._debug_key("F")
	check(game.map.formes.visible and game.map.formes.get_child_count() > 0, "touche F : formes du décor")
	await free_game(game)
	scr.debug_choix["role"] = "hider"
	scr.debug_choix["seul"] = true
	ecran.preparer_debug()
	check(str(cfg["debug_role"]) == "hider" and str(cfg["visite"]) == "chasse", "personne en face : la visite")
	ecran.preparer()
	check(not bool(cfg["debug"]) and str(cfg["visite"]) == "" and not bool(cfg["sans_chrono"]), "partie rapide normale : debug remis à zéro")
	scr.reinitialiser()
	ecran.queue_free()
	await process_frame


# ------------------------------------------------------------------ coups spéciaux (#627, #630)

## Fait vivre les coups et les effets `secs` s (comme pendant la chasse).
func avance_coups(game: BkGame, secs: float) -> void:
	for i: int in int(round(secs / DT)):
		game.coups.maj(DT)


## Données (GDD §4.4) : 13 persos × 2 coups, champs communs, familles connues, recharges ≈25 s (chassé)
## et ≈20 s (chasseur) ; les 26 sont codés (étape 4).
func test_coups_donnees() -> void:
	var d: Dictionary = BkCoups.donnees()
	var persos: Dictionary = d.get("persos", {})
	var familles: Dictionary = d.get("familles", {})
	check(persos.size() == 13, "13 persos (%d)" % persos.size())
	check(familles.size() == 6 and near(float(d.get("aimant_deg", 0.0)), 20.0, 1e-6), "6 familles, aimant de 20°")
	var ids: Dictionary = {}
	for ch: Variant in BkRules.data()["characters"]:
		check(persos.has(ch), "coups de %s" % ch)
		for role: String in ["chasse", "chasseur"]:
			var c: Dictionary = BkCoups.coup_de(str(ch), role == "chasseur")
			for k: String in ["id", "nom", "famille", "recharge", "portee", "duree"]:
				check(c.has(k), "%s/%s : champ %s" % [ch, role, k])
			check(familles.has(str(c.get("famille", ""))), "%s/%s : famille connue (%s)" % [ch, role, c.get("famille")])
			check(near(float(c.get("recharge", 0.0)), 25.0 if role == "chasse" else 20.0, 5.0),
				"%s/%s : recharge %.0f s" % [ch, role, float(c.get("recharge", 0.0))])
			check(BkCoups.code(c), "%s/%s : codé (pret, famille connue)" % [ch, role])
			check(not ids.has(c.get("id")), "id unique : %s" % c.get("id"))
			ids[c.get("id")] = true
	check(str(BkCoups.coup_de("louis", false)["nom"]) == "Passe-Muraille" and str(BkCoups.coup_de("louis", true)["nom"]) == "Cache-Cache !",
		"coups de Louis")


## Recharge (GDD §4.1) : le coup part, la recharge du coup démarre (bouton plein → vide), un second appui
## ne fait rien ; un gâteau basque recharge tout de suite (chassé ou chasseur), sans point ni sprint ; un
## coup prêt ne mange pas le gâteau ; un coup pas encore codé est « bientôt » et ne consomme rien.
func test_recharge() -> void:
	var game: BkGame = await make_game()
	var h: BkActor = game.hunter
	game.local = h
	check(game.action_label(h) == "Cache-Cache !" and near(game.action_cooldown(h), 0.0, 1e-6), "coup prêt")
	check(game.coups.lance(h) == "", "le coup part")
	var rc: float = float(BkCoups.coup_de("louis", true)["recharge"])
	check(near(h.coup_cd, rc, 1e-6) and near(game.action_cooldown(h), 1.0, 1e-6), "recharge de %.0f s" % rc)
	check(game.coups.lance(h) == "attente" and game.coups.actifs.size() == 1, "en recharge : rien ne part")
	for i: int in 60 * 5:
		h.step(Vector2.ZERO, Vector2.ZERO, DT)
	check(near(h.coup_cd, rc - 5.0, 0.05) and near(game.action_cooldown(h), (rc - 5.0) / rc, 0.01),
		"la recharge s'écoule (%.2f s)" % h.coup_cd)
	# Gâteau : recharge immédiate du chasseur.
	var s0: int = h.score
	game.gateaux = [{"pos": h.position}]
	game._update_ideas(DT)
	check(h.coup_cd <= 0.0 and game.gateaux.is_empty(), "gâteau mangé : coup rechargé")
	check(h.score == s0 and near(h.speed(), BkRules.px("speed_hunter") * h.speed_mult, 1e-3), "ni point ni sprint")
	game.gateaux = [{"pos": h.position}]
	game._update_ideas(DT)
	check(game.gateaux.size() == 1, "coup déjà prêt : le gâteau reste au sol")
	# Chassé.
	var c: BkActor = game.actors[1]
	c.position = tile_pos(game, 28, 12)
	c.coup_cd = 10.0
	c.coup_cd_max = 25.0
	var sc: int = c.score
	game.gateaux = [{"pos": c.position}]
	game._update_ideas(DT)
	check(c.coup_cd <= 0.0 and c.score == sc, "chassé : gâteau = recharge, pas de point")
	# Coup pas encore codé (pret faux) : « bientôt », rien de consommé.
	c.character = "txomin"
	var fil: Dictionary = BkCoups.coup_de("txomin", false)
	fil["pret"] = false
	check(game.action_label(c) == "Fil d'Ariane" and game.coups.lance(c) == "bientot" and c.coup_cd <= 0.0,
		"coup pas prêt : « bientôt », rien de consommé")
	fil["pret"] = true
	await free_game(game)


## Garde-fous (GDD §4.3) : effet gênant ≤ 3 s, fenêtre de gêne partagée, puis 2 s de protection ;
## commandes inversées ≤ 2 s ; révélé non plafonné et accepté pendant la protection ; insensible refuse ;
## figé bloque, inversé retourne, ralenti ralentit ; un coup de chassé qui gêne le chasseur rapporte 2
## points ; chasseur aveuglé : la jauge ne monte plus.
func test_plafond_protection() -> void:
	var game: BkGame = await make_game()
	var co: BkCoups = game.coups
	var a: BkActor = game.actors[1]
	a.position = devant(game, 3)
	var cap: float = BkRules.f("effet_max_genant_s")
	check(near(cap, 3.0, 1e-6) and near(BkRules.f("effet_protection_s"), 2.0, 1e-6) and near(BkRules.f("effet_inverse_max_s"), 2.0, 1e-6),
		"réglages : 3 s, 2 s de protection, inversé 2 s")
	check(co.applique_effet(a, "fige", 10.0), "figé posé")
	check(near(float(a.effets["fige"]["left"]), cap, 1e-6), "plafonné à %.0f s (%.2f)" % [cap, float(a.effets["fige"]["left"])])
	avance_coups(game, 1.0)
	check(co.applique_effet(a, "colle", 5.0), "collé par-dessus")
	check(near(float(a.effets["colle"]["left"]), cap - 1.0, 0.05), "fenêtre de gêne partagée : %.2f s" % float(a.effets["colle"]["left"]))
	avance_coups(game, cap - 1.0 + 2.0 * DT)
	check(not BkEffets.gene_en_cours(a) and near(a.protection, BkRules.f("effet_protection_s"), 0.05),
		"gêne finie au bout de 3 s, protection %.2f s" % a.protection)
	check(not co.applique_effet(a, "ralenti", 1.0) and not co.applique_effet(a, "fige", 1.0), "protection : aucun nouvel effet gênant")
	check(co.applique_effet(a, "revele", 10.0) and near(float(a.effets["revele"]["left"]), 10.0, 1e-6), "révélé : non plafonné, passe la protection")
	avance_coups(game, BkRules.f("effet_protection_s") + 2.0 * DT)
	check(a.protection <= 0.0, "protection finie")
	check(co.applique_effet(a, "inverse", 5.0) and near(float(a.effets["inverse"]["left"]), 2.0, 1e-6), "inversé : 2 s au plus")
	var x0: float = a.position.x
	a.step(Vector2.RIGHT, Vector2.ZERO, 0.1)
	check(a.position.x < x0 - 1.0, "inversé : on part à l'opposé")
	BkEffets.efface(a)
	check(co.applique_effet(a, "fige", 1.0), "figé")
	var p0: Vector2 = a.position
	a.step(Vector2.RIGHT, Vector2.ZERO, 0.1)
	check(a.position == p0, "figé : immobile")
	BkEffets.efface(a)
	var v0: float = a.speed()
	co.applique_effet(a, "ralenti", 2.0)
	check(near(a.speed() / v0, 1.0 - BkRules.f("effet_ralenti_k"), 1e-4), "ralenti : vitesse × 0,7")
	BkEffets.efface(a)
	co.applique_effet(a, "insensible", 4.0)
	check(not co.applique_effet(a, "fige", 1.0) and near(float(a.effets["insensible"]["left"]), 4.0, 1e-6), "insensible : refuse, et dure 4 s")
	# Coup de chassé qui gêne le chasseur : +2 (GDD §2.3) ; chasseur aveuglé : la jauge ne monte plus.
	var h: BkActor = game.hunter
	var s0: int = a.score
	check(co.applique_effet(h, "aveugle", 5.0, {}, a) and a.score == s0 + BkRules.score("hider_coup_touche"),
		"chassé qui touche le chasseur : +%d" % BkRules.score("hider_coup_touche"))
	check(near(float(h.effets["aveugle"]["left"]), cap, 1e-6), "aveuglé plafonné à 3 s")
	BkEffets.efface(a)
	a.gauge = 0.0
	tick(game, 0.2)
	check(a.gauge <= 0.0, "chasseur aveuglé : la jauge ne monte pas")
	await free_game(game)


## Visée (GDD §4.2) : droit devant, aimant de ±20° vers la cible visible la mieux alignée, à portée ;
## rien au-delà de 20°, derrière un mur, hors de portée ou invisible.
func test_aimant() -> void:
	var game: BkGame = await make_game()
	var co: BkCoups = game.coups
	var h: BkActor = game.hunter
	var t: float = game.map.tile
	var a: BkActor = game.actors[1]
	var b: BkActor = game.actors[2]
	var cibles: Array[BkActor] = [a]
	a.position = h.position + Vector2.from_angle(deg_to_rad(15.0)) * 4.0 * t
	var r: Dictionary = co.vise(h, Vector2.RIGHT, 8.0 * t, cibles)
	check(r["cible"] == a and absf(angle_difference((r["dir"] as Vector2).angle(), deg_to_rad(15.0))) < 0.02, "15° : aimanté vers la cible")
	a.position = h.position + Vector2.from_angle(deg_to_rad(30.0)) * 4.0 * t
	r = co.vise(h, Vector2.RIGHT, 8.0 * t, cibles)
	check(r["cible"] == null and (r["dir"] as Vector2).is_equal_approx(Vector2.RIGHT), "30° : droit devant")
	a.position = h.position + Vector2.from_angle(deg_to_rad(10.0)) * 9.0 * t
	r = co.vise(h, Vector2.RIGHT, 8.0 * t, cibles)
	check(r["cible"] == null, "hors de portée : rien")
	a.position = h.position + Vector2.from_angle(deg_to_rad(15.0)) * 4.0 * t
	b.position = h.position + Vector2.from_angle(deg_to_rad(-5.0)) * 5.0 * t
	cibles.append(b)
	r = co.vise(h, Vector2.RIGHT, 8.0 * t, cibles)
	check(r["cible"] == b, "deux cibles : la mieux alignée")
	BkEffets.force(b, "invisible")
	r = co.vise(h, Vector2.RIGHT, 8.0 * t, cibles)
	check(r["cible"] == a, "cible invisible ignorée")
	# Derrière un mur plein : (12, 10) regarde (12, 8) par-dessus le mur (12, 9).
	h.position = tile_pos(game, 12, 10)
	a.position = tile_pos(game, 12, 8)
	var seul: Array[BkActor] = [a]
	r = co.vise(h, Vector2.UP, 8.0 * t, seul)
	check(r["cible"] == null, "derrière un mur : rien")
	# Le chasseur vise les chassés hors cachette ; un chassé vise le chasseur.
	a.hidden_in = 0
	check(not co.adversaires(h, {}).has(a) and co.adversaires(h, {"touche_cachette": true}).has(a), "cachette : pas touché sauf drapeau")
	a.hidden_in = -1
	var vs: Array[BkActor] = co.adversaires(a, {})
	check(vs.size() == 1 and vs[0] == h, "un chassé vise le chasseur")
	await free_game(game)


## Passe-Muraille (Louis chassé) : par-dessus un muret (en vol, sans collision, au-dessus de la case),
## posé derrière ; rien contre un mur plein (recharge non consommée) ; à travers une cloison fine ; l'IA
## en danger saute l'obstacle qui l'éloigne du chasseur.
func test_passe_muraille() -> void:
	var game: BkGame = await make_game()
	var m: BkMap = game.map
	var l: BkActor = game.actors[1]
	check(m.at(Vector2i(24, 16)) == "m" and m.walkable(Vector2i(24, 15)) and m.walkable(Vector2i(24, 17)), "précondition : muret en (24, 16)")
	l.position = m.center(Vector2i(24, 17))
	l.look = -PI * 0.5
	check(game.action_label(l) == "Passe-Muraille", "bouton : Passe-Muraille")
	check(game.coups.lance(l) == "", "le saut part")
	check(l.en_coup and near(l.coup_cd, 25.0, 1e-6), "en coup, recharge de 25 s")
	avance_coups(game, 0.25)
	check(l.saut_px > 10.0 and m.to_tile(l.position) == Vector2i(24, 16) and l.collision_mask == 0,
		"en vol au-dessus du muret (%.0f px, case %s)" % [l.saut_px, m.to_tile(l.position)])
	var p_vol: Vector2 = l.position
	l.step(Vector2.DOWN, Vector2.ZERO, 0.1)
	check(l.position == p_vol, "en vol : les commandes ne bougent pas le perso")
	avance_coups(game, 0.4)
	check(not l.en_coup and m.to_tile(l.position) == Vector2i(24, 15) and l.collision_mask == BkMap.LAYER_MOVE and l.saut_px == 0.0,
		"posé derrière le muret (%s)" % m.to_tile(l.position))
	# Mur plein : rien, recharge non consommée.
	l.coup_cd = 0.0
	l.position = m.center(Vector2i(12, 10))
	l.look = -PI * 0.5
	check(m.at(Vector2i(12, 9)) == "#" and m.walkable(Vector2i(12, 8)), "précondition : mur plein en (12, 9)")
	check(game.coups.lance(l) == "Rien à franchir devant" and l.coup_cd <= 0.0 and not l.en_coup, "mur plein : rien, recharge non consommée")
	# Rien devant (sol libre) : rien non plus.
	l.position = m.center(Vector2i(25, 12))
	l.look = 0.0
	check(game.coups.lance(l) != "" and l.coup_cd <= 0.0, "sol libre devant : rien")
	# Cloison fine.
	l.position = m.center(Vector2i(9, 13))
	l.look = 0.0
	check(m.at(Vector2i(10, 13)) == "|", "précondition : cloison fine en (10, 13)")
	check(game.coups.lance(l) == "", "cloison fine : le saut part")
	avance_coups(game, 0.7)
	check(m.to_tile(l.position) == Vector2i(11, 13), "de l'autre côté de la cloison (%s)" % m.to_tile(l.position))
	# Regard en biais (surtout vers le bas, un peu à gauche) : l'axe dominant, puis l'autre.
	var dirs: Array[Vector2i] = BkCoupDeplacement.directions(Vector2(-0.5, 1.0))
	check(dirs.size() == 2 and dirs[0] == Vector2i(0, 1) and dirs[1] == Vector2i(-1, 0), "biais : axe dominant puis l'autre (%s)" % str(dirs))
	# IA : chassé menacé contre le muret, chasseur en dessous : il saute vers le haut.
	l.coup_cd = 0.0
	l.position = m.center(Vector2i(24, 17))
	l.look = PI * 0.5
	l.gauge = 0.4
	game.hunter.position = m.center(Vector2i(24, 21))
	check(not game.coups.essaie_ia(l, {"menace": false}), "IA sans danger : rien")
	check(game.coups.essaie_ia(l, {"menace": true}) and l.en_coup, "IA en danger : elle saute")
	avance_coups(game, 0.7)
	check(m.to_tile(l.position) == Vector2i(24, 15), "IA : par-dessus le muret, loin du chasseur (%s)" % m.to_tile(l.position))
	await free_game(game)


## Cache-Cache ! (Louis chasseur) : bulle « 1, 2, 3… j'arrive ! » et annonce vues de tous ; pendant 5 s,
## le chassé libre le plus proche laisse une piste de pas qui s'estompe ; pas dans une cachette ; l'IA du
## chasseur suit le dernier pas.
func test_cache_cache() -> void:
	var game: BkGame = await make_game()
	var h: BkActor = game.hunter
	var t: float = game.map.tile
	game.local = h
	var a1: BkActor = game.actors[1]
	var a2: BkActor = game.actors[2]
	a1.position = tile_pos(game, 28, 12)
	a2.position = tile_pos(game, 33, 12)
	check(game.coups.lance(h) == "", "Cache-Cache ! part")
	var inst: BkCoupRevele = game.coups.actifs[0] as BkCoupRevele
	check(inst != null and inst.cible == a1, "cible : le chassé le plus proche")
	check(game.coups.bulles.size() == 1 and str(game.coups.bulles[0]["texte"]).contains("j'arrive"), "bulle « 1, 2, 3… j'arrive ! »")
	check(game.coups.annonces.size() == 1 and str(game.coups.annonces[0]["nom"]) == "Cache-Cache !", "annonce au-dessus du chasseur")
	for i: int in 60:
		a1.position += Vector2(0, 3.0 * t / 60.0)
		a2.position += Vector2(0, 3.0 * t / 60.0)
		game.coups.maj(DT)
	var params: Dictionary = BkCoups.coup_de("louis", true)["params"]
	check(inst.pas.size() >= int(3.0 / float(params["pas_ecart"])), "pas posés en marchant (%d)" % inst.pas.size())
	check(inst.pas.all(func(p: Dictionary) -> bool: return absf((p["pos"] as Vector2).x - a1.position.x) < 1.0), "seulement les pas du plus proche")
	check(game.coups.piste_de(h).distance_to(a1.position) < t, "dernier pas : là où il est")
	var hai: BkAi = BkAi.new(game, h, "normal")
	hai._think_hunter()
	check(hai.clue != Vector2.INF and hai.clue.distance_to(a1.position) < 1.5 * t, "IA du chasseur : le dernier pas devient l'indice")
	# Après 5 s : plus de nouveaux pas ; la piste s'estompe puis le coup se termine.
	avance_coups(game, 4.2)
	for i2: int in 30:
		a1.position += Vector2(0, -2.0 * t / 30.0)
		game.coups.maj(DT)
	check(inst.pas.all(func(p: Dictionary) -> bool: return float(p["age"]) > 0.4), "après 5 s : plus de nouveaux pas")
	avance_coups(game, float(params["pas_vie"]))
	check(game.coups.actifs.is_empty(), "la piste s'est estompée, coup fini")
	# Un chassé dans une cachette n'est pas pisté : le suivant le plus proche l'est.
	a1.hidden_in = 0
	h.coup_cd = 0.0
	check(game.coups.lance(h) == "" and (game.coups.actifs[0] as BkCoupRevele).cible == a2, "chassé en cachette ignoré")
	a1.hidden_in = -1
	await free_game(game)


## Pièges et onde de détection retirés (GDD §4, 22/10) : plus de réglages, de points ni d'IA ; le
## bouton ne propose plus « Piège » ni « Onde » ; les points « coup qui touche le chasseur » les remplacent.
func test_pieges_retires() -> void:
	for k: String in ["trap_cooldown", "trap_max", "trap_slow", "trap_duration", "trap_seen_range", "detect_cooldown",
			"detect_radius", "detect_duration", "detect_hint_duration", "gateau_sprint", "gateau_duree"]:
		check(not BkRules.data().has(k), "réglage retiré : " + k)
	var sc: Dictionary = BkRules.data()["score"]
	check(not sc.has("hider_trap_hit") and not sc.has("hider_cake") and int(sc.get("hider_coup_touche", 0)) == 2,
		"points : coup qui touche le chasseur +2")
	for lv: Variant in BkRules.data()["ai"]:
		var cfg: Dictionary = BkRules.ai(str(lv))
		check(not cfg.has("trap_ambush") and not cfg.has("trap_chase") and not cfg.has("smart_wave") and cfg.has("coup"),
			"IA %s : plus de piège ni d'onde, un réglage de coup" % lv)
	for o: Dictionary in BkRules.options_partie():
		for r: Dictionary in o.get("reglages", []):
			check(str(r.get("cle", "")) != "gateau_duree", "option du sprint de gâteau retirée")
	var game: BkGame = await make_game()
	check(not ("traps" in game) and not ("reveals" in game), "plus de pièges ni d'ondes dans la partie")
	check(not game.has_method("_place_trap") and not game.has_method("_detect") and not game.has_method("_update_traps"),
		"plus de pose ni de déclenchement")
	var ai: BkAi = BkAi.new(game, game.actors[1], "normal")
	check(not ai.has_method("on_trap") and not ai.has_method("on_detect") and not ("ambush" in ai), "IA : plus de piège ni d'onde")
	for a: BkActor in game.actors:
		a.position = tile_pos(game, 24, 18)
		check(not (game.action_label(a) in ["Piège", "Onde"]), "bouton sans Piège ni Onde (%s)" % game.action_label(a))
	await free_game(game)


# ------------------------------------------------------------------ éléments livrés (23/10)

## Élément en cours du perso de `a` après une image.
func joue(a: BkActor, secs: float = DT) -> String:
	var n: int = maxi(1, int(round(secs / DT)))
	for i: int in n:
		a.perso._process(DT)
	return a.perso.element_courant()


## Chaque élément livré d'un perso est lu tel quel ; un élément manquant prend un voisin ou une
## silhouette de repli, jamais une image vide ; plus aucun set de perso n'a d'élément ghost.
func test_elements_livres_et_replis() -> void:
	for c: Variant in BkRules.data().get("characters", []):
		var dir: String = BkPerso.dossier(str(c))
		check(not ResourceLoader.exists(dir + "ghost_sheet.png"), "%s : plus d'élément ghost dans le set" % c)
		for el: String in BkPerso.ELEMENTS:
			if ResourceLoader.exists(dir + el + "_sheet.png"):
				check(BkPerso.livre(str(c), el), "%s : %s livré, lu tel quel" % [c, el])
	for el: String in BkPerso.ELEMENTS + PackedStringArray(["marcher", "sursaut", "parler"]):
		if el == "lift":
			continue
		var d: Dictionary = BkPerso.element("perso_de_test", el)
		check(not d.is_empty() and d["tex"] != null and int(d["n"]) >= 1, "repli de %s sans planche" % el)
	var v: Dictionary = BkPerso.element("louis", "sursaut")
	check(v.get("voisin", "") == "idle", "élément absent d'un vrai set : voisin idle (%s)" % v.get("voisin", ""))
	var pnj_renverse: Dictionary = BkPerso.element("festayre", "renverse")
	check(pnj_renverse.has("voisin") or pnj_renverse.has("repli"), "PNJ sans renverse : repli propre")
	var p: Dictionary = BkPerso.portrait("louis")
	check(BkPerso.livre("louis", "portrait") and (p["cell"] as Vector2) == Vector2(64, 64), "portrait de Louis 64×64")
	check(BkPerso.portrait_tex("louis", 32).get_width() == 32, "portrait réduit pour le HUD")
	check(not BkPerso.portrait("perso_de_test").is_empty(), "portrait de repli")
	check(BkPerso.FAMILLES.has("fantome") and not BkPerso.ELEMENTS.has("ghost"), "ghost n'est plus un élément de perso")


## Effets subis (GDD §4.5) : le perso joue l'animation d'effet ; renversé sans rotation quand la planche existe.
func test_effets_animes() -> void:
	var game: BkGame = await make_game()
	var a: BkActor = game.actors[1]
	a.position = devant(game, 3)
	var attendu: Dictionary = {"fige": "etourdi", "inverse": "etourdi", "renverse": "renverse", "colle": "colle",
		"ralenti": "ralenti", "aveugle": "aveugle", "tracte": "tracte"}
	for type: String in attendu:
		BkEffets.efface(a)
		BkEffets.force(a, type, {"vers": a.position + Vector2(64, 0)} if type == "tracte" else {})
		check(joue(a) == attendu[type], "%s : animation %s (%s)" % [type, attendu[type], a.perso.element_courant()])
	BkEffets.efface(a)
	BkEffets.force(a, "renverse")
	joue(a)
	check(is_zero_approx(a.perso.rotation), "renversé : la planche renverse, pas de sprite couché")
	BkEffets.efface(a)
	check(joue(a) == "idle", "effet fini : retour à l'idle")
	await free_game(game)


## interagir (fouille, disjoncteur), lancement des coups selon le rôle, victoire et défaite de fin de round.
func test_gestes_et_fin() -> void:
	var game: BkGame = await make_game()
	var h: BkActor = game.hunter
	var a: BkActor = game.actors[1]
	a.position = devant(game, 3)
	h.search_left = 1.0
	check(joue(h) == "interagir", "fouille : interagir")
	h.search_left = 0.0
	a.use_left = 1.0
	check(joue(a) == "interagir", "disjoncteur : interagir")
	a.use_left = 0.0
	check(game.coups.lance(h) == "", "coup du chasseur lancé")
	check(joue(h) == "cast_chasseur", "lancement du chasseur : cast_chasseur")
	h.velocity = Vector2(100, 0)
	check(joue(h, 0.2) == "cast_chasseur", "le lancement passe par-dessus la course")
	var l: float = h.once_length("cast")
	joue(h, l + 0.05)
	check(h.perso.element_courant() == "run", "après le lancement : la course reprend")
	h.velocity = Vector2.ZERO
	a.play_once("cast")
	check(joue(a) == "cast_chasse", "lancement d'un chassé : cast_chasse")
	joue(a, 1.0)
	a.end_pose = "victory"
	check(joue(a) == "victoire", "fin de round gagnée : victoire")
	a.end_pose = "sad"
	check(joue(a) == "defaite", "fin de round perdue : defaite")
	await free_game(game)


## Fantôme commun (#646) : appear à l'apparition, float à l'arrêt, advance en mouvement, planches du set
## fantome pour tous les persos, jamais d'élément ghost cherché dans les sets.
func test_fantome_commun() -> void:
	var game: BkGame = await make_game()
	var a: BkActor = game.actors[1]
	a.character = "maia"
	a.set_character("maia")
	a.position = devant(game, 3)
	joue(a)
	game._found(a)
	check(joue(a) == "lift", "trouvé : envol (lift)")
	joue(a, BkRules.f("lift_s"))
	check(a.perso.element_courant() == "appear", "puis le fantôme commun apparaît (appear)")
	var appear: Dictionary = BkPerso.element(BkPerso.FANTOME, "appear")
	check(not appear.has("repli") and a.perso.texture == appear["tex"], "planche du fantôme commun")
	joue(a, 1.0)
	check(a.perso.element_courant() == "float", "à l'arrêt : float")
	a.velocity = Vector2(80, 0)
	check(joue(a) == "advance", "en mouvement : advance")
	check(a.perso.texture == BkPerso.element(BkPerso.FANTOME, "advance")["tex"], "même fantôme pour tous")
	check(a.display_name != "", "le pseudo dit à qui il est")
	for k: Variant in BkPerso._cache:
		check(not str(k).ends_with("/ghost"), "élément ghost cherché : " + str(k))
	await free_game(game)


## PNJ (GDD §3.8, base de #647) : pnj_nombre humains, sets réels d'abord, hors des joueurs, sans collision
## bloquante ; ils font leurs activités, marchent, sursautent et fuient un coup spécial ou une panne.
func test_foule_pnj() -> void:
	var game: BkGame = await make_game()
	var f: BkFoule = game.foule
	var n: int = int(BkRules.f("pnj_nombre"))
	check(n >= 15 and n <= 25, "15 à 25 humains par carte (%d)" % n)
	check(f.pnj.size() == n, "%d PNJ posés (attendu %d)" % [f.pnj.size(), n])
	var reels: int = 0
	var dispo: int = 0
	var humains: Dictionary = BkFoule._donnees()["humains"]
	for id: Variant in humains:
		if not BkPerso.placeholder(str(id)):
			dispo += 1
	for a: BkActor in f.pnj:
		check(not game.actors.has(a) and a.collision_layer == 0, "%s : hors des joueurs, traversable" % a.character)
		check(not BkRules.data()["characters"].has(a.character), "jamais un perso jouable")
		check(a.get_parent() == game.actors[0].get_parent(), "même calque trié que les persos")
		if not BkPerso.placeholder(a.character):
			reels += 1
	check(reels == mini(dispo, n), "sets réels d'abord (%d sur %d disponibles)" % [reels, dispo])
	# Activités en boucle, puis marche.
	var acts: int = 0
	for a: BkActor in f.pnj:
		var el: String = joue(a)
		if el != "idle" and el != "run":
			acts += 1
	check(acts >= n / 2, "activités jouées (%d)" % acts)
	for e: Dictionary in f.etats:
		e["t"] = 0.0
		e["fixe"] = false
	var p0: Array[Vector2] = []
	for a: BkActor in f.pnj:
		p0.append(a.position)
	for i: int in 60:
		f.maj(DT)
	var bouges: int = 0
	for k: int in f.pnj.size():
		if f.pnj[k].position.distance_to(p0[k]) > 4.0:
			bouges += 1
	check(bouges >= n / 2, "ils marchent entre des points (%d)" % bouges)
	var marcheurs: Array = range(n).filter(func(k: int) -> bool: return f.etats[k]["mode"] == "marche")
	check(not marcheurs.is_empty() and joue(f.pnj[int(marcheurs[0])]) == "marcher", "en marche : élément marcher")
	# Coup spécial proche : sursaut puis fuite (run) hors du rayon.
	var cible: BkActor = f.pnj[1]
	var centre: Vector2 = cible.position + Vector2(8, 0)
	var d0: float = cible.position.distance_to(centre)
	f.coup(centre)
	check(f.etats[1]["mode"] == "sursaut" and joue(cible) == "sursaut", "coup proche : sursaut")
	var vu_fuir: bool = false
	for i2: int in 240:
		f.maj(DT)
		if f.etats[1]["mode"] == "fuite":
			vu_fuir = vu_fuir or joue(cible) == "run"
	check(vu_fuir, "après le sursaut : il fuit en courant (run)")
	check(cible.position.distance_to(centre) > d0 + game.map.tile * 2.0, "il s'est éloigné du coup (%.0f px)" % cible.position.distance_to(centre))
	# Panne de son secteur : sursaut.
	var p2: BkActor = f.pnj[4]
	f.etats[4]["mode"] = "activite"
	f.panne(game.map.secteur_of(game.map.to_tile(p2.position)))
	check(f.etats[4]["mode"] == "sursaut", "lumière coupée dans son secteur : sursaut")
	# Vu du chasseur : seulement ce qu'il voit, silhouette dans l'ombre.
	var vu: BkActor = f.pnj[2]
	f.etats[2]["mode"] = "activite"
	f.etats[2]["fixe"] = true
	vu.position = devant(game, 2)
	var loin: BkActor = f.pnj[3]
	f.etats[3]["fixe"] = true
	f.etats[3]["mode"] = "activite"
	loin.position = tile_pos(game, CHASSEUR.x - 6, CHASSEUR.y)
	f.maj_vue(true, 1.0)
	check(vu.shown and not loin.shown, "chasseur : PNJ dans son cône vu, dans son dos caché")
	f.maj_vue(false, 1.0)
	check(loin.shown, "chassé : toute la foule visible")
	await free_game(game)
