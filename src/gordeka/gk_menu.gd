extends Control
## Accueil du prototype (SPEC-GORDEKA §6.1) : jouer contre l'IA, avec le nombre de joueurs,
## la difficulté et sa couleur. Le jeu en ligne viendra au jalon 4.

const LEVELS: PackedStringArray = ["facile", "normal", "malin"]
const LEVEL_NAMES: PackedStringArray = ["Facile", "Normal", "Malin"]

var _players: Label
var _level: Label
var _color: Label
var _swatch: ColorRect


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg: ColorRect = ColorRect.new()
	bg.color = Color("1f3b57")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var col: VBoxContainer = VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override(&"separation", 18)
	center.add_child(col)
	col.add_child(_label("MIARRITZE GORDEKA", 64, Color("ffd34a")))
	col.add_child(_label("Cache-cache au Port des Pêcheurs — prototype", 26, Color(1, 1, 1, 0.75)))
	var cfg: Dictionary = GkGame.config
	var profiles: Node = get_node_or_null("/root/Profiles")
	if profiles and profiles.has_method("active"):
		var p: Dictionary = profiles.active()
		if str(p.get("pseudo", "")) != "":
			cfg["name"] = str(p["pseudo"])
	_players = _cycler(col, func(d: int) -> void: cfg["players"] = clampi(int(cfg["players"]) + d, 2, 8))
	_level = _cycler(col, func(d: int) -> void:
		cfg["level"] = LEVELS[(LEVELS.find(str(cfg["level"])) + d + LEVELS.size()) % LEVELS.size()])
	_color = _cycler(col, func(d: int) -> void: cfg["color"] = (int(cfg["color"]) + d + 12) % 12)
	_swatch = ColorRect.new()
	_swatch.custom_minimum_size = Vector2(44, 44)
	_color.get_parent().add_child(_swatch)
	var play: Button = Button.new()
	play.text = "Jouer contre l'IA"
	play.custom_minimum_size = Vector2(420, 84)
	play.add_theme_font_size_override(&"font_size", 36)
	play.pressed.connect(func() -> void: _start(""))
	col.add_child(play)
	var online: Button = Button.new()
	online.text = "En ligne avec les copains (bientôt)"
	online.disabled = true
	online.custom_minimum_size = Vector2(420, 60)
	online.add_theme_font_size_override(&"font_size", 24)
	col.add_child(online)
	# TEMPORAIRE, debug (Julien, 2026-10-20) : visite de la carte en chassé ou en chasseur (GkGame.visite).
	var dbg: HBoxContainer = HBoxContainer.new()
	dbg.alignment = BoxContainer.ALIGNMENT_CENTER
	dbg.add_theme_constant_override(&"separation", 12)
	for spec: Array in [["DEBUG · Visite : chassé", "chasse"], ["DEBUG · Visite : chasseur", "chasseur"]]:
		var b: Button = Button.new()
		b.text = str(spec[0])
		b.custom_minimum_size = Vector2(300, 52)
		b.add_theme_font_size_override(&"font_size", 22)
		b.add_theme_color_override(&"font_color", Color("ffd34a"))
		var mode: String = str(spec[1])
		b.pressed.connect(func() -> void: _start(mode))
		dbg.add_child(b)
	col.add_child(dbg)
	col.add_child(_label("Bouger : flèches, ZQSD, stick ou pouce gauche — Action : Espace, A ou pouce droit", 20, Color(1, 1, 1, 0.6)))
	_refresh()
	play.grab_focus.call_deferred()


func _start(visite: String) -> void:
	GkGame.config["visite"] = visite
	get_tree().change_scene_to_file("res://src/gordeka/gk_game.tscn")


func _label(text: String, size: int, color: Color) -> Label:
	var l: Label = Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override(&"font_size", size)
	l.add_theme_color_override(&"font_color", color)
	return l


func _cycler(parent: Container, change: Callable) -> Label:
	var row: HBoxContainer = HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override(&"separation", 16)
	var label: Label = _label("", 30, Color.WHITE)
	label.custom_minimum_size = Vector2(380, 0)
	for d: int in [-1, 1]:
		var b: Button = Button.new()
		b.text = "<" if d < 0 else ">"
		b.custom_minimum_size = Vector2(64, 56)
		b.add_theme_font_size_override(&"font_size", 30)
		b.pressed.connect(func() -> void:
			change.call(d)
			_refresh())
		row.add_child(b)
		if d < 0:
			row.add_child(label)
	parent.add_child(row)
	return label


func _refresh() -> void:
	var cfg: Dictionary = GkGame.config
	_players.text = "Joueurs : %d (toi + %d IA)" % [int(cfg["players"]), int(cfg["players"]) - 1]
	_level.text = "IA : %s" % LEVEL_NAMES[LEVELS.find(str(cfg["level"]))]
	var names: Array = GkRules.data().get("color_names", [])
	_color.text = "Couleur : %s" % str(names[int(cfg["color"]) % names.size()])
	_swatch.color = GkRules.color(int(cfg["color"]))
