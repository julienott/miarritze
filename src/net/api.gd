extends Node
## Api — client HTTP de l'API PHP (backend/, docs/ONLINE.md).
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

