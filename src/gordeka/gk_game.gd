class_name GkGame
extends Node2D
## Partie de Gordeka contre l'IA (prototype gris, SPEC-GORDEKA §2-4, jalon 1).
## La partie tourne entièrement ici (rôle d'hôte) : rounds, vision du chasseur, capture,
## cachettes, pièges, détections, sorties et points. Les joueurs n'envoient que move/look/action.

## VERSUS (écran de suspense entre le tirage et la cachette) est ajouté en dernier : les valeurs des
## autres phases ne bougent pas.
enum Phase { DRAW, HIDE, HUNT, END, PODIUM, VERSUS }

const COUNT_WORDS: PackedStringArray = ["bat", "bi", "hiru", "lau", "bost", "sei", "zazpi", "zortzi",
	"bederatzi", "hamar", "hamaika", "hamabi", "hamahiru", "hamalau", "hamabost"]
## Emotes (SPEC-GORDEKA §3.2) : animation du perso, dans l'ordre des touches 1 à 6 et des bulles
## (icônes dessinées par GkDraw.emote_icon). Permises seulement hors de l'action (`emotes_allowed`).
const EMOTES: PackedStringArray = ["emote_salut", "emote_rire", "emote_danse", "emote_pouce",
	"emote_chut", "emote_langue"]
## Tremblement d'une cachette (entrée, sortie, fouille) et frémissement quand quelqu'un est dedans.
const SHAKE_FREQ: float = 60.0
const SHAKE_PX: float = 4.0
const SHIVER_FREQ: float = 45.0
const SHIVER_PX: float = 1.5
## Caisse procédurale (sans image) : couvercle ouvert, en part de la hauteur de la caisse.
const LID_K: float = 0.35
const LID_OPEN_K: float = 0.5
## Mesures de tension (statistiques seulement, pas des règles) : hystérésis d'un frôlement (cases),
## temps hors de vue qui clôt un « vu » (s), part de la vitesse au-dessus de laquelle on bouge, rayon
## et durée d'une planque, écart entre deux planques (cases), portée d'une sortie de cachette « en
## fuite » (cases), fenêtre d'une capture après évasion et des captures de fin de round (s).
const TENSION_HYST: float = 0.5
const TENSION_VU_GRACE: float = 0.4
const TENSION_BOUGE: float = 0.3
const TENSION_PLANQUE_R: float = 1.0
const TENSION_PLANQUE_S: float = 3.0
const TENSION_PLANQUE_ECART: float = 4.0
const TENSION_FUITE: float = 6.0
const TENSION_JUSTESSE_S: float = 15.0
const TENSION_FIN_S: float = 30.0
## Détection progressive : durée du « ! » d'une capture, du « ? » qui retombe et du « ouf ! » (s).
const ALERT_BANG_S: float = 0.9
const ALERT_LOST_S: float = 1.2
const OUF_S: float = 1.4
## QA `--gk-qa-cachette` : temps passé dedans, puis dehors, avant la prochaine entrée (s).
const QA_OUT_S: float = 2.0
const QA_GAP_S: float = 2.0

## Réglages de la partie, posés par la partie rapide et le profil (menus/gk_partie_rapide.gd,
## GkProfil.vers_partie) : rounds = nombre de rounds de la partie (0 : rounds_defaut de rules.json,
## sinon un par joueur), emote = emote favorite du joueur (jouée sur le podium).
static var config: Dictionary = {"players": 6, "level": "normal", "map": "port_pecheurs",
	"name": "Toi", "color": 0, "rounds": 0, "emote": 0}

var map: GkMap
var actors: Array[GkActor] = []
var brains: Dictionary = {}          # id → GkAi
var local: GkActor
var input: GkInput
var hud: GkHud
var phase: Phase = Phase.DRAW
var phase_t: float = 0.0
var hunt_elapsed: float = 0.0
var round_no: int = 0
var hunter: GkActor
## Cachettes : {tile, pos, occupant, lock, shake} et leur animation (`_open_cachette`) : open (0 → 1),
## delay (attente avant d'ouvrir), hold (reste ouverte), close_shake (tremblement à la fermeture),
## jiggle (tremblement dessiné ; `shake`, lui, est l'indice que lit l'IA du chasseur : entrée, sortie,
## fin de fouille),
## squash_t (écrasement en cours), shiver / shiver_wait (frémissement quand quelqu'un est dedans).
var cachettes: Array = []
var traps: Array = []                # [{pos, owner}]
## Sorties tirées au sort pour ce round (parmi les sorties possibles de la carte).
var open_exits: Array[Vector2i] = []
var open_exit_zones: Array[String] = []
var reveals: Array = []              # [{pos, left, id}] (détection du chasseur)
var messages: Array = []             # [{text, left, color}]
var _sac: Array[int] = []
var _last_hunter: int = -1
var _seen: Dictionary = {}           # id → vu par le chasseur cette image
var _search_target: Dictionary = {}  # id du chasseur → index de cachette fouillée
var _round_hiders: int = 0
var _round_found: int = 0
var _overlay: Node2D
var _camera: Camera2D
var _dark: CanvasModulate
var _cone_light: PointLight2D
var _near_light: PointLight2D
## Mêmes lumières pour les objets debout du décor : ombrées par les murs de la grille seulement, pas
## par la base des objets (sinon le haut d'un objet, au-delà de sa propre base, tombe dans le noir).
var _cone_light_decor: PointLight2D
var _near_light_decor: PointLight2D
var _bots_only: bool = false
var _force_role: String = ""
var _log: bool = false
var _local_bot: bool = false          # QA : le joueur local est piloté par l'IA (garde son perso)
## Affichage 3D abandonné le 2026-10-19 (docs/GORDEKA_STYLE_2D.md) : 2D par défaut, `--gk-3d`
## rouvre l'ancienne vue 3D.
var use_3d: bool = false
## QA : `--gk-perso=louis` donne ce perso à tout le monde (voir ses animations sur toutes les IA).
var _all_char: String = ""
## QA gameplay : niveau imposé au chasseur IA (`--gk-hunter-level=`), arrêt après N rounds
## (`--gk-rounds=`), statistiques par round en JSON (`--gk-stats`).
var _hunter_level: String = ""
var _rounds_max: int = 0
var _stats: bool = false
var _st: Dictionary = {}
var _revealed_at: Dictionary = {}     # id du chassé → instant de la dernière onde qui l'a montré
var _trap_hit_at: float = -100.0
## Idées de gameplay (drapeaux `idee_*` de rules.json) : gâteaux basques au sol [{pos}],
## mouettes posées [{pos, away (s avant leur retour), fly (s d'envol à dessiner)}], instant de la
## dernière capture (chasseur bredouille), derniers bruits entendus (statistiques).
var gateaux: Array = []
var mouettes: Array = []
var _cake_respawn: Array[float] = []    # instants de réapparition des gâteaux mangés (idee_mouvement)
var _last_find_t: float = 0.0
var _noise_at: float = -100.0
var _tickle_free_until: float = 0.0     # chasseur à l'abri des chatouilles jusqu'à cet instant (répit)
var _rescues: int = 0                   # délivrances déjà faites ce round
## Mesures de tension (`--gk-stats`, docs/GORDEKA_EQUILIBRAGE.md) : état par chassé (id → {…}) pour
## les frôlements, les « vu puis perdu », le mouvement et les changements de planque.
var _tens: Dictionary = {}
var _heat_t: float = 0.0
## Statistiques du dernier round terminé (tests).
var last_stats: Dictionary = {}
## Détection progressive (`idee_detection`) : jauge affichée au-dessus du chasseur (la plus haute des
## jauges des chassés), « ! » d'une capture (s restantes) et « ? » qui retombe après un frôlement (s).
var hunter_alert: float = 0.0
var alert_bang: float = 0.0
var alert_lost: float = 0.0
var view: GkView3D
## Ressenti du chassé local (idee_frisson) : battement, vignettage, vibration.
var frisson: GkFrisson
var _last_dt: float = 0.0
## QA : `--gk-qa-emotes` fait enchaîner les emotes à tout le monde et ouvre l'éventail ;
## `--gk-qa-podium` passe directement au podium.
var _qa_emotes: bool = false
var _qa_podium: bool = false
## QA : `--gk-qa-cachette=<zone>[@t]` : des chassés entrent dans les cachettes de la zone de sorte
## que la capture (`--delay`) tombe `t` s après l'entrée (0,35 par défaut), ressortent QA_OUT_S s plus
## tard, et ainsi de suite. À lancer avec `--gk-rules=phase_draw:60` (tout le monde reste figé).
var _qa_cachette: String = ""
var _qa_cachette_t: float = 0.35
var _qa_next: float = -1.0
var _qa_inside: bool = false
var _qa_clock: float = 0.0
## QA : `--gk-qa-place=<acteur>:<x>,<y>[:<regard en degrés>]` (répétable ; acteur 0 = le joueur local,
## x et y en cases, décimales permises) pose un acteur au premier round (à lancer avec
## `--gk-rules=phase_draw:60` : tout le monde reste figé).
var _qa_place: Array = []
## TEMPORAIRE, debug (Julien, 2026-10-20) : « visite en tant que chassé / chasseur ». Carte complète,
## ni chrono ni fin de manche, personne d'autre (`--gk-visite-figurants` : les autres sont là,
## immobiles), pour vérifier collisions, masquage, cachettes, décor et animations. Lancement : menu
## (config["visite"]), `--gk-visite=chasse|chasseur`, web `#scene=gk_game&visite=…`. Touches : F les
## formes du décor, C le perso suivant ; Échap ou Quitter : retour au menu. À retirer après la mise au point.
var visite: String = ""
var _figurants: bool = false
## QA de la visite : `--gk-visite-fantome` (ou la touche G) met le joueur en fantôme ; `--gk-qa-tourne`
## le fait tourner en rond tout seul ; `--gk-qa-rafale=<dossier>,<n>,<intervalle s>,<début s>` enregistre
## n captures d'écran de suite puis quitte (planches d'animation).
var _visite_fantome: bool = false
var _qa_tourne: bool = false
var _qa_zoom: float = 0.0             # QA `--gk-qa-zoom=<z>` : zoom de la caméra du joueur
var _rafale: Array = []
var _rafale_t: float = 0.0
var _rafale_i: int = 0
## Lampe du chasseur allumée pour cette manche (hunter_reveal joué en fin de phase cachée).
var _reveal_joue: bool = false
## Nombre de rounds de la partie, podium ensuite (SPEC-GORDEKA §2.2) ; 0 = sans fin (IA contre IA
## sans `--gk-rounds`). Écran Versus entre le tirage et la cachette, sauté en IA contre IA, en
## visite et avec `--gk-sans-versus` ; versus et podium sont des écrans posés sur le calque 9, sous
## le HUD (bouton Quitter, éventail des emotes).
var rounds_total: int = 0
var _sans_versus: bool = false
var _ecrans: CanvasLayer
var versus: GkVersus
var podium: GkPodium


func _exit_tree() -> void:
	GkRules.retire_carte()


