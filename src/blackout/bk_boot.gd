extends Node
## Démarrage de Miarritze Blackout : thème cartoon en 1280×720 (BkUi), profils mis à jour pour
## Blackout, puis « Qui joue ? » (SPEC-GORDEKA §6.0).
## QA : `--scene=bk_game` (web : `#scene=bk_game`) lance directement une partie contre l'IA ;
## avec `--bk-visite=chasse|chasseur` (web : `#scene=bk_game&visite=…`), la visite de debug ;
## `--scene=bk_accueil|bk_profil|bk_reglages|bk_partie_rapide|bk_qui_joue|bk_en_ligne` ouvre cet écran
## (un profil « Testeur » est créé s'il n'y en a aucun).


func _ready() -> void:
	get_tree().root.theme = BkUi.theme()
	BkProfil.migrer()
	var id: String = BkNav.depart(BkRules.args())
	if id != "qui_joue":
		BkProfil.assurer_qa()
		BkProfil.vers_partie()
	BkNav.aller(id)
