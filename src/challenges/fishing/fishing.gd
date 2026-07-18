class_name Fishing
extends ChallengeBase
## Port des Pêcheurs — pêche (cf. DESIGN.md §4.3).
## On ferre au "!" puis on gère la tension : maintenir pour remonter,
## relâcher pour la faire redescendre. Jauge vert / orange / rouge.
## FSM : Cast, Bite, Reel, Slack, Snap, Landed.

const _DOCK_Y: float = 412.0
const _LOUIS_X: float = 210.0
const _BOBBER_HOME: Vector2 = Vector2(430.0, 560.0)

@export var cast_duration: float = 0.8
@export var bite_delay_min: float = 0.6
@export var bite_delay_max: float = 2.2
@export var bite_window: float = 1.0
@export var reel_rate: float = 0.22
@export var slack_rate: float = 0.06
@export var tension_up_rate: float = 0.55
@export var tension_down_rate: float = 0.65
@export var red_zone: float = 0.85
@export var orange_zone: float = 0.6
@export var snap_grace: float = 0.5

## Types de poissons : résistance, points, rareté, sprite.
const _FISH_TYPES: Array[Dictionary] = [
	{"name": "Sardine", "resist": 0.7, "points": 15, "weight": 5.0, "tex": "fish_sardine"},
	{"name": "Dorade", "resist": 1.0, "points": 30, "weight": 3.0, "tex": "fish_dorade"},
	{"name": "Thon", "resist": 1.45, "points": 60, "weight": 1.5, "tex": "fish_thon"},
	{"name": "Thon doré", "resist": 1.7, "points": 120, "weight": 0.3, "tex": "fish_dore"},
]

var _fsm: StateMachine
var _fish: Dictionary = {}
var _progress: float = 0.0
var _tension: float = 0.0
var _player: LouisSprite
var _bobber: Sprite2D
var _line: Line2D
var _caught_sprite: Sprite2D = null
var _status_label: Label
var _tension_bar: ColorRect
var _tension_fill: ColorRect
var _progress_bar: ColorRect
var _progress_fill: ColorRect
var _bob_time: float = 0.0


func _on_begin() -> void:
	_player = LouisSprite.new()
	_player.position = Vector2(_LOUIS_X, _DOCK_Y - LouisSprite.FEET_Y)
	add_child(_player)
	_player.play(&"fish")

	_line = Line2D.new()
	_line.width = 3.0
	_line.default_color = Color(0.97, 0.95, 0.89, 0.7)
	add_child(_line)

	_bobber = SpriteUtil.sprite("bobber")
	_bobber.position = _BOBBER_HOME
	add_child(_bobber)

	_status_label = Label.new()
	_status_label.add_theme_font_size_override(&"font_size", 36)
	_status_label.position = Vector2(400.0, 200.0)
	add_child(_status_label)

	_tension_bar = _make_bar(Vector2(336.0, 636.0), Vector2(608.0, 44.0), Color(0.14, 0.08, 0.12, 0.9))
	_tension_fill = _make_bar(Vector2(342.0, 642.0), Vector2(0.0, 32.0), Color(0.3, 0.85, 0.3))
	_progress_bar = _make_bar(Vector2(336.0, 586.0), Vector2(608.0, 32.0), Color(0.14, 0.08, 0.12, 0.9))
	_progress_fill = _make_bar(Vector2(342.0, 592.0), Vector2(0.0, 20.0), Color(0.4, 0.7, 1.0))

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
	_bob_time += delta
	_fsm.update(delta)
	_update_visuals()


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


func _update_visuals() -> void:
	var fighting: bool = _fsm.current_name == &"reel" or _fsm.current_name == &"slack"
	for bar: ColorRect in [_tension_bar, _tension_fill, _progress_bar, _progress_fill]:
		bar.visible = fighting
	if fighting:
		_tension_fill.size.x = 596.0 * clampf(_tension, 0.0, 1.0)
		if _tension >= red_zone:
			_tension_fill.color = Color(0.9, 0.2, 0.15)
		elif _tension >= orange_zone:
			_tension_fill.color = Color(0.95, 0.65, 0.15)
		else:
			_tension_fill.color = Color(0.3, 0.85, 0.3)
		_progress_fill.size.x = 596.0 * clampf(_progress, 0.0, 1.0)
		# le bouchon se rapproche du ponton avec la progression
		_bobber.position = _BOBBER_HOME.lerp(Vector2(290.0, 490.0), _progress)
	else:
		_bobber.position = _BOBBER_HOME + Vector2(0.0, 3.0 * sin(_bob_time * 2.0))
	# fil de pêche : de la canne au bouchon
	_line.points = PackedVector2Array([
		_player.position + Vector2(58.0, 34.0),
		_bobber.position + Vector2(12.0, 4.0),
	])


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


func show_catch() -> void:
	_caught_sprite = SpriteUtil.sprite(_fish["tex"])
	_caught_sprite.position = _player.position + Vector2(70.0, -30.0)
	add_child(_caught_sprite)


func hide_catch() -> void:
	if _caught_sprite != null:
		_caught_sprite.queue_free()
		_caught_sprite = null


# --- États ---

class CastState extends State:
	var _time_left: float = 0.0

	func enter(_previous: StringName) -> void:
		var fishing: Fishing = machine.owner_node as Fishing
		_time_left = fishing.cast_duration
		fishing.hide_catch()
		fishing._bobber.visible = false
		fishing.set_status("On lance la ligne…")

	func update(delta: float) -> void:
		var fishing: Fishing = machine.owner_node as Fishing
		_time_left -= delta
		if _time_left <= 0.0:
			fishing._bobber.visible = true
			AudioManager.sfx(&"splash")
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
				fishing.set_status("ÇA MORD ! TAPE !")
				AudioManager.sfx(&"bite")
		else:
			# le bouchon s'agite frénétiquement
			fishing._bobber.position += Vector2(0.0, 4.0 * sin(_window_left * 40.0))
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

	func enter(previous: StringName) -> void:
		var fishing: Fishing = machine.owner_node as Fishing
		if previous != &"slack":
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
		fishing.set_status("Oh non, la ligne a casse !")
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
		fishing.show_catch()
		fishing.set_status("%s ! +%d" % [fishing._fish["name"], points])
		AudioManager.sfx(&"landed")

	func update(delta: float) -> void:
		var fishing: Fishing = machine.owner_node as Fishing
		if fishing._caught_sprite != null:
			fishing._caught_sprite.position.y -= 30.0 * delta
		_time_left -= delta
		if _time_left <= 0.0:
			machine.transition_to(&"cast")
