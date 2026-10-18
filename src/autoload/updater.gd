extends Node
## Updater — mise à jour automatique de la version Steam Deck (Linux).
##
## Actif seulement dans l'export « SteamDeck » (fonctionnalité `steamdeck`),
## jamais en web ni dans l'éditeur. Au lancement :
##   1. si une version plus récente a déjà été téléchargée (user://update/),
##      le jeu se relance dessus avec `--main-pack` ;
##   2. sinon il lit le manifeste du site ; si une version plus récente
##      existe, il télécharge son .pck, vérifie taille + sha256, l'installe
##      dans user://update/ puis se relance dessus ;
##   3. si le moteur Godot a changé (le .pck ne suffit plus), il télécharge
##      le paquet complet .tar.gz et le décompresse dans le dossier du jeu.
## Toute erreur (pas de réseau, fichier corrompu, dossier en lecture seule)
## laisse démarrer la version présente : on ne bloque jamais le joueur.
## Garde-fou : une version téléchargée qui ne démarre pas (2 essais sans
## confirmation) est écartée et n'est plus jamais retentée.
##
## Le numéro de build et la version sont injectés par la CI dans
## project.godot (application/config/build, application/config/version).
## Arguments utiles (tests) : `--no-update`, `--force-updater`,
## `--update-manifest=<url>`.

## Émis quand le démarrage peut continuer (pas de mise à jour, ou échec).
## En cas de mise à jour réussie, le jeu se relance et ce signal n'est pas émis.
signal finished

const MANIFEST_URL: String = "https://miarritze.ijulien.com/steamdeck/manifest.json"
const UPDATE_DIR: String = "user://update"
const STATE_PATH: String = "user://update/state.json"
const MANIFEST_TIMEOUT_S: float = 5.0
const DOWNLOAD_TIMEOUT_S: float = 600.0
## Lancements sans confirmation au-delà desquels une version est écartée.
const MAX_TRIES: int = 2
## Durée de jeu après laquelle une version téléchargée est jugée saine.
const CONFIRM_DELAY_S: float = 8.0

## Vrai tant que la vérification est en cours (boot attend `finished`).
var busy: bool = false

var _manifest_url: String = MANIFEST_URL
var _build: int = 0
var _state: Dictionary = {}
var _http: HTTPRequest
var _layer: CanvasLayer
var _label: Label


func _ready() -> void:
	set_process(false)
	if not _enabled():
		return
	_build = int(ProjectSettings.get_setting("application/config/build", 0))
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--update-manifest="):
			_manifest_url = arg.trim_prefix("--update-manifest=")
	busy = true
	_start.call_deferred()


## Version lisible (affichée dans les réglages, par exemple).
static func version_text() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "dev"))


func _enabled() -> bool:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.has("--no-update"):
		return false
	if args.has("--force-updater"):
		return true
	return OS.has_feature("steamdeck") and not OS.has_feature("editor")


func _engine_version() -> String:
	var info: Dictionary = Engine.get_version_info()
	return "%d.%d.%d" % [int(info["major"]), int(info["minor"]), int(info["patch"])]


func _start() -> void:
	DirAccess.make_dir_recursive_absolute(UPDATE_DIR)
	_state = _load_state()
	if _redirect_to_downloaded():
		return
	_confirm_running_build()
	_fetch_manifest()


# --- 1. Version déjà téléchargée -------------------------------------------

## Relance sur le .pck téléchargé s'il est plus récent que celui qui tourne.
func _redirect_to_downloaded() -> bool:
	var state_build: int = int(_state.get("build", 0))
	var pck: String = str(_state.get("pck", ""))
	if state_build <= _build or pck == "":
		# Version installée à jour (ou réinstallée depuis le site) : ménage.
		if state_build > 0 and state_build < _build:
			_forget_downloaded()
		return false
	if not FileAccess.file_exists(pck) or str(_state.get("godot", "")) != _engine_version():
		_forget_downloaded()
		return false
	if not bool(_state.get("confirmed", false)) and int(_state.get("tries", 0)) >= MAX_TRIES:
		# Cette version n'a jamais réussi à démarrer : on l'écarte.
		_state["bad_build"] = state_build
		_forget_downloaded()
		return false
	_relaunch(pck)
	return true


## La version téléchargée tourne : après quelques secondes sans plantage,
## on la déclare saine.
func _confirm_running_build() -> void:
	if int(_state.get("build", 0)) != _build or bool(_state.get("confirmed", false)):
		return
	get_tree().create_timer(CONFIRM_DELAY_S).timeout.connect(func() -> void:
		_state["confirmed"] = true
		_state["tries"] = 0
		_save_state())


func _forget_downloaded() -> void:
	var pck: String = str(_state.get("pck", ""))
	if pck != "" and FileAccess.file_exists(pck):
		DirAccess.remove_absolute(pck)
	for key: String in ["build", "pck", "godot", "tries", "confirmed"]:
		_state.erase(key)
	_save_state()


# --- 2. Manifeste ------------------------------------------------------------

func _fetch_manifest() -> void:
	_http = HTTPRequest.new()
	_http.timeout = MANIFEST_TIMEOUT_S
	add_child(_http)
	_http.request_completed.connect(_on_manifest)
	if _http.request(_manifest_url) != OK:
		_done()


