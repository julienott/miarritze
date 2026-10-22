extends SceneTree
## Tests headless de Blackout : détection progressive (jauge, seuils), ressenti du chassé, mesures
## de tension (frôlements, vu puis perdu), une partie IA contre IA courte, et la partie en N rounds
## (tirage en sac, versus, podium), la partie rapide (réglages → règles), le profil (persistance),
## la carte bac à sable (cases de vue et de passage), les persos en pixel art (planches et repli).
## godot --headless --path . --fixed-fps 60 --script res://tests/bk_tests.gd [-- --only=nom]

const GAME: String = "res://src/blackout/bk_game.tscn"
const DT: float = 1.0 / 60.0

var _failures: int = 0
var _passed: int = 0
var _only: String = ""
var _saved: Dictionary = {}
var _saved_cfg: Dictionary = {}


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
		test_persos_px32, test_cases_vue_passage, test_bac_a_sable, test_regles_carte]
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
## les mesures à la main. Chasseur = acteur 0 en CHASSEUR regardant vers l'est.
func make_game() -> BkGame:
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
		a.frozen = false
		a.gauge = 0.0
		a.position = Vector2(-5000, -5000)
	game._st.merge(BkGame.tension_keys(), true)
	game._tens.clear()
	game.hunter.position = tile_pos(game, CHASSEUR.x, CHASSEUR.y)
	game.hunter.look = 0.0
	return game


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
	check(m.lampadaires.size() >= m.secteurs.size(), "des lampadaires dans chaque secteur")
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
