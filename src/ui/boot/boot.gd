extends Control
## Démarrage : bascule immédiatement vers l'écran titre (ou vers une scène
## de QA passée par l'URL `#scene=<id>` en web, ou `--scene=` en natif).


func _ready() -> void:
	_route.call_deferred()


func _route() -> void:
	var target: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--autofight=") or arg.begins_with("--autotower="):
			return   # QaCapture lance le combat
		if arg.begins_with("--scene="):
			target = arg.trim_prefix("--scene=")
	if target == "" and OS.has_feature("web"):
		var hash_value: Variant = JavaScriptBridge.eval("window.location.hash", true)
		var text: String = str(hash_value)
		if text.begins_with("#scene="):
			target = text.trim_prefix("#scene=")
	if target == "touchfight":
		# QA : combat complet au tactile contre l'IA Facile.
		InputHub.set_solo()
		SceneRouter.goto(&"fight", {"p1": "louis", "p2": "maia", "stage": "grande_plage",
			"ai": [0, AiBrain.SKILL_EASY], "rounds": 3, "return_to": "title"})
		return
	if target.begins_with("online_qa"):
		_online_qa(target)
		return
	if target == "autoloop":
		BootLoop.next_fight()
		return
	if target == "vs":
		SceneRouter.goto(&"versus_splash", {"p1": "patxi", "p2": "xabi", "c1": 0, "c2": 1,
			"stage": "port_pecheurs", "mode": "qa"})
		return
	if target.begins_with("ending:"):
		SceneRouter.goto(&"ending", {"fighter": target.trim_prefix("ending:"), "score": 12345,
			"unlocked": ["Costume 3", "Titre : Txapeldun"]})
		return
	if target == "tutorial":
		SceneRouter.goto(&"fight", TrainingMode.tutorial_params())
		return
	if target.begins_with("res://"):
		SceneRouter.goto_path(target)
	elif target != "":
		SceneRouter.goto(StringName(target))
	else:
		SceneRouter.goto(&"title")



## QA en ligne (Playwright à deux pages) : #scene=online_qa&pid=1&sec=…&code=…&pseudo=…&role=invite&bot=1
func _online_qa(spec: String) -> void:
	var args: Dictionary = {}
	for part: String in spec.split("&"):
		var kv: PackedStringArray = part.split("=")
		if kv.size() == 2:
			args[kv[0]] = kv[1].uri_decode()
	if Profiles.profiles.is_empty() or str(Profiles.active().get("pseudo", "")) != str(args.get("pseudo", "")):
		Profiles.create(str(args.get("pseudo", "Testeur")))
	Profiles.update_active({"player_id": int(args.get("pid", "0")), "secret": str(args.get("sec", "")),
		"group_code": str(args.get("code", "")), "fighter": str(args.get("fighter", "louis")), "tutorial_done": true})
	OnlineMode.qa = {"role": str(args.get("role", "")), "bot": args.get("bot", "0") == "1",
		"rematch": args.get("rematch", "0") == "1"}
	SceneRouter.goto(&"lobby")
