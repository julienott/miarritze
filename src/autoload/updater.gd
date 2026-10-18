extends Node
## Updater — mise à jour automatique des versions natives Linux (Steam Deck,
## Recalbox).
##
## Actif seulement dans les exports « SteamDeck » (fonctionnalité `steamdeck`)
## et « Recalbox » (fonctionnalité `recalbox`), jamais en web ni depuis
## l'éditeur. Au lancement, il lit le manifeste du site de sa plateforme
## (tools/release/manifest.py) ; si un build plus récent existe :
##   - même moteur Godot : il télécharge le nouveau .pck, vérifie taille et
##     sha256, le met à la place de celui du jeu, puis relance le jeu ;
##   - moteur différent : il télécharge le paquet complet .tar.gz, le vérifie,
##     le décompresse dans le dossier du jeu, puis relance le jeu.
## Le .pck est remplacé à côté de l'exécutable (et pas chargé depuis user://)
## parce que les modèles d'export officiels refusent `--main-pack` et qu'un
## `load_resource_pack()` à chaud ne recharge ni les autoloads ni le cache
## des classes globales. Remplacer un fichier ouvert est sans risque sous
## Linux (renommage atomique ; l'ancien reste lisible par le processus).
## Les sauvegardes (user://) ne sont jamais touchées.
##
## Recalbox (docs/RECALBOX.md) : le jeu vit sur la partition `share` (exFAT,
## sans droit d'exécution) et c'est le lanceur MiarritzeBorroka.sh qui copie
## l'exécutable ailleurs avant de le lancer, en passant `--install-dir=`.
## L'updater dépose alors les nouveaux fichiers à côté, suffixés `.new`, écrit
## le build attendu dans `.relance` et quitte avec RELAUNCH_EXIT_CODE : le
## lanceur met les fichiers en place (le jeu ne tourne plus) et le relance.
## Rien n'est remplacé pendant que le jeu tourne, quel que soit le système de
## fichiers.
##
## Toute erreur (pas de réseau, fichier abîmé, dossier en lecture seule)
## laisse démarrer la version présente : on ne bloque jamais le joueur.
##
## Le numéro de build et la version sont injectés par la CI dans
## project.godot (application/config/build, application/config/version).
## Arguments : `--no-update` (désactive), `--update-manifest=<url>` (tests),
## `--install-dir=<dossier>` (Recalbox, passé par le lanceur).

## Émis quand le démarrage peut continuer (pas de mise à jour, ou échec).
## En cas de mise à jour réussie, le jeu se relance et ce signal n'est pas émis.
signal finished

const MANIFEST_URLS: Dictionary[String, String] = {
	"steamdeck": "https://miarritze.ijulien.com/steamdeck/manifest.json",
	"recalbox": "https://miarritze.ijulien.com/recalbox/manifest.json",
}
const MANIFEST_TIMEOUT_S: float = 5.0
const DOWNLOAD_TIMEOUT_S: float = 600.0
## Passé au jeu relancé : s'il ne tourne pas ce build-là, on n'insiste pas
## (évite une boucle téléchargement / relance).
const UPDATED_ARG: String = "--updated-to="
const INSTALL_DIR_ARG: String = "--install-dir="
## Recalbox : code de sortie qui demande au lanceur de relancer le jeu.
const RELAUNCH_EXIT_CODE: int = 75
## Recalbox : fichier (dans le dossier du jeu) qui donne au lanceur le build attendu.
const RELAUNCH_FILE: String = ".relance"
## Recalbox : dossier du jeu dans les archives .zip (ce qui est à côté du lanceur).
const ZIP_GAME_DIR: String = "roms/ports/miarritze/"
## Recalbox : fichiers du dossier du jeu que la mise à jour ne remplace pas
## (EmulationStation réécrit gamelist.xml, l'image peut avoir été changée).
const ZIP_KEEP: Array[String] = ["gamelist.xml"]

## Vrai tant que la vérification est en cours (boot attend `finished`).
var busy: bool = false

## "steamdeck", "recalbox" ou "" (inactif).
var _platform: String = ""
var _manifest_url: String = ""
var _build: int = 0
var _install_dir: String = ""
var _http: HTTPRequest
var _layer: CanvasLayer
var _label: Label


func _ready() -> void:
	set_process(false)
	_platform = _detect_platform()
	if _platform == "":
		return
	_manifest_url = MANIFEST_URLS[_platform]
	_build = int(ProjectSettings.get_setting("application/config/build", 0))
	_install_dir = OS.get_executable_path().get_base_dir()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--update-manifest="):
			_manifest_url = arg.trim_prefix("--update-manifest=")
		elif arg.begins_with(INSTALL_DIR_ARG):
			_install_dir = arg.trim_prefix(INSTALL_DIR_ARG)
		elif arg.begins_with(UPDATED_ARG) and int(arg.trim_prefix(UPDATED_ARG)) > _build:
			push_warning("Updater: la mise à jour n'a pas pris, on démarre tel quel")
			return
	if not _install_dir_writable():
		return
	busy = true
	_fetch_manifest.call_deferred()


func _detect_platform() -> String:
	if OS.get_cmdline_user_args().has("--no-update"):
		return ""
	if not (OS.has_feature("template") and OS.has_feature("linux")):
		return ""
	for platform: String in MANIFEST_URLS:
		if OS.has_feature(platform):
			return platform
	return ""


func _recalbox() -> bool:
	return _platform == "recalbox"


## Nom de base du jeu (« MiarritzeBorroka »), celui de l'exécutable et du .pck.
func _game_name() -> String:
	return OS.get_executable_path().get_file().get_basename()