func _ready() -> void:
	visite = str(config.get("visite", ""))
	for arg: String in GkRules.args():
		if arg.begins_with("--gk-visite="):
			visite = arg.trim_prefix("--gk-visite=")
		elif arg == "--gk-visite-figurants" or arg == "--gk-visite_figurants=1":
			_figurants = true
		elif arg == "--gk-visite-fantome":
			_visite_fantome = true
		elif arg == "--gk-qa-tourne":
			_qa_tourne = true
		elif arg.begins_with("--gk-qa-zoom="):
			_qa_zoom = float(arg.trim_prefix("--gk-qa-zoom="))
		elif arg.begins_with("--gk-qa-rafale="):
			_rafale = Array(arg.trim_prefix("--gk-qa-rafale=").split(","))
		elif arg == "--gk-bots-only":
			_bots_only = true
		elif arg == "--gk-sans-versus":
			_sans_versus = true
		elif arg == "--gk-local-bot":
			_local_bot = true
		elif arg == "--gk-3d":
			use_3d = true
		elif arg.begins_with("--gk-level="):
			config["level"] = arg.trim_prefix("--gk-level=")
		elif arg.begins_with("--gk-map="):
			# Variante de carte (assets/maps/<id>/, tools/gordeka/make_port_v3.py) : essais A/B.
			config["map"] = arg.trim_prefix("--gk-map=")
		elif arg.begins_with("--gk-players="):
			config["players"] = int(arg.trim_prefix("--gk-players="))
		elif arg.begins_with("--gk-hunter-level="):
			_hunter_level = arg.trim_prefix("--gk-hunter-level=")
		elif arg.begins_with("--gk-rounds="):
			_rounds_max = int(arg.trim_prefix("--gk-rounds="))
		elif arg == "--gk-mannequin":
			GkPerso.use_pantin = true
		elif arg == "--gk-stats":
			_stats = true
		elif arg.begins_with("--gk-perso="):
			_all_char = arg.trim_prefix("--gk-perso=")
		elif arg == "--gk-log":
			_log = true
		elif arg == "--gk-qa-emotes":
			_qa_emotes = true
		elif arg == "--gk-qa-podium":
			_qa_podium = true
		elif arg.begins_with("--gk-qa-cachette="):
			var spec: PackedStringArray = arg.trim_prefix("--gk-qa-cachette=").split("@")
			_qa_cachette = spec[0]
			if spec.size() > 1:
				_qa_cachette_t = float(spec[1])
		elif arg.begins_with("--delay="):
			_qa_next = float(arg.trim_prefix("--delay="))
		elif arg.begins_with("--gk-local-role="):
			_force_role = arg.trim_prefix("--gk-local-role=")
		elif arg.begins_with("--gk-qa-place="):
			_qa_place.append(arg.trim_prefix("--gk-qa-place=").split(":"))
	map = GkMap.new()
	map.draw_2d = not use_3d
	add_child(map)
	map.load_map(str(config.get("map", "port_pecheurs")))
	# Réglages propres à la carte (zones.json → « regles »), retirés à la sortie de la partie.
	GkRules.surcharge_carte(map.regles)
	if not use_3d:
		var water: GkWater = GkWater.new()
		water.map = map
		map.add_child(water)
		map.move_child(water, 0)
	for t: Vector2i in map.cachettes:
		cachettes.append({"tile": t, "pos": map.center(t)})
	_reset_cachettes()
	# QA : première entrée calée pour que la capture tombe `_qa_cachette_t` s après.
	_qa_next = maxf(0.5, (_qa_next if _qa_next > 0.0 else 3.0) - _qa_cachette_t)
	var people: Node2D = Node2D.new()
	people.y_sort_enabled = true
	add_child(people)
	_make_actors(people)
	_make_view()
	if use_3d:
		view = GkView3D.new()
		add_child(view)
		view.setup(self)
	frisson = GkFrisson.new()
	frisson.game = self
	add_child(frisson)
	input = GkInput.new()
	add_child(input)
	input.quit_requested.connect(quit_to_podium)
	hud = GkHud.new()
	hud.game = self
	var hud_layer: CanvasLayer = CanvasLayer.new()
	hud_layer.layer = 10
	add_child(hud_layer)
	hud_layer.add_child(hud)
	# Thème cartoon des menus : un Control sous un CanvasLayer n'hérite pas de celui de la fenêtre.
	hud.theme = GkUi.theme()
	_ecrans = CanvasLayer.new()
	_ecrans.layer = 9
	add_child(_ecrans)
	rounds_total = rounds_pour(config, _bots_only, _rounds_max)
	_start_round()
	if _qa_podium:
		quit_to_podium()


func _make_actors(parent: Node2D) -> void:
	var n: int = clampi(int(config.get("players", 6)), 2, 8)
	if visite != "":
		_force_role = "hunter" if visite == "chasseur" else "hider"
		if not _figurants:
			n = 2                  # le joueur, et l'autre rôle caché hors de la carte
	var all_names: Array = GkRules.data().get("bot_names", [])
	var all_chars: Array = GkRules.data().get("characters", [])
	var my_name: String = str(config.get("name", "Toi"))
	var my_char: String = str(config.get("character", "louis"))
	# Les IA prennent les autres persos du roster, dans le désordre.
	var picks: Array[int] = []
	for i: int in all_chars.size():
		if str(all_chars[i]) != my_char or _bots_only:
			picks.append(i)
	picks.shuffle()
	var drawn: Array[String] = []
	for c: Variant in all_chars:
		if GkPerso.available(str(c)):
			drawn.append(str(c))
	var my_color: int = int(config.get("color", 0))
	var colors: Array[int] = []
	for i: int in 12:
		if i != my_color:
			colors.append(i)
	colors.shuffle()
	for i: int in n:
		var a: GkActor = GkActor.new()
		var bot: bool = i > 0 or _bots_only or _local_bot
		var me: bool = i == 0 and not _bots_only
		var k: int = picks[(i - (0 if _bots_only else 1)) % picks.size()] if not me else -1
		var nm: String = my_name if me else str(all_names[k]) + " (IA)"
		a.character = my_char if me else str(all_chars[k])
		# Tant que tous les persos ne sont pas dessinés, les IA prennent un perso qui l'est.
		if not GkPerso.available(a.character) and not drawn.is_empty():
			a.character = drawn[i % drawn.size()]
		if _all_char != "":
			a.character = _all_char
		a.setup(i, nm, GkRules.color(my_color if i == 0 else colors[i - 1]), bot)
		parent.add_child(a)
		actors.append(a)
		if bot and visite == "":
			brains[i] = GkAi.new(self, a, str(config.get("level", "normal")))
	local = actors[0]


func _make_view() -> void:
	_camera = Camera2D.new()
	_camera.position_smoothing_enabled = true
	_camera.position_smoothing_speed = 8.0
	# Zoom proche d'Among Us : un personnage fait environ 1/11 de la hauteur d'écran.
	_camera.zoom = Vector2(1.25, 1.25)
	if _qa_zoom > 0.0:
		_camera.zoom = Vector2(_qa_zoom, _qa_zoom)
	_camera.limit_left = 0
	_camera.limit_top = 0
	_camera.limit_right = int(map.size_px().x)
	_camera.limit_bottom = int(map.size_px().y)
	add_child(_camera)
	# Vue du chasseur : tout est sombre sauf son cône et un petit cercle, que les objets
	# bloquent (ombres des LightOccluder2D de la carte).
	_dark = CanvasModulate.new()
	_dark.color = Color.WHITE
	add_child(_dark)
	_cone_light = _make_light(_cone_texture(GkRules.f("cone_deg")), GkRules.px("cone_range"))
	_near_light = _make_light(_cone_texture(360.0), GkRules.px("near_radius") + 10.0)
	_cone_light_decor = _make_light(_cone_light.texture, GkRules.px("cone_range"), true)
	_near_light_decor = _make_light(_near_light.texture, GkRules.px("near_radius") + 10.0, true)
	# Calque « dans le monde » non assombri : cône rouge vu des chassés, sorties, cachettes, pièges.
	var layer: CanvasLayer = CanvasLayer.new()
	layer.follow_viewport_enabled = true
	layer.layer = 1
	add_child(layer)
	_overlay = Node2D.new()
	layer.add_child(_overlay)
	_overlay.draw.connect(func() -> void: _draw_overlay(_overlay))


## Lumière du chasseur. Sol et persos (calque 1) : ombrés par les murs et la base des objets ;
## objets debout (`decor`, calque GkDecor.LIGHT_MASK) : ombrés par les murs seulement.
func _make_light(tex: Texture2D, radius: float, decor: bool = false) -> PointLight2D:
	var l: PointLight2D = PointLight2D.new()
	l.texture = tex
	l.texture_scale = radius * 2.0 / float(tex.get_width())
	l.range_item_cull_mask = GkDecor.LIGHT_MASK if decor else 1
	l.shadow_item_cull_mask = 1 if decor else 1 | GkDecor.LIGHT_MASK
	l.shadow_enabled = true
	l.shadow_filter = Light2D.SHADOW_FILTER_PCF5
	l.energy = 0.8
	l.enabled = false
	add_child(l)
	return l


## Texture de lumière (256 px, agrandie par texture_scale) : secteur de `deg` degrés vers +X,
## bords adoucis.
static func _cone_texture(deg: float) -> Texture2D:
	var size: int = 256
	var r: float = 127.0
	var img: Image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	var half: float = deg_to_rad(deg) * 0.5
	var c: Vector2 = Vector2(size, size) * 0.5
	for y: int in size:
		for x: int in size:
			var v: Vector2 = Vector2(x + 0.5, y + 0.5) - c
			var d: float = v.length()
			if d > r:
				continue
			var k: float = clampf((r - d) / (r * 0.12), 0.0, 1.0)
			if deg < 359.0:
				var a: float = absf(v.angle())
				if a > half:
					continue
				k *= clampf((half - a) / deg_to_rad(4.0), 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, k))
	return ImageTexture.create_from_image(img)


# ---------------------------------------------------------------- rounds

## Rounds de la partie : `--gk-rounds`, sinon le choix du menu, sinon rounds_defaut, sinon un par
## joueur ; bornés à rounds_min..rounds_max. Sans fin en IA contre IA sans `--gk-rounds`.
static func rounds_pour(cfg: Dictionary, bots_only: bool = false, forced: int = 0) -> int:
	if forced > 0:
		return forced
	if bots_only:
		return 0
	var r: int = int(cfg.get("rounds", 0))
	if r <= 0:
		r = int(GkRules.f("rounds_defaut"))
	if r <= 0:
		r = int(cfg.get("players", 6))
	return clampi(r, int(GkRules.f("rounds_min")), int(GkRules.f("rounds_max")))


## Le versus se joue-t-il ? Pas en IA contre IA (personne ne regarde), ni en visite.
func versus_actif() -> bool:
	return GkRules.f("phase_versus") > 0.0 and not _bots_only and not _sans_versus and visite == ""


## Partie rapide : le joueur peut terminer plus tôt pendant les scores (SPEC-GORDEKA §2.2).
func peut_terminer() -> bool:
	return phase == Phase.END and visite == "" and not _bots_only


func _start_round() -> void:
	round_no += 1
	phase = Phase.DRAW
	phase_t = GkRules.f("phase_draw")
	hunt_elapsed = 0.0
	traps.clear()
	reveals.clear()
	_search_target.clear()
	_reset_cachettes()
	hunter = _draw_hunter()
	_pick_exits()
	_round_hiders = actors.size() - 1
	_round_found = 0
	_st = {"vue": 0, "fouille_ok": 0, "fouille_vide": 0, "ondes": 0, "ondes_utiles": 0, "montres": 0,
		"trouves_apres_onde": 0, "pieges_poses": 0, "pieges_pris": 0, "trouves_apres_piege": 0,
		"entrees_cachette": 0, "ejections_cachette": 0, "trouves_en_cachette": 0, "sorties": 0,
		"evasions_de_vue": 0, "t_trouves": [], "lieux_trouves": [], "sorties_round": open_exit_zones.duplicate(),
		"chatouilles": 0, "delivres": 0, "grincements": 0, "gateaux": 0, "mouettes": 0,
		"trouves_apres_bruit": 0, "elan_s": 0.0, "fantome_s": 0.0,
		# Carte (tools/gordeka/ab_tension.py chaleur) : présence par case (« x,y » → s, échantillon par
		# seconde), entrées par cachette, lieux des vu-perdu et des frôlements, sorties prises.
		"chaleur": {}, "chaleur_chasseur": {}, "cachettes_entrees": {}, "lieux_vu_perdu": [],
		"lieux_frolements": [], "sorties_lieux": []}
	_heat_t = 0.0
	_st.merge(tension_keys())
	_tens.clear()
	_revealed_at.clear()
	_trap_hit_at = -100.0
	_last_find_t = 0.0
	_noise_at = -100.0
	_tickle_free_until = 0.0
	_rescues = 0
	_place_bonus()
	hunter_alert = 0.0
	alert_bang = 0.0
	alert_lost = 0.0
	for a2: GkActor in actors:
		a2.doubted = false
		a2.ouf_t = 0.0
		a2.speed_mult = 1.0
		a2.tickle_left = 0.0
		a2.sprint_left = 0.0
		a2.chase_left = 0.0
		a2.chase_used = false
		a2.elan_mult = 1.0
		a2.rescue_k = 0.0
		a2.rescued = false
	if hunter.is_bot:
		var hl: String = _hunter_level if _hunter_level != "" else str(config.get("level", "normal"))
		hunter.speed_mult = float(GkRules.ai(hl).get("hunter_speed", 1.0))
	if _hunter_level != "":
		for id: int in brains:
			var b: GkAi = brains[id]
			b.set_level(_hunter_level if actors[id] == hunter else str(config.get("level", "normal")))
	var spots: Array[Vector2i] = _spawn_spots(actors.size())
	var k: int = 1
	for a: GkActor in actors:
		a.set_role(GkActor.Role.HUNTER if a == hunter else GkActor.Role.HIDER)
		a.gauge = 0.0
		a.extract_t = 0.0
		a.alive_t = 0.0
		a.round_points = 0
		a.won_round = false
		a.end_pose = ""
		a.scared = false
		a.hidden_in = -1
		a.vanish_left = 0.0
		a.pop_left = 0.0
		a.search_left = 0.0
		a.slow_left = 0.0
		a.power_cd = 0.0
		a.frozen = true
		a.look = PI * 0.5
		a.position = map.center(spots[0] if a == hunter else spots[mini(k, spots.size() - 1)])
		if a != hunter:
			k += 1
	for b: GkAi in brains.values():
		b.reset()
	if round_no == 1:
		for spec: PackedStringArray in _qa_place:
			var i: int = int(spec[0])
			var xy: PackedStringArray = spec[1].split(",") if spec.size() > 1 else PackedStringArray()
			if i < 0 or i >= actors.size() or xy.size() != 2:
				continue
			actors[i].position = Vector2(float(xy[0]), float(xy[1])) * map.tile
			if spec.size() > 2:
				actors[i].look = deg_to_rad(float(spec[2]))
	if visite != "":
		_start_visite()
		return
	_say("Tu es le CHASSEUR !" if local == hunter else "%s est le chasseur. Cache-toi !" % hunter.display_name,
		Color("ff3b30") if local == hunter else Color("ffffff"), 3.0)


