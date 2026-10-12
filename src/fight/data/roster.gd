class_name Roster
extends RefCounted
## Roster, boss, mannequin et stages (SPEC §5, §6). Ordre d'affichage.

const FIGHTERS: PackedStringArray = [
	"louis", "maia", "patxi", "xabi", "mattin", "amaia",
	"txomin", "kaio", "karramarro", "ramuntxo", "itsaso", "peio",
]
const BOSS: String = "itsasargi"
const DUMMY: String = "hondar"

const STAGES: PackedStringArray = [
	"grande_plage", "cote_basques", "port_pecheurs", "rocher_vierge", "port_vieux",
	"halles", "fronton", "stade", "aquarium", "phare_sommet",
]
const STAGE_NAMES: Dictionary = {
	"grande_plage": "Grande Plage", "grande_plage_soir": "Grande Plage (soir)",
	"cote_basques": "Côte des Basques", "cote_basques_crepuscule": "Côte des Basques (crépuscule)",
	"port_pecheurs": "Port des Pêcheurs", "rocher_vierge": "Rocher de la Vierge",
	"port_vieux": "Port Vieux", "halles": "Les Halles", "fronton": "Le Fronton",
	"stade": "Le Stade", "aquarium": "L'Aquarium", "phare_sommet": "Sommet du Phare",
}


## Stage maison d'un combattant, ramené à un stage existant.
static func home_stage(id: String) -> String:
	var data: Dictionary = FighterDb.load_json(id)
	var stage: String = str(data.get("home_stage", "grande_plage"))
	return stage


static func display_name(id: String) -> String:
	return str(FighterDb.load_json(id).get("name", id.capitalize()))
