class_name TowerMode
extends RefCounted
## Pyramide du Phare (SPEC §3.2) : 9 étages, continues illimités, score.
##  1–5 : adversaires aléatoires, difficulté croissante, sans doublon
##  6   : combat en double (deux adversaires, une seule barre de vie)
##  7   : le Reflet (soi-même, costume alternatif)
##  8   : le rival
##  9   : le Gardien du Phare, au Sommet du Phare, la nuit
## L'état de la partie vit dans `TowerMode.run` entre les écrans.

const FLOORS: int = 9
const DIFFICULTIES: PackedStringArray = ["facile", "normal", "expert"]
const DIFFICULTY_NAMES: PackedStringArray = ["Facile", "Normal", "Expert"]
## Compétence IA de l'étage 1 et de l'étage 8, par difficulté (§13).
const SKILL_RANGE: Array = [[8, 32], [35, 62], [62, 90]]
const LOSS_PENALTY_PCT: int = 20

static var run: TowerMode = null

var fighter: String = "louis"
var costume: int = 0
var difficulty: int = 0
var floors: Array[Dictionary] = []   # {opponents: [id...], costume, stage, kind}
var floor_index: int = 0
var sub_index: int = 0               # combat en double : 0 puis 1
var carried_health: int = 0
var score: int = 0
var losses_here: int = 0
var skill_malus: int = 0
var fight_log: Array[Dictionary] = []


static func start(p_fighter: String, p_costume: int, p_difficulty: int) -> TowerMode:
	var t: TowerMode = TowerMode.new()
	t.fighter = p_fighter
	t.costume = p_costume
	t.difficulty = p_difficulty
	t._build_ladder()
	run = t
	return t


func _build_ladder() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	var data: Dictionary = FighterDb.load_json(fighter)
	var rival: String = str(data.get("ladder_rival", "louis"))
	if rival == fighter or not Roster.FIGHTERS.has(rival):
		rival = Roster.FIGHTERS[0] if fighter != Roster.FIGHTERS[0] else Roster.FIGHTERS[1]
	var pool: Array = []
	for id: String in Roster.FIGHTERS:
		if id != fighter and id != rival:
			pool.append(id)
	_shuffle(pool, rng)
	floors.clear()
	for i: int in 5:
		var id: String = pool[i]
		floors.append({"opponents": [id], "kind": "normal", "stage": Roster.home_stage(id)})
	floors.append({"opponents": [pool[5], pool[6]], "kind": "double", "stage": Roster.home_stage(pool[5])})
	floors.append({"opponents": [fighter], "kind": "reflet", "stage": "cote_basques_crepuscule",
		"costume": (costume + 1) % 4})
	floors.append({"opponents": [rival], "kind": "rival", "stage": Roster.home_stage(rival)})
	floors.append({"opponents": [Roster.BOSS], "kind": "boss", "stage": "phare_sommet"})


func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i: int in range(arr.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp


func current_floor() -> Dictionary:
	return floors[floor_index]


func current_opponent() -> String:
	var opps: Array = current_floor()["opponents"]
	return str(opps[mini(sub_index, opps.size() - 1)])


## Compétence de l'IA à cet étage (rampe 1→8, boss en Expert+).
func ai_skill() -> int:
	var r: Array = SKILL_RANGE[difficulty]
	var skill: int
	if current_floor()["kind"] == "boss":
		skill = mini(int(r[1]) + 10, 100)
	else:
		skill = int(r[0]) + (int(r[1]) - int(r[0])) * mini(floor_index, 7) / 7
	return clampi(skill - skill_malus, 1, 100)


## Paramètres de la scène de combat pour l'étage courant.
func fight_params() -> Dictionary:
	var fl: Dictionary = current_floor()
	var double: bool = fl["kind"] == "double"
	return {
		"p1": fighter, "c1": costume,
		"p2": current_opponent(), "c2": int(fl.get("costume", 0)),
		"stage": fl["stage"],
		"rounds": 1 if double else 3,
		"ai": [0, ai_skill()],
		"autoguard": [1 if difficulty == 0 else 0, 0],
		"health": [carried_health if double and sub_index == 1 else 0, 0],
		"on_end": TowerMode.on_fight_end,
		"mode": "tower",
	}


## Appelé par la scène de combat à la fin du match.
static func on_fight_end(result: Dictionary) -> void:
	if run == null:
		SceneRouter.goto(&"main_menu")
		return
	run._handle_result(result)


func _handle_result(result: Dictionary) -> void:
	var won: bool = int(result.get("winner", -1)) == 0
	var fl: Dictionary = current_floor()
	if not won:
		# Continue illimité : même étage, score réduit de 20 %, rien d'autre.
		score = score * (100 - LOSS_PENALTY_PCT) / 100
		losses_here += 1
		if losses_here >= 2 and losses_here % 2 == 0:
			skill_malus += 10   # adaptation discrète (§13)
		sub_index = 0
		carried_health = 0
		SceneRouter.goto(&"tower", {"event": "lost"})
		return
	var gained: int = fight_score(result)
	score += gained
	fight_log.append({"floor": floor_index, "opponent": current_opponent(), "score": gained})
	if fl["kind"] == "double" and sub_index == 0:
		sub_index = 1
		var health: Array = result.get("health", [0, 0])
		carried_health = int(health[0])
		SceneRouter.goto(&"tower", {"event": "double_next"})
		return
	sub_index = 0
	carried_health = 0
	losses_here = 0
	skill_malus = 0
	floor_index += 1
	if floor_index >= FLOORS:
		_complete()
		return
	SceneRouter.goto(&"tower", {"event": "won"})


## Score d'un combat gagné (§3.2) : victoire, vie, temps, Parfait ×2, finish.
static func fight_score(result: Dictionary) -> int:
	var health: Array = result.get("health", [0, 0])
	var s: int = 1000
	s += int(health[0]) / 2
	s += int(result.get("timer", 0)) / 60 * 10
	if bool(result.get("perfect", false)):
		s *= 2
	if int(result.get("finisher", 0)) != 0:
		s += 500
	return s


func _complete() -> void:
	var profile: Dictionary = Profiles.active()
	var unlocked: Array[String] = []
	if not profile.is_empty():
		var stats: Dictionary = profile.get("stats", {})
		var towers: Dictionary = stats.get("towers", {})
		towers[fighter] = int(towers.get(fighter, 0)) + 1
		stats["towers"] = towers
		var txapelas: Dictionary = stats.get("txapelas", {})
		txapelas["%s_%s" % [fighter, DIFFICULTIES[difficulty]]] = true
		stats["txapelas"] = txapelas
		stats["best_tower"] = maxi(int(stats.get("best_tower", 0)), score)
		var unlocks: Dictionary = profile.get("unlocks", {})
		var costumes: Array = unlocks.get(fighter, [0])
		if not costumes.has(2):
			costumes.append(2)
			unlocked.append("Costume 3 de %s" % Roster.display_name(fighter))
		if difficulty == 2 and not costumes.has(3):
			costumes.append(3)
			unlocked.append("Costume 4 de %s" % Roster.display_name(fighter))
		unlocks[fighter] = costumes
		if not bool(unlocks.get("boss", false)):
			unlocks["boss"] = true
			unlocked.append("Le Gardien du Phare est jouable !")
		Profiles.update_active({"stats": stats, "unlocks": unlocks})
	Api.post_tower_score(fighter, DIFFICULTIES[difficulty], score)
	SceneRouter.goto(&"ending", {"fighter": fighter, "costume": costume, "score": score,
		"unlocked": unlocked, "difficulty": difficulty})
