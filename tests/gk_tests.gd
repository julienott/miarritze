extends SceneTree
## Tests headless de Gordeka : détection progressive (jauge, seuils), ressenti du chassé, mesures
## de tension (frôlements, vu puis perdu) et une partie IA contre IA courte.
## godot --headless --path . --fixed-fps 60 --script res://tests/gk_tests.gd [-- --only=nom]

const GAME: String = "res://src/gordeka/gk_game.tscn"
const DT: float = 1.0 / 60.0

var _failures: int = 0
var _passed: int = 0
var _only: String = ""
var _saved: Dictionary = {}


func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			_only = arg.trim_prefix("--only=")
	_saved = GkRules.data().duplicate(true)
	_run.call_deferred()


func _run() -> void:
	var tests: Array[Callable] = [test_jauge_remplissage, test_jauge_decroissance, test_jauge_sans_detection,
		test_frisson_intensite, test_frisson_coeur, test_frisson_local, test_frolements, test_vu_perdu, test_capture_pas_frolement, test_poursuite, test_poursuite_tous_vus,
		test_options_partie, test_partie_ia_courte]
	for t: Callable in tests:
		if _only != "" and not t.get_method().contains(_only):
			continue
		GkRules._data = _saved.duplicate(true)
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
		g = GkGame.next_gauge(g, vis, d, DT)
		t += DT
	return t


# ------------------------------------------------------------------ options de partie

## Catalogue des options validées (futur menu de création de partie) : chaque clé existe dans
## rules.json, les choix sont bornés et seules les clés déclarées sont acceptées.
func test_options_partie() -> void:
	var opts: Array = GkRules.options_partie()
	check(not opts.is_empty(), "options_partie.json vide ou illisible")
	for o: Dictionary in opts:
		for r: Dictionary in o.get("reglages", []):
			check(GkRules.data().has(str(r["cle"])), "clé inconnue de rules.json : " + str(r["cle"]))
	GkRules.appliquer_options({"gateaux_nombre": 99, "idee_gateaux": 0, "pas_une_option": 5})
	check(near(GkRules.f("gateaux_nombre"), 8.0, 0.001), "curseur non borné")
	check(not GkRules.on("idee_gateaux"), "on/off non appliqué")
	check(not GkRules.data().has("pas_une_option"), "clé non déclarée acceptée")


# ------------------------------------------------------------------ jauge de détection

func test_jauge_remplissage() -> void:
	GkRules._data["idee_detection"] = 1.0
	var tile: float = GkRules.f("tile_px")
	var near_px: float = GkRules.px("near_radius")
	var far_px: float = GkRules.px("cone_range")
	var t_near: float = fill_time(near_px, 1.0)
	var t_far: float = fill_time(far_px, 1.0)
	check(near(t_near, GkRules.f("detection_temps_pres"), 2.0 * DT), "tout près : pleine en %.2f s (attendu %.2f)" % [t_near, GkRules.f("detection_temps_pres")])
	check(near(t_far, GkRules.f("detection_temps_loin"), 2.0 * DT), "au bout du cône : pleine en %.2f s (attendu %.2f)" % [t_far, GkRules.f("detection_temps_loin")])
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
	check(near(GkGame.detection_rate(far_px, 0.0) * GkRules.f("detection_temps_loin"), GkRules.f("detection_partiel"), 1e-4),
		"part vue nulle : vitesse × detection_partiel")


