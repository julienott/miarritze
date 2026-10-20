extends Node
## Démarrage de Miarritze Gordeka : thème cartoon en 1280×720 (GkUi), profils mis à jour pour
## Gordeka, puis « Qui joue ? » (SPEC-GORDEKA §6.0).
## QA : `--scene=gk_game` (web : `#scene=gk_game`) lance directement une partie contre l'IA ;
## avec `--gk-visite=chasse|chasseur` (web : `#scene=gk_game&visite=…`), la visite de debug ;
## `--scene=gk_accueil|gk_profil|gk_reglages|gk_partie_rapide|gk_qui_joue|gk_en_ligne` ouvre cet écran
## (un profil « Testeur » est créé s'il n'y en a aucun).


func _ready() -> void:
	get_tree().root.theme = GkUi.theme()
	GkProfil.migrer()
	var id: String = GkNav.depart(GkRules.args())
	if id != "qui_joue":
		GkProfil.assurer_qa()
		GkProfil.vers_partie()
	GkNav.aller(id)
