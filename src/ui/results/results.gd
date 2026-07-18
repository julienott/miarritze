extends Control
## Écran de fin d'épreuve : score obtenu, meilleur score, cumul.
## Lit le payload de navigation posé par SceneRouter.goto_results.

const _TITLES: Dictionary = {
	&"beach_run": "Grande Plage",
	&"surf": "Côte des Basques",
	&"fishing": "Port des Pêcheurs",
	&"rock_crossing": "Rocher de la Vierge",
	&"espadrille": "Port Vieux",
	&"lighthouse": "Le Phare",
}

@onready var _title_label: Label = %TitleLabel
@onready var _score_label: Label = %ScoreLabel
@onready var _best_label: Label = %BestLabel
@onready var _cumulative_label: Label = %CumulativeLabel
@onready var _replay_button: Button = %ReplayButton
@onready var _hub_button: Button = %HubButton
@onready var _leaderboard_button: Button = %LeaderboardButton


func _ready() -> void:
	var challenge: StringName = SceneRouter.last_challenge
	_title_label.text = str(_TITLES.get(challenge, String(challenge)))
	_score_label.text = str(SceneRouter.last_score)
	if SceneRouter.last_was_best:
		_best_label.text = "🎉 Nouveau record !"
	else:
		_best_label.text = "Ton record : %d" % ScoreManager.best(challenge)
	_cumulative_label.text = "Cumul : %d" % ScoreManager.cumulative()
	_replay_button.pressed.connect(_on_replay_button_pressed)
	_hub_button.pressed.connect(_on_hub_button_pressed)
	_leaderboard_button.pressed.connect(_on_leaderboard_button_pressed)


func _on_replay_button_pressed() -> void:
	SceneRouter.goto_challenge(SceneRouter.last_challenge)


func _on_hub_button_pressed() -> void:
	SceneRouter.goto_hub()


func _on_leaderboard_button_pressed() -> void:
	SceneRouter.goto_leaderboard(SceneRouter.last_challenge)
