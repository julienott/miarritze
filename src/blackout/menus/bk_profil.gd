class_name BkProfil
extends RefCounted
## Profil Blackout (GDD-BLACKOUT.md) par-dessus les profils locaux de l'appareil (autoload
## Profiles, user://profiles.json, 4 au plus) : pseudo et perso, rien d'autre (GDD §7.1 : ni couleur,
## ni emote, ni cosmétique). Aucune donnée personnelle, plus de code de groupe. Les champs d'avant
## (Borroka, couleur et emote de Blackout) restent dans le fichier, ignorés. Les anciens profils
## reçoivent leur perso au premier chargement (`migrer`).

## Clé gardée telle quelle (« gk_ » du nom d'avant) : elle est déjà dans les user://profiles.json des
## appareils ; la renommer perdrait le perso des profils existants.
const PERSO: String = "gk_perso"
const GROS_MOTS_PATH: String = "res://data/blackout/gros_mots.json"

static var _gros_mots: PackedStringArray = []


static func profiles() -> Node:
	return (Engine.get_main_loop() as SceneTree).root.get_node_or_null("/root/Profiles")


## Ajoute le perso aux profils qui n'en ont pas (anciens profils Borroka) : le perso de Borroka s'il
## existe dans Blackout, sinon Louis.
static func migrer() -> void:
	var p: Node = profiles()
	if p == null:
		return
	var change: bool = false
	var persos: Array = BkRules.data().get("characters", [])
	for i: int in p.profiles.size():
		var prof: Dictionary = p.profiles[i]
		if not prof.has(PERSO) or not persos.has(str(prof[PERSO])):
			var f: String = str(prof.get("fighter", "louis"))
			prof[PERSO] = f if persos.has(f) else "louis"
			change = true
	if change:
		p.save()


static func actif() -> Dictionary:
	var p: Node = profiles()
	return p.active() if p != null else {}


static func a_un_actif() -> bool:
	return not actif().is_empty()


static func pseudo() -> String:
	return str(actif().get("pseudo", "Toi"))


static func perso() -> String:
	return str(actif().get(PERSO, "louis"))


static func regler(cle: String, valeur: Variant) -> void:
	var p: Node = profiles()
	if p != null:
		p.update_active({cle: valeur})


## Message d'erreur pour un pseudo refusé, "" s'il est bon : 2 à 15 lettres, chiffres, - ou _
## (Profiles.pseudo_ok, comme le serveur), sans gros mot (copie de la liste du serveur).
static func erreur_pseudo(texte: String) -> String:
	var t: String = texte.strip_edges()
	if t.length() < 2:
		return "Au moins 2 lettres"
	if t.length() > 15:
		return "15 lettres au plus"
	if t.contains(" "):
		return "Sans espace"
	if profiles() != null and not profiles().pseudo_ok(t):
		return "Lettres, chiffres, - ou _ seulement"
	if gros_mot(t):
		return "Ce pseudo n'est pas permis, choisis-en un autre"
	return ""


## Même filtre que backend/src/Profanity.php : minuscules sans accents, chiffres « leet » remis en
## lettres, puis on cherche les mots de la liste dans ce qui reste.
static func gros_mot(texte: String) -> bool:
	if _gros_mots.is_empty():
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(GROS_MOTS_PATH))
		if d is Dictionary:
			_gros_mots = PackedStringArray((d as Dictionary).get("mots", []))
	var n: String = normaliser(texte)
	for m: String in _gros_mots:
		if n.contains(m):
			return true
	return false


const ACCENTS: Dictionary = {"à": "a", "â": "a", "ä": "a", "á": "a", "ã": "a", "å": "a", "ç": "c",
	"é": "e", "è": "e", "ê": "e", "ë": "e", "í": "i", "ì": "i", "î": "i", "ï": "i", "ñ": "n", "ó": "o",
	"ò": "o", "ô": "o", "ö": "o", "õ": "o", "ú": "u", "ù": "u", "û": "u", "ü": "u", "ý": "y", "ÿ": "y",
	"œ": "oe", "æ": "ae"}
const LEET: Dictionary = {"0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t", "@": "a", "$": "s"}


static func normaliser(texte: String) -> String:
	var out: String = ""
	for ch: String in texte.to_lower():
		ch = str(ACCENTS.get(ch, ch))
		ch = str(LEET.get(ch, ch))
		for c: String in ch:
			if c >= "a" and c <= "z":
				out += c
	return out


## Crée un profil (actif) avec ses champs Blackout ; renvoie le message d'erreur, ou "".
static func creer(texte: String) -> String:
	var err: String = erreur_pseudo(texte)
	if err != "":
		return err
	var p: Node = profiles()
	for prof: Dictionary in p.profiles:
		if str(prof.get("pseudo", "")).to_lower() == texte.strip_edges().to_lower():
			return "Ce pseudo est déjà sur cet appareil"
	if not p.create(texte.strip_edges()):
		return "4 profils au plus"
	p.update_active({PERSO: "louis"})
	return ""


## Le profil actif joue la partie qui commence : pseudo et perso.
static func vers_partie() -> void:
	if not a_un_actif():
		return
	BkGame.config["name"] = pseudo()
	BkGame.config["character"] = perso()


## QA (`--scene=bk_accueil`… sans profil) : un profil jetable pour voir les écrans.
static func assurer_qa() -> void:
	var p: Node = profiles()
	if p != null and p.profiles.is_empty():
		creer("Testeur")
	elif p != null and not a_un_actif():
		p.select(0)
