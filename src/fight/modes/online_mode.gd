class_name OnlineMode
extends RefCounted
## État d'une partie en ligne entre les écrans (SPEC §3.4) : match du
## serveur, choix des deux joueurs, signalisation et lien P2P (nœuds
## rattachés à l'autoload Api pour survivre aux changements de scène).

const PICK_SECONDS: int = 30
const STAGE_SECONDS: int = 20      # l'hôte choisit la map pendant que l'invité attend

static var current: Dictionary = {}       # match_id, host, opponent, stage, seed, state
static var my_pick: Dictionary = {}     # fighter, costume, pseudo, express
static var their_pick: Dictionary = {}
static var signaling: Signaling = null
static var link: P2PLink = null
static var qa: Dictionary = {}          # automatisation des tests (rôle, bot)
static var rematch_votes: Dictionary = {}


## Messages de contrôle globaux (reçus quel que soit l'écran affiché).
static func handle_ctrl(d: Dictionary) -> void:
	if str(d.get("t", "")) == "rematch":
		rematch_votes["them"] = true


static func reset_net() -> void:
	if link != null and is_instance_valid(link):
		link.close()
		link.queue_free()
	if signaling != null and is_instance_valid(signaling):
		signaling.queue_free()
	link = null
	signaling = null
	their_pick = {}
	rematch_votes = {}


static func leave() -> void:
	if not current.is_empty():
		Api.call_api(HTTPClient.METHOD_POST, "/match/cancel", {"match_id": int(current.get("match_id", 0))},
			func(_ok: bool, _c: int, _d: Variant) -> void: pass)
	reset_net()
	current = {}
	SceneRouter.goto(&"lobby")


static func is_host() -> bool:
	return bool(current.get("host", false))


## Paramètres de la scène de combat : J1 = hôte, J2 = invité.
static func fight_params() -> Dictionary:
	var host_pick: Dictionary = my_pick if is_host() else their_pick
	var guest_pick: Dictionary = their_pick if is_host() else my_pick
	var express: bool = bool(my_pick.get("express", false)) or bool(their_pick.get("express", false))
	return {
		"p1": str(host_pick.get("fighter", "louis")), "c1": int(host_pick.get("costume", 0)),
		"p2": str(guest_pick.get("fighter", "louis")), "c2": int(guest_pick.get("costume", 0)),
		"names": [str(host_pick.get("pseudo", "?")), str(guest_pick.get("pseudo", "?"))],
		"stage": str(current.get("stage", "grande_plage")), "seed": int(current.get("seed", 1)),
		"rounds": 3, "ai": [0, 0], "finishers": not express,
		"mode": "online", "local_slot": 0 if is_host() else 1,
		"delay": int(my_pick.get("delay", 2)), "return_to": "lobby",
	}