## Visite (debug, temporaire) : chasse tout de suite, sans fin ; les autres restent immobiles, ou
## sont rangés hors de la carte, invisibles, sans figurants.
func _start_visite() -> void:
	phase = Phase.HUNT
	phase_t = 1.0e9
	for a: GkActor in actors:
		a.frozen = a != local
		if a != local and not _figurants:
			a.position = Vector2(-100000, -100000)
			a.visible = false
			a.collision_layer = 0
	messages.clear()
	if _visite_fantome:
		visite_toggle_ghost()
	if local == hunter:
		hunter.play_once("hunter_reveal")      # la lampe s'allume, comme au début d'une chasse
	_say("Visite %s (debug) : F formes, C perso, G fantôme" % ("du chasseur" if local == hunter else "du chassé"),
		Color("ffd34a"), 4.0)


## Visite : le chassé passe en fantôme (et revient), pour voir le vol et les ailes.
func visite_toggle_ghost() -> void:
	if local == hunter:
		return
	local.set_role(GkActor.Role.HIDER if local.role == GkActor.Role.GHOST else GkActor.Role.GHOST)


## QA `--gk-qa-rafale` : captures successives de l'écran, puis on quitte.
func _qa_rafale(dt: float) -> void:
	_rafale_t += dt
	var n: int = int(_rafale[1]) if _rafale.size() > 1 else 8
	var step: float = float(_rafale[2]) if _rafale.size() > 2 else 0.12
	var start: float = float(_rafale[3]) if _rafale.size() > 3 else 2.0
	if _rafale_t < start + step * _rafale_i:
		return
	if _rafale_i >= n:
		get_tree().quit()
		return
	DirAccess.make_dir_recursive_absolute(str(_rafale[0]))
	get_viewport().get_texture().get_image().save_png(str(_rafale[0]).path_join("rafale_%02d.png" % _rafale_i))
	_rafale_i += 1


## Visite : perso suivant du roster (seulement ceux qui sont dessinés).
func visite_next_character() -> void:
	var chars: Array = GkRules.data().get("characters", [])
	var i: int = chars.find(local.character)
	for k: int in range(1, chars.size() + 1):
		var c: String = str(chars[(i + k) % chars.size()])
		if GkPerso.available(c):
			local.set_character(c)
			if local == hunter:
				local.play_once("hunter_reveal")
			_say(c.capitalize(), Color.WHITE, 1.5)
			return


func visite_toggle_formes() -> void:
	if map.formes:
		map.formes.visible = not map.formes.visible


func _unhandled_input(event: InputEvent) -> void:
	if visite == "" or not event is InputEventKey or not (event as InputEventKey).pressed or (event as InputEventKey).echo:
		return
	match (event as InputEventKey).physical_keycode:
		KEY_F:
			visite_toggle_formes()
		KEY_C:
			visite_next_character()
		KEY_G:
			visite_toggle_ghost()


## Tirage « en sac » : chacun est chasseur une fois avant qu'on recommence, jamais deux fois de suite.
func _draw_hunter() -> GkActor:
	if _sac.is_empty():
		for a: GkActor in actors:
			_sac.append(a.id)
		_sac.shuffle()
		if _sac.size() > 1 and _sac[0] == _last_hunter:
			_sac.append(_sac.pop_front())
		if round_no == 1 and _force_role != "":
			_sac.erase(local.id)
			if _force_role == "hunter":
				_sac.push_front(local.id)
			else:
				_sac.append(local.id)
	var id: int = _sac.pop_front()
	_last_hunter = id
	return actors[id]


func _spawn_spots(n: int) -> Array[Vector2i]:
	var c: Vector2i = map.spawns[0] if not map.spawns.is_empty() else Vector2i(map.width / 2, map.height / 2)
	var out: Array[Vector2i] = [c]
	var r: int = 1
	while out.size() < n and r < 6:
		for dy: int in range(-r, r + 1):
			for dx: int in range(-r, r + 1):
				var t: Vector2i = c + Vector2i(dx * 2, dy * 2)
				if maxi(absi(dx), absi(dy)) == r and map.walkable(t) and not out.has(t):
					out.append(t)
		r += 1
	return out


func _finish_round() -> void:
	phase = Phase.END
	phase_t = GkRules.f("phase_end")
	for a: GkActor in actors:
		a.frozen = true
		if a == hunter:
			continue
		if a.role == GkActor.Role.HIDER:
			if a.hidden_in >= 0:
				_leave_cachette(a, false)
			_give(a, GkRules.score("hider_survive"))
			a.won_round = true
		_give(a, int(a.alive_t / 10.0) * GkRules.score("hider_per_10s"))
		if a.role == GkActor.Role.OUT:
			a.won_round = true
	if _round_found >= _round_hiders and _round_hiders > 0:
		_give(hunter, GkRules.score("hunter_all"))
	hunter.won_round = _round_found * 2 > _round_hiders
	for a: GkActor in actors:
		if a.role == GkActor.Role.HIDER or a.role == GkActor.Role.HUNTER:
			a.end_pose = "victory" if a.won_round else "sad"
	if _stats:
		# Épisodes encore ouverts au chrono : le chasseur est passé tout près sans trouver.
		for id: int in _tens:
			for r: int in [2, 3]:
				if bool(_tens[id]["near%d" % r]):
					_st["frolements_%d" % r] += 1
		_st["round"] = round_no
		_st["niveau"] = str(config.get("level", "normal"))
		_st["niveau_chasseur"] = _hunter_level if _hunter_level != "" else _st["niveau"]
		_st["chasses"] = _round_hiders
		_st["trouves"] = _round_found
		_st["restes_caches"] = _hiders_left()
		_st["duree"] = snappedf(hunt_elapsed, 0.1)
		last_stats = _st.duplicate(true)
		print("[gk-stats] " + JSON.stringify(_st))
		if _rounds_max > 0 and round_no >= _rounds_max:
			get_tree().quit()
	if _log:
		var out: int = actors.filter(func(a: GkActor) -> bool: return a.role == GkActor.Role.OUT).size()
		print("[gk] round %d : chasseur %s, trouvés %d/%d, échappés %d, restés cachés %d, durée %.0f s" % [
			round_no, hunter.display_name, _round_found, _round_hiders, out,
			_round_hiders - _round_found - out, hunt_elapsed])
		if _stats:
			print("[gk]   tension : frôlements %d (< 2 cases) / %d (< 3), vu puis perdu %d sur %d, %.1f cases/min, changements de planque %d" % [
				_st["frolements_2"], _st["frolements_3"], _st["vu_perdu"], _st["vus"],
				float(_st["cases_parcourues"]) / maxf(float(_st["chasse_s"]) / 60.0, 0.01), _st["changements_planque"]])


func _give(a: GkActor, pts: int) -> void:
	a.score += pts
	a.round_points += pts


func quit_to_podium() -> void:
	if visite != "":
		go_menu()
		return
	if phase == Phase.PODIUM:
		return
	phase = Phase.PODIUM
	_fermer_versus()
	for a: GkActor in actors:
		a.frozen = true
		a.end_pose = ""
		a.stop_emote()
	if _bots_only and DisplayServer.get_name() == "headless":
		get_tree().quit()
		return
	podium = GkPodium.new()
	podium.game = self
	podium.theme = GkUi.theme()
	_ecrans.add_child(podium)
	# Le joueur local fait son emote favorite en montant sur le podium.
	if not local.is_bot:
		emote(local, int(config.get("emote", 0)))
	var am: Node = get_node_or_null("/root/AudioManager")
	if am != null:
		am.play_music(&"victory")


func go_menu() -> void:
	GkNav.aller("accueil")


func _ouvrir_versus() -> void:
	phase = Phase.VERSUS
	phase_t = GkRules.f("phase_versus")
	messages.clear()
	versus = GkVersus.new()
	versus.game = self
	versus.theme = GkUi.theme()
	versus.duree = phase_t
	_ecrans.add_child(versus)


func _fermer_versus() -> void:
	if versus != null:
		versus.queue_free()
		versus = null


## Fin du tirage ou du versus : les chassés filent se cacher, le chasseur compte.
func _debut_cachette() -> void:
	_fermer_versus()
	phase = Phase.HIDE
	phase_t = GkRules.f("phase_hide")
	for a: GkActor in actors:
		a.frozen = a == hunter
	_reveal_joue = false
	_say("Cachez-vous !" if local != hunter else "Compte jusqu'à quinze…", Color.WHITE, 2.0)


# ---------------------------------------------------------------- boucle

func _physics_process(dt: float) -> void:
	if not _rafale.is_empty():
		_qa_rafale(dt)
	_last_dt = dt
	_update_emotes(dt)
	if _qa_cachette != "":
		_qa_cachettes(dt)
	if phase == Phase.PODIUM:
		_update_view()
		return
	phase_t -= dt
	match phase:
		Phase.DRAW:
			if phase_t <= 0.0:
				if versus_actif():
					_ouvrir_versus()
				else:
					_debut_cachette()
		Phase.VERSUS:
			if phase_t <= 0.0:
				_debut_cachette()
		Phase.HIDE:
			# Le chasseur allume sa lampe juste avant d'être lâché, encore figé (anim_reveal_avance) :
			# le geste se joue en entier, sans glisser sous ses pieds quand il part.
			if not _reveal_joue and GkRules.f("anim_reveal_avance") > 0.5 \
					and phase_t <= hunter.once_length("hunter_reveal"):
				_reveal_joue = true
				hunter.play_once("hunter_reveal")
			if phase_t <= 0.0:
				phase = Phase.HUNT
				phase_t = GkRules.f("phase_hunt")
				hunter.frozen = false
				if not _reveal_joue:
					hunter.play_once("hunter_reveal")
				_reveal_joue = true
				_say("Le chasseur arrive !", Color("ff3b30"), 2.0)
		Phase.HUNT:
			hunt_elapsed += dt
			if absf(hunt_elapsed - GkRules.f("exits_open_at")) < dt * 0.5 + 0.0001:
				_say("Les sorties sont ouvertes !", Color("6fe08a"), 3.0)
			if visite == "" and (phase_t <= 0.0 or _hiders_left() == 0):
				_finish_round()
		Phase.END:
			if phase_t <= 0.0:
				if rounds_total > 0 and round_no >= rounds_total:
					quit_to_podium()
				else:
					_start_round()
				return
	_control(dt)
	if phase == Phase.HUNT:
		_update_searches(dt)
		_update_traps()
		if visite != "chasse":
			_update_capture(dt)
		if _stats:
			track_tension(dt)
		if visite == "":
			_update_exits(dt)
		_update_ideas(dt)
		for a: GkActor in actors:
			if a.role == GkActor.Role.HIDER:
				a.alive_t += dt
			elif a.role == GkActor.Role.GHOST and _stats:
				_st["fantome_s"] = float(_st["fantome_s"]) + dt
	_update_cachettes(dt)
	alert_bang = maxf(0.0, alert_bang - dt)
	alert_lost = maxf(0.0, alert_lost - dt)
	for a3: GkActor in actors:
		a3.ouf_t = maxf(0.0, a3.ouf_t - dt)
	for r: Dictionary in reveals:
		r["left"] = float(r["left"]) - dt
	reveals = reveals.filter(func(r: Dictionary) -> bool: return float(r["left"]) > 0.0)
	for m: Dictionary in messages:
		m["left"] = float(m["left"]) - dt
	messages = messages.filter(func(m: Dictionary) -> bool: return float(m["left"]) > 0.0)
	_update_view()