func _engine_version() -> String:
	var info: Dictionary = Engine.get_version_info()
	return "%d.%d.%d" % [int(info["major"]), int(info["minor"]), int(info["patch"])]


func _install_dir_writable() -> bool:
	var probe: String = _install_dir.path_join(".miarritze_write_test")
	var file: FileAccess = FileAccess.open(probe, FileAccess.WRITE)
	if file == null:
		return false
	file.close()
	DirAccess.remove_absolute(probe)
	return true


# --- Manifeste -----------------------------------------------------------------

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
	if remote_build <= _build:
		_done()
		return
	var same_engine: bool = str(manifest.get("godot", "")) == _engine_version()
	var entry: Variant = manifest.get("pck", null) if same_engine else _package_entry(manifest)
	if not entry is Dictionary:
		_done()
		return
	_download(entry as Dictionary, remote_build, same_engine)


## Paquet complet : unique (`package`, Steam Deck) ou un par architecture
## (`packages`, Recalbox : arm64 et x86_64).
func _package_entry(manifest: Dictionary) -> Variant:
	var packages: Variant = manifest.get("packages", null)
	if packages is Dictionary:
		return (packages as Dictionary).get(Engine.get_architecture_name(), null)
	return manifest.get("package", null)


# --- Téléchargement ------------------------------------------------------------

func _download(entry: Dictionary, remote_build: int, is_pck: bool) -> void:
	var url: String = _resolve(str(entry.get("url", "")))
	# Fichier temporaire dans le dossier du jeu : le renommage final est atomique.
	var ext: String = "pck" if is_pck else str(entry.get("url", "")).get_extension()
	var part: String = _install_dir.path_join(".update-%d.%s.part" % [remote_build, ext])
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
			set_process(false)
			var ok: bool = result == HTTPRequest.RESULT_SUCCESS and code == 200 and _verify(part, entry)
			if ok:
				ok = _install_pck(part) if is_pck else _install_package(part)
			if FileAccess.file_exists(part):
				DirAccess.remove_absolute(part)
			if ok:
				_relaunch(remote_build)
			else:
				_done())
	if _http.request(url) != OK:
		_http.queue_free()
		_http = null
		_done()


func _process(_delta: float) -> void:
	if _http == null or _label == null:
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


## Même moteur : le nouveau .pck remplace celui que charge l'exécutable
## (Recalbox : posé à côté en `.new`, le lanceur le met en place).
func _install_pck(part: String) -> bool:
	if _recalbox():
		return DirAccess.rename_absolute(part, _install_dir.path_join(_game_name() + ".pck.new")) == OK
	var pck: String = OS.get_executable_path().get_basename() + ".pck"
	return DirAccess.rename_absolute(part, pck) == OK


## Moteur différent : on décompresse le paquet complet sur le dossier du jeu.
func _install_package(part: String) -> bool:
	_show("Installation de la nouvelle version…")
	if _recalbox():
		return _install_zip(part)
	var output: Array = []
	var code: int = OS.execute("tar", ["-xzf", part, "-C", _install_dir, "--strip-components=1"],
		output, true)
	if code != 0:
		push_warning("Updater: échec de tar (%d) %s" % [code, str(output)])
	return code == 0


## Recalbox : extrait du .zip le contenu du dossier du jeu, chaque fichier
## suffixé `.new` (le lanceur les renomme une fois le jeu arrêté).
func _install_zip(part: String) -> bool:
	var zip: ZIPReader = ZIPReader.new()
	if zip.open(part) != OK:
		return false
	var written: PackedStringArray = []
	var ok: bool = true
	for path: String in zip.get_files():
		var name: String = path.trim_prefix(ZIP_GAME_DIR)
		if not path.begins_with(ZIP_GAME_DIR) or name == "" or name.contains("/") or name in ZIP_KEEP:
			continue
		var target: String = _install_dir.path_join(name + ".new")
		var file: FileAccess = FileAccess.open(target, FileAccess.WRITE)
		if file == null:
			ok = false
			break
		file.store_buffer(zip.read_file(path))
		file.close()
		written.append(target)
	zip.close()
	if written.is_empty():
		ok = false
	if not ok:
		for target: String in written:
			DirAccess.remove_absolute(target)
	return ok


# --- Relance -------------------------------------------------------------------

func _relaunch(new_build: int) -> void:
	_show("C'est prêt !\nLe jeu redémarre…")
	if _recalbox():
		# Le lanceur relance le jeu (voir l'en-tête) : on lui laisse le build attendu.
		var file: FileAccess = FileAccess.open(_install_dir.path_join(RELAUNCH_FILE), FileAccess.WRITE)
		if file == null:
			_done()
			return
		file.store_string(str(new_build))
		file.close()
		await get_tree().process_frame
		await get_tree().process_frame
		get_tree().quit(RELAUNCH_EXIT_CODE)
		return
	var args: PackedStringArray = []
	if DisplayServer.get_name() == "headless":
		args.append("--headless")
	args.append("--")
	for arg: String in OS.get_cmdline_user_args():
		if not arg.begins_with(UPDATED_ARG):
			args.append(arg)
	args.append(UPDATED_ARG + str(new_build))
	# Deux frames pour afficher le message, puis on passe la main.
	await get_tree().process_frame
	await get_tree().process_frame
	if OS.create_process(OS.get_executable_path(), args) == -1:
		push_warning("Updater: relance impossible")
		_done()
		return
	get_tree().quit()


func _done() -> void:
	_hide()
	busy = false
	finished.emit()


# --- Affichage -------------------------------------------------------------------

func _resolve(url: String) -> String:
	if url.begins_with("http://") or url.begins_with("https://"):
		return url
	return _manifest_url.get_base_dir().path_join(url)


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
