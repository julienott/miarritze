extends Control
## Hub — carte illustrée de Biarritz. Chaque lieu est un bouton posé sur
## son monument (positions calées sur bg_hub, échelle x4).

const _PLACES: Array[Dictionary] = [
	{"id": &"beach_run", "title": "Grande Plage", "pos": Vector2(880, 150)},
	{"id": &"surf", "title": "Côte des Basques", "pos": Vector2(520, 660)},
	{"id": &"fishing", "title": "Port des Pêcheurs", "pos": Vector2(430, 430)},
	{"id": &"rock_crossing", "title": "Rocher de la Vierge", "pos": Vector2(300, 520)},
	{"id": &"espadrille", "title": "Port Vieux", "pos": Vector2(430, 600)},
	{"id": &"lighthouse", "title": "Le Phare", "pos": Vector2(470, 280)},
]

@onready var _player_label: Label = %PlayerLabel
@onready var _cumulative_label: Label = %CumulativeLabel
@onready var _leaderboard_button: Button = %LeaderboardButton
@onready var _change_player_button: Button = %ChangePlayerButton


func _ready() -> void:
	_player_label.text = "%s — groupe %s" % [GameState.pseudo, GameState.group_code]
	_cumulative_label.text = "Cumul : %d / %d pour le Phare" % [
		ScoreManager.cumulative(), Balance.LIGHTHOUSE_UNLOCK_THRESHOLD]
	_leaderboard_button.pressed.connect(_on_leaderboard_button_pressed)
	_change_player_button.pressed.connect(_on_change_player_button_pressed)
	_build_place_buttons()
	AudioManager.play_music(&"menu")   # le thème Hegoak continue sur la carte


func _build_place_buttons() -> void:
	var lighthouse_unlocked: bool = GameState.is_lighthouse_unlocked()
	for place: Dictionary in _PLACES:
		var id: StringName = place["id"]
		var button: Button = Button.new()
		button.add_theme_font_size_override(&"font_size", 14)
		var best: int = ScoreManager.best(id)
		if id == &"lighthouse" and not lighthouse_unlocked:
			button.text = "%s (a debloquer)" % place["title"]
			button.disabled = true
		else:
			button.text = place["title"] if best == 0 else "%s — %d" % [place["title"], best]
			button.pressed.connect(_on_place_button_pressed.bind(id))
		add_child(button)
		# centre le bouton sur son monument
		await get_tree().process_frame
		button.position = (place["pos"] as Vector2) - button.size * 0.5


func _on_place_button_pressed(id: StringName) -> void:
	SceneRouter.goto_challenge(id)


func _on_leaderboard_button_pressed() -> void:
	SceneRouter.goto_leaderboard()


func _on_change_player_button_pressed() -> void:
	GameState.clear_session()
	SceneRouter.goto_pseudo_entry()