func _control(dt: float) -> void:
	for a: GkActor in actors:
		var move: Vector2 = Vector2.ZERO
		var look_dir: Vector2 = Vector2.ZERO
		var act: bool = false
		if a.is_bot and not brains.has(a.id):
			a.step(Vector2.ZERO, Vector2.ZERO, dt)      # figurant immobile de la visite
			continue
		if a.is_bot:
			var cmd: Dictionary = (brains[a.id] as GkAi).update(dt)
			move = cmd.get("move", Vector2.ZERO)
			look_dir = cmd.get("look", Vector2.ZERO)
			act = bool(cmd.get("action", false))
		else:
			move = input.move()
			if _qa_tourne:
				move = Vector2.from_angle(hunt_elapsed * 1.6)
			act = input.take_action()
		a.step(move, look_dir, dt)
		if act:
			act_for(a)


## Le bouton d'action, selon le rôle et l'endroit (SPEC-GORDEKA §4, §8).
func act_for(a: GkActor) -> void:
	if phase != Phase.HIDE and phase != Phase.HUNT:
		return
	match a.role:
		GkActor.Role.HIDER:
			if a.hidden_in >= 0:
				if _stats and phase == Phase.HUNT and hunter.position.distance_to(a.position) < TENSION_FUITE * map.tile:
					_st["sorties_fuite"] += 1
				_leave_cachette(a, false)
				return
			var c: int = near_cachette(a, true)
			if c >= 0:
				_enter_cachette(a, c)
			elif a.power_cd <= 0.0:
				_place_trap(a)
		GkActor.Role.HUNTER:
			if phase != Phase.HUNT or a.search_left > 0.0:
				return
			var c2: int = near_cachette(a, false)
			if c2 >= 0:
				a.search_left = GkRules.f("search_time")
				_search_target[a.id] = c2
				# Elle tremble, s'ouvre pendant la fouille, puis se referme (fin de fouille).
				var sh: float = GkRules.f("cachette_shake_search")
				cachettes[c2]["jiggle"] = sh
				_open_cachette(cachettes[c2], sh, a.search_left - sh, GkRules.f("cachette_shake_found"))
			elif a.power_cd <= 0.0:
				_detect(a)


## Libellé du bouton d'action pour un joueur (HUD).
func action_label(a: GkActor) -> String:
	match a.role:
		GkActor.Role.HIDER:
			if a.hidden_in >= 0:
				return "Sortir"
			if near_cachette(a, true) >= 0:
				return "Entrer"
			return "Piège"
		GkActor.Role.HUNTER:
			if near_cachette(a, false) >= 0:
				return "Fouiller"
			return "Onde"
	return ""


func action_cooldown(a: GkActor) -> float:
	var label: String = action_label(a)
	if label == "Piège":
		return a.power_cd / GkRules.f("trap_cooldown")
	if label == "Onde":
		return a.power_cd / GkRules.f("detect_cooldown")
	return 0.0


# ---------------------------------------------------------------- emotes

## Emotes seulement hors de l'action : au tirage, sur le podium, ou fantôme ou échappé.
## Jamais en jeu actif, pour ne pas tricher ni gêner la cachette (Julien, 2026-10-19).
func emotes_allowed(a: GkActor) -> bool:
	return phase == Phase.DRAW or phase == Phase.PODIUM or a.role == GkActor.Role.GHOST \
		or a.role == GkActor.Role.OUT


## Lance l'emote `i` : geste du perso et bulle d'icône au-dessus de sa tête.
func emote(a: GkActor, i: int) -> void:
	if i < 0 or i >= EMOTES.size() or not emotes_allowed(a):
		return
	if a.emote_t > GkRules.f("emote_duration") - GkRules.f("emote_gap"):
		return
	a.emote = i
	a.emote_t = GkRules.f("emote_duration")
	a.play_once(EMOTES[i])


func _update_emotes(dt: float) -> void:
	input.emotes_enabled = emotes_allowed(local) and (not local.is_bot or _qa_emotes)
	if _qa_emotes and input.emotes_enabled:
		input.wheel_open = true
	for a: GkActor in actors:
		if a.emote_t > 0.0 and not emotes_allowed(a):
			a.stop_emote()
		a.emote_t = maxf(0.0, a.emote_t - dt)
		var e: int = -1
		if a == local and not a.is_bot:
			e = input.take_emote()
		elif brains.has(a.id):
			e = (brains[a.id] as GkAi).want_emote(dt)
		if _qa_emotes and a.emote_t <= 0.0:
			e = (a.id + round_no) % EMOTES.size()
		if e >= 0:
			emote(a, e)


func _hiders_left() -> int:
	return actors.filter(func(a: GkActor) -> bool: return a.role == GkActor.Role.HIDER).size()


# ---------------------------------------------------------------- vision et capture

## Le chasseur voit-il un corps de rayon `r` en `p` ? Au moins un point du corps visible (sight_fraction).
func sees(h: GkActor, p: Vector2, r: float) -> bool:
	return sight_fraction(h, p, r, false) > 0.0


## Part visible d'un corps de rayon `r` en `p` (0 à 1) ; 0 hors du cône et du petit cercle. On vise
## plusieurs points du corps (#607) : trois lignes (centre et deux bords) et, sur chacune, trois hauteurs
## (vue_pieds, vue_buste, vue_tete, en part de la hauteur d'un perso), depuis l'œil du chasseur
## (vue_oeil, au moins aussi haut que la tête). Un point est caché par un mur ou un objet plus haut que l'œil (couche 2), par un objet
## plus bas dont la ligne passe sous le haut (GkDecor.low_blocks), ou, au-delà de masque_vue_portee, par
## la silhouette d'un objet dessiné devant lui (GkDecor.covered_at). Un objet bas ne cache donc plus
## qu'une partie d'un perso debout (jauge plus lente, detection_partiel) ; un objet haut le cache.
## `all_rays` faux : s'arrête au premier point vu.
func sight_fraction(h: GkActor, p: Vector2, r: float, all_rays: bool = true) -> float:
	var v: Vector2 = p - h.position
	var d: float = v.length()
	if d > sight_range(h, p) + r:
		return 0.0
	if d > GkRules.px("near_radius") + r:
		var half: float = deg_to_rad(GkRules.f("cone_deg")) * 0.5 + atan2(r, maxf(d, 1.0))
		if absf(angle_difference(h.look, v.angle())) > half:
			return 0.0
	var eye: float = eye_height()
	var levels: Array[float] = [GkRules.f("vue_pieds"), GkRules.f("vue_buste"), GkRules.f("vue_tete")]
	var screen: bool = map.decor != null and d > GkRules.px("masque_vue_portee") + r
	var hidden_lv: Array[bool] = []
	for lv: float in levels:
		hidden_lv.append(screen and map.decor.covered_at(p, lv * GkPerso.HEIGHT_PX))
	var side: Vector2 = v.orthogonal().normalized() * r * 0.8
	var n: int = 0
	var total: int = 0
	for target: Vector2 in [p, p + side, p - side]:
		var clear: bool = clear_line(h.position, target)
		for k: int in levels.size():
			total += 1
			if not clear or hidden_lv[k]:
				continue
			if map.decor and map.decor.low_blocks(h.position, target, eye, levels[k] * GkPerso.HEIGHT_PX):
				continue
			n += 1
			if not all_rays:
				return 1.0
	return float(n) / float(maxi(total, 1))


## Hauteur de l'œil du chasseur (px au-dessus du pied) : vue_oeil × hauteur d'un perso.
static func eye_height() -> float:
	return GkRules.f("vue_oeil") * GkPerso.HEIGHT_PX


## Portée du cône du chasseur vers `p` (px) : `grotte_portee` cases au plus dans le noir (`idee_grottes`),
## quand le chasseur ou ce qu'il regarde est sur une case sombre de la carte (grottes, tunnels).
func sight_range(h: GkActor, p: Vector2) -> float:
	var full: float = GkRules.px("cone_range")
	if not GkRules.on("idee_grottes") or map.dark.is_empty():
		return full
	if map.dark.has(map.to_tile(p)) or map.dark.has(map.to_tile(h.position)):
		return minf(full, GkRules.px("grotte_portee"))
	return full


## Détection progressive (`idee_detection`) : vitesse de remplissage de la jauge (par seconde) d'un
## chassé en `p` dont la part `vis` est visible. Pleine en detection_temps_pres s tout près (petit
## cercle), en detection_temps_loin s au bout du cône ; plus lente s'il n'est vu qu'en partie.
static func detection_rate(d: float, vis: float) -> float:
	var near: float = GkRules.px("near_radius")
	var far: float = GkRules.px("cone_range")
	var k: float = clampf((d - near) / maxf(far - near, 1.0), 0.0, 1.0)
	var t: float = lerpf(GkRules.f("detection_temps_pres"), GkRules.f("detection_temps_loin"), k)
	return lerpf(GkRules.f("detection_partiel"), 1.0, clampf(vis, 0.0, 1.0)) / maxf(t, 0.05)


## Jauge d'un chassé après `dt` s : remplie s'il est vu (`vis` > 0, à `d` px du chasseur), sinon
## vidée doucement. Sans détection progressive : capture en capture_time s, vidage capture_decay fois
## plus vite (règle d'avant, gardée pour l'A/B).
static func next_gauge(gauge: float, vis: float, d: float, dt: float) -> float:
	var progressive: bool = GkRules.on("idee_detection")
	if vis > 0.0:
		return gauge + dt * (detection_rate(d, vis) if progressive else 1.0 / GkRules.f("capture_time"))
	var decay: float = GkRules.f("detection_decroissance") if progressive \
		else GkRules.f("capture_decay") / GkRules.f("capture_time")
	return maxf(0.0, gauge - dt * decay)


## Hauteur du corps (px au-dessus du pied) qui doit être recouverte pour qu'un corps de rayon `r`
## soit masqué par un objet : 2 rayons, environ la moitié d'un perso dessiné (même règle pour la vue
## du chasseur et pour la transparence vue des coéquipiers).
static func mask_height(r: float) -> float:
	return r * 2.0


func clear_line(a: Vector2, b: Vector2) -> bool:
	var q: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(a, b, GkMap.LAYER_SIGHT)
	return get_world_2d().direct_space_state.intersect_ray(q).is_empty()


func _update_capture(dt: float) -> void:
	_seen.clear()
	if hunter.frozen:
		return
	var progressive: bool = GkRules.on("idee_detection")
	var peak: float = 0.0
	for a: GkActor in actors:
		if a.role != GkActor.Role.HIDER or a.hidden_in >= 0:
			a.gauge = 0.0
			a.doubted = false
			a.chase_used = false
			continue
		var vis: float = sight_fraction(hunter, a.position, a.radius, progressive)
		_seen[a.id] = vis > 0.0
		var before: float = a.gauge
		a.gauge = next_gauge(a.gauge, vis, a.position.distance_to(hunter.position), dt)
		if a.gauge >= 1.0:
			_found(a)
			if progressive:
				alert_bang = ALERT_BANG_S
			continue
		if a.gauge >= GkRules.f("detection_doute"):
			a.doubted = true
		if GkRules.on("idee_poursuite"):
			_update_chase(a, vis > 0.0)
		if before > 0.0 and a.gauge <= 0.0:
			if _stats:
				_st["evasions_de_vue"] += 1
			# Frôlement visible de tous : le « ? » du chasseur retombe, le chassé souffle « ouf ! ».
			if progressive and a.doubted:
				a.ouf_t = OUF_S
				alert_lost = ALERT_LOST_S
			a.doubted = false
			a.chase_used = false
		peak = maxf(peak, a.gauge)
	hunter_alert = peak
	# Poursuite pour tous les chassés visibles (Julien) : tant que le chasseur est en poursuite, tout
	# chassé qu'il voit (déjà là au départ ou entré dans son champ) en profite aussi.
	if GkRules.on("idee_poursuite") and GkRules.on("poursuite_tous_vus") and hunter.chase_left > 0.0:
		for a: GkActor in actors:
			if a.role == GkActor.Role.HIDER and bool(_seen.get(a.id, false)):
				a.chase_left = maxf(a.chase_left, hunter.chase_left)


