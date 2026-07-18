class_name Fishing
extends ChallengeBase
## Port des Pêcheurs — pêche (cf. DESIGN.md §4.3).
## On ferre au "!" puis on gère la tension : maintenir pour remonter
## (la tension monte), relâcher pour la faire redescendre. Jauge
## vert / orange / rouge très lisible. FSM : Cast, Bite, Reel, Slack,
## Snap, Landed.

@export var cast_duration: float = 0.8
@export var bite_delay_min: float = 0.6
@export var bite_delay_max: float = 2.2
@export var bite_window: float = 1.0          # temps pour ferrer après le "!"
@export var reel_rate: float = 0.22           # progression/s en remontant
@export var slack_rate: float = 0.06          # progression perdue/s relâché
@export var tension_up_rate: float = 0.55     # tension/s en remontant (× résistance)
@export var tension_down_rate: float = 0.65   # tension/s relâché
@export var red_zone: float = 0.85            # au-delà : danger
@export var orange_zone: float = 0.6
@export var snap_grace: float = 0.5           # secondes en rouge avant la casse

## Types de poissons : taille, résistance, points (placeholder Phase 4 : sprites).
const _FISH_TYPES: Array[Dictionary] = [
	{"name": "Sardine", "resist": 0.7, "points": 15, "weight": 5.0},
	{"name": "Dorade", "resist": 1.0, "points": 30, "weight": 3.0},
	{"name": "Thon", "resist": 1.45, "points": 60, "weight": 1.5},
	{"name": "Thon doré", "resist": 1.7, "points": 120, "weight": 0.3},
]

var _fsm: StateMachine
var _fish: Dictionary = {}
var _progress: float = 0.0
var _tension: float = 0.0
var _status_label: Label
var _tension_bar: ColorRect
var _tension_fill: ColorRect
var _progress_bar: ColorRect
var _progress_fill: ColorRect


func _on_begin() -> void:
	_status_label = Label.new()
	_status_label.add_theme_font_size_override(&"font_size", 52)
	_status_label.position = Vector2(440.0, 240.0)
	add_child(_status_label)

	_tension_bar = _make_bar(Vector2(340.0, 620.0), Vector2(600.0, 36.0), Color(0.15, 0.15, 0.15))
	_tension_fill = _make_bar(Vector2(343.0, 623.0), Vector2(0.0, 30.0), Color(0.3, 0.85, 0.3))
	_progress_bar = _make_bar(Vector2(340.0, 570.0), Vector2(600.0, 24.0), Color(0.15, 0.15, 0.25))
	_progress_fill = _make_bar(Vector2(343.0, 573.0), Vector2(0.0, 18.0), Color(0.4, 0.7, 1.0))

	_fsm = StateMachine.new(self)
	_fsm.add_state(&"cast", CastState.new())
	_fsm.add_state(&"bite", BiteState.new())
	_fsm.add_state(&"reel", ReelState.new())
	_fsm.add_state(&"slack", SlackState.new())
	_fsm.add_state(&"snap", SnapState.new())
	_fsm.add_state(&"landed", LandedState.new())
	_fsm.transition_to(&"cast")


func _on_tapped(position: Vector2) -> void:
	_fsm.handle_tap(position)


func _physics_process(delta: float) -> void:
	if not is_running():
		return
	_fsm.update(delta)
	_update_bars()


func _pick_fish() -> void:
	var total: float = 0.0
	for fish: Dictionary in _FISH_TYPES:
		total += fish["weight"]
	var roll: float = randf() * total
	for fish: Dictionary in _FISH_TYPES:
		roll -= fish["weight"]
		if roll <= 0.0:
			_fish = fish
			return
	_fish = _FISH_TYPES[0]


func _update_bars() -> void:
	var fighting: bool = _fsm.current_name == &"reel" or _fsm.current_name == &"slack"
	_tension_bar.visible = fighting
	_tension_fill.visible = fighting
	_progress_bar.visible = fighting
	_progress_fill.visible = fighting
	if not fighting:
		return
	_tension_fill.size.x = 594.0 * clampf(_tension, 0.0, 1.0)
	if _tension >= red_zone:
		_tension_fill.color = Color(0.9, 0.2, 0.15)
	elif _tension >= orange_zone:
		_tension_fill.color = Color(0.95, 0.65, 0.15)
	else:
		_tension_fill.color = Color(0.3, 0.85, 0.3)
	_progress_fill.size.x = 594.0 * clampf(_progress, 0.0, 1.0)


