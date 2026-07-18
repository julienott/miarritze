class_name ChallengeBase
extends Node2D
## Cycle de vie commun à toutes les épreuves (cf. CLAUDE.md §5.1).
##
## v2 : chaque épreuve commence par une CARTE D'INTRO (le beau décor issu
## des photos + titre, lieu, consignes, Démarrer / Retour). Au démarrage,
## le décor bascule sur un fond de gameplay lisible (play_bg) et l'épreuve
## dispose de 3 VIES (cœurs) — plus de vie = fin de l'épreuve.

signal finished(score: int)

@export var challenge_id: StringName      # "beach_run", "surf", ...
@export var time_limit: float = 0.0        # 0 = sans limite (démarre au start)

@export_group("Intro")
@export var intro_title: String = ""
@export var intro_place: String = ""
@export_multiline var intro_text: String = ""
## Fond de gameplay ("" = l'épreuve gère son propre décor).
@export var play_bg: String = ""

@export_group("Vies")
@export var max_lives: int = 3

var _score: int = 0
var _running: bool = false
var _time_left: float = 0.0
var _lives: int = 3
var _intro_layer: CanvasLayer = null
var _hearts: Array[TextureRect] = []

@onready var _score_label: Label = %ScoreLabel
@onready var _time_label: Label = %TimeLabel
@onready var _hud: CanvasLayer = _score_label.get_parent() as CanvasLayer
@onready var _touch: TouchInput = %Touch


func _ready() -> void:
	_touch.tapped.connect(_on_touch_tapped)
	_touch.drag_started.connect(_on_touch_drag_started)
	_touch.drag_updated.connect(_on_touch_drag_updated)
	_touch.drag_ended.connect(_on_touch_drag_ended)
	_build_hearts()
	_hud.visible = false
	_show_intro()


# --- Intro ---

func _show_intro() -> void:
	_intro_layer = CanvasLayer.new()
	add_child(_intro_layer)

	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0.09, 0.06, 0.1, 0.35)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_intro_layer.add_child(dim)

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_intro_layer.add_child(center)

	var panel: PanelContainer = PanelContainer.new()
	center.add_child(panel)
	var box: VBoxContainer = VBoxContainer.new()
	box.custom_minimum_size = Vector2(760.0, 0.0)
	box.add_theme_constant_override(&"separation", 14)
	panel.add_child(box)

	var title: Label = Label.new()
	title.text = intro_title
	title.add_theme_font_size_override(&"font_size", 34)
	title.add_theme_color_override(&"font_color", Color(0.97, 0.95, 0.89))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var place: Label = Label.new()
	place.text = intro_place
	place.add_theme_font_size_override(&"font_size", 18)
	place.add_theme_color_override(&"font_color", Color(0.95, 0.78, 0.24))
	place.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(place)

	var text: Label = Label.new()
	text.text = intro_text
	text.add_theme_font_size_override(&"font_size", 16)
	text.add_theme_color_override(&"font_color", Color(0.97, 0.95, 0.89))
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(text)

	var buttons: HBoxContainer = HBoxContainer.new()
	buttons.add_theme_constant_override(&"separation", 18)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(buttons)

	var back_button: Button = Button.new()
	back_button.text = "← Carte"
	back_button.custom_minimum_size = Vector2(220.0, 64.0)
	back_button.pressed.connect(SceneRouter.goto_hub)
	buttons.add_child(back_button)

	var start_button: Button = Button.new()
	start_button.text = "C'est parti !"
	start_button.custom_minimum_size = Vector2(280.0, 64.0)
	start_button.pressed.connect(_on_start_pressed)
	buttons.add_child(start_button)


func _on_start_pressed() -> void:
	_intro_layer.queue_free()
	_intro_layer = null
	_swap_to_play_background()
	_hud.visible = true
	begin()


func _swap_to_play_background() -> void:
	var bg: Node = get_node_or_null("Bg")
	if bg == null:
		return
	if play_bg == "":
		bg.queue_free()
	elif bg is PixelBg:
		(bg as PixelBg).switch_to(play_bg)


# --- Vies ---

func _build_hearts() -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	row.position = Vector2(584.0, 14.0)
	_hud.add_child(row)
	_lives = max_lives
	for i: int in max_lives:
		var heart: TextureRect = TextureRect.new()
		heart.texture = load("res://assets/sprites/heart.png")
		heart.custom_minimum_size = Vector2(32.0, 28.0)
		heart.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		heart.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		row.add_child(heart)
		_hearts.append(heart)


## Retire une vie (feedback inclus). À 0, l'épreuve se termine.
func lose_life() -> void:
	if not _running or _lives <= 0:
		return
	_lives -= 1
	_hearts[_lives].texture = load("res://assets/sprites/heart_empty.png")
	AudioManager.sfx(&"hit")
	if _lives <= 0:
		end()


func lives_left() -> int:
	return _lives


# --- Cycle de vie ---

func begin() -> void:
	_score = 0
	_running = true
	_time_left = time_limit
	AudioManager.play_music(challenge_id)
	_on_begin()
	_update_hud()


func add_score(points: int) -> void:
	_score += points
	_score = maxi(_score, 0)
	_update_hud()


func score() -> int:
	return _score


func is_running() -> bool:
	return _running


func end() -> void:
	if not _running:
		return
	_running = false
	_on_finish()
	var is_best: bool = ScoreManager.submit_local(challenge_id, _score)
	if is_best:
		LeaderboardClient.post_score(challenge_id, _score)
	finished.emit(_score)
	SceneRouter.goto_results(challenge_id, _score, is_best)


func _process(delta: float) -> void:
	if not _running or time_limit <= 0.0:
		return
	_time_left -= delta
	if _time_left <= 0.0:
		_time_left = 0.0
		_update_hud()
		end()
	else:
		_update_hud()


# --- Hooks à surcharger par l'épreuve concrète ---

func _on_begin() -> void:
	pass


func _on_finish() -> void:
	pass


func _on_tapped(_position: Vector2) -> void:
	pass


func _on_drag_started(_position: Vector2) -> void:
	pass


func _on_drag_updated(_position: Vector2, _vector: Vector2) -> void:
	pass


func _on_drag_ended(_position: Vector2, _vector: Vector2) -> void:
	pass


# --- Interne ---

func _on_touch_tapped(position: Vector2) -> void:
	if _running:
		_on_tapped(position)


func _on_touch_drag_started(position: Vector2) -> void:
	if _running:
		_on_drag_started(position)


func _on_touch_drag_updated(position: Vector2, vector: Vector2) -> void:
	if _running:
		_on_drag_updated(position, vector)


func _on_touch_drag_ended(position: Vector2, vector: Vector2) -> void:
	if _running:
		_on_drag_ended(position, vector)


func _update_hud() -> void:
	_score_label.text = str(_score)
	if time_limit > 0.0:
		_time_label.text = str(ceili(_time_left))
	else:
		_time_label.text = ""


## Le doigt est-il maintenu (utile aux épreuves à pression continue).
func _is_touch_pressed() -> bool:
	return _touch.is_pressed()