## Poursuite (idee_poursuite) : multiplicateur de vitesse du chasseur (`hunter`) ou du chassé repéré.
## poursuite_mult_chasseur / poursuite_mult_chasse, ou poursuite_mult s'ils valent 0.
static func chase_mult(hunter_side: bool) -> float:
	var k: float = GkRules.f("poursuite_mult_chasseur" if hunter_side else "poursuite_mult_chasse")
	return k if k > 0.0 else GkRules.f("poursuite_mult")


## Poursuite : un chassé dont la jauge atteint poursuite_seuil (0,3 = le « ? ») part en poursuite avec
## le chasseur, tous deux plus rapides pendant poursuite_duree_s s ; poursuite_tant_que_vu = 1 : la
## durée se recharge tant que le chasseur le voit (elle compte alors après l'avoir perdu de vue).
func _update_chase(a: GkActor, seen: bool) -> void:
	var dur: float = GkRules.f("poursuite_duree_s")
	var start: bool = a.chase_left <= 0.0 and seen and a.gauge >= GkRules.f("poursuite_seuil") \
		and not a.chase_used
	var keep: bool = a.chase_left > 0.0 and seen and GkRules.on("poursuite_tant_que_vu")
	if not start and not keep:
		return
	if start:
		a.chase_used = true
		if hunter.chase_left <= 0.0:
			if _stats:
				_st["poursuites"] += 1
			if frisson:
				frisson.play_chase()
	a.chase_left = dur
	hunter.chase_left = maxf(hunter.chase_left, dur)


## Compteurs de tension d'un round (`--gk-stats`) : frôlements (le chasseur passe à moins de 2 ou
## 3 cases d'un chassé sans le trouver), « vu puis perdu » (un chassé entre dans la vue du chasseur
## puis en sort sans être trouvé), doutes (« ? » de la détection progressive), mouvement des chassés
## (cases parcourues ; secondes en mouvement, immobile ou en cachette ; changements de planque ;
## sorties de cachette en fuite) et captures « au dernier moment ».
static func tension_keys() -> Dictionary:
	return {"frolements_2": 0, "frolements_3": 0, "frolements_2_cachette": 0, "vus": 0, "vu_perdu": 0,
		"doutes": 0, "doutes_perdus": 0, "cases_parcourues": 0.0, "chasse_s": 0.0, "bouge_s": 0.0,
		"immobile_s": 0.0, "cachette_s": 0.0, "changements_planque": 0, "sorties_fuite": 0,
		"captures_course": 0, "captures_apres_evasion": 0, "captures_fin": 0, "poursuites": 0,
		"poursuite_s": 0.0, "captures_poursuite": 0}


## Met à jour les compteurs de tension (après la capture de cette image : un chassé trouvé a déjà
## perdu son état, son épisode en cours ne compte donc pas).
func track_tension(dt: float) -> void:
	if hunter == null or hunter.frozen:
		return
	var t: float = map.tile
	_heat_t += dt
	var sample: bool = _heat_t >= 1.0
	if sample:
		_heat_t -= 1.0
		_heat(_st["chaleur_chasseur"], hunter.position)
	if hunter.chase_left > 0.0:
		_st["poursuite_s"] += dt
	for a: GkActor in actors:
		if a == hunter:
			continue
		if a.role != GkActor.Role.HIDER:
			_tens.erase(a.id)
			continue
		if not _tens.has(a.id):
			_tens[a.id] = {"near2": false, "near3": false, "near2_in": false, "vu": false, "unseen": 0.0,
				"doute": false, "last": a.position, "anchor": a.position, "anchor_t": 0.0,
				"spot": Vector2.INF, "escaped_at": -100.0}
		var s: Dictionary = _tens[a.id]
		if sample:
			_heat(_st["chaleur"], a.position)
		# Frôlements : épisode ouvert sous r cases, refermé au-delà de r + TENSION_HYST.
		var d: float = a.position.distance_to(hunter.position) / t
		for r: int in [2, 3]:
			var k: String = "near%d" % r
			if not bool(s[k]) and d < float(r):
				s[k] = true
			elif bool(s[k]) and d > float(r) + TENSION_HYST:
				s[k] = false
				_st["frolements_%d" % r] += 1
				if r == 2:
					_st["lieux_frolements"].append(_tile_list(a.position))
				if r == 2 and bool(s["near2_in"]):
					_st["frolements_2_cachette"] += 1
		s["near2_in"] = bool(s["near2"]) and (bool(s["near2_in"]) or a.hidden_in >= 0)
		# Vu puis perdu : hors de vue pendant TENSION_VU_GRACE s sans avoir été trouvé.
		if bool(_seen.get(a.id, false)):
			s["unseen"] = 0.0
			if not bool(s["vu"]):
				s["vu"] = true
				_st["vus"] += 1
		elif bool(s["vu"]):
			s["unseen"] = float(s["unseen"]) + dt
			if float(s["unseen"]) >= TENSION_VU_GRACE:
				s["vu"] = false
				s["escaped_at"] = hunt_elapsed
				_st["vu_perdu"] += 1
				_st["lieux_vu_perdu"].append(_tile_list(a.position))
		# Doutes : la jauge passe le seuil du « ? », puis retombe à zéro sans capture.
		if not bool(s["doute"]) and a.gauge >= GkRules.f("detection_doute"):
			s["doute"] = true
			_st["doutes"] += 1
		elif bool(s["doute"]) and a.gauge <= 0.0:
			s["doute"] = false
			_st["doutes_perdus"] += 1
		# Mouvement (un saut d'entrée ou de sortie de cachette ne compte que pour un pas).
		var step: float = minf(a.position.distance_to(s["last"]), a.speed() * dt * 2.0)
		s["last"] = a.position
		_st["chasse_s"] += dt
		_st["cases_parcourues"] += step / t
		if a.hidden_in >= 0:
			_st["cachette_s"] += dt
		elif step > a.speed() * dt * TENSION_BOUGE:
			_st["bouge_s"] += dt
		else:
			_st["immobile_s"] += dt
		# Planques : on reste TENSION_PLANQUE_S s dans un rayon de TENSION_PLANQUE_R case ; une
		# nouvelle planque à plus de TENSION_PLANQUE_ECART cases de la précédente est un changement.
		var here: Vector2 = cachettes[a.hidden_in]["pos"] if a.hidden_in >= 0 else a.position
		if here.distance_to(s["anchor"]) > t * TENSION_PLANQUE_R:
			s["anchor"] = here
			s["anchor_t"] = 0.0
		else:
			s["anchor_t"] = float(s["anchor_t"]) + dt
			var anchor: Vector2 = s["anchor"]
			if float(s["anchor_t"]) >= TENSION_PLANQUE_S and anchor.distance_to(s["spot"]) > t * TENSION_PLANQUE_ECART:
				if s["spot"] != Vector2.INF:
					_st["changements_planque"] += 1
				s["spot"] = anchor


## Présence d'un perso sur sa case (statistiques de carte, une seconde par échantillon).
func _heat(d: Dictionary, p: Vector2) -> void:
	var tt: Vector2i = map.to_tile(p)
	var k: String = "%d,%d" % [tt.x, tt.y]
	d[k] = int(d.get(k, 0)) + 1


func _tile_list(p: Vector2) -> Array:
	var tt: Vector2i = map.to_tile(p)
	return [tt.x, tt.y]


func _found(a: GkActor, via: String = "vue") -> void:
	if _stats:
		_st[via] = int(_st.get(via, 0)) + 1
		(_st["t_trouves"] as Array).append(snappedf(hunt_elapsed, 0.1))
		var tt: Vector2i = map.to_tile(a.position)
		(_st["lieux_trouves"] as Array).append([tt.x, tt.y])
		if hunt_elapsed - float(_revealed_at.get(a.id, -100.0)) < 12.0:
			_st["trouves_apres_onde"] += 1
		if hunt_elapsed - _trap_hit_at < 8.0:
			_st["trouves_apres_piege"] += 1
		if hunt_elapsed - _noise_at < 10.0:
			_st["trouves_apres_bruit"] += 1
		# Captures « au dernier moment » : en pleine course, juste après une évasion, ou en fin de round.
		if via == "vue" and a.velocity.length() > a.speed() * TENSION_BOUGE:
			_st["captures_course"] += 1
		if _tens.has(a.id) and hunt_elapsed - float(_tens[a.id]["escaped_at"]) < TENSION_JUSTESSE_S:
			_st["captures_apres_evasion"] += 1
		if a.chase_left > 0.0:
			_st["captures_poursuite"] += 1
		if hunt_elapsed > GkRules.f("phase_hunt") - TENSION_FIN_S:
			_st["captures_fin"] += 1
	_last_find_t = hunt_elapsed
	# Poursuite : elle s'arrête avec la capture (sauf si un autre chassé est encore poursuivi).
	a.chase_left = 0.0
	if actors.all(func(b: GkActor) -> bool: return b == hunter or b.chase_left <= 0.0):
		hunter.chase_left = 0.0
	hunter.elan_mult = 1.0
	a.rescue_k = 0.0
	if a.hidden_in >= 0:
		_leave_cachette(a, false)
	a.play_once("found")
	a.set_role(GkActor.Role.GHOST)
	a.gauge = 0.0
	_round_found += 1
	_give(hunter, GkRules.score("hunter_find"))
	_say("%s : trouvé !" % a.display_name, Color("ffcf4a"), 2.0)
	for b: GkAi in brains.values():
		b.on_found(a)


# ---------------------------------------------------------------- cachettes

## Cachette à portée de main (`free_only` : libre et pas verrouillée), sinon -1.
func near_cachette(a: GkActor, free_only: bool) -> int:
	var best: int = -1
	var bd: float = GkRules.px("use_range") + map.tile * 0.5
	for i: int in cachettes.size():
		var c: Dictionary = cachettes[i]
		if free_only and (int(c["occupant"]) >= 0 or float(c["lock"]) > 0.0):
			continue
		var d: float = a.position.distance_to(c["pos"])
		if d < bd:
			bd = d
			best = i
	return best


func _enter_cachette(a: GkActor, i: int) -> void:
	var c: Dictionary = cachettes[i]
	c["occupant"] = a.id
	c["creak_wait"] = 0.0
	a.hidden_in = i
	a.hidden_t = 0.0
	a.gauge = 0.0
	a.position = c["pos"]
	a.pop_left = 0.0
	a.play_once("hide_in")
	# Elle s'ouvre d'un coup, le perso plonge (durée de son hide_in, bornée), elle se referme et tremble.
	var dive: float = clampf(a.once_length("hide_in"), GkRules.f("cachette_dive_min"), GkRules.f("cachette_dive_max"))
	a.vanish_left = dive
	c["shake"] = GkRules.f("cachette_shake_in")
	_open_cachette(c, 0.0, dive, GkRules.f("cachette_shake_in"))
	if _stats and phase == Phase.HUNT:
		_st["entrees_cachette"] += 1
		var ck: String = "%d,%d" % [(c["tile"] as Vector2i).x, (c["tile"] as Vector2i).y]
		_st["cachettes_entrees"][ck] = int(_st["cachettes_entrees"].get(ck, 0)) + 1


func _leave_cachette(a: GkActor, forced: bool) -> void:
	var i: int = a.hidden_in
	if i < 0:
		return
	var c: Dictionary = cachettes[i]
	c["occupant"] = -1
	if forced:
		c["lock"] = GkRules.f("hide_lock")
	a.hidden_in = -1
	a.vanish_left = 0.0
	a.play_once("hide_out")
	# Elle s'ouvre, le perso jaillit (dessiné de la cachette jusqu'à sa case), elle se referme.
	a.pop_from = c["pos"]
	a.pop_left = GkRules.f("cachette_out_s")
	c["shake"] = GkRules.f("cachette_shake_out")
	_open_cachette(c, 0.0, a.pop_left, GkRules.f("cachette_shake_out"))
	# Ressort sur la case libre voisine la plus loin du chasseur.
	var best: Vector2 = c["pos"]
	var bd: float = -1.0
	for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var t: Vector2i = (c["tile"] as Vector2i) + d
		if map.walkable(t):
			var dist: float = map.center(t).distance_to(hunter.position) if hunter else 0.0
			if dist > bd:
				bd = dist
				best = map.center(t)
	a.position = best


func _reset_cachettes() -> void:
	for c: Dictionary in cachettes:
		c.merge({"occupant": -1, "lock": 0.0, "shake": 0.0, "jiggle": 0.0, "open": 0.0, "delay": 0.0, "hold": 0.0,
			"close_shake": 0.0, "squash_t": 0.0, "shiver": 0.0, "creak": 0.0, "creak_wait": 0.0,
			"shiver_wait": GkRules.f("cachette_shiver_gap") * randf_range(1.0, 2.0)}, true)