func test_jauge_decroissance() -> void:
	GkRules._data["idee_detection"] = 1.0
	var dec: float = GkRules.f("detection_decroissance")
	var g: float = 0.8
	var t: float = 0.0
	while g > 0.0 and t < 10.0:
		g = GkGame.next_gauge(g, 0.0, 0.0, DT)
		t += DT
	check(near(t, 0.8 / dec, 2.0 * DT), "hors de vue : redescend en %.2f s (attendu %.2f)" % [t, 0.8 / dec])
	check(g == 0.0, "jamais sous zéro")
	# Redescente plus lente que la montée de près : un frôlement laisse le temps de voir le « ? ».
	check(dec < 1.0 / GkRules.f("detection_temps_pres"), "redescend plus lentement qu'elle ne monte de près")
	# Seuil du « ? » franchi avant la capture, à toute distance.
	var g2: float = GkGame.next_gauge(0.0, 1.0, GkRules.px("near_radius"), DT)
	check(g2 < GkRules.f("detection_doute"), "le « ? » n'est pas immédiat (une image ne suffit pas)")
	check(GkRules.f("detection_doute") > 0.0 and GkRules.f("detection_doute") < 1.0, "seuil du « ? » entre 0 et 1")


func test_jauge_sans_detection() -> void:
	GkRules._data["idee_detection"] = 0.0
	var t: float = fill_time(GkRules.px("cone_range"), 1.0 / 3.0)
	check(near(t, GkRules.f("capture_time"), 2.0 * DT), "règle d'avant : capture en capture_time à toute distance (%.2f s)" % t)
	var g: float = GkGame.next_gauge(0.5, 0.0, 0.0, 0.1)
	check(near(g, 0.5 - 0.1 * GkRules.f("capture_decay") / GkRules.f("capture_time"), 1e-5), "règle d'avant : vidage rapide")


# ------------------------------------------------------------------ ressenti du chassé

func test_frisson_intensite() -> void:
	var tile: float = GkRules.f("tile_px")
	check(GkFrisson.intensity(GkRules.px("frisson_portee") + tile, 0.0) == 0.0, "rien au-delà de frisson_portee")
	check(near(GkFrisson.intensity(0.0, 0.0), 1.0, 1e-5), "maximum au contact")
	var last: float = 2.0
	for k: int in 10:
		var v: float = GkFrisson.intensity(tile * k, 0.0)
		check(v <= last + 1e-6, "décroît avec la distance (%d cases)" % k)
		last = v
	check(GkFrisson.intensity(GkRules.px("frisson_portee") + tile, 0.2) >= 0.7, "en train d'être vu : au moins fort, même de loin")


func test_frisson_coeur() -> void:
	var s: AudioStreamWAV = GkFrisson.heartbeat_stream()
	check(s.data.size() > 4000 and s.get_length() > 0.3, "battement de cœur généré (%.2f s)" % s.get_length())


## En partie : le chassé local ressent le chasseur proche ; le chasseur, lui, jamais.
func test_frisson_local() -> void:
	GkRules._data["idee_frisson"] = 1.0
	var game: GkGame = await make_game()
	var me: GkActor = game.actors[1]
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
	me.position = game.hunter.position + Vector2(-(GkRules.f("frisson_portee") + 2.0) * game.map.tile, 0)
	for i: int in 60:
		game.frisson._process(DT)
	check(game.frisson.level < 0.05, "loin : plus de frisson (%.2f)" % game.frisson.level)
	game.local = game.hunter
	for i: int in 60:
		game.frisson._process(DT)
	check(game.frisson.level == 0.0, "le chasseur n'a pas de frisson")
	await free_game(game)


# ------------------------------------------------------------------ mesures de tension

## Partie posée sur la carte, sans boucle de jeu : on place les acteurs et on appelle la capture et
## les mesures à la main. Chasseur = acteur 0 en (36, 17) regardant vers l'est, place du fronton.
func make_game() -> GkGame:
	var game: GkGame = (load(GAME) as PackedScene).instantiate()
	GkGame.config["players"] = 3
	root.add_child(game)
	game.set_physics_process(false)
	await physics_frame
	await physics_frame
	game._stats = true
	game.phase = GkGame.Phase.HUNT
	game.hunter = game.actors[0]
	for a: GkActor in game.actors:
		a.set_role(GkActor.Role.HUNTER if a == game.hunter else GkActor.Role.HIDER)
		a.frozen = false
		a.gauge = 0.0
		a.position = Vector2(-5000, -5000)
	game._st.merge(GkGame.tension_keys(), true)
	game._tens.clear()
	game.hunter.position = tile_pos(game, 36, 17)
	game.hunter.look = 0.0
	return game


