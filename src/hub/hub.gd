extends Control
## Hub — carte de Biarritz (sélection de lieu).
##
## 6 zones cliquables (placeholders en attendant la vraie carte, Phase 4).
## Affiche le cumul, le meilleur score par lieu, et l'état du Phare
## (verrouillé tant que le cumul n'a pas franchi le seuil).

const _PLACES: Array[Dictionary] = [
	{"id": &"beach_run", "title": "Grande Plage", "hint": "Course sur le sable"},
	{"id": &"surf", "title": "Côte des Basques", "hint": "Surf"},
	{"id": &"fishing", "title": "Port des Pêcheurs", "hint": "Pêche"},
	{"id": &"rock_crossing", "title": "Rocher de la Vierge", "hint": "Traversée"},
	{"id": &"espadrille", "title": "Port Vieux", "hint": "Lancer d'espadrille"},
	{"id": &"lighthouse", "title": "Le Phare", "hint": "Ascension"},
]

@onready var _player_label: Label = %PlayerLabel
@onready var _cumulative_label: Label = %CumulativeLabel
@onready var _places_grid: GridContainer = %PlacesGrid
@onready var _leaderboard_button: Button = %LeaderboardButton
@onready var _change_player_button: Button = %ChangePlayerButton


func _ready() -> void:
	_player_label.text = "%s — groupe %s" % [GameState.pseudo, GameState.group_code]
	_cumulative_label.text = "Cumul : %d" % ScoreManager.cumulative()
	_leaderboard_button.pressed.connect(_on_leaderboard_button_pressed)
	_change_player_button.pressed.connect(_on_change_player_button_pressed)
	_build_place_buttons()
	AudioManager.play_music(&"hub")


func _build_place_buttons() -> void:
	var lighthouse_unlocked: bool = GameState.is_lighthouse_unlocked()
	for place: Dictionary in _PLACES:
		var id: StringName = place["id"]
		var button: Button = Button.new()
		button.custom_minimum_size = Vector2(340, 130)
		button.add_theme_font_size_override(&"font_size", 26)
		var best: int = ScoreManager.best(id)
		if id == &"lighthouse" and not lighthouse_unlocked:
			button.text = "%s\n🔒 Cumul %d requis" % [place["title"], Balance.LIGHTHOUSE_UNLOCK_THRESHOLD]
			button.disabled = true
		else:
			button.text = "%s\n%s — best %d" % [place["title"], place["hint"], best]
			button.pressed.connect(_on_place_button_pressed.bind(id))
		_places_grid.add_child(button)


func _on_place_button_pressed(id: StringName) -> void:
	SceneRouter.goto_challenge(id)


func _on_leaderboard_button_pressed() -> void:
	SceneRouter.goto_leaderboard()


func _on_change_player_button_pressed() -> void:
	GameState.clear_session()
	SceneRouter.goto_pseudo_entry()