## Ouvre la cachette après `delay` s, la garde ouverte `hold` s, puis la referme en tremblant
## `close_shake` s. Chaque ouverture et chaque fermeture l'écrasent un peu (squash and stretch).
func _open_cachette(c: Dictionary, delay: float, hold: float, close_shake: float) -> void:
	c["delay"] = delay
	c["hold"] = maxf(hold, 0.0)
	c["close_shake"] = close_shake
	if delay <= 0.0:
		c["squash_t"] = GkRules.f("cachette_squash_s")


## Ce qu'on dessine d'une cachette (calque de jeu et images du décor) : ouverture (0 → 1),
## écrasement (> 0 écrasée, < 0 étirée), décalage horizontal du tremblement et du frémissement (px).
func cachette_look(i: int) -> Dictionary:
	if i < 0 or i >= cachettes.size():
		return {"open": 0.0, "squash": 0.0, "dx": 0.0}
	var c: Dictionary = cachettes[i]
	var squash: float = 0.0
	var ss: float = GkRules.f("cachette_squash_s")
	if float(c["squash_t"]) > 0.0 and ss > 0.0:
		# Écrasée, puis étirée, puis un petit rebond qui s'éteint.
		var p: float = 1.0 - float(c["squash_t"]) / ss
		squash = GkRules.f("cachette_squash") * sin(p * TAU * 1.5) * (1.0 - p)
	var shake: float = float(c["jiggle"])
	var dx: float = sin(shake * SHAKE_FREQ) * SHAKE_PX * signf(shake) \
		+ sin(float(c["shiver"]) * SHIVER_FREQ) * SHIVER_PX
	return {"open": float(c["open"]), "squash": squash, "dx": dx}


func _update_cachettes(dt: float) -> void:
	for c: Dictionary in cachettes:
		c["lock"] = maxf(0.0, float(c["lock"]) - dt)
		c["shake"] = maxf(0.0, float(c["shake"]) - dt)
		c["jiggle"] = maxf(0.0, float(c["jiggle"]) - dt)
		c["squash_t"] = maxf(0.0, float(c["squash_t"]) - dt)
		c["shiver"] = maxf(0.0, float(c["shiver"]) - dt)
		c["creak"] = maxf(0.0, float(c["creak"]) - dt)
		if float(c["delay"]) > 0.0:
			c["delay"] = float(c["delay"]) - dt
			if float(c["delay"]) <= 0.0:
				c["squash_t"] = GkRules.f("cachette_squash_s")
		elif float(c["hold"]) > 0.0:
			c["open"] = move_toward(float(c["open"]), 1.0, dt / maxf(GkRules.f("cachette_open_s"), 0.01))
			c["hold"] = float(c["hold"]) - dt
			if float(c["hold"]) <= 0.0:
				c["squash_t"] = GkRules.f("cachette_squash_s")
				c["jiggle"] = maxf(float(c["jiggle"]), float(c["close_shake"]))
		else:
			c["open"] = move_toward(float(c["open"]), 0.0, dt / maxf(GkRules.f("cachette_close_s"), 0.01))
			# Quelqu'un dedans : un petit frémissement de temps en temps. Ce n'est pas `shake` : l'IA
			# du chasseur, qui fouille les cachettes qui tremblent, ne s'y fie pas.
			if int(c["occupant"]) >= 0:
				c["shiver_wait"] = float(c["shiver_wait"]) - dt
				if float(c["shiver_wait"]) <= 0.0:
					c["shiver"] = GkRules.f("cachette_shiver_s")
					c["shiver_wait"] = GkRules.f("cachette_shiver_gap") * randf_range(1.0, 2.0)
	for a: GkActor in actors:
		a.vanish_left = maxf(0.0, a.vanish_left - dt)
		a.pop_left = maxf(0.0, a.pop_left - dt)
		if a.hidden_in >= 0:
			a.hidden_t += dt
			# Cachette qui grince : passé `grince_apres` s dedans, elle craque toutes les `grince_ecart` s.
			if GkRules.on("idee_grince") and phase == Phase.HUNT and a.inside() \
					and a.hidden_t >= GkRules.f("grince_apres"):
				var c: Dictionary = cachettes[a.hidden_in]
				c["creak_wait"] = float(c.get("creak_wait", 0.0)) - dt
				if float(c["creak_wait"]) <= 0.0:
					c["creak_wait"] = GkRules.f("grince_ecart")
					c["creak"] = 0.9
					c["shake"] = 1.0
					c["jiggle"] = maxf(float(c["jiggle"]), 0.5)
					_noise(c["pos"], "grincements")
					if a == local and a.hidden_t < GkRules.f("grince_apres") + dt * 1.5:
						_say("Ta cachette grince !", Color("ffd34a"), 2.0)
			if a.hidden_t >= GkRules.f("hide_max"):
				_leave_cachette(a, true)
				if _stats:
					_st["ejections_cachette"] += 1
				if a == local:
					_say("Trop longtemps caché : dehors !", Color("ffcf4a"), 2.0)


## QA (`--gk-qa-cachette`) : entrées et sorties à heure fixe dans les cachettes d'une zone.
func _qa_cachettes(dt: float) -> void:
	_qa_clock += dt
	if _qa_clock < _qa_next:
		return
	if _qa_inside:
		for a: GkActor in actors:
			if a.hidden_in >= 0:
				_leave_cachette(a, false)
		_qa_next += QA_GAP_S
	else:
		var free: Array[GkActor] = []
		for a: GkActor in actors:
			if a != hunter and a.role == GkActor.Role.HIDER and a.hidden_in < 0:
				free.append(a)
		for i: int in cachettes.size():
			var z: int = map.zone_of(cachettes[i]["tile"])
			if free.is_empty() or z < 0 or not GkMap._plain(str(map.zones[z]["name"])).begins_with(GkMap._plain(_qa_cachette)):
				continue
			if int(cachettes[i]["occupant"]) < 0:
				_enter_cachette(free.pop_front(), i)
		_qa_next += QA_OUT_S
	_qa_inside = not _qa_inside


func _update_searches(dt: float) -> void:
	for a: GkActor in actors:
		if a.search_left <= 0.0:
			continue
		a.search_left -= dt
		if a.search_left <= 0.0:
			var c: Dictionary = cachettes[int(_search_target.get(a.id, 0))]
			var occ: int = int(c["occupant"])
			c["shake"] = GkRules.f("cachette_shake_found")
			if occ >= 0:
				if _stats:
					_st["fouille_ok"] += 1
					_st["trouves_en_cachette"] += 1
				_found(actors[occ], "fouille")
			else:
				if _stats:
					_st["fouille_vide"] += 1
				if a == local:
					_say("Personne…", Color.WHITE, 1.2)


# ---------------------------------------------------------------- pouvoirs

func _place_trap(a: GkActor) -> void:
	traps.append({"pos": a.position, "owner": a.id})
	var mine: Array = traps.filter(func(t: Dictionary) -> bool: return int(t["owner"]) == a.id)
	if mine.size() > int(GkRules.f("trap_max")):
		traps.erase(mine[0])
	a.power_cd = GkRules.f("trap_cooldown")
	a.play_once("trap")
	if _stats:
		_st["pieges_poses"] += 1


func _update_traps() -> void:
	if hunter.frozen:
		return
	for t: Dictionary in traps.duplicate():
		if hunter.position.distance_to(t["pos"]) < hunter.radius + map.tile * 0.3:
			traps.erase(t)
			hunter.slow_left = GkRules.f("trap_duration")
			if _stats:
				_st["pieges_pris"] += 1
				_trap_hit_at = hunt_elapsed
			var owner: GkActor = actors[int(t["owner"])]
			_give(owner, GkRules.score("hider_trap_hit"))
			_say("Piège de %s !" % owner.display_name, Color("f2c12e"), 1.6)
			for b: GkAi in brains.values():
				b.on_trap(t["pos"])


func _detect(h: GkActor) -> void:
	h.power_cd = GkRules.f("detect_cooldown")
	h.play_once("detect")
	var found: Array[Vector2] = []
	for a: GkActor in actors:
		if a.role == GkActor.Role.HIDER and a.position.distance_to(h.position) <= GkRules.px("detect_radius"):
			reveals.append({"pos": a.position, "left": GkRules.f("detect_duration"), "id": a.id})
			found.append(a.position)
			_revealed_at[a.id] = hunt_elapsed
	reveals.append({"pos": h.position, "left": 0.6, "id": -1})     # l'onde elle-même
	# Personne dans le rayon : une flèche vers le chassé libre le plus proche (l'onde donne
	# toujours un indice, sans révéler où il est exactement).
	var hint: Vector2 = Vector2.ZERO
	if found.is_empty():
		var best: GkActor = null
		for a: GkActor in actors:
			if a.role == GkActor.Role.HIDER and (best == null
					or a.position.distance_to(h.position) < best.position.distance_to(h.position)):
				best = a
		if best != null:
			hint = (best.position - h.position).normalized()
			reveals.append({"pos": h.position, "dir": hint, "left": GkRules.f("detect_hint_duration"), "id": -2})
	if _stats:
		_st["ondes"] += 1
		_st["montres"] += found.size()
		if not found.is_empty():
			_st["ondes_utiles"] += 1
	if brains.has(h.id):
		(brains[h.id] as GkAi).on_detect(found, hint)
	if h != local:
		_say("Le chasseur lance une onde !", Color("9fd8ef"), 1.4)


# ---------------------------------------------------------------- idées de gameplay (A/B)

## Gâteaux basques et mouettes du round, sur des cases libres et dégagées (couverture ≤ 2),
## loin du départ et espacées entre elles.
func _place_bonus() -> void:
	gateaux.clear()
	mouettes.clear()
	_cake_respawn.clear()
	var want_g: int = int(GkRules.f("gateaux_nombre")) if GkRules.on("idee_gateaux") else 0
	var want_m: int = int(GkRules.f("mouettes_nombre")) if GkRules.on("idee_mouettes") else 0
	if want_g + want_m == 0:
		return
	var spawn: Vector2 = map.center(map.spawns[0]) if not map.spawns.is_empty() else map.size_px() * 0.5
	var taken: Array[Vector2] = []
	for tries: int in 40:
		if gateaux.size() >= want_g and mouettes.size() >= want_m:
			break
		var p: Vector2 = _bonus_spot(taken, spawn)
		if p == Vector2.INF:
			continue
		taken.append(p)
		if gateaux.size() < want_g:
			gateaux.append({"pos": p})
		else:
			mouettes.append({"pos": p, "away": 0.0, "fly": 0.0})


## Case libre et dégagée (couverture ≤ 2) à au moins 8 cases de `away` et 9 cases de chaque point
## de `taken`, au hasard ; Vector2.INF si on n'en trouve pas.
func _bonus_spot(taken: Array[Vector2], away: Vector2) -> Vector2:
	var keys: Array = map.cover.keys()
	for tries: int in 40:
		var t: Vector2i = keys[randi() % keys.size()]
		if int(map.cover[t]) > 2 or map.at(t) != "." and map.at(t) != ":" and map.at(t) != "=":
			continue
		var p: Vector2 = map.center(t)
		if p.distance_to(away) < 8.0 * map.tile:
			continue
		var ok: bool = true
		for q: Vector2 in taken:
			if p.distance_to(q) < 9.0 * map.tile:
				ok = false
				break
		if ok:
			return p
	return Vector2.INF


## Un bruit (cachette qui grince, mouettes qui s'envolent) : le chasseur IA l'entend s'il est à
## portée ; un chasseur humain le voit sur son écran (dessiné dans le calque du monde).
func _noise(pos: Vector2, stat: String) -> void:
	_noise_at = hunt_elapsed
	if _stats:
		_st[stat] = int(_st[stat]) + 1
	var hear: float = GkRules.px("grince_ouie" if stat == "grincements" else "mouettes_ouie")
	if brains.has(hunter.id) and hunter.position.distance_to(pos) <= hear:
		(brains[hunter.id] as GkAi).on_noise(pos)