func tile_pos(game: GkGame, x: float, y: float) -> Vector2:
	return Vector2(x + 0.5, y + 0.5) * game.map.tile


## `secs` s de jeu : capture puis mesures (comme dans _physics_process).
func tick(game: GkGame, secs: float) -> void:
	var n: int = int(round(secs / DT))
	for i: int in n:
		game.hunt_elapsed += DT
		game._update_capture(DT)
		game.track_tension(DT)


func free_game(game: GkGame) -> void:
	game.queue_free()
	await process_frame


func test_frolements() -> void:
	var game: GkGame = await make_game()
	var h: GkActor = game.actors[1]
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
	GkRules._data["idee_detection"] = 1.0
	var game: GkGame = await make_game()
	var h: GkActor = game.actors[1]
	h.position = tile_pos(game, 41, 17)                 # devant, à 5 cases
	check(game.sees(game.hunter, h.position, h.radius), "précondition : vu devant")
	tick(game, 0.4)
	check(h.role == GkActor.Role.HIDER and h.gauge > GkRules.f("detection_doute"), "jauge entamée, pas encore trouvé (%.2f)" % h.gauge)
	check(game.hunter_alert > GkRules.f("detection_doute"), "le « ? » s'affiche au-dessus du chasseur")
	h.position = game.hunter.position + Vector2(-5.0 * game.map.tile, 0)     # sorti du cône
	tick(game, GkGame.TENSION_VU_GRACE + 0.1)
	check(int(game._st["vus"]) == 1 and int(game._st["vu_perdu"]) == 1, "vu puis perdu compté (%d/%d)" % [game._st["vu_perdu"], game._st["vus"]])
	check(h.gauge > 0.0, "la jauge redescend doucement (%.2f)" % h.gauge)
	tick(game, 2.0)
	check(h.gauge == 0.0 and h.ouf_t > 0.0, "jauge vide, « ouf ! » du chassé qui s'en tire")
	check(int(game._st["doutes"]) == 1 and int(game._st["doutes_perdus"]) == 1, "doute compté puis perdu")
	check(int(game._st["evasions_de_vue"]) == 1, "évasion comptée")
	await free_game(game)


func test_capture_pas_frolement() -> void:
	GkRules._data["idee_detection"] = 1.0
	var game: GkGame = await make_game()
	var h: GkActor = game.actors[1]
	h.position = game.hunter.position + Vector2(1.0 * game.map.tile, 0)      # tout près, devant
	tick(game, GkRules.f("detection_temps_pres") + 0.1)
	check(h.role == GkActor.Role.GHOST, "trouvé de près en detection_temps_pres")
	check(game.alert_bang > 0.0, "« ! » au-dessus du chasseur")
	h.position = game.hunter.position + Vector2(-6.0 * game.map.tile, 0)
	tick(game, 0.2)
	check(int(game._st["frolements_2"]) == 0 and int(game._st["vu_perdu"]) == 0, "une capture n'est ni un frôlement ni un vu-perdu")
	await free_game(game)


# ------------------------------------------------------------------ poursuite (désactivée par défaut)