func _on_manifest(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_http.queue_free()
	_http = null
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_done()
		return
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not data is Dictionary:
		_done()
		return
	var manifest: Dictionary = data
	var remote_build: int = int(manifest.get("build", 0))
	if remote_build <= _build or remote_build == int(_state.get("bad_build", 0)):
		_done()
		return
	var same_engine: bool = str(manifest.get("godot", "")) == _engine_version()
	var entry: Variant = manifest.get("pck" if same_engine else "package", null)
	if not entry is Dictionary:
		_done()
		return
	if not same_engine and not _install_dir_writable():
		_done()
		return
	_download(entry as Dictionary, remote_build, same_engine, str(manifest.get("version", "")))


# --- 3. Téléchargement -------------------------------------------------------

func _download(entry: Dictionary, remote_build: int, is_pck: bool, version: String) -> void:
	var url: String = _resolve(str(entry.get("url", "")))
	var target: String = "%s/miarritze-%d.%s" % [UPDATE_DIR, remote_build, "pck" if is_pck else "tar.gz"]
	var part: String = target + ".part"
	_show("Nouvelle version du jeu !\nTéléchargement…")
	_http = HTTPRequest.new()
	_http.timeout = DOWNLOAD_TIMEOUT_S
	_http.download_file = part
	_http.download_chunk_size = 262144
	_http.accept_gzip = false
	add_child(_http)
	set_process(true)
	_http.request_completed.connect(
		func(result: int, code: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
			_http.queue_free()
			_http = null
			if result != HTTPRequest.RESULT_SUCCESS or code != 200 or not _verify(part, entry):
				DirAccess.remove_absolute(part)
				_done()
				return
			if FileAccess.file_exists(target):
				DirAccess.remove_absolute(target)
			DirAccess.rename_absolute(part, target)
			if is_pck:
				_install_pck(target, remote_build)
			else:
				_install_package(target, version))
	if _http.request(url) != OK:
		_http.queue_free()
		_http = null
		_done()


func _process(_delta: float) -> void:
	if _http == null or _label == null or _http.download_file == "":
		return
	var total: int = _http.get_body_size()
	if total > 0:
		var percent: int = int(100.0 * float(_http.get_downloaded_bytes()) / float(total))
		_label.text = "Nouvelle version du jeu !\nTéléchargement… %d %%" % percent


func _verify(path: String, entry: Dictionary) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() != int(entry.get("size", -1)):
		return false
	file.close()
	return FileAccess.get_sha256(path) == str(entry.get("sha256", "")).to_lower()


func _install_pck(pck: String, remote_build: int) -> void:
	var previous: String = str(_state.get("pck", ""))
	if previous != "" and previous != pck and FileAccess.file_exists(previous):
		DirAccess.remove_absolute(previous)
	_state["build"] = remote_build
	_state["pck"] = pck
	_state["godot"] = _engine_version()
	_state["tries"] = 0
	_state["confirmed"] = false
	_save_state()
	_relaunch(pck)


## Moteur différent : on remplace le jeu entier dans son dossier (Linux
## autorise l'écrasement d'un exécutable en cours d'exécution).
func _install_package(archive: String, _version: String) -> void:
	_show("Installation de la nouvelle version…")
	var install_dir: String = OS.get_executable_path().get_base_dir()
	var output: Array = []
	var code: int = OS.execute("tar", ["-xzf", ProjectSettings.globalize_path(archive),
		"-C", install_dir, "--strip-components=1"], output, true)
	DirAccess.remove_absolute(archive)
	if code != 0:
		push_warning("Updater: échec de tar (%d) %s" % [code, str(output)])
		_done()
		return
	# Le nouveau paquet contient déjà le dernier .pck : l'ancien téléchargé ne sert plus.
	_forget_downloaded()
	_relaunch("")


func _install_dir_writable() -> bool:
	if not OS.has_feature("linux"):
		return false
	var probe: String = OS.get_executable_path().get_base_dir().path_join(".miarritze_write_test")
	var file: FileAccess = FileAccess.open(probe, FileAccess.WRITE)
	if file == null:
		return false
	file.close()
	DirAccess.remove_absolute(probe)
	return true


# --- Relance -----------------------------------------------------------------

func _relaunch(pck: String) -> void:
	_show("C'est prêt !\nLe jeu redémarre…")
	var args: PackedStringArray = []
	if pck != "":
		args.append_array(["--main-pack", ProjectSettings.globalize_path(pck)])
		_state["tries"] = int(_state.get("tries", 0)) + 1
		_save_state()
	var user_args: PackedStringArray = OS.get_cmdline_user_args()
	if not user_args.is_empty():
		args.append("--")
		args.append_array(user_args)
	# Une frame pour afficher le message, puis on passe la main.
	await get_tree().process_frame
	await get_tree().process_frame
	if OS.create_process(OS.get_executable_path(), args) == -1:
		push_warning("Updater: relance impossible")
		_hide()
		_done()
		return
	get_tree().quit()


func _done() -> void:
	_hide()
	busy = false
	finished.emit()


# --- État + affichage ----------------------------------------------------------

func _resolve(url: String) -> String:
	if url.begins_with("http://") or url.begins_with("https://"):
		return url
	return _manifest_url.get_base_dir().path_join(url)


func _load_state() -> Dictionary:
	if not FileAccess.file_exists(STATE_PATH):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(STATE_PATH))
	return data if data is Dictionary else {}


func _save_state() -> void:
	var file: FileAccess = FileAccess.open(STATE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(_state))


func _show(text: String) -> void:
	if _layer == null:
		_layer = CanvasLayer.new()
		_layer.layer = 120
		add_child(_layer)
		var bg: ColorRect = ColorRect.new()
		bg.color = Color(0.11, 0.13, 0.26)
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		_layer.add_child(bg)
		_label = Label.new()
		_label.set_anchors_preset(Control.PRESET_FULL_RECT)
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_layer.add_child(_label)
	_label.text = text


func _hide() -> void:
	if _layer != null:
		_layer.queue_free()
		_layer = null
		_label = null
