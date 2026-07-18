class_name ChallengeBase
extends Node2D
## Cycle de vie commun à toutes les épreuves (cf. CLAUDE.md §5.1).
##
## Une épreuve concrète étend cette classe, surcharge les hooks _on_begin /
## _on_finish et les gestes (_on_tapped, _on_drag_*). Elle ne connaît que
## cette base et les autoloads — jamais les autres épreuves.

signal finished(score: int)

@export var challenge_id: StringName      # "beach_run", "surf", ...
@export var time_limit: float = 0.0        # 0 = sans limite

var _score: int = 0
var _running: bool = false
var _time_left: float = 0.0

@onready var _score_label: Label = %ScoreLabel
@onready var _time_label: Label = %TimeLabel
@onready var _touch: TouchInput = %Touch


func _ready() -> void:
	_touch.tapped.connect(_on_touch_tapped)
	_touch.drag_started.connect(_on_touch_drag_started)
	_touch.drag_updated.connect(_on_touch_drag_updated)
	_touch.drag_ended.connect(_on_touch_drag_ended)
	_update_hud()
	begin()


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