func _update_ideas(dt: float) -> void:
	# Chatouille : un fantôme qui touche le chasseur le fait rire, et il ralentit un instant.
	if GkRules.on("idee_chatouille") and not hunter.frozen:
		for a: GkActor in actors:
			if a.role == GkActor.Role.GHOST and a.power_cd <= 0.0 and hunt_elapsed >= _tickle_free_until \
					and a.position.distance_to(hunter.position) < GkRules.px("chatouille_portee"):
				a.power_cd = GkRules.f("chatouille_cooldown")
				hunter.tickle_left = GkRules.f("chatouille_duree")
				_tickle_free_until = hunt_elapsed + GkRules.f("chatouille_repit")
				_give(a, GkRules.score("ghost_tickle"))
				_say("Tu chatouilles le chasseur !" if a == local else "%s chatouille le chasseur !" % a.display_name,
					Color("ffd34a"), 1.6)
				if _stats:
					_st["chatouilles"] += 1
	# Délivrance : un chassé libre et hors de vue reste près d'un fantôme, qui revient en jeu.
	if GkRules.on("idee_delivrance") and _rescues < int(GkRules.f("delivrance_max")):
		for gh: GkActor in actors:
			if gh.role != GkActor.Role.GHOST or gh.rescued:
				continue
			var helper: GkActor = null
			for a: GkActor in actors:
				if a.role == GkActor.Role.HIDER and a.hidden_in < 0 and a.gauge <= 0.0 \
						and a.position.distance_to(gh.position) < GkRules.px("delivrance_portee"):
					helper = a
					break
			if helper == null:
				gh.rescue_k = maxf(0.0, gh.rescue_k - dt / GkRules.f("delivrance_temps"))
				continue
			gh.rescue_k += dt / GkRules.f("delivrance_temps")
			if gh.rescue_k >= 1.0:
				_rescue(gh, helper)
	# Gâteaux basques : un chassé qui en ramasse un marque un point et file un moment.
	for g2: Dictionary in gateaux.duplicate():
		for a: GkActor in actors:
			if a.role == GkActor.Role.HIDER and a.hidden_in < 0 \
					and a.position.distance_to(g2["pos"]) < GkRules.px("gateau_portee"):
				gateaux.erase(g2)
				if GkRules.on("idee_mouvement"):
					_cake_respawn.append(hunt_elapsed + GkRules.f("gateaux_reapparition"))
				a.sprint_left = GkRules.f("gateau_duree")
				_give(a, GkRules.score("hider_cake"))
				if a == local:
					_say("Gâteau basque : ça file !", Color("ffd34a"), 1.6)
				if _stats:
					_st["gateaux"] += 1
				break
	# Mouvement : un gâteau mangé réapparaît ailleurs, loin du chasseur (on a une raison de bouger).
	if not _cake_respawn.is_empty() and hunt_elapsed >= _cake_respawn[0]:
		var taken: Array[Vector2] = []
		for g3: Dictionary in gateaux:
			taken.append(g3["pos"])
		var p: Vector2 = _bonus_spot(taken, hunter.position)
		if p != Vector2.INF:
			_cake_respawn.pop_front()
			gateaux.append({"pos": p})
	# Mouettes : un chassé qui passe trop près les fait s'envoler en criant (indice pour le chasseur).
	for m: Dictionary in mouettes:
		m["fly"] = maxf(0.0, float(m["fly"]) - dt)
		if float(m["away"]) > 0.0:
			m["away"] = float(m["away"]) - dt
			continue
		for a: GkActor in actors:
			if a.role == GkActor.Role.HIDER and a.hidden_in < 0 \
					and a.position.distance_to(m["pos"]) < GkRules.px("mouettes_portee"):
				m["away"] = GkRules.f("mouettes_retour")
				m["fly"] = 1.5
				_noise(m["pos"], "mouettes")
				break
	# Chasseur bredouille : sans capture depuis `bredouille_apres` s, il a le vent dans le dos.
	if GkRules.on("idee_bredouille") and not hunter.frozen:
		var dry: bool = hunt_elapsed - _last_find_t >= GkRules.f("bredouille_apres")
		if dry and hunter.elan_mult <= 1.0:
			_say("Le chasseur a le vent dans le dos !", Color("9fd8ef"), 2.0)
		hunter.elan_mult = GkRules.f("bredouille_vitesse") if dry else 1.0
		if dry and _stats:
			_st["elan_s"] = float(_st["elan_s"]) + dt


func _rescue(gh: GkActor, helper: GkActor) -> void:
	gh.rescued = true
	_rescues += 1
	for a: GkActor in actors:
		a.rescue_k = 0.0
	gh.set_role(GkActor.Role.HIDER)
	gh.position = helper.position          # un fantôme traverse les murs : il revient à côté de son sauveur
	gh.gauge = 0.0
	gh.play_once("hide_out")
	_round_found -= 1
	_give(helper, GkRules.score("hider_rescue"))
	if helper == local:
		_say("Tu délivres %s !" % gh.display_name, Color("6fe08a"), 2.0)
	elif gh == local:
		_say("%s te délivre : rejoue !" % helper.display_name, Color("6fe08a"), 2.0)
	else:
		_say("%s délivre %s !" % [helper.display_name, gh.display_name], Color("6fe08a"), 2.0)
	if _stats:
		_st["delivres"] += 1
	if brains.has(gh.id):
		(brains[gh.id] as GkAi).reset()


# ---------------------------------------------------------------- sorties

## Tire les sorties du round : `exits_per_round` groupes, éloignés d'au moins `exits_min_gap` cases
## (pour ne pas ouvrir deux sorties voisines). On rompt ainsi la routine d'un round à l'autre.
func _pick_exits() -> void:
	open_exits.clear()
	open_exit_zones.clear()
	var groups: Array = map.exit_groups.duplicate()
	groups.shuffle()
	var picked: Array = []
	for grp: Dictionary in groups:
		if picked.size() >= int(GkRules.f("exits_per_round")):
			break
		var c: Vector2 = _group_center(grp)
		var ok: bool = true
		for p: Dictionary in picked:
			if c.distance_to(_group_center(p)) < GkRules.f("exits_min_gap"):
				ok = false
		if ok:
			picked.append(grp)
	for grp: Dictionary in picked:
		open_exits.append_array(grp["tiles"])
		open_exit_zones.append(str(grp["zone"]))


func _group_center(grp: Dictionary) -> Vector2:
	var s: Vector2 = Vector2.ZERO
	for t: Vector2i in grp["tiles"]:
		s += Vector2(t)
	return s / float((grp["tiles"] as Array).size())


func _open_exit_rects() -> Array[Rect2i]:
	var out: Array[Rect2i] = []
	for grp: Dictionary in map.exit_groups:
		if open_exits.has((grp["tiles"] as Array)[0]):
			var r: Rect2i = Rect2i(grp["tiles"][0], Vector2i.ONE)
			for t: Vector2i in grp["tiles"]:
				r = r.merge(Rect2i(t, Vector2i.ONE))
			out.append(r)
	return out


func exits_open() -> bool:
	return phase == Phase.HUNT and hunt_elapsed >= GkRules.f("exits_open_at")


func _update_exits(dt: float) -> void:
	if not exits_open():
		return
	for a: GkActor in actors:
		if a.role != GkActor.Role.HIDER or a.hidden_in >= 0:
			continue
		if open_exits.has(map.to_tile(a.position)) and a.gauge <= 0.0:
			a.extract_t += dt
			if a.extract_t >= GkRules.f("extract_hold"):
				a.play_once("extract")
				a.set_role(GkActor.Role.OUT)
				if _stats:
					_st["sorties"] += 1
					var zi: int = map.zone_of(map.to_tile(a.position))
					_st["sorties_lieux"].append(str(map.zones[zi]["name"]) if zi >= 0 else "?")
				_give(a, GkRules.score("hider_extract"))
				_say("%s s'est échappé !" % a.display_name, Color("6fe08a"), 2.0)
		else:
			a.extract_t = 0.0


# ---------------------------------------------------------------- affichage

func _say(text: String, color: Color, seconds: float) -> void:
	messages.append({"text": text, "left": seconds, "color": color})
	if messages.size() > 3:
		messages.pop_front()


func _update_view() -> void:
	var as_hunter: bool = local == hunter and phase != Phase.END and phase != Phase.PODIUM
	_dark.color = Color(0.3, 0.3, 0.4) if as_hunter else Color.WHITE
	for l: PointLight2D in [_cone_light, _near_light, _cone_light_decor, _near_light_decor]:
		l.enabled = as_hunter
		if as_hunter:
			l.position = hunter.position
			l.rotation = hunter.look
	# Dans le noir (`idee_grottes`), le cône éclairé raccourcit comme la vue.
	if as_hunter:
		var k: float = sight_range(hunter, hunter.position) / GkRules.px("cone_range")
		for l2: PointLight2D in [_cone_light, _cone_light_decor]:
			l2.texture_scale = GkRules.px("cone_range") * 2.0 * k / float(l2.texture.get_width())
	# Un chassé masqué par le haut d'un objet : ses coéquipiers (jamais le chasseur) voient l'objet
	# en transparence.
	if map.decor:
		var fade: Dictionary = {}
		if local != hunter:
			for a: GkActor in actors:
				if a.role == GkActor.Role.HIDER and a.hidden_in < 0:
					var i: int = map.decor.masking(a.position, mask_height(a.radius))
					if i >= 0:
						fade[i] = true
		map.decor.update_fades(fade, GkRules.f("masque_fondu"), _last_dt)
	var scare: float = GkRules.px("scared_range")
	for a: GkActor in actors:
		a.scared = phase == Phase.HUNT and a.role == GkActor.Role.HIDER \
			and a.position.distance_to(hunter.position) < scare
		var show: bool = true
		if a.role == GkActor.Role.OUT:
			show = a == local
		elif as_hunter and a != hunter:
			show = a.role == GkActor.Role.HIDER and bool(_seen.get(a.id, false))
		if a.shown != show:
			a.shown = show
			a.queue_redraw()
	_camera.position = local.position
	if use_3d:
		view.refresh(_last_dt)
		for a: GkActor in actors:
			a.draw_2d = false
		_dark.color = Color.WHITE
		for l: PointLight2D in [_cone_light, _near_light, _cone_light_decor, _near_light_decor]:
			l.enabled = false
	else:
		_overlay.queue_redraw()
	hud.queue_redraw()


## Position à l'écran d'un point du jeu (HUD), en 2D comme en 3D.
func screen_pos(p: Vector2, height: float = 0.0) -> Vector2:
	if use_3d:
		return view.screen_pos(p, height)
	return get_viewport().get_canvas_transform() * p


## Cône du chasseur (polygone par lancer de rayons), vu des chassés et des fantômes.
func cone_polygon(h: GkActor) -> PackedVector2Array:
	var pts: PackedVector2Array = [h.position]
	var half: float = deg_to_rad(GkRules.f("cone_deg")) * 0.5
	var rng: float = sight_range(h, h.position)
	var n: int = 40
	for i: int in n + 1:
		var a: float = h.look - half + 2.0 * half * float(i) / float(n)
		pts.append(_ray_end(h.position, h.position + Vector2.from_angle(a) * rng))
	return pts


func _ray_end(a: Vector2, b: Vector2) -> Vector2:
	var q: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(a, b, GkMap.LAYER_SIGHT)
	var hit: Dictionary = get_world_2d().direct_space_state.intersect_ray(q)
	return hit["position"] if not hit.is_empty() else b


