extends Node
## Api — client HTTP de l'API PHP (SPEC-BORROKA §9.4).
##
## Toutes les requêtes sont asynchrones : `call_api()` renvoie via le
## callback `on_done(ok: bool, code: int, data: Variant)`. En export web,
## l'API est sur la même origine (/api) ; hors web, on vise `api_base_override`
## (dev local : php -S) ou l'URL de prod.

## URL de base hors web (éditeur / desktop / tests).
@export var fallback_api_url: String = "https://miarritze.ijulien.com/api"

var api_base: String = ""


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--api="):
			api_base = arg.trim_prefix("--api=")
	if api_base != "":
		return
	if OS.has_feature("web"):
		# HTTPRequest exige une URL absolue, même en web.
		var origin: Variant = JavaScriptBridge.eval("window.location.origin", true)
		api_base = str(origin) + "/api" if origin != null else fallback_api_url
	else:
		api_base = fallback_api_url


## Appel générique. `auth` ajoute player_id + secret du profil actif.
func call_api(method: HTTPClient.Method, path: String, body: Dictionary,
		on_done: Callable, auth: bool = true) -> void:
	var payload: Dictionary = body.duplicate()
	if auth:
		var profile: Dictionary = Profiles.active()
		payload["player_id"] = int(profile.get("player_id", 0))
		payload["secret"] = str(profile.get("secret", ""))
	var http: HTTPRequest = HTTPRequest.new()
	http.timeout = 10.0
	add_child(http)
	http.request_completed.connect(_on_completed.bind(http, on_done))
	var url: String = api_base + path
	var body_text: String = ""
	if method == HTTPClient.METHOD_GET:
		var query: PackedStringArray = []
		for key: Variant in payload:
			query.append("%s=%s" % [str(key).uri_encode(), str(payload[key]).uri_encode()])
		if not query.is_empty():
			url += ("&" if "?" in url else "?") + "&".join(query)
	else:
		body_text = JSON.stringify(payload)
	var error: Error = http.request(url, ["Content-Type: application/json"], method, body_text)
	if error != OK:
		http.queue_free()
		on_done.call(false, 0, null)


func _on_completed(result: int, response_code: int, _headers: PackedStringArray,
		body: PackedByteArray, http: HTTPRequest, on_done: Callable) -> void:
	http.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS:
		on_done.call(false, 0, null)
		return
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	on_done.call(response_code >= 200 and response_code < 300, response_code, data)


## Score de pyramide → classement du groupe (si le profil a rejoint un groupe).
func post_tower_score(fighter: String, difficulty: String, score: int) -> void:
	if int(Profiles.active().get("player_id", 0)) <= 0:
		return
	call_api(HTTPClient.METHOD_POST, "/tower/score",
		{"fighter": fighter, "difficulty": difficulty, "score": score},
		func(_ok: bool, _code: int, _data: Variant) -> void: pass)


## Envoie la carte de joueur au serveur (si le profil a rejoint un groupe).
func sync_profile() -> void:
	var p: Dictionary = Profiles.active()
	if int(p.get("player_id", 0)) <= 0:
		return
	call_api(HTTPClient.METHOD_POST, "/profile", {
		"fighter": str(p.get("fighter", "louis")), "costume": int(p.get("costume", 0)),
		"banner": int(p.get("banner", 0)), "title": str(p.get("title", "")),
		"emote": int(p.get("emote", 0)), "stats": p.get("stats", {}),
	}, func(_ok: bool, _c: int, _d: Variant) -> void: pass)


## Crée un groupe et le rejoint. on_done(ok: bool, message: String).
func create_group(on_done: Callable) -> void:
	call_api(HTTPClient.METHOD_POST, "/group", {}, func(ok: bool, _c: int, data: Variant) -> void:
		if ok and data is Dictionary:
			join_group(str((data as Dictionary).get("code", "")), on_done)
		else:
			on_done.call(false, "Serveur injoignable"))


## Rejoint le groupe `code` avec le profil actif. on_done(ok: bool, message: String).
func join_group(code: String, on_done: Callable) -> void:
	code = code.strip_edges().to_upper()
	if code.length() != 6:
		on_done.call(false, "Le code fait 6 caractères")
		return
	var pseudo: String = str(Profiles.active().get("pseudo", ""))
	call_api(HTTPClient.METHOD_POST, "/group/join", {"code": code, "pseudo": pseudo},
		func(ok: bool, _c: int, data: Variant) -> void:
			if ok and data is Dictionary:
				var d: Dictionary = data
				Profiles.update_active({"group_code": code, "player_id": int(d.get("player_id", 0)),
					"secret": str(d.get("secret", ""))})
				sync_profile()
				on_done.call(true, "Bienvenue dans le groupe %s !" % code)
			else:
				var msg: String = str((data as Dictionary).get("error", "")) if data is Dictionary else ""
				on_done.call(false, "Impossible : %s" % (msg if msg != "" else "serveur injoignable")), false)