func test_poursuite() -> void:
	GkRules._data["idee_detection"] = 1.0
	check(not GkRules.on("idee_poursuite"), "poursuite désactivée par défaut (c'est Julien qui décide)")
	GkRules._data["idee_poursuite"] = 1.0
	GkRules._data["poursuite_mult_chasseur"] = 1.15
	GkRules._data["poursuite_mult_chasse"] = 1.25
	var game: GkGame = await make_game()
	var h: GkActor = game.actors[1]
	var base_h: float = h.speed()
	var base_c: float = game.hunter.speed()
	h.position = tile_pos(game, 41, 17)
	tick(game, 0.1)
	check(h.chase_left == 0.0, "pas de poursuite avant le « ? »")
	tick(game, 0.25)
	check(h.gauge >= GkRules.f("poursuite_seuil") and h.role == GkActor.Role.HIDER, "précondition : « ? » atteint, pas trouvé")
	check(h.chase_left > 0.0 and game.hunter.chase_left > 0.0, "« ? » : poursuite des deux")
	check(near(h.speed(), base_h * 1.25, 0.01) and near(game.hunter.speed(), base_c * 1.15, 0.01), "vitesses de poursuite (chassé ×1,25, chasseur ×1,15)")
	check(int(game._st["poursuites"]) == 1, "une poursuite comptée")
	h.position = game.hunter.position + Vector2(-6.0 * game.map.tile, 0)        # il s'échappe
	for i: int in int((GkRules.f("poursuite_duree_s") + 0.2) / DT):
		h.step(Vector2.ZERO, Vector2.ZERO, DT)
		game.hunter.step(Vector2.ZERO, Vector2.ZERO, DT)
		game.hunt_elapsed += DT
		game._update_capture(DT)
	check(h.chase_left == 0.0 and near(h.speed(), base_h, 0.01), "après poursuite_duree_s : vitesse normale")
	check(int(game._st["poursuites"]) == 1, "pas de nouvelle poursuite sans nouveau repérage")
	await free_game(game)


## Précision de Julien : pendant la poursuite, tous les chassés que voit le chasseur en profitent.
func test_poursuite_tous_vus() -> void:
	GkRules._data["idee_detection"] = 1.0
	GkRules._data["idee_poursuite"] = 1.0
	for tous: float in [1.0, 0.0]:
		GkRules._data["poursuite_tous_vus"] = tous
		var game: GkGame = await make_game()
		var h1: GkActor = game.actors[1]
		var h2: GkActor = game.actors[2]
		h1.position = tile_pos(game, 41, 17)
		h2.position = game.hunter.position + Vector2(-6.0 * game.map.tile, 0)    # dans son dos
		tick(game, 0.35)
		check(h1.chase_left > 0.0 and h2.chase_left == 0.0, "seul le chassé vu part en poursuite")
		h2.position = tile_pos(game, 41, 16)                                      # entre dans le champ
		tick(game, DT)
		if tous > 0.5:
			check(h2.chase_left > 0.0, "tous_vus : le chassé qui entre dans le champ en profite aussi")
		else:
			check(h2.chase_left == 0.0, "chassé repéré seul : l'autre n'en profite pas")
		await free_game(game)


# ------------------------------------------------------------------ partie IA contre IA

func test_partie_ia_courte() -> void:
	for k: String in ["idee_detection", "idee_mouvement", "idee_frisson"]:
		GkRules._data[k] = 1.0
	GkRules._data["phase_draw"] = 0.5
	GkRules._data["phase_hide"] = 3.0
	GkRules._data["phase_hunt"] = 25.0
	GkRules._data["phase_end"] = 0.5
	GkRules._data["exits_open_at"] = 10.0
	GkGame.config["players"] = 6
	var game: GkGame = (load(GAME) as PackedScene).instantiate()
	game._bots_only = true
	game._stats = true
	root.add_child(game)
	var frames: int = 0
	while game.round_no < 3 and frames < 60 * 90:
		await physics_frame
		frames += 1
	check(game.round_no >= 3, "deux rounds complets joués (%d images)" % frames)
	check(game.hunter != null and game.actors.size() == 6, "six joueurs, un chasseur")
	var keys: Dictionary = GkGame.tension_keys()
	for k: String in keys:
		check(game.last_stats.has(k), "mesure présente : " + k)
	check(float(game.last_stats.get("chasse_s", 0.0)) > 0.0, "temps de chasse mesuré")
	await free_game(game)