func _make_bar(bar_position: Vector2, size: Vector2, color: Color) -> ColorRect:
	var bar: ColorRect = ColorRect.new()
	bar.position = bar_position
	bar.size = size
	bar.color = color
	bar.visible = false
	add_child(bar)
	return bar


func set_status(text: String) -> void:
	_status_label.text = text


# --- États ---

class CastState extends State:
	var _time_left: float = 0.0

	func enter(_previous: StringName) -> void:
		var fishing: Fishing = machine.owner_node as Fishing
		_time_left = fishing.cast_duration
		fishing.set_status("On lance la ligne…")

	func update(delta: float) -> void:
		_time_left -= delta
		if _time_left <= 0.0:
			machine.transition_to(&"bite")


class BiteState extends State:
	var _wait_left: float = 0.0
	var _window_left: float = 0.0
	var _biting: bool = false

	func enter(_previous: StringName) -> void:
		var fishing: Fishing = machine.owner_node as Fishing
		_wait_left = randf_range(fishing.bite_delay_min, fishing.bite_delay_max)
		_biting = false
		fishing.set_status("…")

	func update(delta: float) -> void:
		var fishing: Fishing = machine.owner_node as Fishing
		if not _biting:
			_wait_left -= delta
			if _wait_left <= 0.0:
				_biting = true
				_window_left = fishing.bite_window
				fishing.set_status("❗ ÇA MORD !")
				AudioManager.sfx(&"bite")
		else:
			_window_left -= delta
			if _window_left <= 0.0:
				fishing.set_status("Trop tard…")
				machine.transition_to(&"cast")

	func handle_tap(_position: Vector2) -> void:
		if _biting:
			var fishing: Fishing = machine.owner_node as Fishing
			fishing._pick_fish()
			fishing._progress = 0.0
			fishing._tension = 0.2
			machine.transition_to(&"reel")


class ReelState extends State:
	var _red_time: float = 0.0

	func enter(_previous: StringName) -> void:
		var fishing: Fishing = machine.owner_node as Fishing
		if _previous != &"slack":
			_red_time = 0.0
		fishing.set_status("On remonte ! (%s)" % fishing._fish["name"])

	func update(delta: float) -> void:
		var fishing: Fishing = machine.owner_node as Fishing
		if not fishing._is_touch_pressed():
			machine.transition_to(&"slack")
			return
		var resist: float = fishing._fish["resist"]
		fishing._progress += fishing.reel_rate / resist * delta
		fishing._tension += fishing.tension_up_rate * resist * delta
		if fishing._progress >= 1.0:
			machine.transition_to(&"landed")
			return
		if fishing._tension >= fishing.red_zone:
			_red_time += delta
			if fishing._tension >= 1.0 or _red_time >= fishing.snap_grace:
				machine.transition_to(&"snap")
		else:
			_red_time = 0.0


class SlackState extends State:
	func enter(_previous: StringName) -> void:
		var fishing: Fishing = machine.owner_node as Fishing
		fishing.set_status("La ligne se détend…")

	func update(delta: float) -> void:
		var fishing: Fishing = machine.owner_node as Fishing
		if fishing._is_touch_pressed():
			machine.transition_to(&"reel")
			return
		fishing._tension = maxf(fishing._tension - fishing.tension_down_rate * delta, 0.0)
		fishing._progress = maxf(fishing._progress - fishing.slack_rate * delta, 0.0)


class SnapState extends State:
	var _time_left: float = 0.0

	func enter(_previous: StringName) -> void:
		var fishing: Fishing = machine.owner_node as Fishing
		_time_left = 1.0
		fishing.set_status("💥 La ligne a cassé !")
		AudioManager.sfx(&"snap")

	func update(delta: float) -> void:
		_time_left -= delta
		if _time_left <= 0.0:
			machine.transition_to(&"cast")


class LandedState extends State:
	var _time_left: float = 0.0

	func enter(_previous: StringName) -> void:
		var fishing: Fishing = machine.owner_node as Fishing
		_time_left = 1.2
		var points: int = fishing._fish["points"]
		fishing.add_score(points)
		fishing.set_status("🐟 %s ! +%d" % [fishing._fish["name"], points])
		AudioManager.sfx(&"landed")

	func update(delta: float) -> void:
		_time_left -= delta
		if _time_left <= 0.0:
			machine.transition_to(&"cast")
