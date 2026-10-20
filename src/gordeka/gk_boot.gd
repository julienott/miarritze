extends Node
## Démarrage de Miarritze Gordeka : thème lisible en 1280×720, puis l'accueil.
## QA : `--scene=gk_game` (web : `#scene=gk_game`) lance directement une partie contre l'IA ;
## avec `--gk-visite=chasse|chasseur` (web : `#scene=gk_game&visite=…`), la visite de debug.


func _ready() -> void:
	var theme: Theme = Theme.new()
	theme.default_font_size = 26
	get_tree().root.theme = theme
	var target: String = "res://src/gordeka/gk_menu.tscn"
	for arg: String in GkRules.args():
		if arg.begins_with("--scene=gk_game"):
			target = "res://src/gordeka/gk_game.tscn"
	get_tree().change_scene_to_file.call_deferred(target)