func _draw_overlay(ci: CanvasItem) -> void:
	var as_hunter: bool = local == hunter and phase != Phase.END and phase != Phase.PODIUM
	var font: Font = ThemeDB.fallback_font
	# Sorties : grisées tant qu'elles sont fermées.
	var open: bool = exits_open()
	for r: Rect2i in _open_exit_rects():
		var px: Rect2 = Rect2(Vector2(r.position) * map.tile, Vector2(r.size) * map.tile)
		ci.draw_rect(px, Color(0.3, 0.9, 0.45, 0.35) if open else Color(0.4, 0.4, 0.4, 0.25))
		ci.draw_rect(px, Color("6fe08a") if open else Color("8a8a8a"), false, 4.0)
		ci.draw_string(font, px.position + Vector2(0, px.size.y * 0.5 + 8), "SORTIE" if open else "FERMÉE",
			HORIZONTAL_ALIGNMENT_CENTER, px.size.x, 22, Color.WHITE)
	# Cachettes : caisse orange qui s'ouvre, s'écrase et tremble (entrée, sortie, fouille).
	for i: int in cachettes.size():
		var c: Dictionary = cachettes[i]
		var look: Dictionary = cachette_look(i)
		var sq: float = float(look["squash"])
		var size: Vector2 = Vector2(map.tile, map.tile) * 0.84 * Vector2(1.0 + sq * 0.6, 1.0 - sq)
		var bottom: Vector2 = (c["pos"] as Vector2) + Vector2(float(look["dx"]), map.tile * 0.42)
		var px2: Rect2 = Rect2(bottom - Vector2(size.x * 0.5, size.y), size)
		# Cachette dessinée par pixelforge : l'image du décor (animée par GkDecor) remplace la caisse.
		if not map.decor.has_image_at(c["tile"]):
			_draw_crate(ci, px2, float(look["open"]), float(c["lock"]) > 0.0)
		var occ: int = int(c["occupant"])
		if occ >= 0 and not as_hunter and actors[occ].inside():
			# Les chassés savent qui est dedans : deux yeux de la couleur du joueur.
			ci.draw_circle(px2.get_center() + Vector2(-9, 8), 6, actors[occ].color)
			ci.draw_circle(px2.get_center() + Vector2(9, 8), 6, actors[occ].color)
	# Cachette qui grince : « crac ! » au-dessus, vu de tous (c'est un bruit).
	for c3: Dictionary in cachettes:
		if float(c3["creak"]) > 0.0:
			var k3: float = float(c3["creak"]) / 0.9
			var p3: Vector2 = (c3["pos"] as Vector2) + Vector2(0, -map.tile * (0.8 + 0.4 * (1.0 - k3)))
			_draw_noise_bubble(ci, font, p3, "crac !", k3)
	# Gâteaux basques au sol (vus de tous, chasseur compris : ils attirent les chassés à découvert).
	for g2: Dictionary in gateaux:
		var gp: Vector2 = g2["pos"]
		var bob: float = sin(hunt_elapsed * 4.0 + gp.x) * 3.0
		GkDraw.ellipse(ci, gp + Vector2(0, 10), 20, 6, Color(0, 0, 0, 0.2))
		GkDraw.ellipse(ci, gp + Vector2(0, bob), 20, 13, Color("e7b45a"), 3.0)
		GkDraw.ellipse(ci, gp + Vector2(0, bob - 3), 13, 7, Color("f2cf7f"))
		for k7: int in 3:
			ci.draw_line(gp + Vector2(-8 + k7 * 8, bob - 7), gp + Vector2(-4 + k7 * 8, bob + 1), Color("b5772a"), 2.0)
		GkDraw.ellipse(ci, gp + Vector2(6, bob - 6), 4, 3, Color("c62828"), 1.5)
	# Mouettes posées (petits « v » blancs) ; envolées, elles montent en criant « kaio ! ».
	for m: Dictionary in mouettes:
		var mp: Vector2 = m["pos"]
		var fly: float = float(m["fly"])
		if float(m["away"]) <= 0.0:
			for k5: int in 3:
				_draw_gull(ci, mp + Vector2(-26 + k5 * 26, (k5 % 2) * 12), 1.0 if k5 != 1 else -1.0)
		elif fly > 0.0:
			var up: float = (1.5 - fly) * 70.0
			for k6: int in 3:
				var bp2: Vector2 = mp + Vector2(-24 + k6 * 24 + (1.5 - fly) * 20 * (k6 - 1), -up - k6 * 10)
				ci.draw_polyline(PackedVector2Array([bp2 + Vector2(-10, -4), bp2, bp2 + Vector2(10, -4)]),
					Color(1, 1, 1, fly / 1.5), 3.0, true)
			_draw_noise_bubble(ci, font, mp + Vector2(0, -map.tile * 0.9 - up * 0.5), "kaio !", fly / 1.5)
	# Pièges : visibles des chassés ; le chasseur ne les voit que tout près, dans sa vue.
	for t: Dictionary in traps:
		var p: Vector2 = t["pos"]
		if as_hunter and (p.distance_to(hunter.position) > GkRules.px("trap_seen_range") or not sees(hunter, p, 6.0)):
			continue
		ci.draw_circle(p, 18, Color(0.95, 0.75, 0.2, 0.55))
		for k: int in 4:
			var a: float = float(k) * PI / 4.0
			ci.draw_line(p - Vector2.from_angle(a) * 18, p + Vector2.from_angle(a) * 18, Color("5a3410"), 3.0)
	# Cône rouge du chasseur, vu des chassés et des fantômes.
	if not as_hunter and hunter and (phase == Phase.HUNT or phase == Phase.HIDE):
		var poly: PackedVector2Array = cone_polygon(hunter)
		ci.draw_colored_polygon(poly, Color(1, 0.15, 0.1, 0.22 if phase == Phase.HUNT else 0.1))
		ci.draw_polyline(poly, Color(1, 0.2, 0.15, 0.5), 2.0)
		ci.draw_arc(hunter.position, GkRules.px("near_radius"), 0, TAU, 32, Color(1, 0.2, 0.15, 0.45), 2.0)
	# Détection progressive : jauge, « ? » et « ! » au-dessus du chasseur (vus de tous), « ouf ! » d'un
	# chassé qui s'en tire (vu des chassés et des fantômes, et du chasseur s'il le voit).
	if GkRules.on("idee_detection") and hunter and phase == Phase.HUNT:
		_draw_alert(ci, font)
		for a4: GkActor in actors:
			if a4.ouf_t > 0.0 and a4.role == GkActor.Role.HIDER and a4.hidden_in < 0 \
					and (not as_hunter or bool(_seen.get(a4.id, false))):
				var k4: float = a4.ouf_t / OUF_S
				_draw_noise_bubble(ci, font, a4.position + Vector2(0, a4.name_y() - 20.0 - 30.0 * (1.0 - k4)), "ouf !",
					k4, Color("6fe08a"))
	# Onde de détection et silhouettes révélées.
	for r2: Dictionary in reveals:
		var left: float = float(r2["left"])
		if int(r2["id"]) == -2:
			if as_hunter or not local.is_hider():
				_draw_hint_arrow(ci, hunter.position, r2["dir"], left)
		elif int(r2["id"]) < 0:
			var k2: float = 1.0 - left / 0.6
			ci.draw_arc(r2["pos"], GkRules.px("detect_radius") * k2, 0, TAU, 64, Color(0.6, 0.85, 1.0, 1.0 - k2), 6.0)
		elif as_hunter or not local.is_hider():
			ci.draw_circle(r2["pos"], 26, Color(0.6, 0.85, 1.0, 0.5))
			ci.draw_arc(r2["pos"], 30, 0, TAU, 24, Color(0.6, 0.85, 1.0), 3.0)
	# Progression de la sortie.
	for a: GkActor in actors:
		if a.extract_t > 0.0 and a.role == GkActor.Role.HIDER and (not as_hunter or bool(_seen.get(a.id, false))):
			ci.draw_arc(a.position, a.radius + 14, -PI * 0.5, -PI * 0.5 + TAU * a.extract_t / GkRules.f("extract_hold"),
				32, Color("6fe08a"), 6.0)


## Caisse orange procédurale (cachette sans image) : le couvercle, sur le dessus, bascule vers
## l'arrière quand elle s'ouvre (`open` 0 → 1) et montre l'intérieur sombre.
func _draw_crate(ci: CanvasItem, r: Rect2, open: float, locked: bool) -> void:
	var ink: Color = Color("5a3410")
	var lid_h: float = r.size.y * LID_K
	ci.draw_rect(r, Color("e08a2e") if not locked else Color("8a6a4a"))
	ci.draw_rect(r, ink, false, 4.0)
	if open <= 0.01:
		ci.draw_line(r.position + Vector2(6, lid_h), Vector2(r.end.x - 6, r.position.y + lid_h), ink, 3.0)
		return
	# Intérieur sombre à la place du dessus, puis le couvercle levé derrière la charnière.
	var inside: Rect2 = Rect2(r.position + Vector2(5, 5), Vector2(r.size.x - 10, lid_h - 3))
	ci.draw_rect(inside, Color("2a1606").lerp(Color("e08a2e"), 1.0 - open))
	var up: float = r.size.y * LID_OPEN_K * open
	var lid: PackedVector2Array = [r.position + Vector2(-2, 2), Vector2(r.end.x + 2, r.position.y + 2),
		Vector2(r.end.x - 1, r.position.y - up), r.position + Vector2(1, -up)]
	ci.draw_colored_polygon(lid, Color("c46e1c"))
	lid.append(lid[0])
	ci.draw_polyline(lid, ink, 3.0)


## Mouette posée, de profil (`face` 1 vers la droite, -1 vers la gauche).
func _draw_gull(ci: CanvasItem, p: Vector2, face: float) -> void:
	GkDraw.ellipse(ci, p + Vector2(0, 12), 13, 4, Color(0, 0, 0, 0.18))
	ci.draw_line(p + Vector2(-3, 6), p + Vector2(-3, 12), Color("f6a91e"), 3.0)
	ci.draw_line(p + Vector2(3, 6), p + Vector2(3, 12), Color("f6a91e"), 3.0)
	GkDraw.ellipse(ci, p, 14, 9, Color.WHITE, 2.5)
	GkDraw.ellipse(ci, p + Vector2(-3 * face, -1), 9, 5, Color("aab4c0"), 2.0)
	GkDraw.ellipse(ci, p + Vector2(11 * face, -9), 7, 7, Color.WHITE, 2.5)
	GkDraw.poly(ci, PackedVector2Array([p + Vector2(16 * face, -10), p + Vector2(25 * face, -8),
		p + Vector2(16 * face, -6)]), Color("f6a91e"), 1.5)
	ci.draw_circle(p + Vector2(13 * face, -11), 1.8, GkDraw.INK)


## Bulle de bruit (grincement, mouettes) : texte cerné d'encre, qui s'efface avec `k` (1 → 0).
func _draw_noise_bubble(ci: CanvasItem, font: Font, at: Vector2, text: String, k: float,
		col: Color = Color("ffd34a"), fsize: int = 30) -> void:
	var a: float = clampf(k * 3.0, 0.0, 1.0)
	ci.draw_string_outline(font, at - Vector2(100, 0), text, HORIZONTAL_ALIGNMENT_CENTER, 200, fsize, 8,
		Color(GkDraw.INK, a))
	ci.draw_string(font, at - Vector2(100, 0), text, HORIZONTAL_ALIGNMENT_CENTER, 200, fsize, Color(col, a))


## Jauge de détection au-dessus du chasseur : barre jaune → rouge (la plus haute des jauges des
## chassés), « ? » qui gonfle dès detection_doute, « ! » rouge à la capture, « ? » gris qui retombe
## quand un chassé s'en tire.
func _draw_alert(ci: CanvasItem, font: Font) -> void:
	var head: Vector2 = hunter.position + Vector2(0, hunter.name_y() - 40.0)
	if alert_bang > 0.0:
		var k: float = alert_bang / ALERT_BANG_S
		var pop: int = int(64.0 + 24.0 * sin((1.0 - k) * PI))
		_draw_noise_bubble(ci, font, head + Vector2(0, 8), "!", k, Color("ff3b30"), pop)
		return
	var g: float = hunter_alert
	if g <= 0.0 and alert_lost <= 0.0:
		return
	if g > 0.0:
		var w: float = 76.0
		var r: Rect2 = Rect2(head + Vector2(-w * 0.5, 10), Vector2(w, 12))
		ci.draw_rect(r.grow(3), GkDraw.INK)
		ci.draw_rect(r, Color(1, 1, 1, 0.25))
		ci.draw_rect(Rect2(r.position, Vector2(w * clampf(g, 0.0, 1.0), r.size.y)),
			Color("ffd34a").lerp(Color("ff3b30"), clampf(g, 0.0, 1.0)))
	if g >= GkRules.f("detection_doute"):
		var pulse: float = 1.0 + 0.15 * sin(hunt_elapsed * 18.0)
		_draw_noise_bubble(ci, font, head, "?", 1.0, Color("ffd34a").lerp(Color("ff3b30"), g), int(44.0 * pulse * (0.8 + 0.4 * g)))
	elif alert_lost > 0.0:
		var k2: float = alert_lost / ALERT_LOST_S
		_draw_noise_bubble(ci, font, head + Vector2(0, 10.0 * (1.0 - k2)), "?", k2, Color("c8ccd4"), 40)


## Flèche d'indice de l'onde : part du chasseur dans la direction du chassé le plus proche.
func _draw_hint_arrow(ci: CanvasItem, from: Vector2, dir: Vector2, left: float) -> void:
	var a: float = clampf(left, 0.0, 1.0)
	var c: Color = Color(0.6, 0.85, 1.0, a)
	var p0: Vector2 = from + dir * map.tile * 1.4
	var p1: Vector2 = from + dir * map.tile * 3.2
	ci.draw_line(p0, p1, c, 8.0, true)
	var side: Vector2 = dir.orthogonal() * map.tile * 0.45
	ci.draw_colored_polygon(PackedVector2Array([p1 + dir * map.tile * 0.7, p1 + side, p1 - side]), c)
