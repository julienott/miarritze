extends Control
## Tableaux de classement : par épreuve et au cumul (cf. DESIGN.md §5.2).
## Lit l'API via LeaderboardClient ; portée = groupe de GameState.

const _TABS: Array[Dictionary] = [
	{"id": &"", "title": "Cumul"},
	{"id": &"beach_run", "title": "Grande Plage"},
	{"id": &"surf", "title": "Côte des Basques"},
	{"id": &"fishing", "title": "Port des Pêcheurs"},
	{"id": &"rock_crossing", "title": "Rocher de la Vierge"},
	{"id": &"espadrille", "title": "Port Vieux"},
	{"id": &"lighthouse", "title": "Le Phare"},
]

@onready var _tab_select: OptionButton = %TabSelect
@onready var _rows: VBoxContainer = %Rows
@onready var _status_label: Label = %StatusLabel
@onready var _back_button: Button = %BackButton


func _ready() -> void:
	for tab: Dictionary in _TABS:
		_tab_select.add_item(tab["title"])
	_tab_select.item_selected.connect(_on_tab_selected)
	_back_button.pressed.connect(_on_back_button_pressed)
	LeaderboardClient.leaderboard_fetched.connect(_on_leaderboard_fetched)
	LeaderboardClient.request_failed.connect(_on_request_failed)
	var focus_index: int = 0
	for i: int in _TABS.size():
		if _TABS[i]["id"] == SceneRouter.leaderboard_focus:
			focus_index = i
			break
	_tab_select.select(focus_index)
	_fetch(focus_index)


func _on_tab_selected(index: int) -> void:
	_fetch(index)


func _fetch(index: int) -> void:
	_clear_rows()
	_status_label.text = "Chargement…"
	LeaderboardClient.fetch_leaderboard(_TABS[index]["id"])


func _on_leaderboard_fetched(entries: Array[Dictionary]) -> void:
	_clear_rows()
	if entries.is_empty():
		_status_label.text = "Personne au classement — sois le premier !"
		return
	_status_label.text = ""
	var rank: int = 1
	for entry: Dictionary in entries:
		var pseudo: String = str(entry.get("pseudo", "?"))
		var value: int = int(entry.get("best_score", entry.get("total", 0)))
		var row: Label = Label.new()
		row.add_theme_font_size_override(&"font_size", 30)
		row.text = "%d.  %s — %d" % [rank, pseudo, value]
		if pseudo == GameState.pseudo:
			row.add_theme_color_override(&"font_color", Color(1.0, 0.85, 0.3))
		_rows.add_child(row)
		rank += 1


func _on_request_failed(endpoint: String, _code: int, _message: String) -> void:
	if endpoint.begins_with("/leaderboard"):
		_status_label.text = "Impossible de charger le classement"


func _clear_rows() -> void:
	for child: Node in _rows.get_children():
		child.queue_free()


func _on_back_button_pressed() -> void:
	SceneRouter.goto_hub()
