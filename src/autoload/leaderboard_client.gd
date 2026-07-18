extends Node
## LeaderboardClient — appels HTTP à l'API PHP (async via HTTPRequest).
##
## Contrat d'API : CLAUDE.md §6.2. Toutes les méthodes sont asynchrones ;
## les résultats reviennent par signaux (au passé, cf. conventions §3).
## En export web, l'API est sur la même origine (/api) ; en desktop/éditeur
## on retombe sur l'URL de prod pour pouvoir playtester la chaîne complète.

## Émis après POST /api/group réussi (création d'un groupe).
signal group_created(code: String)

## Émis après POST /api/group/join réussi.
signal group_joined(player_id: int, secret: String)

## Émis après POST /api/score réussi.
signal score_posted(challenge: StringName, best_score: int, cumulative: int)

## Émis après GET /api/leaderboard réussi. `entries` : Array[Dictionary]
## ({ pseudo, best_score } par épreuve, { pseudo, total } au cumul).
signal leaderboard_fetched(entries: Array[Dictionary])

## Émis quand une requête échoue (réseau ou erreur API).
## `message` : texte d'erreur renvoyé par l'API (vide si erreur réseau).
signal request_failed(endpoint: String, code: int, message: String)

## URL de base de l'API hors web (éditeur / desktop).
@export var fallback_api_url: String = "https://miarritze.ijulien.com/api"

var _api_base: String


func _ready() -> void:
	if OS.has_feature("web"):
		# HTTPRequest exige une URL absolue, même en web : on reconstruit
		# l'origine de la page (le jeu et l'API partagent le même domaine).
		var origin: Variant = JavaScriptBridge.eval("window.location.origin", true)
		_api_base = str(origin) + "/api" if origin != null else fallback_api_url
	else:
		_api_base = fallback_api_url


## Crée un groupe → group_created(code).
func create_group() -> void:
	_request(HTTPClient.METHOD_POST, "/group", {}, _on_group_created)


## Rejoint un groupe avec un pseudo → group_joined(player_id, secret).
func join_group(code: String, pseudo: String) -> void:
	_request(HTTPClient.METHOD_POST, "/group/join",
		{"code": code, "pseudo": pseudo}, _on_group_joined)


## Poste un score (auth via GameState) → score_posted(...).
func post_score(challenge: StringName, score: int) -> void:
	if GameState.player_id <= 0:
		return
	_request(HTTPClient.METHOD_POST, "/score", {
		"player_id": GameState.player_id,
		"secret": GameState.player_secret,
		"challenge": String(challenge),
		"score": score,
	}, _on_score_posted.bind(challenge))


## Récupère un classement. `challenge` vide → classement cumulé.
## → leaderboard_fetched(entries).
func fetch_leaderboard(challenge: StringName = &"") -> void:
	var query: String = "?code=%s" % GameState.group_code.uri_encode()
	if challenge == &"":
		query += "&type=cumulative"
	else:
		query += "&challenge=%s" % String(challenge).uri_encode()
	_request(HTTPClient.METHOD_GET, "/leaderboard" + query, {}, _on_leaderboard_fetched)


func _request(method: HTTPClient.Method, path: String, body: Dictionary,
		on_success: Callable) -> void:
	var http: HTTPRequest = HTTPRequest.new()
	http.timeout = 10.0
	add_child(http)
	http.request_completed.connect(_on_request_completed.bind(http, path, on_success))
	var headers: PackedStringArray = ["Content-Type: application/json"]
	var body_text: String = "" if method == HTTPClient.METHOD_GET else JSON.stringify(body)
	var error: Error = http.request(_api_base + path, headers, method, body_text)
	if error != OK:
		http.queue_free()
		request_failed.emit(path, 0, "")


func _on_request_completed(result: int, response_code: int,
		_headers: PackedStringArray, body: PackedByteArray,
		http: HTTPRequest, path: String, on_success: Callable) -> void:
	http.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS:
		request_failed.emit(path, 0, "")
		return
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if response_code < 200 or response_code >= 300:
		var message: String = ""
		if data is Dictionary:
			message = str((data as Dictionary).get("error", ""))
		request_failed.emit(path, response_code, message)
		return
	on_success.call(data)


func _on_group_created(data: Variant) -> void:
	if data is Dictionary:
		group_created.emit(str((data as Dictionary).get("code", "")))


func _on_group_joined(data: Variant) -> void:
	if data is Dictionary:
		var dict: Dictionary = data
		group_joined.emit(int(dict.get("player_id", 0)), str(dict.get("secret", "")))


func _on_score_posted(data: Variant, challenge: StringName) -> void:
	if data is Dictionary:
		var dict: Dictionary = data
		score_posted.emit(challenge, int(dict.get("best_score", 0)),
			int(dict.get("cumulative", 0)))


func _on_leaderboard_fetched(data: Variant) -> void:
	var entries: Array[Dictionary] = []
	if data is Array:
		for entry: Variant in (data as Array):
			if entry is Dictionary:
				entries.append(entry as Dictionary)
	leaderboard_fetched.emit(entries)
