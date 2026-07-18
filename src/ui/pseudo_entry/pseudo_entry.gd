extends Control
## Saisie du pseudo + code de groupe. Deux chemins :
## - "Rejoindre" avec un code existant partagé par un copain ;
## - "Créer un groupe" : l'API renvoie un code, puis on rejoint avec.
## Aucune donnée personnelle : pseudo seul (cf. DESIGN.md §5.3).

@onready var _pseudo_edit: LineEdit = %PseudoEdit
@onready var _code_edit: LineEdit = %CodeEdit
@onready var _join_button: Button = %JoinButton
@onready var _create_button: Button = %CreateButton
@onready var _error_label: Label = %ErrorLabel


func _ready() -> void:
	_join_button.pressed.connect(_on_join_button_pressed)
	_create_button.pressed.connect(_on_create_button_pressed)
	LeaderboardClient.group_created.connect(_on_group_created)
	LeaderboardClient.group_joined.connect(_on_group_joined)
	LeaderboardClient.request_failed.connect(_on_request_failed)
	_pseudo_edit.text = GameState.pseudo
	_code_edit.text = GameState.group_code


func _on_join_button_pressed() -> void:
	var pseudo: String = _pseudo_edit.text.strip_edges()
	var code: String = _code_edit.text.strip_edges().to_upper()
	if not _validate_pseudo(pseudo):
		return
	if code.length() < 4:
		_show_error("Entre le code du groupe (ou crée un groupe)")
		return
	_set_busy(true)
	GameState.set_identity(pseudo, code)
	LeaderboardClient.join_group(code, pseudo)


func _on_create_button_pressed() -> void:
	var pseudo: String = _pseudo_edit.text.strip_edges()
	if not _validate_pseudo(pseudo):
		return
	_set_busy(true)
	LeaderboardClient.create_group()


func _on_group_created(code: String) -> void:
	if code == "":
		_show_error("Erreur à la création du groupe")
		_set_busy(false)
		return
	_code_edit.text = code
	var pseudo: String = _pseudo_edit.text.strip_edges()
	GameState.set_identity(pseudo, code)
	LeaderboardClient.join_group(code, pseudo)


func _on_group_joined(player_id: int, secret: String) -> void:
	GameState.set_credentials(player_id, secret)
	SceneRouter.goto_hub()


func _on_request_failed(_endpoint: String, _code: int, message: String) -> void:
	_set_busy(false)
	if message == "":
		_show_error("Pas de connexion — réessaie")
	else:
		_show_error(message)


func _validate_pseudo(pseudo: String) -> bool:
	if pseudo.length() < 2 or pseudo.length() > 15:
		_show_error("Choisis un pseudo (2 à 15 lettres)")
		return false
	return true


func _show_error(message: String) -> void:
	_error_label.text = message


func _set_busy(busy: bool) -> void:
	_join_button.disabled = busy
	_create_button.disabled = busy
	if busy:
		_error_label.text = ""
